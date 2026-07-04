"""Generate photographic-looking landscape images for Look App Store screenshots.

Procedural scenes (no external assets, no licensing concerns): sunsets, mountain
layers, night skies, aurora, foggy forest, dunes, ocean minimal, city bokeh, and
lake reflections. Each image gets EXIF (date, camera, some GPS) so the app's
metadata UI is populated.

Usage:
    python demo/generate_screenshot_library.py <output_dir>
    python demo/generate_screenshot_library.py <output_dir> --seed <server_url> <db_path>

With --seed, the script also imports the folder into a running Look server and
seeds favorites, tags, albums, and smart collections so every screen has real
content. Run the server with PHOTO_DIR=<output_dir> DB_PATH=<db_path> first.
"""
import math
import os
import random
import sys
import datetime

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import piexif

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(20260703)


def vgrad(w, h, stops):
    """Vertical gradient from a list of (position 0..1, (r,g,b)) stops."""
    stripe = Image.new("RGB", (1, h))
    px = stripe.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                f = (t - p0) / max(1e-6, p1 - p0)
                px[0, y] = tuple(int(c0[k] + (c1[k] - c0[k]) * f) for k in range(3))
                break
        else:
            px[0, y] = stops[-1][1]
    return stripe.resize((w, h))


def glow(img, cx, cy, radius, color, strength=1.0):
    layer = Image.new("RGB", img.size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 24
    for i in range(steps, 0, -1):
        r = radius * i / steps
        a = strength * (1 - i / steps) ** 2
        c = tuple(int(ch * a) for ch in color)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c)
    layer = layer.filter(ImageFilter.GaussianBlur(radius / 6))
    return Image.blend(img, Image.new("RGB", img.size, (0, 0, 0)), 0.0).point(lambda p: p) if False else \
        Image.composite(Image.new("RGB", img.size, (255, 255, 255)), img, Image.new("L", img.size, 0)) if False else \
        _screen(img, layer)


def _screen(a, b):
    import PIL.ImageChops as C
    return C.screen(a, b)


def ridge_points(w, y_base, jag, seed, step=None):
    """Smooth rolling ridge: sparse random control heights joined with cosine
    interpolation plus a touch of fine detail — reads as terrain, not sawtooth."""
    rnd = random.Random(seed)
    n_ctrl = 7
    ctrl = [rnd.uniform(-jag, jag) for _ in range(n_ctrl + 1)]
    fine_phase = rnd.random() * 6.28
    pts = []
    for x in range(0, w + 6, 6):
        t = x / w * n_ctrl
        i = min(int(t), n_ctrl - 1)
        f = t - i
        mu = (1 - math.cos(f * math.pi)) / 2
        y = ctrl[i] * (1 - mu) + ctrl[i + 1] * mu
        y += math.sin(x / w * 40 + fine_phase) * jag * 0.08
        pts.append((x, y_base + y))
    return pts


def draw_ridge(img, y_base, jag, color, seed, blur=2):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = ridge_points(img.width, y_base, jag, seed)
    poly = [(0, img.height)] + pts + [(img.width, img.height)]
    d.polygon(poly, fill=color + (255,))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    img.paste(layer, (0, 0), layer)
    return img


def add_grain(img, sigma=9, alpha=0.045):
    noise = Image.effect_noise(img.size, sigma).convert("RGB")
    return Image.blend(img, noise, alpha)


def add_vignette(img, strength=0.32):
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([-w * 0.35, -h * 0.35, w * 1.35, h * 1.35], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(min(w, h) * 0.22))
    dark = ImageEnhance.Brightness(img).enhance(1 - strength)
    return Image.composite(img, dark, mask)


def finish(img, warm=1.0):
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    img = add_grain(img)
    img = add_vignette(img)
    img = ImageEnhance.Color(img).enhance(1.08)
    img = ImageEnhance.Contrast(img).enhance(1.04)
    return img


# ---------------------------------------------------------------- scenes

