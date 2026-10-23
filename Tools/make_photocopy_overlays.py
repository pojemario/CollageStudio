#!/usr/bin/env python3
"""Generates the Photocopy overlay pack (9:16), drawn from scratch:

  Assets.xcassets/Overlays/Copy916/Copy916_PC<NN>.imageset

What a picture goes through on an office copier: blotchy toner in the
darks, the lamp's soft band of light, streaks from a scratched drum, the
shadow of the lid, a warm paper cast, white dropouts. 1152x2048 straight-
alpha PNGs, laid over the collage as they are (normal blend); each also
gets a "_Thumb" picker thumbnail over a sample photo.

Usage:  venv/bin/python Tools/make_photocopy_overlays.py [--preview out.png]
        (same venv as make_analog_overlays.py: pillow numpy scipy)
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, zoom

sys.path.insert(0, os.path.dirname(__file__))
from make_analog_overlays import ROOT, write_folder, write_imageset  # noqa: E402

W, H = 1152, 2048
TW, TH = 180, 320
PACK = "Copy916"

TONER = np.float32([34, 26, 20])        # warm black
PAPER = np.float32([244, 234, 214])     # cream
WARM = np.float32([196, 160, 112])      # the copier's sepia cast


class Copy:
    """Premultiplied RGBA layers composited "over", like paint on glass."""

    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.rgb = np.zeros((H, W, 3), np.float32)   # premultiplied
        self.a = np.zeros((H, W), np.float32)
        self.y, self.x = np.mgrid[0:H, 0:W].astype(np.float32)

    def paint(self, color, alpha):
        alpha = np.clip(alpha, 0, 1).astype(np.float32)
        self.rgb = color * alpha[..., None] + self.rgb * (1 - alpha[..., None])
        self.a = alpha + self.a * (1 - alpha)

    def noise(self, scale, octaves=3):
        """Smooth noise, about 0...1, with features `scale` pixels across."""
        total, amp, norm = np.zeros((H, W), np.float32), 1.0, 0.0
        for o in range(octaves):
            s = max(scale / 2 ** o, 2)
            small = self.rng.standard_normal((int(H / s) + 2, int(W / s) + 2)).astype(np.float32)
            big = zoom(small, s, order=3)[:H, :W]
            total += big * amp
            norm += amp
            amp *= .5
        total /= norm
        return np.clip(total * .35 + .5, 0, 1)

    # -------------------------------------------------------------- elements

    def warm_cast(self, strength):
        self.paint(WARM, np.full((H, W), strength))

    def wash(self, strength):
        """Faded, low-contrast copy: a veil of paper."""
        self.paint(PAPER, np.full((H, W), strength) * (.85 + .3 * self.noise(500, 2)))

    def mottle(self, strength, scale=60, coverage=.5):
        """Toner that went down unevenly: blotches."""
        n = self.noise(scale, 4)
        blot = np.clip((n - (1 - coverage)) / .18, 0, 1)
        self.paint(TONER, blot * strength * (.7 + .6 * self.noise(scale / 4, 2)))

    def speckle(self, count, dark=True, size=(.6, 2.2)):
        m = np.zeros((H, W), np.float32)
        ys = self.rng.integers(0, H, count)
        xs = self.rng.integers(0, W, count)
        m[ys, xs] = self.rng.uniform(.4, 1, count)
        m = gaussian_filter(m, self.rng.uniform(*size)) * 9
        self.paint(TONER if dark else PAPER, np.clip(m, 0, 1))

    def grain(self, strength):
        """Coarse toner grain, only the strongest grains (the app's own
        Grain effect does the fine stuff, and the PNGs stay small)."""
        g = gaussian_filter(self.rng.standard_normal((H, W)).astype(np.float32), .9)
        g = g / g.std()
        self.paint(TONER, np.clip((g - 2.6) * 2, 0, 1) * strength)
        self.paint(PAPER, np.clip((-g - 2.8) * 2, 0, 1) * strength * .8)

    def haze(self, strength, scale=90, coverage=.5):
        """Pale fog in patches, strongest over the darks on a real copy."""
        n = gaussian_filter(self.noise(scale, 4), 3)
        fog = np.clip((n - (1 - coverage)) / .4, 0, 1) ** 1.5
        self.paint(PAPER, fog * strength * (.75 + .5 * self.noise(scale / 3, 2)))

    def lamp_band(self, x0, width, strength, hard_edge=False):
        """The copier lamp's band of light running down the page."""
        d = (self.x - x0 * W) / (width * W)
        # Flat across, with soft but definite edges.
        band = 1 / (1 + np.exp(np.minimum((np.abs(d) - 1) * 9, 50)))
        if hard_edge:                       # the edge of the glass / the page
            band = np.where(d < 0, np.exp(-d ** 2 * 40), band)
            line = np.exp(-((self.x - x0 * W) / 1.6) ** 2) * .5
            self.paint(PAPER, line * (.8 + .2 * self.noise(200, 2)))
        wobble = .8 + .4 * self.noise(700, 2)
        self.paint(PAPER, band * strength * wobble)

    def lid_shadow(self, side, depth, strength):
        """Where the lid didn't close: a dark edge, ragged."""
        edge = self.x if side == "left" else (W - 1 - self.x)
        ragged = depth * W * (.8 + .5 * self.noise(300, 3))
        shade = np.clip(1 - edge / ragged, 0, 1) ** 1.6
        self.paint(TONER, shade * strength)

    def drum_streaks(self, count, strength, light_share=.3):
        """Thin lines straight down the page from a scratched drum."""
        for _ in range(count):
            x = self.rng.uniform(0, W)
            w = self.rng.uniform(.6, 3.5)
            col = np.exp(-((self.x[0] - x) / w) ** 2)
            fade = np.clip(self.noise(900, 1)[:, int(x) % W] * 1.6 - .2, 0, 1)
            alpha = col[None, :] * fade[:, None] * strength * self.rng.uniform(.4, 1)
            light = self.rng.random() < light_share
            self.paint(PAPER if light else TONER, alpha)

    def scan_bands(self, count, strength):
        """Faint horizontal bands where the scan stuttered."""
        for _ in range(count):
            y = self.rng.uniform(0, H)
            h = self.rng.uniform(2, 14)
            row = np.exp(-((self.y[:, 0] - y) / h) ** 2)
            dark = self.rng.random() < .6
            self.paint(TONER if dark else PAPER, row[:, None] * np.ones((1, W)) * strength * self.rng.uniform(.4, 1))

    def dropouts(self, strength, scale=40):
        """Patches where the toner didn't take: white holes in the darks."""
        n = self.noise(scale, 3)
        holes = gaussian_filter(np.clip((n - .78) / .06, 0, 1), 1.5)
        self.paint(PAPER, holes * strength)

    def image(self):
        a = np.clip(self.a, 0, 1)
        rgb = np.where(a[..., None] > 1e-4, self.rgb / np.maximum(a[..., None], 1e-4), 0)
        out = np.dstack([rgb, a * 255]).clip(0, 255).astype(np.uint8)
        return Image.fromarray(out, "RGBA")


