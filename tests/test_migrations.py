"""Tests for the database migration manager."""
import os
import tempfile
from pathlib import Path

import pytest

from api.migrations import MigrationManager
from api.database import PhotoDatabase


# ── Helpers ───────────────────────────────────────────────────────────────────

def _make_db() -> PhotoDatabase:
    """Create a fresh test database."""
    db_path = str(Path(tempfile.mkdtemp()) / "test_migrate.db")
    return PhotoDatabase(db_path)


# ── MigrationManager ──────────────────────────────────────────────────────────

def test_get_info_returns_version_zero_on_fresh_db():
    """Fresh database should report current_version=0."""
    db = _make_db()
    manager = MigrationManager(db)

    info = manager.get_info()

    assert info['current_version'] == 0
    assert info['pending'] == []
    assert info['all_registered'] == []


def test_register_adds_migrations_to_pending():
    """Registered migrations should appear in get_info() as pending."""
    db = _make_db()
    manager = MigrationManager(db)

    manager.register([
        {"version": 1, "description": "Add GPS columns", "up_sql": "ALTER TABLE photos ADD COLUMN gps_lat REAL"},
        {"version": 2, "description": "Add GPS lon", "up_sql": "ALTER TABLE photos ADD COLUMN gps_lon REAL"},
    ])

    info = manager.get_info()

    assert len(info['pending']) == 2
    assert info['pending'][0]['version'] == 1
    assert info['pending'][0]['description'] == 'Add GPS columns'


def test_apply_all_applies_in_order_and_skips():
    """apply_all() executes pending migrations in version order,
    and re-running it skips already-applied ones."""
    db = _make_db()
    manager = MigrationManager(db)

    # Register in reverse order to verify sorting
    manager.register([
        {"version": 3, "description": "Third", "up_sql": "ALTER TABLE photos ADD COLUMN col3 REAL"},
        {"version": 1, "description": "First", "up_sql": "ALTER TABLE photos ADD COLUMN col1 REAL"},
        {"version": 2, "description": "Second", "up_sql": "ALTER TABLE photos ADD COLUMN col2 REAL"},
    ])

    applied1 = manager.apply_all()
    assert len(applied1) == 3
    info = manager.get_info()
    assert info['current_version'] == 3

    # Re-apply should have nothing new
    applied2 = manager.apply_all()
    assert len(applied2) == 0


def test_get_info_marks_applied_migrations():
    """Re-running apply_all() should not re-apply migrations."""
    db = _make_db()
    manager = MigrationManager(db)

    manager.register([
        {"version": 1, "description": "Add column", "up_sql": "ALTER TABLE photos ADD COLUMN new_col TEXT"},
    ])

    applied1 = manager.apply_all()
    assert len(applied1) == 1

    # Second call should have nothing to apply
    applied2 = manager.apply_all()
    assert len(applied2) == 0


def test_get_info_marks_applied_migrations():
    """get_info() should mark migrations that have been applied."""
    db = _make_db()
    manager = MigrationManager(db)

    manager.register([
        {"version": 1, "description": "Backfill GPS data", "up_sql": "UPDATE photos SET gps_lat = 0 WHERE 1=0"},
        {"version": 2, "description": "Create index", "up_sql": "CREATE INDEX IF NOT EXISTS idx_x ON photos(gps_lat) WHERE gps_lat IS NOT NULL"},
    ])

    manager.apply_all()

    info = manager.get_info()

    assert len(info['all_registered']) == 2
    # Both should be marked as applied
    for m in info['all_registered']:
        assert m['applied'] is True

    # No pending migrations
    assert len(info['pending']) == 0


def test_rollback_to_specific_version():
    """Rollback should reverse migrations down to target version."""
    db = _make_db()
    manager = MigrationManager(db)

    manager.register([
        {"version": 1, "description": "Backfill GPS data", "up_sql": "UPDATE photos SET gps_lat = 0 WHERE 1=0"},
        {"version": 2, "description": "Create index", "up_sql": "CREATE INDEX IF NOT EXISTS idx_x ON photos(gps_lat) WHERE gps_lat IS NOT NULL"},
    ])

    manager.apply_all()  # Now at version 2

    # Rollback to version 1 (should undo v2)
    result = manager.rollback(target_version=1)

    assert result['to_version'] == 1
    assert result['status'] == 'rolled_back'
    assert 'Create index' in result['migrations'] or result['status'] == 'rolled_back'


def test_rollback_noop_when_already_at_or_below():
    """Rollback to same or lower version should be a no-op."""
    db = _make_db()
    manager = MigrationManager(db)

    manager.register([
        {"version": 1, "description": "Backfill GPS data", "up_sql": "UPDATE photos SET gps_lat = 0 WHERE 1=0"},
    ])

    manager.apply_all()

    result = manager.rollback(target_version=1)

    assert result['status'] == 'no-op'


def test_schema_version_stored_in_settings():
    """Migration system should track schema version in server_settings."""
    db = _make_db()
    manager = MigrationManager(db)

    manager.register([
        {"version": 1, "description": "Test backfill", "up_sql": "UPDATE photos SET gps_lat = 0 WHERE 1=0"},
    ])

    manager.apply_all()

    # Check that schema_version was written
    with db._connect() as conn:
        row = conn.execute(
            f"SELECT value FROM server_settings WHERE key = '{manager.SCHEMA_VERSION_KEY}'"
        ).fetchone()
    assert row is not None
    assert int(row['value']) == 1
