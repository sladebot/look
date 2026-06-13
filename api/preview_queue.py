"""Priority preview generation queue for thumbnails and RAW JPEG previews."""
import os
import queue
import threading
from pathlib import Path
from typing import Optional


class PreviewQueue:
    """Small bounded worker pool for non-blocking preview generation."""

    def __init__(self, config, processor, decoder, scanner, db):
        self.config = config
        self.processor = processor
        self.decoder = decoder
        self.scanner = scanner
        self.db = db
        self._queue = queue.PriorityQueue()
        self._queued = set()
        self._lock = threading.Lock()
        self._seq = 0
        self._stop = threading.Event()
        workers = max(1, min(int(getattr(config, "preview_workers", 4)), 8))
        self._workers = [
            threading.Thread(target=self._worker, daemon=True, name=f"preview-{idx}")
            for idx in range(workers)
        ]

    def start(self):
        for worker in self._workers:
            if not worker.is_alive():
                worker.start()

    def stop(self):
        self._stop.set()
        for _ in self._workers:
            self._queue.put((999999, self._next_seq(), "stop", "", "", 0))
        for worker in self._workers:
            worker.join(timeout=2)

    def enqueue_thumbnail(self, photo_id: str, filepath: str, size: int, priority: int = 50):
        self._enqueue("thumbnail", photo_id, filepath, size, priority)

    def enqueue_full(self, photo_id: str, filepath: str, priority: int = 80):
        self._enqueue("full", photo_id, filepath, 0, priority)

    def _enqueue(self, kind: str, photo_id: str, filepath: str, size: int, priority: int):
        key = (kind, photo_id, size)
        with self._lock:
            if key in self._queued:
                return
            self._queued.add(key)
            seq = self._next_seq()
        self._queue.put((priority, seq, kind, photo_id, filepath, size))

    def _next_seq(self) -> int:
        self._seq += 1
        return self._seq

    def _worker(self):
        while not self._stop.is_set():
            priority, seq, kind, photo_id, filepath, size = self._queue.get()
            key = (kind, photo_id, size)
            try:
                if kind == "stop":
                    return
                if kind == "thumbnail":
                    self._generate_thumbnail(photo_id, filepath, size)
                elif kind == "full":
                    self._resolve_preview(filepath)
            except Exception as exc:
                print(f"[preview] ERROR {kind} {filepath}: {exc}")
            finally:
                with self._lock:
                    self._queued.discard(key)
                self._queue.task_done()

    def _generate_thumbnail(self, photo_id: str, filepath: str, size: int):
        preview_path = self._resolve_preview(filepath)
        if not preview_path:
            return
        thumb_path = self.processor.get_thumbnail(preview_path, size)
        if thumb_path and os.path.exists(thumb_path):
            self.db.mark_thumbnail(photo_id, True)

    def _resolve_preview(self, filepath: str) -> Optional[str]:
        source = Path(filepath)
        if source.suffix.lower() in self.decoder.raw_extensions:
            sidecar = self.scanner.find_sidecar_jpeg(source)
            if sidecar:
                return str(sidecar)
            return self.decoder.decode(filepath, quiet=True)
        if source.exists():
            return filepath
        return None
