import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from database import PhotoDatabase


class WatchDirectoryScanTests(unittest.TestCase):
    def test_scan_all_watch_dirs_uses_supported_image_extensions(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            photos_dir = root / "photos"
            photos_dir.mkdir()
            (photos_dir / "sample.jpg").write_bytes(b"not really a jpeg, scan only checks extension")
            (photos_dir / "notes.txt").write_text("ignore me")

            db = PhotoDatabase(str(root / "library.db"))
            self.assertTrue(db.add_watch_dir(str(photos_dir)))

            photos = db.scan_all_watch_dirs()

            self.assertEqual(len(photos), 1)
            self.assertEqual(photos[0]["filename"], "sample.jpg")

    def test_scan_all_watch_dirs_skips_inactive_directories(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            photos_dir = root / "photos"
            photos_dir.mkdir()
            (photos_dir / "sample.jpg").write_bytes(b"scan only checks extension")

            db = PhotoDatabase(str(root / "library.db"))
            self.assertTrue(db.add_watch_dir(str(photos_dir)))
            self.assertTrue(db.set_watch_active(str(photos_dir), False))

            self.assertEqual(db.scan_all_watch_dirs(), [])


if __name__ == "__main__":
    unittest.main()
