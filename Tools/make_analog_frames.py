#!/usr/bin/env python3
"""Generates the "Analog Frames (9:16)" frame pack.

Each frame is a 1152x2048 PNG (2x the 576x1024 canvas, i.e. pixel-exact at
export): opaque white paper gap on the outside, a medium-format style film
border with its imperfections, and a transparent window for the collage.

Output goes straight into the asset catalog as
  Assets.xcassets/FramePacks/Analog916/Analog916_<Name>_m<LLTTRRBB>_r9x16.imageset
where m.. are the minimum content margins in canvas pixels (see CanvasFrameSet).

Usage:  python3 -m venv venv && venv/bin/pip install pillow numpy scipy
        venv/bin/python Tools/make_analog_frames.py [--preview out.png]
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy.ndimage import gaussian_filter

W, H = 1152, 2048
CANVAS_SCALE = 2          # PNG pixels per canvas pixel
TUCK = 8                  # PNG px the collage slides under the inner film edge
PACK_DIR = os.path.join(os.path.dirname(__file__), "..", "CollageStudio",
                        "Assets.xcassets", "FramePacks", "Analog916")
FONT_DIN = "/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf"
FONT_NARROW = "/System/Library/Fonts/Supplemental/Arial Narrow Bold.ttf"

Y, X = np.mgrid[0:H, 0:W].astype(np.float32)


# ---------------------------------------------------------------- helpers

def noise(rng, sigma):
    """Smooth 2D noise with unit standard deviation."""
    n = gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), sigma)
    return n / (n.std() + 1e-6)


def rrect_sdf(x0, y0, x1, y1, r):
    """Signed distance to a rounded rect (negative inside)."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    qx = np.abs(X - cx) - ((x1 - x0) / 2 - r)
    qy = np.abs(Y - cy) - ((y1 - y0) / 2 - r)
    return (np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
            + np.minimum(np.maximum(qx, qy), 0) - r)


def cov(d, soft=1.2):
    """Coverage (1 inside) of a signed-distance field with a soft edge."""
    return np.clip(0.5 - d / soft, 0, 1)


def over(dst_rgb, dst_a, rgb, a):
    """Composite a straight-alpha layer over a premultiplied destination."""
    a3 = a[..., None]
    return rgb * a3 + dst_rgb * (1 - a3), a + dst_a * (1 - a)


