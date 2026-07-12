"""Generate sample photos of recognizable PLACES for Look App Store screenshots.

Travel-poster style: landmark silhouettes over atmospheric gradients — Paris,
San Francisco, Kyoto, New York, Santorini, Giza, London, Monument Valley,
Big Sur, Banff. Fully procedural (no external assets, no licensing concerns).
Each image carries EXIF (date, camera, real landmark GPS) so the app's Places
map and metadata UI are populated.

Usage:
    python demo/generate_place_photos.py <output_dir>
    python demo/generate_place_photos.py <output_dir> --seed <server_url> <db_path>

With --seed, imports the folder into a running Look server and seeds albums,
tags, and favorites. Run the server with PHOTO_DIR=<output_dir> first.
"""
import math
import os
import random
import sys
import datetime

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageChops

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(20260711)


# ── shared helpers ────────────────────────────────────────────────────────────

def vgrad(w, h, stops):
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


def sun_layer(w, h, cx, cy, radius, color):
    layer = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(26, 0, -1):
        r = radius * i / 8
        a = (1 - i / 27) ** 2.4
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=tuple(int(c * a) for c in color))
    d.ellipse([cx - radius * 0.5, cy - radius * 0.5, cx + radius * 0.5, cy + radius * 0.5], fill=color)
    return layer.filter(ImageFilter.GaussianBlur(radius / 5))


def screen(a, b):
    return ImageChops.screen(a, b)


def stars(d, w, h, n, ymax=0.7, rnd=None):
    rnd = rnd or random
    for _ in range(n):
        x, y = rnd.randint(0, w), rnd.randint(0, int(h * ymax))
        b = rnd.randint(120, 255)
        r = rnd.choice([1, 1, 1, 2])
        d.ellipse([x, y, x + r, y + r], fill=(b, b, min(255, b + 15)))


def finish(img):
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    noise = Image.effect_noise(img.size, 9).convert("RGB")
    img = Image.blend(img, noise, 0.04)
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).ellipse([-w * 0.35, -h * 0.35, w * 1.35, h * 1.35], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(min(w, h) * 0.22))
    dark = ImageEnhance.Brightness(img).enhance(0.70)
    img = Image.composite(img, dark, mask)
    img = ImageEnhance.Color(img).enhance(1.08)
    return ImageEnhance.Contrast(img).enhance(1.05)


def soft_paste(img, layer, blur=2):
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    img.paste(layer, (0, 0), layer)


# ── scenes ────────────────────────────────────────────────────────────────────

def scene_paris(w, h, v):
    skies = [
        [(0.0, (46, 40, 84)), (0.45, (196, 96, 108)), (0.68, (250, 168, 106)), (1.0, (30, 26, 44))],
        [(0.0, (26, 30, 62)), (0.5, (150, 92, 128)), (0.7, (240, 150, 110)), (1.0, (24, 22, 38))],
        [(0.0, (60, 46, 90)), (0.5, (214, 120, 110)), (0.7, (252, 190, 128)), (1.0, (36, 30, 48))],
    ]
    img = vgrad(w, h, skies[v % len(skies)])
    img = screen(img, sun_layer(w, h, w * 0.68, h * 0.60, h * 0.10, (255, 190, 120)))
    sil = (18, 14, 22)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # rooftop skyline
    rnd = random.Random(v * 7 + 1)
    y0 = h * 0.86
    x = 0
    while x < w:
        bw = rnd.randint(int(w * 0.04), int(w * 0.10))
        bh = rnd.randint(int(h * 0.03), int(h * 0.08))
        d.rectangle([x, y0 - bh, x + bw, h], fill=sil + (255,))
        x += bw
    # Eiffel tower: concave taper
    cx, base_y, top_y = w * 0.40, h * 0.88, h * 0.16
    half_base = w * 0.14
    pts_l, pts_r = [], []
    for i in range(21):
        t = i / 20
        y = base_y + (top_y - base_y) * t
        half = half_base * (1 - t) ** 2.3 + w * 0.006
        pts_l.append((cx - half, y))
        pts_r.append((cx + half, y))
    d.polygon(pts_l + pts_r[::-1], fill=sil + (255,))
    # base arch cut (sky window)
    arch_r = half_base * 0.55
    sky_patch = img.crop((int(cx - arch_r), int(base_y - arch_r), int(cx + arch_r), int(base_y)))
    mask = Image.new("L", sky_patch.size, 0)
    ImageDraw.Draw(mask).pieslice([0, 0, sky_patch.width, 2 * sky_patch.height], 180, 360, fill=255)
    layer.paste((0, 0, 0, 0), (int(cx - arch_r), int(base_y - arch_r)), mask)
    # platforms + antenna
    for t, ww in [(0.24, 1.35), (0.55, 1.5)]:
        y = base_y + (top_y - base_y) * t
        half = (half_base * (1 - t) ** 2.3 + w * 0.006) * ww
        d.rectangle([cx - half, y - h * 0.008, cx + half, y + h * 0.008], fill=sil + (255,))
    d.line([cx, top_y, cx, top_y - h * 0.05], fill=sil + (255,), width=max(2, int(w * 0.004)))
    soft_paste(img, layer)
    return img


