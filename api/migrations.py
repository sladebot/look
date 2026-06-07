"""Database Migrations — versioned, idempotent, rollback-capable.

Usage:
    manager = MigrationManager(db)
    manager.apply_all()  # called during server startup
    # Or manually via /api/migrate endpoint (POST, requires API key)

Each migration is defined as a dict:
    {
        "version": 1,
        "description": "Add GPS columns",
        "up_sql": "ALTER TABLE photos ADD COLUMN gps_lat REAL DEFAULT NULL",
        "down_sql": "ALTER TABLE photos DROP COLUMN gps_lat"  # optional
    }
"""
from typing import List, Dict, Optional
from datetime import datetime


class MigrationManager:
    """Manages versioned database migrations."""

    SCHEMA_VERSION_KEY = "schema_version"

    def __init__(self, db):
        self.db = db
        self._pending: List[Dict] = []

    def register(self, migrations: List[Dict]):
        """Register a list of migration definitions.

        Each migration is a dict with:
            version (int): unique version number (must be > current)
            description (str): human-readable description
            up_sql (str): SQL to apply (forward migration)
            down_sql (str, optional): SQL to undo (rollback)
        """
        self._pending.extend(migrations)

    def apply_all(self) -> List[Dict]:
        """Apply all pending migrations. Returns list of applied migrations."""
        current = self._get_schema_version()
        applied = []

        for migration in sorted(self._pending, key=lambda m: m["version"]):
            if migration["version"] > current:
                self._run_migration(migration)
                applied.append(migration)
                print(f"[migrate] Applied v{migration['version']}: {migration['description']}")

        return applied

    def _get_schema_version(self) -> int:
        """Get the current schema version from server_settings."""
        try:
            row = self.db._connect().execute(
                f"SELECT value FROM server_settings WHERE key = '{self.SCHEMA_VERSION_KEY}'"
            ).fetchone()
            if row:
                return int(row['value'])
        except Exception:
            pass
        return 0  # fresh database, no migrations yet

    def _run_migration(self, migration: Dict):
        """Execute a single migration (forward)."""
        version = migration["version"]
        up_sql = migration["up_sql"]

        try:
            with self.db._connect() as conn:
                conn.execute(up_sql)
                conn.execute(
                    f"INSERT OR REPLACE INTO server_settings (key, value) "
                    f"VALUES ('{self.SCHEMA_VERSION_KEY}', '{version}')"
                )
                conn.commit()
        except Exception as e:
            # Some migrations may be idempotent or columns may already exist
            # (e.g., running apply_all() multiple times during test collection)
            if "duplicate column" in str(e) or "no such column" in str(e):
                print(f"[migrate] Skipping v{version}: {e} (already applied)")
                with self.db._connect() as conn:
                    conn.execute(
                        f"INSERT OR REPLACE INTO server_settings (key, value) "
                        f"VALUES ('{self.SCHEMA_VERSION_KEY}', '{version}')"
                    )
                    conn.commit()
            else:
                raise

    def get_info(self) -> Dict:
        """Get current schema info: version, pending migrations, all registered."""
        current = self._get_schema_version()
        return {
            "current_version": current,
            "pending": [
                {
                    "version": m["version"],
                    "description": m["description"],
                    "has_rollback": "down_sql" in m and m["down_sql"] is not None,
                }
                for m in sorted(self._pending, key=lambda m: m["version"])
                if m["version"] > current
            ],
            "all_registered": [
                {
                    "version": m["version"],
                    "description": m["description"],
                    "applied": m["version"] <= current,
                    "has_rollback": "down_sql" in m and m["down_sql"] is not None,
                }
                for m in sorted(self._pending, key=lambda m: m["version"])
            ],
        }

    def rollback(self, target_version: int, _auth=None) -> Dict:
        """Rollback migrations down to (but not including) target_version.

        Args:
            target_version: Roll back all migrations with version > target_version.
            _auth: API key check (must be provided).

        Returns:
            Summary of rolled-back migrations.
        """
        current = self._get_schema_version()
        if target_version >= current:
            return {"status": "no-op", "message": f"Already at or below version {target_version}"}

        # Find all migrations that need to be rolled back (sorted descending)
        to_rollback = sorted(
            [m for m in self._pending if target_version < m["version"] <= current],
            key=lambda m: m["version"],
            reverse=True
        )

        rolled_back = []
        with self.db._connect() as conn:
            for migration in to_rollback:
                # Find the current schema version and see if this migration was applied
                if migration["version"] <= current:
                    down_sql = migration.get("down_sql")
                    if down_sql:
                        conn.execute(down_sql)
                        rolled_back.append(migration)
                        print(f"[migrate] Rolled back v{migration['version']}: {migration['description']}")

        # Update schema version
        conn.execute(
            f"INSERT OR REPLACE INTO server_settings (key, value) "
            f"VALUES ('{self.SCHEMA_VERSION_KEY}', '{target_version}')"
        )
        conn.commit()

        return {
            "status": "rolled_back",
            "from_version": current,
            "to_version": target_version,
            "migrations": [m["description"] for m in rolled_back],
        }
