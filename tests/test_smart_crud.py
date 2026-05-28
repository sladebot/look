import tempfile, os, json
from api.database import PhotoDatabase


def test_delete_album_on_smart_collection():
    """delete_album works on smart_collection source albums."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        album_id = db.create_album('Test Smart', 'desc', source='smart_collection')
        albums_before = db.get_smart_collections()
        assert len(albums_before) == 1
        success = db.delete_album(album_id)
        assert success is True
        albums_after = db.get_smart_collections()
        assert len(albums_after) == 0
    finally:
        os.unlink(db_path)
