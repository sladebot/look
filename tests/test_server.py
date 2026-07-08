"""Tests for FastAPI server endpoints — GPS, task queue, rate limiter, migrations."""
import os
import tempfile
from pathlib import Path

import httpx
import pytest
from httpx import ASGITransport

from api.server import app
from api.database import PhotoDatabase


# ── Helpers ───────────────────────────────────────────────────────────────────

def _make_db() -> tuple[PhotoDatabase, str]:
    """Create a test database and return (db, db_path)."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_server.db")
    return PhotoDatabase(db_path), db_path


# ── Health endpoint ───────────────────────────────────────────────────────────

def test_health_returns_ok():
    """GET /api/health should return status ok with basic info."""
    transport = ASGITransport(app=app)
    client = httpx.Client(transport=transport, base_url="http://test")
    try:
        resp = client.get("/api/health")
    finally:
        client.close()

    assert resp.status_code == 200
    data = resp.json()
    assert data['status'] == 'ok'
    assert 'photo_count' in data
    assert 'db_path' in data


# ── GPS / Nearby endpoint ─────────────────────────────────────────────────────

def test_nearby_photos_endpoint_returns_geo_results():
    """GET /api/photos/nearby should work and return geospatial results."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_nearby.db")

    import api.server
    from api.server import PhotoDatabase as PD, Config

    config = Config(photo_dir='/tmp', db_path=db_path)
    db = PD(db_path)

    # Store a photo with GPS
    db.store_photo({
        'id': 'test1', 'filename': 'nyc.jpg', 'filepath': '/tmp/n.jpg',
        'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'indexed_at': '2024-01-01',
        'gps_lat': 40.7128, 'gps_lon': -74.0060,
    })

    # Patch the module-level db to point to test db
    old_db = api.server.db
    api.server.db = db

    try:
        transport = ASGITransport(app=app)
        client = httpx.Client(transport=transport, base_url="http://test")
        try:
            resp = client.get("/api/photos/nearby", params={
                'lat': 40.7128, 'lon': -74.0060, 'radius_km': 50
            })
        finally:
            client.close()

        assert resp.status_code == 200
        data = resp.json()
        assert data['center']['lat'] == 40.7128
        assert data['center']['lon'] == -74.0060
        assert data['radius_km'] == 50.0
        assert 'photos' in data
        assert 'total' in data
    finally:
        api.server.db = old_db