def scene_goldengate(w, h, v):
    img = vgrad(w, h, [(0.0, (120, 138, 158)), (0.55, (176, 186, 194)), (0.75, (128, 146, 158)), (1.0, (70, 88, 104))])
    img = screen(img, sun_layer(w, h, w * 0.2, h * 0.25, h * 0.05, (240, 230, 210)))
    bridge = (108, 40, 28)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    deck_y = h * 0.62
    d.rectangle([0, deck_y, w, deck_y + h * 0.018], fill=bridge + (255,))
    tw = w * 0.02
    for tx in (w * 0.30, w * 0.70):
        d.rectangle([tx - tw / 2, h * 0.26, tx + tw / 2, deck_y + h * 0.02], fill=bridge + (255,))
        for cy in (h * 0.33, h * 0.42, h * 0.52):
            d.rectangle([tx - tw * 1.4, cy, tx + tw * 1.4, cy + h * 0.012], fill=bridge + (255,))
    def cable(x0, y0, x1, y1, sag):
        pts = []
        for i in range(25):
            t = i / 24
            x = x0 + (x1 - x0) * t
            y = (1 - t) * y0 + t * y1 + sag * math.sin(math.pi * t)
            pts.append((x, y))
        d.line(pts, fill=bridge + (255,), width=max(2, int(h * 0.006)))
        return pts
    top = h * 0.27
    main = cable(w * 0.30, top, w * 0.70, top, h * 0.30)
    cable(0, h * 0.48, w * 0.30, top, h * 0.05)
    cable(w * 0.70, top, w, h * 0.48, h * 0.05)
    for px, py in main[::2]:
        d.line([px, py, px, deck_y], fill=bridge + (200,), width=1)
    soft_paste(img, layer, blur=1)
    # fog band
    fog = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(fog).rectangle([0, h * 0.52, w, h * 0.78], fill=(228, 232, 234, 120))
    soft_paste(img, fog, blur=int(h * 0.05))
    # water
    d2 = ImageDraw.Draw(img)
    rnd = random.Random(v * 11)
    for i in range(24):
        y = int(h * 0.80) + int(h * 0.2 * (i / 24) ** 1.3)
        d2.line([0, y, w, y], fill=(96, 116, 130), width=1)
    return img


