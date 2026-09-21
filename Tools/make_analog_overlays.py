#!/usr/bin/env python3
"""Generates the analog overlay packs (9:16):

  Assets.xcassets/Overlays/Dust916/Dust916_<Name>.imageset   dust & scratches
  Assets.xcassets/Overlays/Leak916/Leak916_<Name>.imageset   light leaks

Dust overlays are 1152x2048 (pixel-exact at export) so specks stay crisp.
Light leaks are smooth, so they ship at 576x1024; the app screen-blends them.
Both are straight-alpha PNGs on a transparent background.

Usage:  venv/bin/python Tools/make_analog_overlays.py [--preview out.png]
        (same venv as make_analog_frames.py: pillow numpy scipy)
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter

ROOT = os.path.join(os.path.dirname(__file__), "..", "CollageStudio", "Assets.xcassets", "Overlays")


def write_imageset(pack, name, image):
    d = os.path.join(ROOT, pack, f"{name}.imageset")
    os.makedirs(d)
    image.save(os.path.join(d, f"{name}.png"), optimize=True)
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)


def write_folder(path):
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)


# ------------------------------------------------------------ dust & scratches

DW, DH = 1152, 2048


class DustCanvas:
    """Light and dark debris drawn on separate masks, merged into one RGBA."""

    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.light = Image.new("L", (DW, DH), 0)
        self.dark = Image.new("L", (DW, DH), 0)

    def _draw(self, dark):
        return ImageDraw.Draw(self.dark if dark else self.light)

    def specks(self, count, big=.05, dark=False):
        d, rng = self._draw(dark), self.rng
        for _ in range(count):
            x, y = rng.uniform(0, DW), rng.uniform(0, DH)
            r = rng.choice([.7, 1.0, 1.4, 2.0, 3.4], p=[.34 - big, .3, .2, .16, big])
            d.ellipse([x - r, y - r * rng.uniform(.5, 1), x + r, y + r],
                      fill=int(rng.uniform(110, 255)))

    def clumps(self, count, dark=False):
        """Irregular crumbs: a few overlapping blobs."""
        d, rng = self._draw(dark), self.rng
        for _ in range(count):
            x, y = rng.uniform(0, DW), rng.uniform(0, DH)
            for _ in range(rng.integers(3, 8)):
                r = rng.uniform(1.2, 4.0)
                ox, oy = rng.normal(0, 3.5, 2)
                d.ellipse([x + ox - r, y + oy - r, x + ox + r, y + oy + r],
                          fill=int(rng.uniform(150, 255)))

    def hairs(self, count, length=(50, 170), dark=False):
        """Curly fibres: a random walk with momentum."""
        d, rng = self._draw(dark), self.rng
        for _ in range(count):
            x, y = rng.uniform(0, DW), rng.uniform(0, DH)
            ang, curl = rng.uniform(0, 6.28), rng.uniform(-.10, .10)
            pts = []
            for _ in range(int(rng.uniform(*length))):
                pts.append((x, y))
                ang += curl + rng.normal(0, .07)
                x, y = x + np.cos(ang) * 2.2, y + np.sin(ang) * 2.2
            d.line(pts, fill=int(rng.uniform(130, 230)), width=int(rng.choice([1, 1, 2])))

    def scratches(self, count, dark=False):
        """Film-transport scratches: long, near-vertical, broken in places."""
        d, rng = self._draw(dark), self.rng
        for _ in range(count):
            x = rng.uniform(0, DW)
            y, y_end = rng.uniform(-200, DH * .6), 0
            y_end = y + rng.uniform(DH * .25, DH * 1.1)
            drift = rng.normal(0, .015)
            level = rng.uniform(70, 210)
            while y < y_end:
                seg = rng.uniform(30, 260)
                if rng.random() < .8:       # gaps where the scratch skipped
                    x2 = x + drift * seg + rng.normal(0, .4)
                    d.line([(x, y), (x2, y + seg)], fill=int(level * rng.uniform(.6, 1)), width=1)
                    x = x2
                y += seg

    def nicks(self, count, dark=False):
        """Short random-direction scuffs from handling."""
        d, rng = self._draw(dark), self.rng
        for _ in range(count):
            x, y = rng.uniform(0, DW), rng.uniform(0, DH)
            ang, ln = rng.uniform(0, 6.28), rng.uniform(8, 46)
            d.line([(x, y), (x + np.cos(ang) * ln, y + np.sin(ang) * ln)],
                   fill=int(rng.uniform(90, 200)), width=1)

    def rings(self, count):
        """Faint drying marks left by water drops."""
        d, rng = self._draw(False), self.rng
        for _ in range(count):
            x, y, r = rng.uniform(0, DW), rng.uniform(0, DH), rng.uniform(18, 70)
            d.ellipse([x - r, y - r * rng.uniform(.8, 1.1), x + r, y + r],
                      outline=int(rng.uniform(40, 90)), width=2)

    def image(self):
        light = np.asarray(self.light.filter(ImageFilter.GaussianBlur(.6)), np.float32) / 255
        dark = np.asarray(self.dark.filter(ImageFilter.GaussianBlur(.7)), np.float32) / 255
        a = light + dark * (1 - light)
        tone = np.where(a > 0, light / np.maximum(a, 1e-4), 1)[..., None]
        rgb = np.float32([18, 15, 13]) * (1 - tone) + np.float32([252, 249, 240]) * tone
        out = np.dstack([rgb, a[..., None] * 255]).clip(0, 255).round().astype(np.uint8)
        return Image.fromarray(out, "RGBA")


def dust_fine(c):
    c.specks(260, big=.02)
    c.hairs(2, (30, 80))


def dust_heavy(c):
    c.specks(1500)
    c.clumps(40)
    c.hairs(9)
    c.nicks(30)


def dust_hairs(c):
    c.hairs(22, (70, 220))
    c.specks(180, big=.03)


def dust_scratches(c):
    c.scratches(16)
    c.nicks(40)
    c.specks(160, big=.02)


def dust_grit(c):           # print-style dark debris with a little light dust
    c.specks(520, dark=True)
    c.clumps(26, dark=True)
    c.hairs(7, dark=True)
    c.specks(180, big=.02)


def dust_worn(c):           # a negative that lived in a shoebox
    c.scratches(9)
    c.rings(12)
    c.specks(800)
    c.clumps(18)
    c.hairs(6)
    c.nicks(60)
    c.specks(140, dark=True)


DUST = [("Fine", 101, dust_fine), ("Heavy", 103, dust_heavy), ("Hairs", 107, dust_hairs),
        ("Scratches", 109, dust_scratches), ("Grit", 113, dust_grit), ("Worn", 127, dust_worn)]


# ------------------------------------------------------------ light leaks

LW, LH = 576, 1024
LY, LX = np.mgrid[0:LH, 0:LW].astype(np.float32)
U, V = LX / LW, LY / LH             # 0..1 across / down

WARM = [(0, (255, 30, 8)), (.35, (255, 70, 14)), (.65, (255, 145, 32)), (.88, (255, 212, 112)),
        (1, (255, 246, 218))]
MAGENTA = [(0, (220, 20, 130)), (.45, (244, 48, 120)), (.75, (255, 112, 98)), (1, (255, 228, 194))]
GOLD = [(0, (240, 96, 10)), (.45, (254, 152, 30)), (.8, (255, 214, 120)), (1, (255, 250, 228))]


def lnoise(rng, sigma):
    n = gaussian_filter(rng.standard_normal((LH, LW)).astype(np.float32), sigma)
    return n / (n.std() + 1e-6)


def wobble(rng, sigma, lo, hi):
    """Smooth multiplier between lo and hi — no hard plateaus."""
    return lo + (hi - lo) * (.5 + .5 * np.tanh(lnoise(rng, sigma)))


def ramp(f, stops):
    xs = [s[0] for s in stops]
    return np.dstack([np.interp(f, xs, [s[1][i] for s in stops]) for i in range(3)])


def leak_image(rng, f, stops, strength=.95):
    """f: leak intensity 0..1. Hotter areas are both brighter and more opaque;
    the faint tail is cut so the leak stays local instead of fogging the frame."""
    f = np.clip((np.clip(f, 0, 1) - .06) / .94, 0, 1)
    grain = 1 + rng.standard_normal((LH, LW)).astype(np.float32) * .05
    a = np.clip(f ** .75 * strength * grain, 0, 1)
    a = a + (rng.random((LH, LW)).astype(np.float32) - .5) / 255     # dither banding away
    out = np.dstack([ramp(f, stops), a[..., None] * 255]).clip(0, 255).round().astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def leak_edge(rng):         # camera back not quite closed: fog from the right edge
    reach = wobble(rng, 70, .07, .22)
    return leak_image(rng, np.exp(-(1 - U) / reach) * wobble(rng, 90, .7, 1.05), WARM)


def leak_corner(rng):       # bloom out of the top-left corner
    d = np.hypot(U * .9, V * 1.6) * wobble(rng, 70, .85, 1.15)
    return leak_image(rng, np.exp(-d / .22), WARM)


def leak_band(rng):         # slit leak: a soft vertical band with a hot core
    cx = .68 + .05 * np.sin(V * 5) + .02 * lnoise(rng, 80)
    core = np.exp(-((U - cx) / .05) ** 2)
    halo = np.exp(-((U - cx) / .16) ** 2) * .6
    return leak_image(rng, np.maximum(core, halo) * wobble(rng, 90, .45, 1.05), WARM)


def leak_burn(rng):         # end of the roll: the top of the frame burnt out
    edge = .24 + .05 * np.tanh(lnoise(rng, 60)) + .02 * np.sin(U * 9)
    body = 1 / (1 + np.exp((V - edge) / .035))
    f = body * (.5 + .55 * np.exp(-V / .09))        # white-hot only at the very top
    return leak_image(rng, f, WARM, strength=1.0)


def leak_magenta(rng):      # expired-film pink creeping in from the left and bottom
    side = np.exp(-U / wobble(rng, 80, .08, .22))
    floor = np.exp(-(1 - V) / .10) * .75
    return leak_image(rng, np.maximum(side, floor) * wobble(rng, 90, .7, 1.05), MAGENTA)


def leak_streaks(rng):      # diagonal streaks of stray light
    t = U * .8 + V * .45
    f = np.zeros((LH, LW), np.float32)
    for center, width, gain in [(.30, .03, .9), (.47, .06, .6), (.78, .045, .85), (.95, .08, .65)]:
        f = np.maximum(f, np.exp(-((t - center) / width) ** 2) * gain)
    return leak_image(rng, f * wobble(rng, 100, .35, 1.1), GOLD)


LEAKS = [("Edge", 201, leak_edge), ("Corner", 203, leak_corner), ("Band", 207, leak_band),
         ("Burn", 211, leak_burn), ("Magenta", 223, leak_magenta), ("Streaks", 227, leak_streaks)]


# ------------------------------------------------------------ main

def main():
    preview_path = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == "--preview" else None
    shutil.rmtree(ROOT, ignore_errors=True)
    write_folder(ROOT)
    write_folder(os.path.join(ROOT, "Dust916"))
    write_folder(os.path.join(ROOT, "Leak916"))

    rendered = []
    for name, seed, build in DUST:
        canvas = DustCanvas(seed)
        build(canvas)
        image = canvas.image()
        write_imageset("Dust916", f"Dust916_{name}", image)
        rendered.append(("normal", image))
        print(f"Dust916_{name}")
    for name, seed, build in LEAKS:
        image = build(np.random.default_rng(seed))
        write_imageset("Leak916", f"Leak916_{name}", image)
        rendered.append(("screen", image))
        print(f"Leak916_{name}")

    if preview_path:                        # contact sheet over a fake photo
        tw, th = 288, 512
        gy, gx = np.mgrid[0:th, 0:tw]
        photo = np.stack([40 + 90 * gy / th, 70 + 60 * gx / tw, 120 - 60 * gy / th], -1).astype(np.float32)
        sheet = Image.new("RGB", (tw * 6 + 70, th * 2 + 30), (128, 128, 128))
        for i, (mode, image) in enumerate(rendered):
            o = np.asarray(image.resize((tw, th), Image.LANCZOS), np.float32)
            rgb, a = o[..., :3], o[..., 3:] / 255
            if mode == "screen":
                blended = 255 - (255 - photo) * (255 - rgb) / 255
            else:
                blended = rgb
            tile = photo * (1 - a) + blended * a
            sheet.paste(Image.fromarray(tile.clip(0, 255).astype(np.uint8), "RGB"),
                        (10 + (i % 6) * (tw + 10), 10 + (i // 6) * (th + 10)))
        sheet.save(preview_path)


if __name__ == "__main__":
    main()
