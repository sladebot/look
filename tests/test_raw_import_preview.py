import importlib
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory


class RawImportPreviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.photo_dir = self.root / "photos"
        self.photo_dir.mkdir()
        self.old_env = {key: os.environ.get(key) for key in ("DB_PATH", "PHOTO_DIR")}
        os.environ["DB_PATH"] = str(self.root / "library.db")
        os.environ["PHOTO_DIR"] = str(self.photo_dir)
        self.server = importlib.import_module("api.server")
        for name in (
            "config", "db", "scanner", "processor", "decoder", "smart_albums",
            "dedup", "tags_manager", "task_queue", "preview_queue",
            "rate_limiter", "migrator",
        ):
            setattr(self.server, name, None)
        self.server._ensure_runtime()

    def tearDown(self):
        for name in (
            "config", "db", "scanner", "processor", "decoder", "smart_albums",
            "dedup", "tags_manager", "task_queue", "preview_queue",
            "rate_limiter", "migrator",
        ):
            setattr(self.server, name, None)
        for key, value in self.old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.tmp.cleanup()

    def test_raw_import_uses_sidecar_metadata_and_existing_preview_thumbnail(self):
        raw_path = self.root / "DSC0001.ARW"
        raw_path.write_bytes(b"raw placeholder")
        sidecar_path = self.root / "DSC0001.jpg"
        sidecar_path.write_bytes(b"sidecar jpeg")
        thumb_path = self.photo_dir / ".thumbnails" / "thumb.jpg"

        class FakeDecoder:
            raw_extensions = (".arw",)

            def get_converted_path(self, path):
                return str(Path(path).with_suffix(".converted.jpg"))

        class FakeProcessor:
            def process(self, path):
                suffix = Path(path).suffix.lower()
                if suffix == ".arw":
                    return {
                        "width": None,
                        "height": None,
                        "mime_type": "image/x-raw",
                        "exif": {},
                        "thumb_path": None,
                        "has_thumbnail": False,
                        "is_raw": True,
                    }
                return {
                    "width": 6000,
                    "height": 4000,
                    "mime_type": "image/jpeg",
                    "exif": {},
                    "thumb_path": str(thumb_path),
                    "has_thumbnail": False,
                }

            def find_existing_thumbnail(self, path, width):
                if Path(path) == sidecar_path:
                    thumb_path.parent.mkdir(parents=True, exist_ok=True)
                    thumb_path.write_bytes(b"thumbnail")
                    return str(thumb_path)
                return None

            def get_thumbnail(self, path, width):
                return str(thumb_path)

        class FakeScanner:
            def find_sidecar_jpeg(self, path):
                return sidecar_path

        fake_decoder = FakeDecoder()
        self.server.decoder = fake_decoder
        self.server.processor = FakeProcessor()
        self.server.scanner = FakeScanner()

        photo_meta = {
            "id": "raw-id",
            "filename": raw_path.name,
            "filepath": str(raw_path),
            "file_size": raw_path.stat().st_size,
            "indexed_at": "2026-01-01T00:00:00",
            "created_at": "2026-01-01T00:00:00",
            "has_thumbnail": False,
            "is_favorite": False,
            "color_tag": "none",
            "is_source_jpeg": False,
        }

        result = self.server._prepare_photo_for_import(photo_meta, FakeScanner())

        self.assertEqual(result["filepath"], str(raw_path))
        self.assertEqual(result["mime_type"], "image/x-raw")
        self.assertEqual(result["width"], 6000)
        self.assertEqual(result["height"], 4000)
        self.assertTrue(result["has_thumbnail"])
        self.assertTrue(thumb_path.exists())


if __name__ == "__main__":
    unittest.main()