def scene_kyoto(w, h, v):
    img = vgrad(w, h, [(0.0, (58, 34, 52)), (0.5, (196, 100, 78)), (0.72, (246, 168, 96)), (1.0, (32, 22, 30))])
    img = screen(img, sun_layer(w, h, w * 0.30, h * 0.55, h * 0.09, (255, 200, 130)))
    sil = (24, 16, 20)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, base = w * 0.62, h * 0.90
    tiers = 5
    for i in range(tiers):
        t = i / (tiers - 1)
        half = w * (0.24 - 0.038 * i)
        roof_y = base - h * (0.10 + 0.135 * i)
        kick = h * 0.028
        d.polygon([
            (cx - half, roof_y), (cx - half * 1.12, roof_y - kick * 0.4),
            (cx - half * 0.2, roof_y - kick * 1.6), (cx + half * 0.2, roof_y - kick * 1.6),
            (cx + half * 1.12, roof_y - kick * 0.4), (cx + half, roof_y),
            (cx + half * 0.72, roof_y + kick * 0.9), (cx - half * 0.72, roof_y + kick * 0.9),
        ], fill=sil + (255,))
        body_half = half * 0.5
        d.rectangle([cx - body_half, roof_y + kick * 0.9, cx + body_half, roof_y + h * 0.10], fill=sil + (255,))
    top = base - h * (0.10 + 0.135 * (tiers - 1)) - h * 0.045
    d.line([cx, top, cx, top - h * 0.07], fill=sil + (255,), width=max(2, int(w * 0.005)))
    for k in range(3):
        d.ellipse([cx - w * 0.008, top - h * 0.02 * (k + 1) - w * 0.008,
                   cx + w * 0.008, top - h * 0.02 * (k + 1) + w * 0.008], fill=sil + (255,))
    rnd = random.Random(v * 13)
    for _ in range(9):
        bx = rnd.randint(0, w)
        br = rnd.randint(int(w * 0.05), int(w * 0.12))
        d.ellipse([bx - br, base - br * 0.7, bx + br, base + br * 0.5], fill=sil + (255,))
    d.rectangle([0, base, w, h], fill=sil + (255,))
    soft_paste(img, layer)
    return img


def scene_nyc(w, h, v):
    img = vgrad(w, h, [(0.0, (10, 14, 34)), (0.6, (22, 28, 56)), (1.0, (44, 42, 66))])
    rnd = random.Random(v * 17 + 3)
    d0 = ImageDraw.Draw(img)
    stars(d0, w, h, 260, 0.6, rnd)
    img = screen(img, sun_layer(w, h, w * 0.82, h * 0.18, h * 0.05, (200, 200, 230)))
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    sil = (12, 12, 20)
    base = h * 0.97
    buildings = []
    x = -w * 0.02
    while x < w:
        bw = rnd.randint(int(w * 0.05), int(w * 0.11))
        bh = rnd.randint(int(h * 0.18), int(h * 0.46))
        d.rectangle([x, base - bh, x + bw, base], fill=sil + (255,))
        buildings.append((x, base - bh, bw, bh))
        x += bw + rnd.randint(2, int(w * 0.01))
    # central spire tower
    cx = w * 0.5
    for i, (hw, hh) in enumerate([(0.06, 0.55), (0.04, 0.66), (0.022, 0.74)]):
        d.rectangle([cx - w * hw, base - h * hh, cx + w * hw, base], fill=sil + (255,))
    d.polygon([(cx - w * 0.012, base - h * 0.74), (cx + w * 0.012, base - h * 0.74), (cx, base - h * 0.82)], fill=sil + (255,))
    # windows
    warm = (255, 214, 140)
    for bx, by, bw_, bh_ in buildings:
        cols = max(2, int(bw_ / (w * 0.014)))
        rows = max(3, int(bh_ / (h * 0.02)))
        for cxi in range(cols):
            for ry in range(rows):
                if rnd.random() < 0.28:
                    wx = bx + (cxi + 0.5) * bw_ / cols
                    wy = by + (ry + 0.5) * bh_ / rows
                    d.rectangle([wx, wy, wx + max(1, w * 0.004), wy + max(1, h * 0.004)], fill=warm + (230,))
    soft_paste(img, layer, blur=1)
    return img