def polygon_mask(polys, ss=4):
    img = Image.new("L", (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    for p in polys:
        d.polygon([(x * ss, y * ss) for x, y in p], fill=255)
    return np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255


def edge_strip(length, height, items, font_path, font_size):
    """Horizontal strip of film edge markings. items: (pos 0..1, kind, value)
    with kind in text / arrow / bars."""
    img = Image.new("L", (length, height), 0)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(font_path, font_size)
    cy = height / 2
    for pos, kind, value in items:
        x = pos * length
        if kind == "text":
            d.text((x, cy), value, font=font, fill=255, anchor="lm")
        elif kind == "arrow":
            s = value
            d.polygon([(x, cy - s), (x + s * 1.5, cy), (x, cy + s)], fill=255)
        elif kind == "bars":          # DX-style latent barcode
            rng = np.random.default_rng(value)
            for i in range(26):
                w = rng.choice([3, 3, 6])
                if rng.random() < 0.6:
                    d.rectangle([x, cy - height * 0.3, x + w, cy + height * 0.3], fill=255)
                x += w + 3
    return img


def place_strip(strip, orient, center, start):
    """Full-size mask of a strip: "v" runs bottom-to-top centered on x=center
    from y=start, "h" runs left-to-right centered on y=center from x=start."""
    full = Image.new("L", (W, H), 0)
    if orient == "v":
        rot = strip.rotate(90, expand=True)
        full.paste(rot, (int(center - rot.width / 2), int(start)))
    else:
        full.paste(strip, (int(start), int(center - strip.height / 2)))
    return np.asarray(full, np.float32) / 255


def dust_mask(rng, specks, hairs, area):
    x0, y0, x1, y1 = area
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for _ in range(specks):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        r = rng.choice([0.7, 0.9, 1.2, 1.6, 2.6], p=[.3, .3, .2, .15, .05])
        d.ellipse([x - r, y - r * rng.uniform(.6, 1), x + r, y + r], fill=int(rng.uniform(120, 255)))
    for _ in range(hairs):       # curly fibres: a random walk with momentum
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        ang, curl = rng.uniform(0, 6.28), rng.uniform(-.12, .12)
        pts = []
        for _ in range(int(rng.uniform(40, 130))):
            pts.append((x, y))
            ang += curl + rng.normal(0, .08)
            x, y = x + np.cos(ang) * 2, y + np.sin(ang) * 2
        d.line(pts, fill=int(rng.uniform(140, 230)), width=1)
    return np.asarray(img.filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255


# ---------------------------------------------------------------- frame

def make_frame(spec):
    rng = np.random.default_rng(spec["seed"])
    gl, gt, gr, gb = spec["gap"]            # white gap, PNG px
    rl, rt, rr, rb = spec["rebate"]         # film border thickness, PNG px

    # Outer film edge
    d_out = rrect_sdf(gl, gt, W - gr, H - gb, spec.get("outer_radius", 3))
    if spec.get("cut_tilt"):                # scissor cuts are never square
        t0, t1 = spec["cut_tilt"]
        d_out = np.maximum(d_out, (gt + (X / W - .5) * t0) - Y)
        d_out = np.maximum(d_out, Y - (H - gb + (X / W - .5) * t1))
    for sigma, amp in spec["outer_rough"]:
        d_out = d_out + noise(rng, sigma) * amp
    film_outer = cov(d_out, spec.get("outer_soft", 1.4))

    # Exposure window (camera gate): straight-ish, soft, rounded corners
    wx0, wy0, wx1, wy1 = gl + rl, gt + rt, W - gr - rr, H - gb - rb
    d_in = rrect_sdf(wx0, wy0, wx1, wy1, spec.get("gate_radius", 10))
    for sigma, amp in spec["inner_rough"]:
        d_in = d_in + noise(rng, sigma) * amp
    window = cov(d_in, spec.get("inner_soft", 3.0))

    # Things poking into the window from the gate edge
    intrusions = np.zeros((H, W), np.float32)
    if spec.get("notches"):                 # Hasselblad-style V notches, left edge
        polys = []
        for fy in spec["notches"]:
            y = wy0 + (wy1 - wy0) * fy
            polys.append([(wx0 - 4, y - 17), (wx0 + 22, y), (wx0 - 4, y + 17)])
        intrusions = np.maximum(intrusions, polygon_mask(polys))
    if spec.get("gate_fuzz"):               # fibres and crud stuck to the gate
        img = Image.new("L", (W, H), 0)
        d = ImageDraw.Draw(img)
        for _ in range(spec["gate_fuzz"]):
            side = rng.integers(4)
            t = rng.uniform(.03, .97)
            r = rng.uniform(1.5, 4.5)
            x, y = [(wx0, wy0 + (wy1 - wy0) * t), (wx1, wy0 + (wy1 - wy0) * t),
                    (wx0 + (wx1 - wx0) * t, wy0), (wx0 + (wx1 - wx0) * t, wy1)][side]
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        intrusions = np.maximum(
            intrusions, np.asarray(img.filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255)
    window = window * (1 - intrusions)
    film = film_outer * (1 - window)

    # --- composite, bottom to top
    rgb = np.zeros((H, W, 3), np.float32)
    a = np.zeros((H, W), np.float32)

    # White paper everywhere outside the film (tucked 3px under its edge)
    paper = 1 - cov(d_out + 3, 1.2)
    rgb, a = over(rgb, a, np.float32([255, 255, 255]), paper)

    if spec.get("shadow"):                  # film strip lying on a lightbox
        sh = gaussian_filter(film_outer, 9) * spec["shadow"] * paper
        rgb, a = over(rgb, a, np.float32([40, 36, 30]), sh)

    # Film base with a little grain and uneven density
    base = np.float32(spec["film_rgb"])
    tone = 1 + noise(rng, 60)[..., None] * .10 + rng.standard_normal((H, W, 1)).astype(np.float32) * .16
    rgb, a = over(rgb, a, np.clip(base * tone, 0, 255), film)

    # Edge markings, slightly uneven with a touch of halation
    if spec.get("markings"):
        m = np.zeros((H, W), np.float32)
        for orient, center, strip in spec["markings"](wx0, wy0, wx1, wy1):
            m = np.maximum(m, place_strip(strip, orient, center, wy0 if orient == "v" else wx0))
        m = gaussian_filter(m, .7) * np.clip(.82 + noise(rng, 5) * .14, .4, 1)
        glow = gaussian_filter(m, 5) * .35
        ink = np.float32(spec["ink_rgb"])
        rgb, a = over(rgb, a, ink, np.clip(glow, 0, 1) * film)
        rgb, a = over(rgb, a, ink, np.clip(m, 0, 1) * film)

    # Light leak: fogging that spills from the film edge into the picture
    if spec.get("leak"):
        band = noise(rng, 90)
        reach = 150 + 110 * band
        f = np.exp(-np.maximum(W - gr - X, 0) / np.maximum(reach, 30))
        f *= np.clip(.55 + .6 * noise(rng, 140), 0, 1)
        f2 = np.exp(-np.hypot(X - gl, Y - gt) / 260) * .8     # corner bloom
        leak = np.clip(np.maximum(f, f2) * spec["leak"], 0, .93) * film_outer
        hot = np.clip(leak * 1.3, 0, 1)[..., None]
        leak_rgb = np.float32([255, 74, 22]) * (1 - hot) + np.float32([255, 214, 140]) * hot
        rgb, a = over(rgb, a, leak_rgb, leak)

    if spec.get("dust"):
        specks, hairs, strength = spec["dust"]
        dm = dust_mask(rng, specks, hairs, (gl, gt, W - gr, H - gb)) * film_outer * strength
        rgb, a = over(rgb, a, np.float32([250, 248, 240]), dm)

    # un-premultiply
    out = np.zeros((H, W, 4), np.uint8)
    out[..., :3] = np.clip(rgb / np.maximum(a[..., None], 1e-4), 0, 255).round()
    out[..., 3] = np.clip(a * 255, 0, 255).round()

    inset = [gl + rl, gt + rt, gr + rr, gb + rb]
    margins = [max(0, min(99, (v - TUCK) // CANVAS_SCALE)) for v in inset]
    return Image.fromarray(out, "RGBA"), margins


# ---------------------------------------------------------------- the pack

def amber_markings(wx0, wy0, wx1, wy1):
    length = int(wy1 - wy0)
    left = edge_strip(length, 56, [
        (.03, "text", "KOLAZ 400-2"), (.24, "arrow", 9), (.27, "text", "11"),
        (.40, "bars", 7), (.56, "text", "KOLAZ 400-2"), (.77, "arrow", 9), (.80, "text", "11A"),
    ], FONT_DIN, 38)
    right = edge_strip(length, 56, [
        (.06, "bars", 3), (.30, "text", "11"), (.52, "text", "SAFETY FILM"), (.80, "text", "12"),
    ], FONT_DIN, 38)
    return [("v", wx0 - 38, left), ("v", wx1 + 38, right)]


def pan_markings(wx0, wy0, wx1, wy1):
    length = int(wy1 - wy0)
    left = edge_strip(length, 48, [
        (.05, "text", "KOLAZ PAN 100"), (.36, "arrow", 8), (.39, "text", "7"),
        (.55, "text", "KOLAZ PAN 100"), (.86, "arrow", 8), (.89, "text", "7A"),
    ], FONT_NARROW, 30)
    right = edge_strip(length, 48, [
        (.12, "text", "7"), (.45, "text", "120"), (.62, "text", "7A"),
    ], FONT_NARROW, 30)
    return [("v", wx0 - 32, left), ("v", wx1 + 32, right)]


def portra400_markings(wx0, wy0, wx1, wy1):
    length = int(wy1 - wy0)
    left = edge_strip(length, 54, [
        (.04, "text", "KODAK PORTRA 400"), (.30, "arrow", 8), (.33, "text", "9"),
        (.54, "text", "KODAK PORTRA 400"), (.80, "arrow", 8), (.83, "text", "9A"),
    ], FONT_DIN, 36)
    right = edge_strip(length, 54, [
        (.08, "text", "9"), (.30, "bars", 12), (.58, "text", "10"), (.78, "bars", 5),
    ], FONT_DIN, 36)
    return [("v", wx0 - 36, left), ("v", wx1 + 36, right)]


def portra160_markings(wx0, wy0, wx1, wy1):
    length = int(wx1 - wx0)
    top = edge_strip(length, 54, [
        (.04, "text", "KODAK PORTRA 160"), (.46, "arrow", 8), (.49, "text", "5"),
        (.70, "bars", 9),
    ], FONT_DIN, 36)
    bottom = edge_strip(length, 54, [
        (.06, "text", "5"), (.30, "bars", 4), (.62, "text", "KODAK PORTRA 160"),
    ], FONT_DIN, 36)
    return [("h", wy0 - 35, top), ("h", wy1 + 37, bottom)]


def hp5_markings(wx0, wy0, wx1, wy1):
    length = int(wy1 - wy0)
    left = edge_strip(length, 50, [
        (.05, "text", "ILFORD HP5 PLUS"), (.34, "arrow", 8), (.37, "text", "23"),
        (.56, "text", "ILFORD HP5 PLUS"), (.85, "arrow", 8), (.88, "text", "23A"),
    ], FONT_NARROW, 30)
    right = edge_strip(length, 50, [
        (.10, "text", "23"), (.48, "text", "SAFETY FILM"), (.84, "text", "24"),
    ], FONT_NARROW, 30)
    return [("v", wx0 - 34, left), ("v", wx1 + 34, right)]


def delta_markings(wx0, wy0, wx1, wy1):
    length = int(wy1 - wy0)
    left = edge_strip(length, 50, [
        (.06, "text", "ILFORD DELTA 100 PROFESSIONAL"), (.62, "arrow", 8), (.65, "text", "14"),
    ], FONT_NARROW, 30)
    right = edge_strip(length, 50, [(.14, "text", "14"), (.74, "text", "15")], FONT_NARROW, 30)
    return [("v", wx0 - 31, left), ("v", wx1 + 31, right)]


FRAMES = [
    dict(name="Notch", seed=11, gap=(58, 58, 58, 58), rebate=(40, 40, 40, 40),
         film_rgb=(15, 15, 16), outer_rough=[(30, 2.2), (4, 1.2)], outer_soft=2.0,
         inner_rough=[(50, 1.4), (5, .8)], gate_radius=12, notches=(.62, .70), gate_fuzz=7,
         dust=(40, 1, .55)),
    dict(name="Amber400", seed=23, gap=(52, 60, 52, 60), rebate=(78, 34, 78, 34),
         film_rgb=(20, 14, 11), outer_rough=[(3, .5)], outer_radius=1, cut_tilt=(7, -5),
         inner_rough=[(60, 1.5), (6, .7)], gate_radius=9, shadow=.30,
         markings=amber_markings, ink_rgb=(238, 146, 44), dust=(30, 0, .45)),
    dict(name="Sloppy", seed=37, gap=(74, 78, 74, 78), rebate=(50, 54, 50, 54),
         film_rgb=(12, 12, 12), outer_rough=[(70, 8), (14, 6), (3.5, 2.6)], outer_soft=7,
         outer_radius=16, inner_rough=[(40, 2.0), (4, 1.0)], gate_radius=14, inner_soft=3.5,
         gate_fuzz=4),
    dict(name="Pan100", seed=41, gap=(56, 62, 56, 62), rebate=(66, 28, 66, 28),
         film_rgb=(16, 16, 16), outer_rough=[(3, .5)], outer_radius=1, cut_tilt=(-6, 8),
         inner_rough=[(60, 1.2), (5, .7)], gate_radius=6, shadow=.30,
         markings=pan_markings, ink_rgb=(226, 226, 220), dust=(60, 2, .6)),
    dict(name="Leak", seed=53, gap=(58, 58, 58, 58), rebate=(44, 36, 44, 36),
         film_rgb=(17, 13, 12), outer_rough=[(26, 2.4), (4, 1.2)], outer_soft=2.0,
         inner_rough=[(50, 1.6), (5, .8)], gate_radius=10, gate_fuzz=5, leak=.95,
         dust=(25, 0, .5)),
    dict(name="Dust", seed=67, gap=(60, 60, 60, 60), rebate=(26, 26, 26, 26),
         film_rgb=(18, 17, 16), outer_rough=[(40, 2.5), (2.2, 2.4), (1.2, 1.4)], outer_soft=1.6,
         inner_rough=[(30, 1.8), (3, 1.3)], gate_radius=7, gate_fuzz=14, dust=(420, 9, .8)),
    # Subtle, clean-edged film stocks with orange-yellow edge printing
    dict(name="Portra400", seed=71, gap=(56, 60, 56, 60), rebate=(74, 32, 74, 32),
         film_rgb=(19, 14, 11), outer_rough=[(40, .8)], outer_radius=2, outer_soft=1.6,
         cut_tilt=(3, -2), inner_rough=[(60, 1.0), (6, .4)], gate_radius=8, inner_soft=2.5,
         shadow=.22, markings=portra400_markings, ink_rgb=(244, 160, 48), dust=(12, 0, .35)),
    dict(name="Portra160", seed=73, gap=(58, 58, 58, 58), rebate=(30, 72, 30, 72),
         film_rgb=(18, 14, 11), outer_rough=[(40, .8)], outer_radius=2, outer_soft=1.6,
         inner_rough=[(60, 1.0), (6, .4)], gate_radius=8, inner_soft=2.5,
         shadow=.22, markings=portra160_markings, ink_rgb=(246, 168, 56), dust=(10, 0, .35)),
    dict(name="HP5", seed=79, gap=(56, 60, 56, 60), rebate=(68, 30, 68, 30),
         film_rgb=(16, 16, 16), outer_rough=[(40, .8)], outer_radius=2, outer_soft=1.6,
         cut_tilt=(-3, 2), inner_rough=[(60, 1.0), (6, .4)], gate_radius=6, inner_soft=2.5,
         shadow=.22, markings=hp5_markings, ink_rgb=(247, 186, 72), dust=(14, 0, .35)),
    dict(name="Delta100", seed=83, gap=(58, 58, 58, 58), rebate=(62, 36, 62, 36),
         film_rgb=(15, 15, 16), outer_rough=[(30, 1.1), (5, .4)], outer_soft=1.8,
         inner_rough=[(60, 1.0), (6, .4)], gate_radius=10, inner_soft=2.5,
         markings=delta_markings, ink_rgb=(245, 176, 62), dust=(10, 0, .3)),
]


def write_imageset(name, image):
    d = os.path.join(PACK_DIR, f"{name}.imageset")
    os.makedirs(d)
    image.save(os.path.join(d, f"{name}.png"), optimize=True)
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)


def main():
    preview_path = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == "--preview" else None
    shutil.rmtree(PACK_DIR, ignore_errors=True)
    os.makedirs(PACK_DIR)
    with open(os.path.join(PACK_DIR, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    with open(os.path.join(PACK_DIR, "..", "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

    rendered = []
    for spec in FRAMES:
        image, m = make_frame(spec)
        name = "Analog916_%s_m%02d%02d%02d%02d_r9x16" % (spec["name"], *m)
        write_imageset(name, image)
        rendered.append(image)
        print(name)

    if preview_path:                        # contact sheet over a fake photo
        tw, th = W // 2, H // 2
        rows = (len(rendered) + 4) // 5
        sheet = Image.new("RGB", (tw * 5 + 60, th * rows + 10 * (rows + 1)), (120, 120, 120))
        gy, gx = np.mgrid[0:th, 0:tw]
        photo = np.stack([90 + 120 * gy / th, 140 + 60 * gx / tw, 200 - 110 * gy / th], -1)
        photo = Image.fromarray(photo.astype(np.uint8), "RGB")
        for i, image in enumerate(rendered):
            tile = photo.copy()
            tile.paste(image.resize((tw, th), Image.LANCZOS), (0, 0), image.resize((tw, th), Image.LANCZOS))
            sheet.paste(tile, (10 + (i % 5) * (tw + 10), 10 + (i // 5) * (th + 10)))
        sheet.save(preview_path)


if __name__ == "__main__":
    main()
