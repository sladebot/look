"""Tests for TagsManager.merge_tags — connection scope fix."""
import tempfile
from pathlib import Path

import pytest

from api.database import PhotoDatabase
from api.config import Config
from api.tags_manager import TagsManager


@pytest.fixture
def db_path(tmp_path):
    """Return a temporary database path."""
    return str(tmp_path / "test_library.db")


@pytest.fixture
def db(db_path):
    """Return an initialized PhotoDatabase."""
    return PhotoDatabase(db_path)


@pytest.fixture
def config():
    """Return a minimal Config with tag history enabled."""
    return Config(
        photo_dir="/tmp/photos",
        db_path="/tmp/test_db.db",
        tag_history_enabled=True,
    )


@pytest.fixture
def tags_manager(db, config):
    """Return a TagsManager bound to a test DB and config."""
    return TagsManager(db=db, config=config)


def _add_photo(db, photo_id: str, filepath: str, filename: str):
    """Helper: store a minimal photo into the test DB."""
    db.store_photo({
        "id": photo_id,
        "filename": filename,
        "filepath": filepath,
        "file_size": 1234,
        "width": 800,
        "height": 600,
        "mime_type": "image/jpeg",
        "created_at": "2025-01-01T00:00:00",
        "indexed_at": "2025-01-01T00:00:00",
    })


def test_merge_tags_source_removed_target_added(tags_manager, db):
    """Verify merge_tags: source tag gone, target tag appears, photos_affected == 1."""
    photo_id = "aaa111"
    filepath = "/tmp/photos/vacation/photo.jpg"
    filename = "photo.jpg"

    # Set up: store a photo and give it the source tag
    _add_photo(db, photo_id, filepath, filename)
    db.add_tag(photo_id, source_tag := "old-tag")

    target_tag = "new-tag"

    # Confirm source tag is present before merge
    tags_before = db.get_tags(photo_id)
    assert source_tag in tags_before
    assert target_tag not in tags_before

    # Perform merge
    result = tags_manager.merge_tags(source_tag, target_tag)

    # Assert results
    assert result["photos_affected"] == 1
    assert result["merged"] == source_tag
    assert result["into"] == target_tag
    assert "error" not in result

    # Verify state after merge: source gone, target present
    tags_after = db.get_tags(photo_id)
    assert source_tag not in tags_after
    assert target_tag in tags_after


def test_merge_tags_no_source_tags(tags_manager, db):
    """Merging when source tag has zero photos returns photos_affected == 0."""
    photo_id = "bbb222"
    _add_photo(db, photo_id, "/tmp/photo.jpg", "photo.jpg")
    db.add_tag(photo_id, "existing-tag")

    result = tags_manager.merge_tags("nonexistent", "target")
    assert result["photos_affected"] == 0


def test_merge_tags_same_tag_returns_error(tags_manager, db):
    """Merging a tag into itself should return an error dict."""
    result = tags_manager.merge_tags("tag", "tag")
    assert "error" in result
    assert result["error"] == "Source and target are the same"


def test_merge_tags_multiple_photos(tags_manager, db):
    """Merge should affect all photos that have the source tag."""
    pids = [f"p{i}" for i in range(5)]
    for i, pid in enumerate(pids):
        _add_photo(db, pid, f"/tmp/photo{i}.jpg", f"photo{i}.jpg")
        db.add_tag(pid, "source")

    result = tags_manager.merge_tags("source", "target")
    assert result["photos_affected"] == 5

    # All 5 photos should now have target, none should have source
    for pid in pids:
        tags = db.get_tags(pid)
        assert "source" not in tags
        assert "target" in tags
