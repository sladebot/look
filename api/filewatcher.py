"""File watcher — monitors watch directories and auto-imports new photos."""
import os
import time
import threading
from pathlib import Path
from typing import Optional, Callable

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler, FileCreatedEvent, FileModifiedEvent
from .scanner import DirectoryScanner, EXCLUDED_DIRS


class PhotoImportHandler(FileSystemEventHandler):
    """Watch for new/modified image files and queue them for import."""

    def __init__(self, config, processor, scanner, db, callback: Optional[Callable] = None):
        self.config = config
        self.processor = processor
        self.scanner = scanner
        self.db = db
        self.callback = callback
        # Map of absolute-path → (mtime, queued-flag) to avoid duplicate imports
        self._pending: dict = {}
        self._lock = threading.Lock()

        # Supported extensions
        self._image_extensions = config.image_extensions
        self._cooldown_s = int(getattr(config, 'filewatcher_cooldown', '3'))

    def on_created(self, event):
        self._maybe_import(event.dest_path if isinstance(event, FileModifiedEvent) else event.src_path)

    def on_modified(self, event):
        self._maybe_import(event.dest_path if isinstance(event, FileModifiedEvent) else event.src_path)

    def _maybe_import(self, path: str):
        """Debounce: only import after cooldown to avoid in-progress writes."""
        resolved = Path(path).resolve()
        path = str(resolved)
        if resolved.name.startswith('._') or '.tmp.' in resolved.name:
            return
        if any(part in EXCLUDED_DIRS for part in resolved.parts):
            return
        ext = resolved.suffix.lower()
        if ext not in self._image_extensions:
            return
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            return

        now = time.time()
        with self._lock:
            previous = self._pending.get(path)
            if previous is None or (now - previous) >= self._cooldown_s:
                self._pending[path] = now
            else:
                return  # still cooling down

        # Run import in daemon thread (doesn't block watchdog)
        threading.Thread(
            target=self._import_file, args=(path, mtime),
            daemon=True, name=f"filewatcher-{Path(path).name}"
        ).start()

    def _import_file(self, path: str, mtime: float):
        """Actually import a single file into the database."""
        try:
            proc_result = self.processor.process(path)
            if not proc_result:
                return

            # Find sidecar JPEG for RAW files
            if self.scanner.find_sidecar_jpeg(Path(path)):
                path = str(self.scanner.find_sidecar_jpeg(Path(path)))

            photo_meta = {
                'id': self.scanner._hash_filepath(path),
                'filename': Path(path).name,
                'filepath': path,
                'file_size': os.path.getsize(path),
                'has_thumbnail': False,
                'is_favorite': False,
                'color_tag': 'none',
                'is_source_jpeg': 0,
                'created_at': time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(mtime)),
                'indexed_at': time.strftime('%Y-%m-%dT%H:%M:%S'),
                'width': proc_result.get('width'),
                'height': proc_result.get('height'),
                'mime_type': proc_result.get('mime_type'),
            }

            self.db.store_photo(photo_meta)
            thumb_path = proc_result.get('thumb_path')
            if thumb_path and os.path.exists(thumb_path):
                self.db.mark_thumbnail(photo_meta['id'], True)

            if self.callback:
                self.callback(photo_meta)
        except Exception as exc:
            print(f"[filewatcher] ERROR importing {path}: {exc}")


class FileWatcherManager:
    """Manages one Observer per watched directory."""

    def __init__(self, config, processor, scanner, db, callback=None):
        self.config = config
        self.processor = processor
        self.scanner = scanner
        self.db = db
        self.callback = callback
        self._observer: Optional[Observer] = None
        self._handlers: dict = {}  # path → handler

    def start(self) -> bool:
        """Start watching all active watch directories."""
        try:
            self._observer = Observer()
            watch_list = self.db.get_watch_list()
            for entry in watch_list:
                if not entry.get('active', True):
                    continue
                directory = str(entry['path'])
                handler = PhotoImportHandler(
                    self.config, self.processor,
                    DirectoryScanner(directory, self.config.image_extensions),
                    self.db, self.callback
                )
                self._observer.schedule(handler, directory, recursive=True)
                self._handlers[directory] = handler
            self._observer.start()
            return True
        except Exception as exc:
            print(f"[filewatcher] ERROR starting watcher: {exc}")
            return False

    def stop(self):
        """Stop all watchers."""
        if self._observer:
            self._observer.stop()
            self._observer.join(timeout=5)
            self._observer = None
        self._handlers.clear()

    def is_running(self) -> bool:
        return self._observer is not None and self._observer.is_alive()

    @staticmethod
    def add_watch_directory(config, db, path: str):
        """Programmatically add a new watch directory to the live watcher."""
        db.add_watch_dir(path)
