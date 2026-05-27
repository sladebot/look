"""Test that EXIF data is persisted as JSON in the photos table."""
import tempfile
import os
import json
from api.database import PhotoDatabase


def test_store_photo_with_exif():
    """store_photo persists exif as JSON in photos table."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        exif_data = {'make': 'Canon', 'model': 'EOS R5'}
        db.store_photo({
            'id': 'p1', 'filename': 'a.jpg', 'filepath': '/tmp/a.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-01-01T00:00:00',
            'indexed_at': '2024-01-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': exif_data,
        })
        photo = db.get_photo('p1')
        stored_exif = photo.get('exif')
        assert stored_exif is not None, "exif column should not be None"
        parsed = json.loads(stored_exif) if isinstance(stored_exif, str) else stored_exif
        assert parsed['make'] == 'Canon'
        assert parsed['model'] == 'EOS R5'
    finally:
        os.unlink(db_path)


def test_store_photo_without_exif():
    """store_photo handles missing/None exif gracefully."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        db.store_photo({
            'id': 'p2', 'filename': 'b.png', 'filepath': '/tmp/b.png',
            'file_size': 200, 'width': 1024, 'height': 768,
            'mime_type': 'image/png', 'created_at': '2024-02-01T00:00:00',
            'indexed_at': '2024-02-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
        })
        photo = db.get_photo('p2')
        stored_exif = photo.get('exif')
        assert stored_exif is None, "exif should be None for non-JPEG without EXIF"
    finally:
        os.unlink(db_path)


def test_store_photo_updates_existing_exif():
    """ON CONFLICT updates exif on re-import of same file."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        db.store_photo({
            'id': 'p3', 'filename': 'c.jpg', 'filepath': '/tmp/c.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-01-01T00:00:00',
            'indexed_at': '2024-01-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Canon', 'model': 'EOS R5'},
        })
        # Re-import with different EXIF (same filepath triggers ON CONFLICT)
        db.store_photo({
            'id': 'p3', 'filename': 'c.jpg', 'filepath': '/tmp/c.jpg',
            'file_size': 150, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-01-01T00:00:00',
            'indexed_at': '2024-01-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Nikon', 'model': 'Z9'},
        })
        photo = db.get_photo('p3')
        stored_exif = json.loads(photo.get('exif'))
        assert stored_exif['make'] == 'Nikon', 'exif should be updated on conflict'
        assert stored_exif['model'] == 'Z9'
    finally:
        os.unlink(db_path)


def test_camera_query_works_with_exif():
    """list_photos with camera filter reads exif via json_extract."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        db.store_photo({
            'id': 'p4a', 'filename': 'd1.jpg', 'filepath': '/tmp/d1.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-01-01T00:00:00',
            'indexed_at': '2024-01-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Canon', 'model': 'EOS R5'},
        })
        db.store_photo({
            'id': 'p4b', 'filename': 'd2.jpg', 'filepath': '/tmp/d2.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-01-02T00:00:00',
            'indexed_at': '2024-01-02T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Nikon', 'model': 'Z9'},
        })
        results = db.list_photos(camera='Canon')
        ids = [p['id'] for p in results]
        assert 'p4a' in ids, 'Canon camera query should find Canon photo'
        assert 'p4b' not in ids, 'Canon camera query should not find Nikon photo'
    finally:
        os.unlink(db_path)