def scene_sunset_ocean(w, h, v):
    palettes = [
        [(0.0, (28, 26, 66)), (0.35, (172, 74, 66)), (0.52, (244, 148, 74)), (0.60, (252, 196, 120)), (1.0, (16, 22, 36))],
        [(0.0, (44, 30, 72)), (0.38, (198, 88, 100)), (0.55, (250, 170, 110)), (0.62, (255, 210, 150)), (1.0, (22, 26, 44))],
        [(0.0, (16, 34, 62)), (0.40, (120, 90, 120)), (0.56, (236, 130, 96)), (0.62, (250, 180, 120)), (1.0, (12, 20, 34))],
    ]
    img = vgrad(w, h, palettes[v % len(palettes)])
    horizon = int(h * 0.60)
    sun_x = w * (0.36 + 0.3 * ((v * 37) % 10) / 10)
    img = _screen(img, _sun_layer(w, h, sun_x, horizon - h * 0.045, h * 0.16, (255, 178, 92)))
    d = ImageDraw.Draw(img)
    rnd = random.Random(v * 11 + 3)
    for i in range(60):
        y = horizon + int((h - horizon) * (i / 60) ** 1.6)
        ln = rnd.randint(int(w * 0.02), int(w * 0.22))
        x = int(sun_x + rnd.randint(-int(w * 0.16), int(w * 0.16)) * (i / 30 + 0.4))
        bright = max(0, 150 - i * 2)
        d.line([x - ln // 2, y, x + ln // 2, y], fill=(255, 190 + rnd.randint(-30, 20), 120, 90), width=2)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    for k in range(3):
        draw_ridge(img, int(h * (0.88 + k * 0.045)), int(h * 0.01), (10 + k * 2, 14 + k * 2, 22 + k * 2), seed=v * 7 + k, blur=3)
    return img


def _sun_layer(w, h, cx, cy, radius, color):
    layer = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(26, 0, -1):
        r = radius * i / 8
        a = (1 - i / 27) ** 2.4
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=tuple(int(c * a) for c in color))
    d.ellipse([cx - radius * 0.5, cy - radius * 0.5, cx + radius * 0.5, cy + radius * 0.5], fill=color)
    return layer.filter(ImageFilter.GaussianBlur(radius / 5))


def scene_mountain_layers(w, h, v):
    skies = [
        [(0.0, (204, 226, 240)), (0.5, (238, 214, 190)), (1.0, (246, 196, 160))],
        [(0.0, (168, 200, 224)), (0.55, (226, 226, 216)), (1.0, (240, 220, 190))],
        [(0.0, (140, 170, 205)), (0.5, (210, 200, 205)), (1.0, (236, 190, 170))],
    ]
    img = vgrad(w, h, skies[v % len(skies)])
    img = _screen(img, _sun_layer(w, h, w * 0.68, h * 0.30, h * 0.05, (255, 230, 190)))
    base = [(96, 118, 142), (76, 96, 120), (56, 74, 96), (38, 52, 70), (24, 34, 48)]
    for k, c in enumerate(base):
        y = int(h * (0.42 + 0.13 * k))
        draw_ridge(img, y, int(h * (0.10 - 0.012 * k)), c, seed=v * 13 + k * 5, blur=2 + (4 - k))
        if k < 4:
            fog = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            fd = ImageDraw.Draw(fog)
            fd.rectangle([0, y + h * 0.02, w, y + h * 0.12], fill=(235, 235, 235, 46 - k * 8))
            fog = fog.filter(ImageFilter.GaussianBlur(h * 0.03))
            img.paste(fog, (0, 0), fog)
    return img


def scene_night_sky(w, h, v):
    img = vgrad(w, h, [(0.0, (12, 16, 38)), (0.5, (24, 32, 64)), (0.82, (52, 56, 92)), (1.0, (88, 74, 96))])
    rnd = random.Random(v * 19 + 1)
    d = ImageDraw.Draw(img)
    for _ in range(700):
        x, y = rnd.randint(0, w), rnd.randint(0, int(h * 0.82))
        b = rnd.randint(130, 255)
        r = rnd.choice([1, 1, 1, 1, 2, 2, 3])
        d.ellipse([x, y, x + r, y + r], fill=(b, b, min(255, b + 20)))
    band = Image.new("L", (w, h), 0)
    bd = ImageDraw.Draw(band)
    for i in range(5000):
        t = rnd.random()
        x = int(t * w)
        cy = h * 0.45 - (x - w / 2) * 0.22
        y = int(cy + rnd.gauss(0, h * 0.085))
        bd.ellipse([x, y, x + 2, y + 2], fill=rnd.randint(30, 130))
    band = band.filter(ImageFilter.GaussianBlur(h * 0.022))
    img = _screen(img, Image.merge("RGB", (band.point(lambda p: p * 0.8),
                                           band.point(lambda p: p * 0.82),
                                           band)))
    img = _screen(img, _sun_layer(w, h, w * 0.5, h * 0.98, h * 0.10, (120, 96, 110)))
    draw_ridge(img, int(h * 0.88), int(h * 0.05), (10, 12, 20), seed=v * 3, blur=2)
    return img


def scene_aurora(w, h, v):
    img = vgrad(w, h, [(0.0, (6, 12, 28)), (0.6, (10, 20, 40)), (1.0, (18, 30, 48))])
    rnd = random.Random(v * 23 + 5)
    layer = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    for band in range(3):
        phase = rnd.random() * 6.28
        amp = h * (0.05 + 0.04 * band)
        yc = h * (0.28 + 0.12 * band)
        for x in range(0, w, 3):
            y = yc + math.sin(x / w * 4.5 + phase) * amp
            hgt = h * (0.10 + 0.08 * math.sin(x / w * 9 + phase))
            g = rnd.randint(120, 200)
            d.line([x, y, x, y + hgt], fill=(20, g, 110 + band * 20), width=3)
    layer = layer.filter(ImageFilter.GaussianBlur(h * 0.025))
    img = _screen(img, layer)
    d2 = ImageDraw.Draw(img)
    for _ in range(260):
        x, y = rnd.randint(0, w), rnd.randint(0, int(h * 0.7))
        b = rnd.randint(120, 240)
        d2.point((x, y), fill=(b, b, b))
    draw_ridge(img, int(h * 0.84), int(h * 0.03), (14, 20, 30), seed=v * 5, blur=2)
    draw_ridge(img, int(h * 0.92), int(h * 0.02), (8, 12, 18), seed=v * 5 + 1, blur=2)
    return img


def scene_foggy_forest(w, h, v):
    """Misty layered hills in green — reads as fog over forested ridges."""
    img = vgrad(w, h, [(0.0, (216, 224, 220)), (0.55, (184, 198, 190)), (1.0, (140, 158, 148))])
    img = _screen(img, _sun_layer(w, h, w * 0.5, h * 0.18, h * 0.05, (240, 244, 236)))
    layers = [(158, 176, 164), (128, 150, 136), (96, 122, 106), (66, 92, 76), (40, 62, 50)]
    for k, c in enumerate(layers):
        y = int(h * (0.40 + 0.135 * k))
        draw_ridge(img, y, int(h * (0.085 - 0.008 * k)), c, seed=v * 29 + k * 3, blur=6 - k)
        if k < len(layers) - 1:
            fog = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            fd = ImageDraw.Draw(fog)
            fd.rectangle([0, y + h * 0.03, w, y + h * 0.15], fill=(228, 234, 228, 64 - k * 10))
            fog = fog.filter(ImageFilter.GaussianBlur(h * 0.035))
            img.paste(fog, (0, 0), fog)
    return img


def scene_dunes(w, h, v):
    img = vgrad(w, h, [(0.0, (244, 216, 178)), (0.45, (240, 188, 140)), (1.0, (206, 140, 92))])
    img = _screen(img, _sun_layer(w, h, w * 0.24, h * 0.22, h * 0.06, (255, 236, 200)))
    rnd = random.Random(v * 31 + 9)
    shades = [(214, 158, 104), (192, 134, 84), (168, 112, 66), (142, 90, 52)]
    for k, c in enumerate(shades):
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        y0 = h * (0.42 + 0.15 * k)
        amp = h * 0.08
        phase = rnd.random() * 6.28
        pts = []
        for x in range(0, w + 8, 8):
            y = y0 + math.sin(x / w * 3.1 + phase) * amp + math.sin(x / w * 7.7 + phase * 2) * amp * 0.3
            pts.append((x, y))
        poly = [(0, h)] + pts + [(w, h)]
        d.polygon(poly, fill=c + (255,))
        for x, y in pts[:: max(1, len(pts) // 90)]:
            d.line([x, y, x, y + 3], fill=(255, 230, 190, 70), width=2)
        layer = layer.filter(ImageFilter.GaussianBlur(2))
        img.paste(layer, (0, 0), layer)
    return img


def scene_ocean_minimal(w, h, v):
    pal = [
        [(0.0, (198, 220, 232)), (0.55, (226, 232, 230)), (0.56, (140, 176, 190)), (0.75, (168, 196, 202)), (1.0, (216, 208, 190))],
        [(0.0, (176, 206, 226)), (0.55, (222, 226, 224)), (0.56, (120, 162, 182)), (0.78, (160, 190, 198)), (1.0, (208, 198, 180))],
    ]
    img = vgrad(w, h, pal[v % len(pal)])
    d = ImageDraw.Draw(img)
    rnd = random.Random(v * 37)
    for i in range(26):
        y = int(h * 0.56) + int((h * 0.22) * (i / 26) ** 1.4)
        d.line([0, y, w, y], fill=(236, 240, 240), width=1)
    for i in range(5):
        y = int(h * (0.78 + i * 0.035))
        d.line([0, y, w, y], fill=(240, 238, 230), width=2)
    return img.filter(ImageFilter.GaussianBlur(1.4))


def scene_city_bokeh(w, h, v):
    img = vgrad(w, h, [(0.0, (10, 12, 22)), (0.6, (24, 20, 34)), (1.0, (40, 28, 32))])
    rnd = random.Random(v * 41 + 13)
    layer = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    warm = [(255, 180, 90), (255, 140, 90), (255, 210, 130), (150, 190, 255), (255, 90, 110), (140, 230, 200)]
    for _ in range(90):
        x, y = rnd.randint(0, w), rnd.randint(int(h * 0.25), h)
        r = rnd.randint(int(h * 0.008), int(h * 0.05))
        c = rnd.choice(warm)
        a = rnd.uniform(0.25, 0.8)
        d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(ch * a) for ch in c))
    layer = layer.filter(ImageFilter.GaussianBlur(h * 0.018))
    img = _screen(img, layer)
    small = Image.new("RGB", (w, h), (0, 0, 0))
    d2 = ImageDraw.Draw(small)
    for _ in range(60):
        x, y = rnd.randint(0, w), rnd.randint(int(h * 0.3), h)
        r = rnd.randint(2, int(h * 0.008))
        c = rnd.choice(warm)
        d2.ellipse([x - r, y - r, x + r, y + r], fill=c)
    small = small.filter(ImageFilter.GaussianBlur(h * 0.004))
    return _screen(img, small)


def scene_lake_reflection(w, h, v):
    top_h = int(h * 0.62)
    top = scene_mountain_layers(w, top_h, v + 2)
    img = Image.new("RGB", (w, h))
    img.paste(top, (0, 0))
    refl = top.transpose(Image.FLIP_TOP_BOTTOM).resize((w, h - top_h))
    refl = refl.filter(ImageFilter.GaussianBlur(3))
    refl = ImageEnhance.Brightness(refl).enhance(0.82)
    img.paste(refl, (0, top_h))
    d = ImageDraw.Draw(img)
    rnd = random.Random(v)
    for i in range(30):
        y = top_h + rnd.randint(0, h - top_h - 2)
        ln = rnd.randint(int(w * 0.04), int(w * 0.3))
        x = rnd.randint(0, w - ln)
        d.line([x, y, x + ln, y], fill=(235, 235, 235, 30), width=1)
    return img.filter(ImageFilter.GaussianBlur(0.8))


SCENES = [
    ("Pacific sunset", scene_sunset_ocean, True),
    ("Ridgeline at dawn", scene_mountain_layers, False),
    ("Night sky over the pass", scene_night_sky, False),
    ("Aurora over the fjord", scene_aurora, True),
    ("Fog in the cedars", scene_foggy_forest, False),
    ("Dune field", scene_dunes, True),
    ("Morning tide", scene_ocean_minimal, False),
    ("City lights defocused", scene_city_bokeh, True),
    ("Lake mirror", scene_lake_reflection, False),
]

SIZES = [(1800, 1200), (1200, 1800), (1800, 1013), (1440, 1440), (1800, 1350)]

CAMERAS = [(b"Sony", b"ILCE-7M4"), (b"FUJIFILM", b"X-T5"), (b"Apple", b"iPhone 17 Pro")]

GPS_SPOTS = [
    (35.0116, 135.7681),   # Kyoto
    (37.7749, -122.4194),  # San Francisco
    (51.4254, -116.1773),  # Banff
    (64.1466, -21.9426),   # Reykjavik
]


def deg_to_dms_rational(deg):
    deg = abs(deg)
    d = int(deg)
    m = int((deg - d) * 60)
    s = round(((deg - d) * 60 - m) * 60 * 100)
    return [(d, 1), (m, 1), (s, 100)]


def seed_server(base_url, db_path):
    """Import the generated folder and seed favorites/tags/albums/smart albums."""
    import json
    import sqlite3
    import time
    import urllib.parse
    import urllib.request

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
        if get("/api/health")["photo_count"] >= 36:
            break
        time.sleep(1)

    photos = get("/api/photos?limit=100")["photos"]
    by_scene = {}
    for p in photos:
        by_scene.setdefault(p["filename"].rsplit(" ", 1)[0], []).append(p)

    # Favorites live in a DB column with no write endpoint; set them directly.
    fav_ids = [ps[0]["id"] for ps in by_scene.values()][:9]
    conn = sqlite3.connect(db_path)
    conn.executemany("UPDATE photos SET is_favorite = 1 WHERE id = ?", [(i,) for i in fav_ids])
    conn.commit()
    conn.close()

    tag_map = {
        "Pacific sunset": ["sunset", "ocean", "golden-hour"],
        "Ridgeline at dawn": ["mountains", "dawn", "hiking"],
        "Night sky over the pass": ["astro", "night", "long-exposure"],
        "Aurora over the fjord": ["aurora", "night", "iceland"],
        "Fog in the cedars": ["fog", "forest", "moody"],
        "Dune field": ["desert", "minimal"],
        "Morning tide": ["ocean", "minimal", "morning"],
        "City lights defocused": ["bokeh", "night", "city"],
        "Lake mirror": ["reflection", "mountains", "calm"],
    }
    for scene, ps in by_scene.items():
        for tag in tag_map.get(scene, []):
            for p in ps[:2]:
                post(f"/api/photos/{p['id']}/tags", tag=tag)

    albums = [
        ("Portfolio selects", "Hand-picked frames ready for print.",
         [ps[0]["id"] for ps in by_scene.values()]),
        ("Iceland trip", "Aurora hunting on the south coast.",
         [p["id"] for p in by_scene.get("Aurora over the fjord", []) + by_scene.get("Night sky over the pass", [])]),
        ("Blue hour studies", "Mountains and water after sundown.",
         [p["id"] for p in by_scene.get("Lake mirror", []) + by_scene.get("Ridgeline at dawn", [])]),
    ]
    for name, desc, ids in albums:
        album = post("/api/albums", name=name, description=desc)
        for pid in ids:
            post(f"/api/albums/{album['id']}/photos/{pid}")

    post("/api/smart-collections", name="Shot on Sony", description="Everything from the A7 IV.",
         rule_spec=json.dumps({"rules": [{"field": "camera", "op": "contains", "value": "Sony"}]}))
    post("/api/smart-collections", name="Night work", description="Astro, aurora, and city lights.",
         rule_spec=json.dumps({"rules": [{"field": "tag", "op": "has_any", "value": ["night", "astro", "aurora"]}]}))
    for c in get("/api/smart-collections")["collections"]:
        post(f"/api/smart-collections/{c['id']}/eval")

    print("seeded:", len(get("/api/albums")["albums"]), "albums (incl. smart),",
          len(get("/api/tags")["tags"]), "tags")


base = datetime.datetime(2026, 6, 5, 8, 30)
count = 0
for idx in range(36):
    name, fn, gps_likely = SCENES[idx % len(SCENES)]
    variant = idx // len(SCENES)
    w, h = SIZES[(idx * 7) % len(SIZES)]
    img = fn(w, h, idx)
    img = finish(img)

    day = idx // 10          # 4 day buckets
    dt = base + datetime.timedelta(days=day, minutes=23 * (idx % 10) + idx)
    stamp = dt.strftime("%Y:%m:%d %H:%M:%S")
    make, model = CAMERAS[idx % len(CAMERAS)]
    exif_dict = {
        "0th": {piexif.ImageIFD.Make: make, piexif.ImageIFD.Model: model},
        "Exif": {piexif.ExifIFD.DateTimeOriginal: stamp.encode(),
                 piexif.ExifIFD.LensModel: b"24-70mm F2.8"},
    }
    if gps_likely or idx % 3 == 0:
        lat, lon = GPS_SPOTS[idx % len(GPS_SPOTS)]
        exif_dict["GPS"] = {
            piexif.GPSIFD.GPSLatitudeRef: b"N" if lat >= 0 else b"S",
            piexif.GPSIFD.GPSLatitude: deg_to_dms_rational(lat),
            piexif.GPSIFD.GPSLongitudeRef: b"E" if lon >= 0 else b"W",
            piexif.GPSIFD.GPSLongitude: deg_to_dms_rational(lon),
        }
    fname = f"{name} {variant + 1:02d}.jpg"
    img.save(os.path.join(OUT, fname), quality=90, exif=piexif.dump(exif_dict))
    count += 1

print("generated", count, "->", OUT)

if "--seed" in sys.argv:
    seed_index = sys.argv.index("--seed")
    seed_server(sys.argv[seed_index + 1].rstrip("/"), sys.argv[seed_index + 2])
