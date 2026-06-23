"""Backfill photos.width / photos.height from rendered previews.

RAW imports store NULL width/height (`processor._process_raw` can't know them
until decode). The iOS justified grid needs real aspect ratios, so read the
dimensions of each photo's displayable preview (orientation-corrected) and
write them back to the DB.

    ./.conda/bin/python -m scripts.backfill_dimensions
"""
import os
import sqlite3
import sys
from pathlib import Path

from PIL import Image

from api.config import Config
from api.decoder import RawDecoder
from api.scanner import DirectoryScanner


def preview_for(filepath, decoder, scanner):
    src = Path(filepath)
    if src.suffix.lower() in decoder.raw_extensions:
        sidecar = scanner.find_sidecar_jpeg(src)
        if sidecar:
            return str(sidecar)
        cp = decoder.get_converted_path(filepath)
        return cp if os.path.exists(cp) else decoder.decode(filepath, quiet=True)
    return filepath if os.path.exists(filepath) else None


def main():
    config = Config()
    decoder = RawDecoder(config)
    scanner = DirectoryScanner(config.photo_dir, config.image_extensions)
    conn = sqlite3.connect(config.db_path)
    conn.row_factory = sqlite3.Row

    rows = conn.execute(
        "SELECT id, filepath FROM photos WHERE width IS NULL OR height IS NULL"
    ).fetchall()
    print(f"[backfill] {len(rows)} photos missing dimensions", flush=True)

    updated = failed = 0
    for i, row in enumerate(rows, 1):
        try:
            preview = preview_for(row["filepath"], decoder, scanner)
            if not preview:
                failed += 1
                continue
            with Image.open(preview) as img:
                w, h = img.size
            conn.execute(
                "UPDATE photos SET width = ?, height = ? WHERE id = ?",
                (w, h, row["id"]),
            )
            updated += 1
        except Exception as e:
            failed += 1
            print(f"[backfill] error {row['filepath']}: {e}", flush=True)
        if i % 200 == 0:
            conn.commit()
            print(f"[backfill] {i}/{len(rows)} updated={updated} failed={failed}", flush=True)

    conn.commit()
    conn.close()
    print(f"[backfill] DONE updated={updated} failed={failed}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
