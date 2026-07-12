"""Fetch REAL photographs for Look App Store screenshots.

Downloads deterministic images from picsum.photos (real photography sourced
from Unsplash; the Unsplash license permits free commercial use, which covers
marketing screenshots). Each download gets fresh EXIF — camera-roll style
filenames, dates spread over several days, camera bodies, and GPS on a subset —
so the app's date grouping, Places map, and metadata UI look like a real
personal library.

Usage:
    python demo/fetch_real_photos.py <output_dir>
    python demo/fetch_real_photos.py <output_dir> --seed <server_url> <db_path>

With --seed, imports the folder into a running Look server and seeds albums,
workflow tags, and favorites. Run the server with PHOTO_DIR=<output_dir> first.
"""
import datetime
import io
import os
import random
import sys
import time
import urllib.request

from PIL import Image
import piexif

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(20260712)

SIZES = [(1800, 1200), (1200, 1800), (1800, 1013), (1440, 1440), (1800, 1350)]
CAMERAS = [(b"Sony", b"ILCE-7M4"), (b"FUJIFILM", b"X-T5"), (b"Apple", b"iPhone 17 Pro")]
GPS_SPOTS = [
    (48.8584, 2.2945),     # Paris
    (37.8199, -122.4783),  # San Francisco
    (35.0116, 135.7681),   # Kyoto
    (51.4254, -116.1773),  # Banff
]
COUNT = 40


def deg_to_dms_rational(deg):
    deg = abs(deg)
    d = int(deg)
    m = int((deg - d) * 60)
    s = round(((deg - d) * 60 - m) * 60 * 100)
    return [(d, 1), (m, 1), (s, 100)]


def fetch(seed, w, h, attempts=4):
    url = f"https://picsum.photos/seed/look-{seed}/{w}/{h}"
    delay = 1.0
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                return Image.open(io.BytesIO(r.read())).convert("RGB")
        except Exception as e:
            if attempt == attempts - 1:
                raise
            time.sleep(delay)
            delay *= 2


def generate():
    base = datetime.datetime(2026, 6, 5, 8, 30)
    for idx in range(COUNT):
        w, h = SIZES[(idx * 7) % len(SIZES)]
        img = fetch(idx + 1, w, h)

        day = idx // 10
        dt = base + datetime.timedelta(days=day, minutes=19 * (idx % 10) + idx)
        stamp = dt.strftime("%Y:%m:%d %H:%M:%S")
        make, model = CAMERAS[idx % len(CAMERAS)]
        exif_dict = {
            "0th": {piexif.ImageIFD.Make: make, piexif.ImageIFD.Model: model},
            "Exif": {piexif.ExifIFD.DateTimeOriginal: stamp.encode(),
                     piexif.ExifIFD.LensModel: b"24-70mm F2.8"},
        }
        if idx % 3 == 0:
            lat, lon = GPS_SPOTS[idx % len(GPS_SPOTS)]
            exif_dict["GPS"] = {
                piexif.GPSIFD.GPSLatitudeRef: b"N" if lat >= 0 else b"S",
                piexif.GPSIFD.GPSLatitude: deg_to_dms_rational(lat),
                piexif.GPSIFD.GPSLongitudeRef: b"E" if lon >= 0 else b"W",
                piexif.GPSIFD.GPSLongitude: deg_to_dms_rational(lon),
            }
        prefix = ["DSC0", "IMG_", "DSCF"][idx % 3]
        name = f"{prefix}{4100 + idx * 7}.jpg"
        img.save(os.path.join(OUT, name), quality=90, exif=piexif.dump(exif_dict))
        print(f"  {name} ({w}x{h})")
    print("fetched", COUNT, "->", OUT)


def seed_server(base_url, db_path):
    import json
    import sqlite3
    import urllib.parse

    def get(endpoint):
        with urllib.request.urlopen(base_url + endpoint) as r:
            return json.load(r)

    def post(endpoint, **params):
        qs = urllib.parse.urlencode(params)
        req = urllib.request.Request(f"{base_url}{endpoint}?{qs}", method="POST")
        with urllib.request.urlopen(req) as r:
            return json.load(r)

    post("/api/import", path=os.path.abspath(OUT))
    for _ in range(60):
        if get("/api/health")["photo_count"] >= COUNT:
            break
        time.sleep(1)

    photos = sorted(get("/api/photos?limit=100")["photos"], key=lambda p: p["filename"])

    # Favorites: roughly one in four.
    fav_ids = [p["id"] for i, p in enumerate(photos) if i % 4 == 0]
    conn = sqlite3.connect(db_path)
    conn.executemany("UPDATE photos SET is_favorite = 1 WHERE id = ?", [(i,) for i in fav_ids])
    conn.commit()
    conn.close()

    # Workflow tags a photographer would actually apply.
    tag_cycle = ["keeper", "print", "share", "travel", "family", "b-roll"]
    for i, p in enumerate(photos):
        post(f"/api/photos/{p['id']}/tags", tag=tag_cycle[i % len(tag_cycle)])
        if i % 5 == 0:
            post(f"/api/photos/{p['id']}/tags", tag="golden-hour")

    albums = [
        ("Portfolio selects", "Hand-picked frames ready for print.", photos[0::4]),
        ("June trip", "Three days on the road.", photos[10:22]),
        ("Client proofs", "Awaiting picks and feedback.", photos[24:33]),
    ]
    for name, desc, members in albums:
        album = post("/api/albums", name=name, description=desc)
        for p in members:
            post(f"/api/albums/{album['id']}/photos/{p['id']}")

    post("/api/smart-collections", name="Shot on Sony", description="Everything from the A7 IV.",
         rule_spec=json.dumps({"rules": [{"field": "camera", "op": "contains", "value": "Sony"}]}))
    post("/api/smart-collections", name="Golden hour", description="Tagged at dusk and dawn.",
         rule_spec=json.dumps({"rules": [{"field": "tag", "op": "has", "value": "golden-hour"}]}))
    for c in get("/api/smart-collections")["collections"]:
        post(f"/api/smart-collections/{c['id']}/eval")

    print("seeded:", len(get("/api/albums")["albums"]), "albums (incl. smart),",
          len(get("/api/tags")["tags"]), "tags")


generate()
if "--seed" in sys.argv:
    i = sys.argv.index("--seed")
    seed_server(sys.argv[i + 1].rstrip("/"), sys.argv[i + 2])