def scene_santorini(w, h, v):
    img = vgrad(w, h, [(0.0, (116, 168, 222)), (0.5, (164, 200, 236)), (0.55, (60, 110, 176)), (1.0, (24, 58, 110))])
    img = screen(img, sun_layer(w, h, w * 0.78, h * 0.30, h * 0.06, (255, 245, 220)))
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rnd = random.Random(v * 19 + 5)
    white = (242, 238, 228)
    shade = (198, 196, 190)
    dome = (44, 96, 180)
    # cliff terraces on the left
    for row in range(6):
        y = h * (0.30 + row * 0.115)
        x = 0
        max_x = w * (0.62 - row * 0.05)
        while x < max_x:
            bw = rnd.randint(int(w * 0.05), int(w * 0.11))
            bh = rnd.randint(int(h * 0.06), int(h * 0.11))
            d.rectangle([x, y, x + bw, y + bh], fill=white + (255,))
            d.rectangle([x + bw - w * 0.012, y, x + bw, y + bh], fill=shade + (255,))
            if rnd.random() < 0.30:
                r = bw * 0.42
                cx0 = x + bw / 2
                d.pieslice([cx0 - r, y - r, cx0 + r, y + r], 180, 360, fill=dome + (255,))
            if rnd.random() < 0.6:
                d.rectangle([x + bw * 0.4, y + bh * 0.35, x + bw * 0.52, y + bh * 0.75], fill=(60, 70, 90, 255))
            x += bw + rnd.randint(2, int(w * 0.015))
    soft_paste(img, layer, blur=1)
    d2 = ImageDraw.Draw(img)
    for i in range(20):
        y = int(h * 0.60) + int(h * 0.38 * (i / 20) ** 1.4)
        x0 = rnd.randint(int(w * 0.3), int(w * 0.6))
        d2.line([x0, y, x0 + rnd.randint(int(w * 0.1), int(w * 0.35)), y], fill=(214, 230, 244), width=1)
    return img


def scene_giza(w, h, v):
    img = vgrad(w, h, [(0.0, (252, 176, 100)), (0.45, (240, 130, 84)), (0.62, (200, 84, 70)), (1.0, (60, 26, 24))])
    img = screen(img, sun_layer(w, h, w * 0.24, h * 0.56, h * 0.10, (255, 210, 140)))
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    lit = (150, 96, 60)
    dark = (74, 42, 32)
    ground = h * 0.80
    for cx, half, ph in [(w * 0.72, w * 0.24, h * 0.34), (w * 0.42, w * 0.17, h * 0.24), (w * 0.20, w * 0.11, h * 0.15)]:
        apex = (cx, ground - ph)
        d.polygon([apex, (cx - half, ground), (cx + half * 0.12, ground)], fill=lit + (255,))
        d.polygon([apex, (cx + half * 0.12, ground), (cx + half, ground)], fill=dark + (255,))
    d.rectangle([0, ground, w, h], fill=(52, 28, 26, 255))
    pts = [(0, ground)]
    for x in range(0, w + 20, 20):
        pts.append((x, ground + math.sin(x / w * 6.28 * 1.5) * h * 0.01))
    pts += [(w, h), (0, h)]
    d.polygon(pts, fill=(52, 28, 26, 255))
    soft_paste(img, layer)
    return img


def scene_london(w, h, v):
    img = vgrad(w, h, [(0.0, (44, 40, 70)), (0.5, (120, 88, 116)), (0.72, (206, 130, 108)), (1.0, (26, 24, 40))])
    img = screen(img, sun_layer(w, h, w * 0.30, h * 0.62, h * 0.07, (255, 190, 130)))
    sil = (16, 14, 24)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    base = h * 0.82
    # parliament roofline
    d.rectangle([0, base - h * 0.09, w * 0.60, base], fill=sil + (255,))
    rnd = random.Random(v * 23)
    for x in range(0, int(w * 0.60), int(w * 0.05)):
        d.polygon([(x, base - h * 0.09), (x + w * 0.012, base - h * 0.14), (x + w * 0.024, base - h * 0.09)], fill=sil + (255,))
    # Big Ben tower
    tx, tw_ = w * 0.68, w * 0.055
    d.rectangle([tx - tw_ / 2, h * 0.36, tx + tw_ / 2, base], fill=sil + (255,))
    clock_y = h * 0.44
    r = tw_ * 0.42
    d.ellipse([tx - r, clock_y - r, tx + r, clock_y + r], fill=(226, 208, 152, 255))
    d.line([tx, clock_y, tx, clock_y - r * 0.62], fill=sil + (255,), width=max(2, int(w * 0.004)))
    d.line([tx, clock_y, tx + r * 0.45, clock_y + r * 0.2], fill=sil + (255,), width=max(2, int(w * 0.004)))
    d.polygon([(tx - tw_ / 2, h * 0.36), (tx + tw_ / 2, h * 0.36), (tx, h * 0.27)], fill=sil + (255,))
    d.line([tx, h * 0.27, tx, h * 0.23], fill=sil + (255,), width=max(2, int(w * 0.004)))
    # Thames
    d.rectangle([0, base, w, h], fill=(20, 20, 34, 255))
    for i in range(16):
        y = base + (h - base) * (i / 16)
        x0 = rnd.randint(0, int(w * 0.7))
        d.line([x0, y, x0 + rnd.randint(int(w * 0.05), int(w * 0.3)), y], fill=(196, 140, 110, 90), width=1)
    soft_paste(img, layer)
    return img