def test_nearby_no_gps_returns_empty():
    """Photos without GPS data should not appear in nearby results."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_no_gps.db")

    import api.server
    from api.server import PhotoDatabase as PD, Config

    config = Config(photo_dir='/tmp', db_path=db_path)
    db = PD(db_path)

    db.store_photo({
        'id': 'no_gps', 'filename': 'x.jpg', 'filepath': '/tmp/x.jpg',
        'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'indexed_at': '2024-01-01',
    })

    old_db = api.server.db
    api.server.db = db

    try:
        transport = ASGITransport(app=app)
        client = httpx.Client(transport=transport, base_url="http://test")
        try:
            resp = client.get("/api/photos/nearby", params={
                'lat': 40.0, 'lon': -74.0, 'radius_km': 100
            })
        finally:
            client.close()

        data = resp.json()
        assert data['total'] == 0
        assert data['photos'] == []
    finally:
        api.server.db = old_db


# ── Display preview endpoint ──────────────────────────────────────────────────

def test_display_preview_endpoint_queues_missing_preview(tmp_path):
    """GET /api/preview/{id} should queue display preview generation."""
    import api.server
    from api.server import PhotoDatabase as PD, Config

    photo_path = tmp_path / "large.jpg"
    photo_path.write_bytes(b"jpeg placeholder")
    db_path = str(tmp_path / "preview.db")
    db = PD(db_path)
    db.store_photo({
        'id': 'photo-preview',
        'filename': 'large.jpg',
        'filepath': str(photo_path),
        'file_size': photo_path.stat().st_size,
        'width': 9504,
        'height': 6336,
        'mime_type': 'image/jpeg',
        'indexed_at': '2026-07-01T00:00:00',
        'has_thumbnail': False,
    })

    class FakeProcessor:
        def __init__(self, config):
            self.config = config

        def find_existing_thumbnail(self, path, size):
            return None

    class FakePreviewQueue:
        def __init__(self, db):
            self.db = db
            self.calls = []

        def enqueue_thumbnail(self, photo_id, filepath, size, priority=50):
            self.calls.append((photo_id, filepath, size, priority))

    config = Config(photo_dir=str(tmp_path), db_path=db_path)
    fake_queue = FakePreviewQueue(db)
    old_db = api.server.db
    old_config = api.server.config
    old_processor = api.server.processor
    old_queue = api.server.preview_queue

    api.server.db = db
    api.server.config = config
    api.server.processor = FakeProcessor(config)
    api.server.preview_queue = fake_queue

    try:
        transport = ASGITransport(app=app)
        client = httpx.Client(transport=transport, base_url="http://test")
        try:
            resp = client.get("/api/preview/photo-preview", params={'size': 1600})
        finally:
            client.close()

        assert resp.status_code == 200
        assert resp.headers["x-look-preview"] == "queued"
        assert resp.headers["content-type"] == "image/jpeg"
        assert fake_queue.calls == [("photo-preview", str(photo_path), 1600, 0)]
    finally:
        api.server.db = old_db
        api.server.config = old_config
        api.server.processor = old_processor
        api.server.preview_queue = old_queue


# ── Task Queue endpoints ──────────────────────────────────────────────────────

def test_submit_dedup_scan_returns_task_id():
    """POST /api/dedup/scan should submit a background task and return task_id."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_submit.db")

    import api.server
    from api.server import PhotoDatabase as PD, Config, TaskQueue, DedupEngine

    config = Config(photo_dir='/tmp', db_path=db_path, dedup_enabled=True)
    db = PD(db_path)

    # Create dedup engine and task queue
    processor = type('Proc', (), {
        'process': lambda self, fp: {'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'exif': {}}
    })()
    dedup = DedupEngine(db, config, processor)
    task_q = TaskQueue(db, dedup_engine=dedup)

    old_db = api.server.db
    old_dedup = api.server.dedup
    old_config = api.server.config
    old_queue = api.server.task_queue

    api.server.db = db
    api.server.dedup = dedup
    api.server.config = config
    api.server.task_queue = task_q

    try:
        transport = ASGITransport(app=app)
        client = httpx.Client(transport=transport, base_url="http://test")
        try:
            resp = client.post("/api/dedup/scan")
        finally:
            client.close()

        assert resp.status_code == 200
        data = resp.json()
        assert data['status'] == 'submitted'
        assert 'task_id' in data
    finally:
        api.server.db = old_db
        api.server.dedup = old_dedup
        api.server.config = old_config
        api.server.task_queue = old_queue


def test_task_list_endpoint():
    """GET /api/tasks should return a list of tasks."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_tasks.db")

    import api.server
    from api.server import PhotoDatabase as PD, Config, TaskQueue

    config = Config(photo_dir='/tmp', db_path=db_path)
    db = PD(db_path)
    task_q = TaskQueue(db)
    task_q.submit_task("test", {})

    old_db = api.server.db
    old_queue = api.server.task_queue

    api.server.db = db
    api.server.task_queue = task_q

    try:
        transport = ASGITransport(app=app)
        client = httpx.Client(transport=transport, base_url="http://test")
        try:
            resp = client.get("/api/tasks")
        finally:
            client.close()

        assert resp.status_code == 200
        data = resp.json()
        assert 'tasks' in data
    finally:
        api.server.db = old_db
        api.server.task_queue = old_queue


def test_get_single_task_endpoint():
    """GET /api/tasks/{task_id} should return task details."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_single.db")

    import api.server
    from api.server import PhotoDatabase as PD, Config, TaskQueue

    config = Config(photo_dir='/tmp', db_path=db_path)
    db = PD(db_path)
    task_q = TaskQueue(db)
    task_id = task_q.submit_task("test", {"key": "val"})

    old_db = api.server.db
    old_queue = api.server.task_queue

    api.server.db = db
    api.server.task_queue = task_q

    try:
        transport = ASGITransport(app=app)
        client = httpx.Client(transport=transport, base_url="http://test")
        try:
            resp = client.get(f"/api/tasks/{task_id}")
        finally:
            client.close()

        assert resp.status_code == 200
        data = resp.json()
        assert data['task_id'] == task_id
        assert data['task_type'] == 'test'
    finally:
        api.server.db = old_db
        api.server.task_queue = old_queue


# ── Migration endpoints ───────────────────────────────────────────────────────

def test_migrate_status_returns_info():
    """GET /api/migrate should return migration info."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_mig.db")

    import api.server
    from api.server import PhotoDatabase as PD, Config, MigrationManager

    config = Config(photo_dir='/tmp', db_path=db_path)
    db = PD(db_path)
    mgr = MigrationManager(db)
    mgr.register([
        {"version": 1, "description": "Test migration", "up_sql": "ALTER TABLE photos ADD COLUMN test_col TEXT"},
    ])

    old_db = api.server.db
    old_migrator = api.server.migrator

    api.server.db = db
    api.server.migrator = mgr

    try:
        transport = ASGITransport(app=app)
        client = httpx.Client(transport=transport, base_url="http://test")
        try:
            resp = client.get("/api/migrate")
        finally:
            client.close()

        assert resp.status_code == 200
        data = resp.json()
        assert 'current_version' in data
        assert 'pending' in data
        assert 'all_registered' in data
    finally:
        api.server.db = old_db
        api.server.migrator = old_migrator


def test_migrate_apply_runs_pending():
    """POST /api/migrate should apply pending migrations."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_apply.db")

    import api.server
    from api.server import PhotoDatabase as PD, Config, MigrationManager

    config = Config(photo_dir='/tmp', db_path=db_path)
    db = PD(db_path)
    mgr = MigrationManager(db)
    mgr.register([
        {"version": 1, "description": "Add test col", "up_sql": "ALTER TABLE photos ADD COLUMN test_col TEXT"},
    ])

    old_db = api.server.db
    old_migrator = api.server.migrator

    api.server.db = db
    api.server.migrator = mgr

    try:
        transport = ASGITransport(app=app)
        client = httpx.Client(transport=transport, base_url="http://test")
        try:
            resp = client.post("/api/migrate")
        finally:
            client.close()

        assert resp.status_code == 200
        data = resp.json()
        assert data['status'] == 'applied'
        assert data['applied_count'] == 1
    finally:
        api.server.db = old_db
        api.server.migrator = old_migrator


