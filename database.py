"""Local Photo Library Server — Database"""
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
                    is_source_jpeg INTEGER DEFAULT 0  -- 1 if this is a converted/sidecar JPEG
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
                
                -- Watch list (folders the server monitors)
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
            """)
    
    def get_photo(self, photo_id: str) -> dict:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM photos WHERE id = ?", (photo_id,)).fetchone()
            return dict(row) if row else None
    
    def list_photos(self, album: str = None, tag: str = None, 
                   limit: int = 50, offset: int = 0) -> list:
        with self._connect() as conn:
            query = """
                SELECT p.* FROM photos p
                LEFT JOIN album_photos ap ON p.id = ap.photo_id
                LEFT JOIN tags t ON p.id = t.photo_id
            """
            params = []
            conditions = []
            
            if album:
                conditions.append("ap.album_id = ?")
                params.append(album)
            if tag:
                conditions.append("t.tag = ?")
                params.append(tag)
            
            if conditions:
                query += " WHERE " + " AND ".join(conditions)
            
            query += " ORDER BY p.created_at DESC LIMIT ? OFFSET ?"
            params.extend([limit, offset])
            
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]
    
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
            
            if name:
                conn.execute("UPDATE albums SET name = ?, updated_at = ? WHERE id = ?", 
                           (name, now, album_id))
            if description is not None:
                conn.execute("UPDATE albums SET description = ?, updated_at = ? WHERE id = ?", 
                           (description, now, album_id))
            
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
        with self._connect() as conn:
            conn.execute("""
                INSERT INTO photos (id, filename, filepath, file_size, width, height, 
                                   mime_type, created_at, indexed_at, has_thumbnail, 
                                   is_favorite, color_tag, is_source_jpeg)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(filepath) DO UPDATE SET
                    file_size = excluded.file_size,
                    width = excluded.width,
                    height = excluded.height,
                    mime_type = excluded.mime_type,
                    created_at = excluded.created_at,
                    indexed_at = excluded.indexed_at,
                    has_thumbnail = excluded.has_thumbnail,
                    is_favorite = excluded.is_favorite,
                    color_tag = excluded.color_tag,
                    is_source_jpeg = excluded.is_source_jpeg
            """, (
                photo['id'], photo['filename'], photo['filepath'],
                photo.get('file_size'), photo.get('width'), photo.get('height'),
                photo.get('mime_type'), photo.get('created_at'),
                photo.get('indexed_at', datetime.now().isoformat()),
                1 if photo.get('has_thumbnail') else 0,
                1 if photo.get('is_favorite') else 0,
                photo.get('color_tag', 'none'),
                1 if photo.get('is_source_jpeg') else 0
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
    
    # ==================== Watch List ====================
    
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
    
    def remove_watch_dir(self, path: str) -> bool:
        """Remove a directory from the watch list."""
        normalized = str(Path(path).resolve())
        with self._connect() as conn:
            result = conn.execute(
                "DELETE FROM watch_list WHERE path = ?", (normalized,)
            ).rowcount
        return result > 0
    
    def set_watch_active(self, path: str, active: bool) -> bool:
        """Enable/disable a watch directory."""
        normalized = str(Path(path).resolve())
        with self._connect() as conn:
            result = conn.execute(
                "UPDATE watch_list SET active = ? WHERE path = ?",
                (1 if active else 0, normalized)
            ).rowcount
        return result > 0
    
    def scan_all_watch_dirs(self, recursive: bool = True) -> list:
        """Scan all watch directories for images."""
        from scanner import DirectoryScanner
        all_photos = []
        watch_dirs = self.get_watch_list()
        
        for entry in watch_dirs:
            if not entry['active']:
                continue
            s = DirectoryScanner(entry['path'], ())  # scan everything, extensions filtered later
            photos = s.scan(recursive=recursive)
            all_photos.extend(photos)
        
        return all_photos
    
    # ==================== Settings ====================
    
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