def scene_monument(w, h, v):
    img = vgrad(w, h, [(0.0, (250, 160, 96)), (0.5, (232, 110, 80)), (0.75, (170, 70, 62)), (1.0, (54, 24, 26))])
    img = screen(img, sun_layer(w, h, w * 0.5, h * 0.30, h * 0.05, (255, 220, 170)))
    rnd = random.Random(v * 29)
    layers = [((150, 74, 60), 0.62, 0.34), ((112, 52, 46), 0.72, 0.42), ((70, 32, 32), 0.84, 0.55)]
    for color, base_t, mesa_h in layers:
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        base = h * base_t
        d.rectangle([0, base, w, h], fill=color + (255,))
        n = rnd.randint(2, 3)
        for _ in range(n):
            cx = rnd.uniform(0.1, 0.9) * w
            top_w = rnd.uniform(0.05, 0.16) * w
            mh = mesa_h * h * rnd.uniform(0.6, 1.0)
            d.polygon([
                (cx - top_w * 1.8, base), (cx - top_w * 0.9, base - mh * 0.85),
                (cx - top_w * 0.7, base - mh), (cx + top_w * 0.7, base - mh),
                (cx + top_w * 0.9, base - mh * 0.85), (cx + top_w * 1.8, base),
            ], fill=color + (255,))
        soft_paste(img, layer, blur=2)
    return img


def scene_bigsur(w, h, v):
    img = vgrad(w, h, [(0.0, (36, 54, 84)), (0.45, (110, 130, 150)), (0.58, (238, 170, 120)), (0.62, (52, 84, 108)), (1.0, (16, 34, 52))])
    rnd = random.Random(v * 31)
    d0 = ImageDraw.Draw(img)
    stars(d0, w, h, 90, 0.4, rnd)
    for i in range(22):
        y = int(h * 0.64) + int(h * 0.34 * (i / 22) ** 1.4)
        x0 = rnd.randint(0, int(w * 0.5))
        d0.line([x0, y, x0 + rnd.randint(int(w * 0.1), int(w * 0.45)), y], fill=(120, 150, 168), width=1)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    sil = (14, 20, 26)
    # headland from the right
    pts = [(w, h)]
    for i in range(21):
        t = i / 20
        x = w - t * w * 0.55
        y = h * (0.62 - 0.16 * math.sin(t * math.pi * 0.5))
        pts.append((x, y))
    pts += [(w * 0.45, h), (w, h)]
    d.polygon(pts, fill=sil + (255,))
    # lighthouse
    lx, ly = w * 0.72, h * 0.475
    lw = w * 0.022
    d.polygon([(lx - lw, ly), (lx + lw, ly), (lx + lw * 0.7, ly - h * 0.075), (lx - lw * 0.7, ly - h * 0.075)], fill=(232, 228, 218, 255))
    d.rectangle([lx - lw * 0.9, ly - h * 0.088, lx + lw * 0.9, ly - h * 0.075], fill=sil + (255,))
    d.rectangle([lx - lw * 0.5, ly - h * 0.10, lx + lw * 0.5, ly - h * 0.088], fill=(255, 226, 150, 255))
    d.pieslice([lx - lw * 0.8, ly - h * 0.115, lx + lw * 0.8, ly - h * 0.085], 180, 360, fill=sil + (255,))
    beam = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(beam).polygon(
        [(lx, ly - h * 0.094), (0, ly - h * 0.20), (0, ly - h * 0.01)], fill=(255, 226, 150, 46))
    soft_paste(img, beam, blur=int(h * 0.01))
    soft_paste(img, layer, blur=1)
    return img


