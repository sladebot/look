"""Test that smart album rule evaluation handles camera rules correctly."""
import tempfile
import os
from api.database import PhotoDatabase


def test_camera_rule_matches_exif():
    """_evaluate_rules with camera:contains matches exif JSON."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        db.store_photo({
            'id': 'p1', 'filename': 'a.jpg', 'filepath': '/tmp/a.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-06-01T00:00:00',
            'indexed_at': '2024-06-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Canon', 'model': 'EOS R5'}
        })
        rules = {'rules': [{'field': 'camera', 'op': 'contains', 'value': 'Canon'}]}
        matching = db._evaluate_rules(rules)
        assert matching == ['p1'], f"Expected ['p1'], got {matching}"
    finally:
        os.unlink(db_path)


def test_no_camera_match_when_different_brand():
    """Camera rule should not match photos with different camera brand."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        db.store_photo({
            'id': 'p2', 'filename': 'b.jpg', 'filepath': '/tmp/b.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-06-01T00:00:00',
            'indexed_at': '2024-06-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Nikon', 'model': 'Z6'}
        })
        rules = {'rules': [{'field': 'camera', 'op': 'contains', 'value': 'Canon'}]}
        matching = db._evaluate_rules(rules)
        assert matching == [], f"Expected [], got {matching}"
    finally:
        os.unlink(db_path)


def test_camera_rule_equals():
    """_evaluate_rules with camera:equals matches exact model."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        db.store_photo({
            'id': 'p3', 'filename': 'c.jpg', 'filepath': '/tmp/c.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-07-01T00:00:00',
            'indexed_at': '2024-07-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Canon', 'model': 'EOS R5'}
        })
        db.store_photo({
            'id': 'p4', 'filename': 'd.jpg', 'filepath': '/tmp/d.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-07-02T00:00:00',
            'indexed_at': '2024-07-02T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Canon', 'model': 'EOS R7'}
        })
        rules = {'rules': [{'field': 'camera', 'op': 'equals', 'value': 'EOS R5'}]}
        matching = db._evaluate_rules(rules)
        assert matching == ['p3'], f"Expected ['p3'], got {matching}"
    finally:
        os.unlink(db_path)


def test_camera_rule_multiple_photos():
    """Camera:contains matches all photos from matching brand."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        db.store_photo({
            'id': 'p5', 'filename': 'e1.jpg', 'filepath': '/tmp/e1.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-08-01T00:00:00',
            'indexed_at': '2024-08-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Nikon', 'model': 'Z6'}
        })
        db.store_photo({
            'id': 'p6', 'filename': 'e2.jpg', 'filepath': '/tmp/e2.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-08-02T00:00:00',
            'indexed_at': '2024-08-02T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Nikon', 'model': 'Z9'}
        })
        db.store_photo({
            'id': 'p7', 'filename': 'e3.jpg', 'filepath': '/tmp/e3.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-08-03T00:00:00',
            'indexed_at': '2024-08-03T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': {'make': 'Sony', 'model': 'A7IV'}
        })
        rules = {'rules': [{'field': 'camera', 'op': 'contains', 'value': 'Nikon'}]}
        matching = db._evaluate_rules(rules)
        assert set(matching) == {'p5', 'p6'}, f"Expected ['p5', 'p6'], got {matching}"
    finally:
        os.unlink(db_path)


def test_no_exif_no_camera_match():
    """Photos without exif should not match camera rules."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        db.store_photo({
            'id': 'p8', 'filename': 'f.png', 'filepath': '/tmp/f.png',
            'file_size': 200, 'width': 1024, 'height': 768,
            'mime_type': 'image/png', 'created_at': '2024-09-01T00:00:00',
            'indexed_at': '2024-09-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
        })
        rules = {'rules': [{'field': 'camera', 'op': 'contains', 'value': 'Canon'}]}
        matching = db._evaluate_rules(rules)
        assert matching == [], f"Expected [] for photo without exif, got {matching}"
    finally:
        os.unlink(db_path)