# ------------------------------------------------------------------ the pack

def pc01(c):            # the lamp's band of light down the left, light grain
    c.warm_cast(.10)
    c.lamp_band(.2, .035, .34)
    c.grain(.35)
    c.speckle(900)


def pc02(c):            # pale haze in patches, warm
    c.warm_cast(.14)
    c.haze(.42, scale=110, coverage=.5)
    c.grain(.45)
    c.speckle(1400)


def pc03(c):            # scratched drum: streaks straight down
    c.warm_cast(.08)
    c.drum_streaks(26, .55)
    c.grain(.3)
    c.speckle(600)


def pc04(c):            # lid left open: dark ragged edge and the lamp's band
    c.warm_cast(.10)
    c.lid_shadow("right", .16, .85)
    c.lamp_band(.2, .03, .26)
    c.grain(.4)


def pc05(c):            # the edge of the glass: a hard bright line, band beside it
    c.warm_cast(.10)
    c.lamp_band(.82, .04, .3, hard_edge=True)
    c.grain(.35)
    c.speckle(800)


def pc06(c):            # toner that didn't take: white dropouts, fine dark dust
    c.warm_cast(.08)
    c.dropouts(.55)
    c.speckle(2600, size=(.5, 1.2))
    c.speckle(500, dark=False, size=(.6, 1.6))
    c.grain(.35)