# ── Rate limiter (end-to-end) ────────────────────────────────────────────────

def test_rate_limit_headers_present():
    """Responses from endpoints under rate limiting should include X-RateLimit-Remaining header."""
    transport = ASGITransport(app=app)
    client = httpx.Client(transport=transport, base_url="http://test")
    try:
        resp = client.get("/api/health")
    finally:
        client.close()

    assert 'X-RateLimit-Remaining' in resp.headers
    int(resp.headers['X-RateLimit-Remaining'])  # should parse as int


def test_dedup_scan_rate_limit():
    """Heavy endpoints should have tighter rate limits."""
    transport = ASGITransport(app=app)
    client = httpx.Client(transport=transport, base_url="http://test")
    try:
        # Exhaust the endpoint-specific bucket (rate=5, burst=5)
        for _ in range(5):
            client.post("/api/dedup/scan")

        # 6th should be rate-limited
        resp = client.post("/api/dedup/scan")

        assert resp.status_code == 429
        data = resp.json()
        assert 'detail' in data
        assert 'retry_after' in data
    finally:
        client.close()


# ── Favorites endpoint ────────────────────────────────────────────────────────

def test_set_photo_favorite_toggles_flag():
    """POST /api/photos/{id}/favorite should set and clear is_favorite."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_favorite.db")

    import api.server
    from api.server import PhotoDatabase as PD

    db = PD(db_path)
    db.store_photo({
        'id': 'fav1', 'filename': 'sunset.jpg', 'filepath': '/tmp/sunset.jpg',
        'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'indexed_at': '2024-01-01',
    })

    old_db = api.server.db
    api.server.db = db
    try:
        transport = ASGITransport(app=app)
        client = httpx.Client(transport=transport, base_url="http://test")
        try:
            resp = client.post("/api/photos/fav1/favorite")
            assert resp.status_code == 200
            assert resp.json() == {"photo_id": "fav1", "is_favorite": True}
            assert db.get_photo("fav1")["is_favorite"] == 1

            resp = client.post("/api/photos/fav1/favorite", params={"value": "false"})
            assert resp.status_code == 200
            assert resp.json()["is_favorite"] is False
            assert db.get_photo("fav1")["is_favorite"] == 0

            resp = client.post("/api/photos/missing/favorite")
            assert resp.status_code == 404
        finally:
            client.close()
    finally:
        api.server.db = old_db


def test_albums_include_cover_photo_id():
    """GET /api/albums should expose cover_photo_id (newest photo, or None when empty)."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_album_cover.db")

    import api.server
    from api.server import PhotoDatabase as PD

    db = PD(db_path)
    db.store_photo({
        'id': 'photo_old', 'filename': 'old.jpg', 'filepath': '/tmp/old.jpg',
        'width': 100, 'height': 100, 'mime_type': 'image/jpeg',
        'created_at': '2024-01-01T00:00:00', 'indexed_at': '2024-01-01',
    })
    db.store_photo({
        'id': 'photo_new', 'filename': 'new.jpg', 'filepath': '/tmp/new.jpg',
        'width': 100, 'height': 100, 'mime_type': 'image/jpeg',
        'created_at': '2024-06-01T00:00:00', 'indexed_at': '2024-06-01',
    })

    filled = db.create_album("Filled")
    db.add_photo_to_album(filled, 'photo_old')
    db.add_photo_to_album(filled, 'photo_new')
    empty = db.create_album("Empty")

    old_db = api.server.db
    api.server.db = db
    try:
        transport = ASGITransport(app=app)
        client = httpx.Client(transport=transport, base_url="http://test")
        try:
            resp = client.get("/api/albums")
            assert resp.status_code == 200
            albums = {a['id']: a for a in resp.json()['albums']}
            # Newest photo (by created_at) is the cover.
            assert albums[filled]['cover_photo_id'] == 'photo_new'
            # Album with no photos has no cover.
            assert albums[empty]['cover_photo_id'] is None
        finally:
            client.close()
    finally:
        api.server.db = old_db