def scene_banff(w, h, v):
    img = vgrad(w, h, [(0.0, (18, 26, 52)), (0.55, (44, 60, 96)), (1.0, (80, 88, 110))])
    rnd = random.Random(v * 37)
    d0 = ImageDraw.Draw(img)
    stars(d0, w, h, 200, 0.55, rnd)
    # back peaks with snow caps
    def peaks(base_t, color, jag, seed, snow=None):
        r = random.Random(seed)
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        base = h * base_t
        pts = [(0, base)]
        x = 0
        summits = []
        while x < w:
            x += r.randint(int(w * 0.08), int(w * 0.16))
            y = base - r.uniform(0.5, 1.0) * jag * h
            pts.append((min(x, w), y))
            summits.append((min(x, w), y))
            x += r.randint(int(w * 0.06), int(w * 0.12))
            pts.append((min(x, w), base - r.uniform(0.05, 0.25) * jag * h))
        pts += [(w, base), (w, h), (0, h)]
        d.polygon(pts, fill=color + (255,))
        if snow:
            for sx, sy in summits:
                d.polygon([(sx - w * 0.035, sy + h * 0.045), (sx, sy), (sx + w * 0.035, sy + h * 0.045)], fill=snow + (255,))
        soft_paste(img, layer, blur=2)
    peaks(0.62, (52, 64, 92), 0.30, v * 3 + 1, snow=(210, 218, 232))
    peaks(0.78, (30, 38, 58), 0.22, v * 3 + 2)
    # treeline + cabin
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    sil = (12, 16, 24)
    base = h * 0.88
    d.rectangle([0, base, w, h], fill=sil + (255,))
    for x in range(0, w, int(w * 0.03)):
        th = rnd.randint(int(h * 0.03), int(h * 0.06))
        d.polygon([(x, base), (x + w * 0.012, base - th), (x + w * 0.024, base)], fill=sil + (255,))
    cx = w * 0.38
    d.polygon([(cx - w * 0.08, base), (cx, base - h * 0.11), (cx + w * 0.08, base)], fill=sil + (255,))
    d.rectangle([cx - w * 0.012, base - h * 0.045, cx + w * 0.012, base - h * 0.012], fill=(255, 210, 130, 255))
    d.rectangle([cx + w * 0.03, base - h * 0.12, cx + w * 0.045, base - h * 0.09], fill=sil + (255,))
    soft_paste(img, layer, blur=1)
    return img


# ── catalog ───────────────────────────────────────────────────────────────────

PLACES = [
    ("Paris at dusk", scene_paris, (48.8584, 2.2945), ["paris", "france", "dusk"]),
    ("Golden Gate fog", scene_goldengate, (37.8199, -122.4783), ["san-francisco", "bridge", "fog"]),
    ("Kyoto pagoda", scene_kyoto, (34.9671, 135.7727), ["kyoto", "japan", "temple"]),
    ("Manhattan nights", scene_nyc, (40.7484, -73.9857), ["new-york", "skyline", "night"]),
    ("Santorini blue", scene_santorini, (36.4614, 25.4315), ["santorini", "greece", "sea"]),
    ("Giza sunset", scene_giza, (29.9792, 31.1342), ["giza", "egypt", "desert"]),
    ("Westminster evening", scene_london, (51.5007, -0.1246), ["london", "uk", "dusk"]),
    ("Monument Valley", scene_monument, (36.9980, -110.0985), ["monument-valley", "usa", "desert"]),
    ("Big Sur light", scene_bigsur, (36.2704, -121.8081), ["big-sur", "coast", "lighthouse"]),
    ("Banff dusk", scene_banff, (51.4254, -116.1773), ["banff", "canada", "mountains"]),
]

SIZES = [(1800, 1200), (1200, 1800), (1800, 1013), (1440, 1440), (1800, 1350)]
CAMERAS = [(b"Sony", b"ILCE-7M4"), (b"FUJIFILM", b"X-T5"), (b"Apple", b"iPhone 17 Pro")]


