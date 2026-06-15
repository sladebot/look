"""One-off: rebuild all RAW previews + thumbnails with the current decoder/processor.

Run after clearing the `converted/` and `thumbnails/` cache dirs so every photo is
re-rendered by the fixed (orientation-correct) code path.

    ./.conda/bin/python -m scripts.regen_thumbnails
"""
import os
import sys
import time
from pathlib import Path

from api.config import Config
from api.database import PhotoDatabase
from api.decoder import RawDecoder
from api.processor import ImageProcessor
from api.scanner import DirectoryScanner

# Sizes the UI actually requests: 512 grid + 1024 detail. Smaller sizes are
# downscaled on-demand from these, so generating these two is sufficient.
SIZES = (512, 1024)


def preview_path_for(filepath: str, decoder: RawDecoder, scanner: DirectoryScanner) -> str | None:
    src = Path(filepath)
    if src.suffix.lower() in decoder.raw_extensions:
        sidecar = scanner.find_sidecar_jpeg(src)
        if sidecar:
            return str(sidecar)
        return decoder.decode(filepath, quiet=True)  # builds converted/ JPEG
    return filepath if os.path.exists(filepath) else None


def main() -> int:
    config = Config()
    db = PhotoDatabase(config.db_path)
    decoder = RawDecoder(config)
    processor = ImageProcessor(config)
    scanner = DirectoryScanner(config.photo_dir, config.image_extensions)

    photos = db.list_photos(limit=10_000_000, offset=0)
    total = len(photos)
    print(f"[regen] {total} photos to process", flush=True)

    ok = skipped = failed = 0
    start = time.time()
    for i, photo in enumerate(photos, 1):
        fp = photo["filepath"]
        try:
            if not os.path.exists(fp):
                skipped += 1
                continue
            preview = preview_path_for(fp, decoder, scanner)
            if not preview:
                failed += 1
                print(f"[regen] no preview: {fp}", flush=True)
                continue
            for size in SIZES:
                processor.generate_thumbnail(preview, size)
            ok += 1
        except Exception as e:  # keep going; one bad file shouldn't stop the run
            failed += 1
            print(f"[regen] error {fp}: {e}", flush=True)

        if i % 50 == 0 or i == total:
            rate = i / max(time.time() - start, 1e-6)
            eta = (total - i) / max(rate, 1e-6)
            print(f"[regen] {i}/{total} ok={ok} skip={skipped} fail={failed} "
                  f"({rate:.1f}/s, eta {eta/60:.1f}m)", flush=True)

    print(f"[regen] DONE ok={ok} skip={skipped} fail={failed} "
          f"in {(time.time()-start)/60:.1f}m", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