def pc07(c):            # faded copy of a copy
    c.wash(.22)
    c.warm_cast(.10)
    c.mottle(.16, scale=110, coverage=.4)
    c.scan_bands(7, .14)
    c.grain(.3)


def pc08(c):            # everything at once: a worn, much-copied page
    c.warm_cast(.14)
    c.haze(.3, scale=90, coverage=.45)
    c.mottle(.16, scale=60, coverage=.35)
    c.lamp_band(.14, .03, .3)
    c.lid_shadow("right", .1, .6)
    c.drum_streaks(12, .4)
    c.scan_bands(4, .12)
    c.dropouts(.35)
    c.grain(.45)
    c.speckle(1500)


PACK_ITEMS = [("PC01", 501, pc01), ("PC02", 502, pc02), ("PC03", 503, pc03), ("PC04", 504, pc04),
              ("PC05", 505, pc05), ("PC06", 506, pc06), ("PC07", 507, pc07), ("PC08", 508, pc08)]


# ------------------------------------------------------------------ thumbnails

def sample_photo(w=TW, h=TH):
    """A light wall with a dark figure: where copier marks show."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    img = np.dstack([200 - 40 * y / h + 10 * x / w] * 3)
    fig = (((x - w * .52) / (w * .2)) ** 2 + ((y - h * .62) / (h * .34)) ** 2) < 1
    head = (((x - w * .52) / (w * .1)) ** 2 + ((y - h * .25) / (h * .07)) ** 2) < 1
    img[fig | head] = 46
    img = gaussian_filter(img, (1.2, 1.2, 0))
    return img * np.float32([1.0, .97, .92])


def thumbnail(image, photo):
    o = np.asarray(image.resize((TW, TH), Image.LANCZOS), np.float32)
    a = np.clip(o[..., 3:] / 255 * 1.3, 0, 1)
    return Image.fromarray((photo * (1 - a) + o[..., :3] * a).clip(0, 255).astype(np.uint8), "RGB")


def main():
    preview = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == "--preview" else None
    folder = os.path.join(ROOT, PACK)
    shutil.rmtree(folder, ignore_errors=True)
    write_folder(folder)
    photo = sample_photo()
    big = sample_photo(576, 1024)
    shots = []
    for name, seed, build in PACK_ITEMS:
        c = Copy(seed)
        build(c)
        image = c.image()
        write_imageset(PACK, f"{PACK}_{name}", image)
        write_imageset(PACK, f"{PACK}_{name}_Thumb", thumbnail(image, photo))
        if preview:
            o = np.asarray(image.resize((576, 1024), Image.LANCZOS), np.float32)
            a = o[..., 3:] / 255
            shots.append(Image.fromarray((big * (1 - a) + o[..., :3] * a).clip(0, 255).astype(np.uint8)))
        print(f"{PACK}_{name}")
    if preview:
        sheet = Image.new("RGB", (4 * 586 + 10, 2 * 1034 + 10), (90, 90, 90))
        for i, s in enumerate(shots):
            sheet.paste(s, (10 + (i % 4) * 586, 10 + (i // 4) * 1034))
        sheet.save(preview)


if __name__ == "__main__":
    main()