def deg_to_dms_rational(deg):
    deg = abs(deg)
    d = int(deg)
    m = int((deg - d) * 60)
    s = round(((deg - d) * 60 - m) * 60 * 100)
    return [(d, 1), (m, 1), (s, 100)]


def generate():
    import piexif
    base = datetime.datetime(2026, 6, 5, 8, 30)
    count = 0
    for idx in range(40):
        name, fn, (lat, lon), _tags = PLACES[idx % len(PLACES)]
        variant = idx // len(PLACES)
        w, h = SIZES[(idx * 7) % len(SIZES)]
        img = finish(fn(w, h, idx))

        day = idx // 10
        dt = base + datetime.timedelta(days=day, minutes=21 * (idx % 10) + idx)
        stamp = dt.strftime("%Y:%m:%d %H:%M:%S")
        make, model = CAMERAS[idx % len(CAMERAS)]
        exif_dict = {
            "0th": {piexif.ImageIFD.Make: make, piexif.ImageIFD.Model: model},
            "Exif": {piexif.ExifIFD.DateTimeOriginal: stamp.encode(),
                     piexif.ExifIFD.LensModel: b"24-70mm F2.8"},
            "GPS": {
                piexif.GPSIFD.GPSLatitudeRef: b"N" if lat >= 0 else b"S",
                piexif.GPSIFD.GPSLatitude: deg_to_dms_rational(lat),
                piexif.GPSIFD.GPSLongitudeRef: b"E" if lon >= 0 else b"W",
                piexif.GPSIFD.GPSLongitude: deg_to_dms_rational(lon),
            },
        }
        img.save(os.path.join(OUT, f"{name} {variant + 1:02d}.jpg"),
                 quality=90, exif=piexif.dump(exif_dict))
        count += 1
    print("generated", count, "->", OUT)


def seed_server(base_url, db_path):
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
        if get("/api/health")["photo_count"] >= 40:
            break
        time.sleep(1)

    photos = get("/api/photos?limit=100")["photos"]
    by_place = {}
    for p in photos:
        by_place.setdefault(p["filename"].rsplit(" ", 1)[0], []).append(p)

    fav_ids = [ps[0]["id"] for ps in by_place.values()]
    conn = sqlite3.connect(db_path)
    conn.executemany("UPDATE photos SET is_favorite = 1 WHERE id = ?", [(i,) for i in fav_ids])
    conn.commit()
    conn.close()

    tag_map = {name: tags for name, _fn, _gps, tags in PLACES}
    for place, ps in by_place.items():
        for tag in tag_map.get(place, []):
            for p in ps[:3]:
                post(f"/api/photos/{p['id']}/tags", tag=tag)

    albums = [
        ("City breaks", "Paris, New York, and London evenings.",
         ["Paris at dusk", "Manhattan nights", "Westminster evening"]),
        ("Coast & islands", "Bridges, cliffs, and lighthouses.",
         ["Golden Gate fog", "Santorini blue", "Big Sur light"]),
        ("Deserts & monuments", "Sandstone, pyramids, and open sky.",
         ["Giza sunset", "Monument Valley"]),
    ]
    for name, desc, places in albums:
        album = post("/api/albums", name=name, description=desc)
        for place in places:
            for p in by_place.get(place, []):
                post(f"/api/albums/{album['id']}/photos/{p['id']}")

    post("/api/smart-collections", name="Night scenes", description="Skylines and stars.",
         rule_spec=json.dumps({"rules": [{"field": "tag", "op": "has_any", "value": ["night", "skyline"]}]}))
    post("/api/smart-collections", name="Shot on Sony", description="Everything from the A7 IV.",
         rule_spec=json.dumps({"rules": [{"field": "camera", "op": "contains", "value": "Sony"}]}))
    for c in get("/api/smart-collections")["collections"]:
        post(f"/api/smart-collections/{c['id']}/eval")

    print("seeded:", len(get("/api/albums")["albums"]), "albums (incl. smart),",
          len(get("/api/tags")["tags"]), "tags")


generate()
if "--seed" in sys.argv:
    i = sys.argv.index("--seed")
    seed_server(sys.argv[i + 1].rstrip("/"), sys.argv[i + 2])
