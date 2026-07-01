"""Local Photo Library Server — Database"""
import json
import os
import sqlite3
from pathlib import Path
from datetime import datetime


class PhotoDatabase:
    """SQLite database for photo library metadata."""

    def __init__(self, db_path: str):
        self.db_path = db_path
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self.init_db()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")

        # Register json_extract fallback for SQLite < 3.38 compatibility
        def _json_extract(data, path):
            if not data:
                return None
            try:
                obj = json.loads(data) if isinstance(data, str) else data
                key = path.lstrip('$.')
                return obj.get(key, None) if isinstance(obj, dict) else None
            except (json.JSONDecodeError, TypeError, AttributeError):
                return None

        conn.create_function("json_extract", 2, _json_extract)
        return conn

    def init_db(self):
        """Initialize database schema."""
        with self._connect() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS photos (
                    id          TEXT PRIMARY KEY,  -- SHA-256 hash of filepath
                    filename    TEXT NOT NULL,
                    filepath    TEXT NOT NULL UNIQUE,
                    file_size   INTEGER,
                    width       INTEGER,
                    height      INTEGER,
                    mime_type   TEXT,
                    created_at  TEXT,
                    indexed_at  TEXT NOT NULL,
                    has_thumbnail INTEGER DEFAULT 0,
                    is_favorite INTEGER DEFAULT 0,
                    color_tag   TEXT DEFAULT 'none',
                    is_source_jpeg INTEGER DEFAULT 0,  -- 1 if this is a converted/sidecar JPEG
                    exif        TEXT DEFAULT NULL,     -- JSON blob of EXIF fields
                    gps_lat     REAL,                  -- latitude extracted from EXIF (nullable)
                    gps_lon     REAL                  -- longitude extracted from EXIF (nullable)
                );

                CREATE INDEX IF NOT EXISTS idx_photos_created ON photos(created_at DESC);
                CREATE INDEX IF NOT EXISTS idx_photos_filename ON photos(filename);
                CREATE INDEX IF NOT EXISTS idx_photos_mime ON photos(mime_type);

                CREATE TABLE IF NOT EXISTS albums (
                    id          TEXT PRIMARY KEY,  -- UUID
                    name        TEXT NOT NULL,
                    description TEXT DEFAULT '',
                    created_at  TEXT NOT NULL,
                    updated_at  TEXT NOT NULL,
                    source      TEXT DEFAULT 'manual',  -- 'manual' | 'smart_collection' | 'imported'
                    folder      TEXT  -- optional: source folder path for import
                );

                CREATE TABLE IF NOT EXISTS album_photos (
                    album_id  TEXT,
                    photo_id  TEXT,
                    PRIMARY KEY (album_id, photo_id),
                    FOREIGN KEY (album_id) REFERENCES albums(id),
                    FOREIGN KEY (photo_id) REFERENCES photos(id)
                );

                CREATE INDEX IF NOT EXISTS idx_ap_photo ON album_photos(photo_id);

                CREATE TABLE IF NOT EXISTS tags (
                    photo_id  TEXT,
                    tag       TEXT,
                    PRIMARY KEY (photo_id, tag),
                    FOREIGN KEY (photo_id) REFERENCES photos(id)
                );

                -- Import tracking (for migration resume)
                CREATE TABLE IF NOT EXISTS import_log (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_dir  TEXT NOT NULL,
                    imported_at TEXT NOT NULL,
                    photos_imported INTEGER DEFAULT 0,
                    status      TEXT DEFAULT 'running',  -- 'running' | 'completed' | 'failed'
                    error       TEXT
                );

                -- Watch list
                CREATE TABLE IF NOT EXISTS watch_list (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    path        TEXT NOT NULL UNIQUE,
                    added_at    TEXT NOT NULL,
                    active      INTEGER DEFAULT 1  -- 1=active, 0=paused
                );

                -- Server settings (key-value store)
                CREATE TABLE IF NOT EXISTS server_settings (
                    key   TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                -- Smart album rule specification (JSON)
                -- (column added via migration; ignored on first run for v0.3.x)
                -- Column: rule_spec TEXT DEFAULT NULL on albums table
                -- If you get a "no such column: rule_spec" error, run once:
                --   ALTER TABLE albums ADD COLUMN rule_spec TEXT DEFAULT NULL;

                -- Content hashes for deduplication (new table)
                CREATE TABLE IF NOT EXISTS content_hashes (
                    photo_id TEXT PRIMARY KEY,
                    phash    TEXT NOT NULL,  -- 64-char hex perceptual hash
                    FOREIGN KEY (photo_id) REFERENCES photos(id)
                );

                -- Tag history (new table)
                CREATE TABLE IF NOT EXISTS tag_history (
                    id       INTEGER PRIMARY KEY AUTOINCREMENT,
                    photo_id TEXT NOT NULL,
                    tag      TEXT NOT NULL,
                    action   TEXT NOT NULL,  -- 'added' | 'removed'
                    by_user  TEXT DEFAULT 'system',
                    timestamp TEXT NOT NULL,
                    FOREIGN KEY (photo_id) REFERENCES photos(id)
                );

                -- Duplicate archive (new table)
                CREATE TABLE IF NOT EXISTS duplicates (
                    photo_id    TEXT,
                    archived_id TEXT PRIMARY KEY,  -- moved to .trash/
                    archive_path TEXT,
                    duplicate_of TEXT,  -- the kept photo_id
                    archived_at TEXT NOT NULL,
                    FOREIGN KEY (photo_id) REFERENCES photos(id),
                    FOREIGN KEY (duplicate_of) REFERENCES photos(id)
                );

                -- Indexes
                CREATE INDEX IF NOT EXISTS idx_ch_phash ON content_hashes(phash);
                CREATE INDEX IF NOT EXISTS idx_th_photo ON tag_history(photo_id);
                CREATE INDEX IF NOT EXISTS idx_photos_gps ON photos(gps_lat, gps_lon) WHERE gps_lat IS NOT NULL;
            """)

        # Migrations: safe no-ops if columns already exist
        migrations = [
            ("ALTER TABLE albums ADD COLUMN rule_spec TEXT DEFAULT NULL",
             "[db] Migration: added rule_spec column to albums"),
            ("ALTER TABLE photos ADD COLUMN exif TEXT DEFAULT NULL",
             "[db] Migration: added exif column to photos"),
            ("ALTER TABLE photos ADD COLUMN gps_lat REAL DEFAULT NULL",
             "[db] Migration: added gps_lat column to photos"),
            ("ALTER TABLE photos ADD COLUMN gps_lon REAL DEFAULT NULL",
             "[db] Migration: added gps_lon column to photos"),
        ]
        for sql, msg in migrations:
            try:
                with self._connect() as conn:
                    conn.execute(sql)
                    print(msg)
            except Exception:
                pass

    def get_photo(self, photo_id: str) -> dict:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM photos WHERE id = ?", (photo_id,)).fetchone()
            return dict(row) if row else None

    def _extend_query(self, query: str, album: str, tag: str,
                      q: str, camera: str, start_date: str, end_date: str,
                      params: list) -> tuple:
        """
        Enrich the base FROM / ORDER BY query with WHERE clauses derived from
        the optional filter parameters, returning (query, params).
        """
        conditions = []

        if album:
            conditions.append("ap.album_id = ?")
            params.append(album)
        if tag:
            conditions.append("t.tag = ?")
            params.append(tag)
        if q:
            conditions.append(
                "(p.filename LIKE ? OR t.tag LIKE ? OR p.filepath LIKE ?)"
            )
            term = f"%{q}%"
            params.extend([term, term, term])
        if camera:
            cond_cam = (
                "json_extract(p.exif, '$.make') LIKE ?"
                " OR json_extract(p.exif, '$.model') LIKE ?"
            )
            conditions.append(f"({cond_cam})")
            params.extend([f"%{camera}%", f"%{camera}%"])
        if start_date:
            conditions.append("p.created_at >= ?")
            params.append(start_date)
        if end_date:
            conditions.append("p.created_at <= ?")
            params.append(end_date)

        if conditions:
            query += " WHERE " + " AND ".join(conditions)

        return query, params

    def list_photos(self, album: str = None, tag: str = None,
                    q: str = None, camera: str = None,
                    start_date: str = None, end_date: str = None,
                    limit: int = 50, offset: int = 0) -> list:
        with self._connect() as conn:
            query = """
                SELECT DISTINCT p.* FROM photos p
                LEFT JOIN album_photos ap ON p.id = ap.photo_id
                LEFT JOIN tags t ON p.id = t.photo_id
            """
            params = []

            if album or tag or q or camera or start_date or end_date:
                query, params = self._extend_query(
                    query, album, tag, q, camera, start_date, end_date, params
                )

            query += " ORDER BY p.created_at DESC LIMIT ? OFFSET ?"
            params.extend([limit, offset])

            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    def count_photos(self, album: str = None, tag: str = None,
                     q: str = None, camera: str = None,
                     start_date: str = None, end_date: str = None) -> int:
        """Count photos matching the same filters used by list_photos."""
        with self._connect() as conn:
            query = """
                SELECT COUNT(DISTINCT p.id) AS cnt FROM photos p
                LEFT JOIN album_photos ap ON p.id = ap.photo_id
                LEFT JOIN tags t ON p.id = t.photo_id
            """
            params = []

            if album or tag or q or camera or start_date or end_date:
                query, params = self._extend_query(
                    query, album, tag, q, camera, start_date, end_date, params
                )

            row = conn.execute(query, params).fetchone()
            return int(row['cnt']) if row else 0

    def get_photo_count(self) -> int:
        with self._connect() as conn:
            return conn.execute("SELECT COUNT(*) as cnt FROM photos").fetchone()['cnt']

    def get_albums(self) -> list:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM albums ORDER BY name").fetchall()
            return [dict(row) for row in rows]

    def get_album(self, album_id: str) -> dict:
        with self._connect() as conn:
            album = conn.execute("SELECT * FROM albums WHERE id = ?", (album_id,)).fetchone()
            if not album:
                return None

            photos = conn.execute("""
                SELECT p.* FROM photos p
                JOIN album_photos ap ON p.id = ap.photo_id
                WHERE ap.album_id = ?
                ORDER BY p.created_at DESC
            """, (album_id,)).fetchall()

            result = dict(album)
            result['photos'] = [dict(p) for p in photos]
            return result

    def create_album(self, name: str, description: str = '',
                     source: str = 'manual', folder: str = None) -> str:
        import uuid
        now = datetime.now().isoformat()
        album_id = str(uuid.uuid4())

        with self._connect() as conn:
            conn.execute("""
                INSERT INTO albums (id, name, description, created_at, updated_at, source, folder)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (album_id, name, description, now, now, source, folder))

        return album_id

    def update_album(self, album_id: str, name: str = None,
                     description: str = None) -> bool:
        with self._connect() as conn:
            now = datetime.now().isoformat()
            changed = False
            if name:
                conn.execute("UPDATE albums SET name = ?, updated_at = ? WHERE id = ?",
                             (name, now, album_id))
                changed = True
            if description is not None:
                conn.execute("UPDATE albums SET description = ?, updated_at = ? WHERE id = ?",
                             (description, now, album_id))
                changed = True
            return conn.total_changes > 0

    def delete_album(self, album_id: str) -> bool:
        with self._connect() as conn:
            conn.execute("DELETE FROM album_photos WHERE album_id = ?", (album_id,))
            conn.execute("DELETE FROM albums WHERE id = ?", (album_id,))
            return conn.total_changes > 0

    def add_photo_to_album(self, album_id: str, photo_id: str):
        with self._connect() as conn:
            conn.execute("""
                INSERT OR IGNORE INTO album_photos (album_id, photo_id)
                VALUES (?, ?)
            """, (album_id, photo_id))

    def remove_photo_from_album(self, album_id: str, photo_id: str):
        with self._connect() as conn:
            conn.execute("""
                DELETE FROM album_photos WHERE album_id = ? AND photo_id = ?
            """, (album_id, photo_id))

    def get_tags(self, photo_id: str) -> list:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT tag FROM tags WHERE photo_id = ?", (photo_id,)
            ).fetchall()
            return [row['tag'] for row in rows]

    def add_tag(self, photo_id: str, tag: str):
        with self._connect() as conn:
            conn.execute(
                "INSERT OR IGNORE INTO tags (photo_id, tag) VALUES (?, ?)",
                (photo_id, tag)
            )

    def delete_tag(self, photo_id: str, tag: str):
        """Remove a specific tag from a photo."""
        with self._connect() as conn:
            conn.execute(
                "DELETE FROM tags WHERE photo_id = ? AND tag = ?",
                (photo_id, tag)
            )

    def search_photos(self, query: str, limit: int = 50) -> list:
        with self._connect() as conn:
            search_term = f"%{query}%"
            rows = conn.execute("""
                SELECT DISTINCT p.* FROM photos p
                LEFT JOIN tags t ON p.id = t.photo_id
                WHERE p.filename LIKE ? OR t.tag LIKE ? OR p.filepath LIKE ?
                ORDER BY p.created_at DESC
                LIMIT ?
            """, (search_term, search_term, search_term, limit)).fetchall()
            return [dict(row) for row in rows]

    def store_photo(self, photo: dict):
        """Store or update a photo in the database."""
        exif_val = photo.get('exif')
        exif_json = json.dumps(exif_val) if exif_val else None
        gps_lat = photo.get('gps_lat')  # top-level extracted from EXIF
        gps_lon = photo.get('gps_lon')

        with self._connect() as conn:
            conn.execute("""
                INSERT INTO photos (id, filename, filepath, file_size, width, height,
                                   mime_type, created_at, indexed_at, has_thumbnail,
                                   is_favorite, color_tag, is_source_jpeg, exif,
                                   gps_lat, gps_lon)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(filepath) DO UPDATE SET
                    file_size = excluded.file_size,
                    -- RAW re-imports report NULL dims (unknown until decode);
                    -- keep any dimensions we already resolved.
                    width = COALESCE(excluded.width, photos.width),
                    height = COALESCE(excluded.height, photos.height),
                    mime_type = excluded.mime_type,
                    created_at = excluded.created_at,
                    indexed_at = excluded.indexed_at,
                    has_thumbnail = CASE
                        WHEN excluded.has_thumbnail = 1 OR photos.has_thumbnail = 1 THEN 1
                        ELSE 0
                    END,
                    is_favorite = excluded.is_favorite,
                    color_tag = excluded.color_tag,
                    is_source_jpeg = excluded.is_source_jpeg,
                    exif = excluded.exif,
                    gps_lat = excluded.gps_lat,
                    gps_lon = excluded.gps_lon
            """, (
                photo['id'], photo['filename'], photo['filepath'],
                photo.get('file_size'), photo.get('width'), photo.get('height'),
                photo.get('mime_type'), photo.get('created_at'),
                photo.get('indexed_at', datetime.now().isoformat()),
                1 if photo.get('has_thumbnail') else 0,
                1 if photo.get('is_favorite') else 0,
                photo.get('color_tag', 'none'),
                1 if photo.get('is_source_jpeg') else 0,
                exif_json,
                gps_lat, gps_lon,
            ))

    def mark_thumbnail(self, photo_id: str, has_thumbnail: bool = True):
        with self._connect() as conn:
            conn.execute(
                "UPDATE photos SET has_thumbnail = ? WHERE id = ?",
                (1 if has_thumbnail else 0, photo_id)
            )

    def set_favorite(self, photo_id: str, is_favorite: bool = True):
        with self._connect() as conn:
            conn.execute(
                "UPDATE photos SET is_favorite = ? WHERE id = ?",
                (1 if is_favorite else 0, photo_id)
            )

    def get_import_log(self) -> list:
        with self._connect() as conn:
            return [dict(row) for row in
                   conn.execute("SELECT * FROM import_log ORDER BY imported_at DESC").fetchall()]

    def log_import(self, source_dir: str, status: str = 'running',
                   photos_imported: int = 0, error: str = None):
        with self._connect() as conn:
            conn.execute("""
                INSERT INTO import_log (source_dir, imported_at, photos_imported, status, error)
                VALUES (?, ?, ?, ?, ?)
            """, (source_dir, datetime.now().isoformat(), photos_imported, status, error))

    # ==================== Watch List ============================================

    def get_watch_list(self) -> list:
        """Return all watch directories."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM watch_list ORDER BY path"
            ).fetchall()
            return [dict(row) for row in rows]

    def add_watch_dir(self, path: str) -> bool:
        """Add a directory to the watch list."""
        normalized = str(Path(path).resolve())
        now = datetime.now().isoformat()
        try:
            with self._connect() as conn:
                conn.execute("""
                    INSERT INTO watch_list (path, added_at, active)
                    VALUES (?, ?, 1)
                """, (normalized, now))
            return True
        except sqlite3.IntegrityError:
            return False  # Already exists

    def update_watch_dir(self, path: str, new_path: str, active: bool = None):
        """Update a watch directory path and optionally its active state."""
        normalized = str(Path(path).resolve())
        new_normalized = str(Path(new_path).resolve())
        fields = ["path = ?"]
        params = [new_normalized]
        if active is not None:
            fields.append("active = ?")
            params.append(1 if active else 0)
        params.append(normalized)

        try:
            with self._connect() as conn:
                result = conn.execute(
                    f"UPDATE watch_list SET {', '.join(fields)} WHERE path = ?",
                    params,
                ).rowcount
            return result > 0
        except sqlite3.IntegrityError:
            return None  # New path already exists

    def remove_watch_dir(self, path: str) -> bool:
        """Remove a directory from the watch list."""
        normalized = str(Path(path).resolve())
        with self._connect() as conn:
            result = conn.execute(
                "DELETE FROM watch_list WHERE path = ?", (normalized,)
            ).rowcount
        return result > 0

    # ── photo pruning / directory sync ────────────────────────────────────────
    # Photos have child rows in album_photos / tags / tag_history /
    # content_hashes / duplicates. Those FKs have no ON DELETE CASCADE and
    # foreign_keys=ON, so children must be deleted before the photo row.
    _CHILD_TABLES = ("album_photos", "tags", "tag_history", "content_hashes")

    @staticmethod
    def _norm(path: str) -> str:
        """Absolute, symlink-resolved path — the one normalization used by all
        directory-boundary logic so it is defined once, not duplicated."""
        return str(Path(path).resolve())

    @staticmethod
    def _is_under(filepath: str, directory: str) -> bool:
        """True if filepath is `directory` itself or lives beneath it, using an
        os.sep boundary so '/a/App Store' does not match '/a/App Store Connect'."""
        return filepath == directory or filepath.startswith(directory + os.sep)

    def _delete_photo_ids(self, conn, ids: list) -> int:
        """Delete photo rows and their children within an existing connection."""
        if not ids:
            return 0
        marks = ",".join("?" * len(ids))
        for table in self._CHILD_TABLES:
            conn.execute(f"DELETE FROM {table} WHERE photo_id IN ({marks})", ids)
        # duplicates references photos twice (the archived row and its keeper).
        conn.execute(
            f"DELETE FROM duplicates WHERE photo_id IN ({marks}) "
            f"OR duplicate_of IN ({marks})", ids + ids,
        )
        return conn.execute(
            f"DELETE FROM photos WHERE id IN ({marks})", ids
        ).rowcount

    def delete_photos_under(self, prefix: str) -> int:
        """Delete every photo whose filepath is `prefix` or lives beneath it,
        along with its child rows. Returns the number of photos removed."""
        directory = self._norm(prefix)
        with self._connect() as conn:
            ids = [
                row[0] for row in conn.execute("SELECT id, filepath FROM photos")
                if self._is_under(row[1], directory)
            ]
            return self._delete_photo_ids(conn, ids)

    def prune_orphans(self, active_dirs: list) -> dict:
        """Reconcile the library against the active watch dirs. Removes photos
        that are (a) no longer under any active watch dir, or (b) whose source
        file is gone — BUT only prunes 'missing' files under watch roots that are
        currently accessible, so an unmounted drive can't wipe the library.

        Returns {removed_untracked, removed_missing, skipped_roots}.
        """
        active = [self._norm(d) for d in active_dirs]
        # A root counts as accessible only if it exists AND has at least one
        # entry — an unmounted /Volumes/X is either absent or an empty stub.
        accessible = {}
        for d in active:
            try:
                accessible[d] = os.path.isdir(d) and any(os.scandir(d))
            except OSError:
                accessible[d] = False

        untracked, missing, skipped = [], [], set()
        with self._connect() as conn:
            for pid, fp in conn.execute("SELECT id, filepath FROM photos"):
                root = next((d for d in active if self._is_under(fp, d)), None)
                if root is None:
                    untracked.append(pid)
                elif not os.path.exists(fp):
                    if accessible.get(root):
                        missing.append(pid)
                    else:
                        skipped.add(root)
            removed_untracked = self._delete_photo_ids(conn, untracked)
            removed_missing = self._delete_photo_ids(conn, missing)
        return {
            "removed_untracked": removed_untracked,
            "removed_missing": removed_missing,
            "skipped_roots": sorted(skipped),
        }

    def set_watch_active(self, path: str, active: bool) -> bool:
        """Enable/disable a watch directory."""
        normalized = str(Path(path).resolve())
        with self._connect() as conn:
            result = conn.execute(
                "UPDATE watch_list SET active = ? WHERE path = ?",
                (1 if active else 0, normalized)
            ).rowcount
        return result > 0

    def scan_all_watch_dirs(self, recursive: bool = True, image_extensions: tuple = None) -> list:
        """Scan all active watch directories for supported image files."""
        from .scanner import DirectoryScanner

        if image_extensions is None:
            image_extensions = (
                ".jpg", ".jpeg", ".png", ".heic", ".heif",
                ".arw", ".cr2", ".nef", ".orf", ".raf", ".pef", ".dng"
            )

        all_photos = []
        watch_dirs = self.get_watch_list()

        for entry in watch_dirs:
            if not entry['active']:
                continue
            s = DirectoryScanner(entry['path'], image_extensions)
            photos = s.scan(recursive=recursive)
            all_photos.extend(photos)

        return all_photos

    # ==================== Settings =============================================

    def get_setting(self, key: str) -> str:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT value FROM server_settings WHERE key = ?", (key,)
            ).fetchone()
            return row['value'] if row else None

    def set_setting(self, key: str, value: str):
        with self._connect() as conn:
            conn.execute("""
                INSERT OR REPLACE INTO server_settings (key, value)
                VALUES (?, ?)
            """, (key, value))

    # ==================== Smart Albums ===========================================

    def get_smart_collections(self) -> list:
        """Return all smart albums (source='smart_collection')."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM albums WHERE source = 'smart_collection' ORDER BY name"
            ).fetchall()
            return [dict(row) for row in rows]

    def update_album_rule(self, album_id: str, rule_spec: str) -> bool:
        """Update the rule spec for a smart album."""
        with self._connect() as conn:
            result = conn.execute(
                "UPDATE albums SET rule_spec = ?, updated_at = ? WHERE id = ? AND source = 'smart_collection'",
                (rule_spec, datetime.now().isoformat(), album_id)
            ).rowcount
            return result > 0

    def update_album_photos_for_smart(self, album_id: str, photo_ids: list) -> int:
        """Replace all photos in a smart album with new photo_ids."""
        with self._connect() as conn:
            # Clear existing
            conn.execute("DELETE FROM album_photos WHERE album_id = ?", (album_id,))
            # Insert new
            for pid in photo_ids:
                conn.execute(
                    "INSERT OR IGNORE INTO album_photos (album_id, photo_id) VALUES (?, ?)",
                    (album_id, pid)
                )
            return len(photo_ids)

    def re_evaluate_smart_album(self, album_id: str) -> list:
        """Get photo IDs that match a smart album's rules."""
        import json
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM albums WHERE id = ? AND source = 'smart_collection'", (album_id,)
            ).fetchone()
        if not row:
            return []
        album = dict(row)
        if not album.get('rule_spec'):
            return []
        return self._evaluate_rules(json.loads(album['rule_spec']), album.get('max_photos', 1000))

    def _evaluate_rules(self, rules: dict, max_photos: int = 1000) -> list:
        """Evaluate rule spec and return matching photo IDs."""
        query = """
            SELECT DISTINCT p.id FROM photos p
            LEFT JOIN tags t ON p.id = t.photo_id
        """
        conditions = []
        params = []

        rule_specs = rules.get('rules', [])
        for rule in rule_specs:
            field = rule.get('field')
            op = rule.get('op', 'contains')
            value = rule.get('value')

            if not field or value is None:
                continue

            if field == 'camera':
                if op == 'equals':
                    cond = (
                        f"json_extract(p.exif, '$.make') = ?"
                        f" OR json_extract(p.exif, '$.model') = ?"
                    )
                    params.extend([value, value])
                else:
                    cond = (
                        f"json_extract(p.exif, '$.make') LIKE ?"
                        f" OR json_extract(p.exif, '$.model') LIKE ?"
                    )
                    params.extend([f'%{value}%', f'%{value}%'])
                conditions.append(cond)

            elif field == 'date_after':
                conditions.append("p.created_at >= ?")
                params.append(value)
            elif field == 'date_before':
                conditions.append("p.created_at <= ?")
                params.append(value)
            elif field == 'date_range':
                conditions.append("p.created_at >= ?")
                params.append(value.get('start', ''))
                conditions.append("p.created_at <= ?")
                params.append(value.get('end', ''))
            elif field == 'tag':
                if op == 'has':
                    conditions.append("t.tag = ?")
                    params.append(value)
                elif op == 'has_any':
                    tags = value if isinstance(value, list) else [value]
                    tag_conditions = " OR ".join(["t.tag = ?"] * len(tags))
                    conditions.append(f"({tag_conditions})")
                    params.extend(tags)
            elif field == 'keyword':
                conditions.append("p.filename LIKE ?")
                params.append(f'%{value}%')
            elif field == 'is_favorite':
                if value:
                    conditions.append("p.is_favorite = 1")

        if conditions:
            query += " WHERE " + " AND ".join(conditions)

        query += " ORDER BY p.created_at DESC LIMIT ?"
        params.append(max_photos)

        with self._connect() as conn:
            rows = conn.execute(query, params).fetchall()
        return [row['id'] for row in rows]

    # ==================== Deduplication ==========================================

    def get_content_hashes(self) -> list:
        """Get all content hashes."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT ch.photo_id, ch.phash, p.filename, p.filepath "
                "FROM content_hashes ch JOIN photos p ON ch.photo_id = p.id"
            ).fetchall()
            return [dict(row) for row in rows]

    def store_content_hash(self, photo_id: str, phash: str):
        """Store or update a content hash for a photo."""
        with self._connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO content_hashes (photo_id, phash) VALUES (?, ?)",
                (photo_id, phash)
            )

    def find_duplicate_groups(self, tolerance: int) -> list:
        """Find groups of photos with similar perceptual hashes."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT ch.photo_id, ch.phash, p.filename, p.filepath "
                "FROM content_hashes ch JOIN photos p ON ch.photo_id = p.id"
            ).fetchall()
            hashes = [dict(row) for row in rows]

            # Group by hamming distance
            groups = []
            seen = set()
            for i, h1 in enumerate(hashes):
                if h1['photo_id'] in seen:
                    continue
                group = [h1]
                seen.add(h1['photo_id'])
                for j, h2 in enumerate(hashes):
                    if i == j or h2['photo_id'] in seen:
                        continue
                    dist = self._hamming_distance(h1['phash'], h2['phash'])
                    if dist <= tolerance:
                        group.append(h2)
                        seen.add(h2['photo_id'])
                if len(group) > 1:
                    groups.append(group)
            return groups

    def _hamming_distance(self, s1: str, s2: str) -> int:
        """Calculate Hamming distance between two hex strings."""
        a, b = int(s1, 16), int(s2, 16)
        xor = a ^ b
        return bin(xor).count('1')

    # ==================== Tag History ===========================================

    def add_tag_history(self, photo_id: str, tag: str, action: str, by_user: str = 'system'):
        """Record a tag change."""
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO tag_history (photo_id, tag, action, by_user, timestamp) VALUES (?, ?, ?, ?, ?)",
                (photo_id, tag, action, by_user, datetime.now().isoformat())
            )

    def get_tag_history(self, photo_id: str) -> list:
        """Get tag change history for a photo."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM tag_history WHERE photo_id = ? ORDER BY timestamp DESC", (photo_id,)
            ).fetchall()
            return [dict(row) for row in rows]

    def get_duplicate_tag_suggestions(self) -> list:
        """Find tags that differ only in case or whitespace."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT LOWER(TRIM(tag)) as normal, tag, COUNT(*) as c "
                "FROM tags GROUP BY LOWER(TRIM(tag)) HAVING c > 1"
            ).fetchall()
            return [dict(row) for row in rows]

    def get_duplicate_groups(self) -> list:
        """Get archived duplicates."""
        with self._connect() as conn:
            rows = conn.execute(
                """SELECT d.*, p.filename FROM duplicates d
                   JOIN photos p ON d.archived_id = p.id"""
            ).fetchall()
            return [dict(row) for row in rows]

    # ==================== Geospatial Query ========================================

    def geo_query(self, lat: float, lon: float, radius_km: float,
                  limit: int = 50, offset: int = 0) -> list:
        """Return photos within radius_km of (lat, lon) using haversine distance.

        Requires gps_lat AND gps_lon to be NOT NULL.
        Uses a subquery to avoid SQLite's restriction on HAVING for non-aggregate queries.
        """
        with self._connect() as conn:
            rows = conn.execute("""
                SELECT * FROM (
                    SELECT p.*,
                           6371.0 * acos(
                               cos(radians(?)) * cos(radians(p.gps_lat)) *
                               cos(radians(p.gps_lon) - radians(?)) +
                               sin(radians(?)) * sin(radians(p.gps_lat))
                           ) AS distance_km
                      FROM photos p
                     WHERE p.gps_lat IS NOT NULL
                       AND p.gps_lon IS NOT NULL
                )
                     WHERE distance_km <= ?
                     ORDER BY distance_km ASC
                     LIMIT ? OFFSET ?
            """, (lat, lon, lat, radius_km, limit, offset)).fetchall()
            result = [dict(row) for row in rows]
            # Round distance to 2 decimal places
            for r in result:
                r['distance_km'] = round(r['distance_km'], 2)
            return result
