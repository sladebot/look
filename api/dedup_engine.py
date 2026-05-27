"""Deduplication Engine — perceptual hashing for duplicate photo detection."""
import math
import os
import shutil
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict
from PIL import Image


class DedupEngine:
    """Detect and merge duplicate photos using perceptual hashing."""

    TRASH_DIR = '.trash'  # Relative to photo_dir

    def __init__(self, db, config, processor=None):
        self.db = db
        self.config = config
        self.processor = processor
        self.photo_dir = Path(config.photo_dir)
        self.trash_dir = self.photo_dir / self.TRASH_DIR
        self.duplicate_groups = []  # Cache from last scan

    def compute_phash(self, filepath: str) -> str:
        """Compute perceptual hash (pHash) of an image.

        Uses a 16x16 DCT-based hash → 64-char hex string.
        """
        try:
            with Image.open(filepath) as img:
                # Convert to grayscale and resize to 16x16
                gray = img.convert('L').resize((16, 16), Image.LANCZOS)

                # Compute DCT (first 8x8 coefficients)
                arr = list(gray.getdata())
                dct_coeffs = self._dct_2d(arr)

                # Median of DCT coefficients (excluding DC)
                coeffs = [c for i, c in enumerate(dct_coeffs) if i != 0]
                median = sorted(coeffs)[len(coeffs) // 2]

                # Generate hash bits
                hash_bits = []
                for c in dct_coeffs:
                    hash_bits.append(1 if c > median else 0)

                # Convert to hex
                hash_hex = ''
                for i in range(0, 128, 4):
                    nibble = 0
                    for j in range(4):
                        nibble = (nibble << 1) | hash_bits[i + j]
                    hash_hex += format(nibble, 'x')

                return hash_hex
        except Exception as e:
            print(f"[dedup] ERROR computing pHash for {filepath}: {e}")
            return None

    def _dct_2d(self, pixels: list) -> list:
        """Compute 2D DCT coefficients for a 16x16 image."""
        import math
        grid = [pixels[i * 16:(i + 1) * 16] for i in range(16)]
        coeffs = [[0.0] * 8 for _ in range(8)]
        for u in range(8):
            for v in range(8):
                total = 0.0
                for x in range(16):
                    for y in range(16):
                        total += grid[x][y] * math.cos((2 * x + 1) * u * math.pi / 32.0) * math.cos((2 * y + 1) * v * math.pi / 32.0)
                coeffs[u][v] = total * 2.0 / 16.0
        return [c for row in coeffs for c in row]

    def scan(self) -> List[Dict]:
        """Scan all photos for content-based duplicates.

        Returns:
            List of duplicate groups, each containing matching photo info.
        """
        # Get all photos
        all_photos = self.db.scan_all_watch_dirs()

        # Compute pHash for photos that don't have one
        for photo in all_photos:
            try:
                phash = self.compute_phash(photo['filepath'])
                if phash:
                    self.db.store_content_hash(photo['id'], phash)
            except Exception as e:
                print(f"[dedup] Skipping {photo['filepath']}: {e}")

        # Find groups by Hamming distance
        self.duplicate_groups = self.db.find_duplicate_groups(self.config.dedup_tolerance)
        return self.duplicate_groups

    def merge_group(self, group_index: int, keep_photo_id: str) -> Dict:
        """Archive all photos in a group except the keeper.

        Args:
            group_index: Index into the duplicate groups list (from last scan)
            keep_photo_id: The photo_id to keep (not archive)

        Returns:
            Summary of the merge operation.
        """
        if group_index >= len(self.duplicate_groups):
            return {'error': f'Invalid group index {group_index}'}

        group = self.duplicate_groups[group_index]
        archived_count = 0
        archived_paths = []

        for photo in group:
            if photo['photo_id'] == keep_photo_id:
                continue

            try:
                src_path = Path(photo['filepath'])
                if not src_path.exists():
                    print(f"[dedup] Skipping missing: {src_path}")
                    continue

                # Create trash directory
                self.trash_dir.mkdir(parents=True, exist_ok=True)
                dest_path = self.trash_dir / src_path.name

                # If conflict, append hash suffix
                counter = 0
                while dest_path.exists():
                    counter += 1
                    dest_path = self.trash_dir / f"{src_path.stem}_{counter}{src_path.suffix}"

                shutil.move(str(src_path), str(dest_path))
                archived_paths.append(str(dest_path))

                # Store in duplicates table
                with self.db._connect() as conn:
                    conn.execute(
                        "INSERT OR IGNORE INTO duplicates (photo_id, archived_id, archive_path, duplicate_of, archived_at) VALUES (?, ?, ?, ?, ?)",
                        (photo['photo_id'], photo['photo_id'], str(dest_path), keep_photo_id, datetime.now().isoformat())
                    )
                archived_count += 1

            except Exception as e:
                print(f"[dedup] ERROR archiving {photo['filepath']}: {e}")

        return {
            'group_id': group_index,
            'kept': keep_photo_id,
            'archived': archived_count,
            'archived_paths': archived_paths
        }
