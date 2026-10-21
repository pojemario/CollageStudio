#!/usr/bin/env python3
"""Generates the Flares overlay pack (9:16):

  Assets.xcassets/Overlays/Flare916/Flare916_<Name>.imageset

Sunlight and lens flares, drawn from scratch: warm backlight glows,
monochrome haze and stars, and lens flares with coloured ghosts. Each is
built as additive light and stored the way the app screen-blends it: colour
plus straight alpha on a transparent background (screening colour c at
alpha a adds a*c of light), so a dark corner of the photo lights up and a
bright one barely changes. 1152x2048, so thin spikes and ghost rims stay
crisp at export. Every flare also gets a "_Thumb" picker thumbnail over
the same dusk photo as the light leaks.

Usage:  <venv>/bin/python Tools/make_flares.py [--preview out.png]
        (same venv as make_analog_overlays.py: pillow numpy scipy)
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(__file__))
from make_analog_overlays import ROOT, TW, TH, leak_thumbnail, sample_photo, write_folder, write_imageset  # noqa: E402

W, H = 1152, 2048
PACK = "Flare916"
Y, X = np.mgrid[0:H, 0:W].astype(np.float32)

# Light colours (linear-ish, 0..1).
WHITE = (1.0, 1.0, 1.0)
CREAM = (1.0, 0.95, 0.82)
BUTTER = (1.0, 0.88, 0.56)
GOLD = (1.0, 0.70, 0.30)
AMBER = (1.0, 0.52, 0.18)
COOL = (0.55, 0.75, 1.0)
CYAN = (0.40, 0.90, 1.0)
GREEN = (0.55, 1.0, 0.60)
VIOLET = (0.75, 0.50, 1.0)
ROSE = (1.0, 0.50, 0.70)


class Light:
    """Additive light on the canvas; positions are fractions of the width /
    height, sizes fractions of the width (so circles stay round)."""

    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.rgb = np.zeros((H, W, 3), np.float32)

    def _d(self, cx, cy):
        return np.hypot((X - cx * W) / W, (Y - cy * H) / W)

    def add(self, f, color, gain):
        self.rgb += f[..., None] * np.float32(color) * gain

    def glow(self, cx, cy, r, color, gain):
        """Gaussian core."""
        self.add(np.exp(-(self._d(cx, cy) / r) ** 2), color, gain)

    def bloom(self, cx, cy, r, color, gain):
        """Long soft tail, like light scattering in the air and the lens."""
        self.add(1 / (1 + (self._d(cx, cy) / r) ** 2) ** 1.5, color, gain)

    def disc(self, cx, cy, r, color, gain, soft=.006, rim=.6):
        """An out-of-focus ghost: a flat disc, a little brighter at its rim."""
        d = self._d(cx, cy)
        inside = np.clip((r - d) / soft + .5, 0, 1)
        edge = np.exp(-((d - r) / (soft * 1.5)) ** 2)
        self.add(inside * (1 - rim * .5) + edge * rim, color, gain)

    def hexagon(self, cx, cy, r, color, gain, soft=.006, turn=.2):
        """An aperture ghost: the iris's six blades."""
        px, py = (X - cx * W) / W, (Y - cy * H) / W
        d = np.zeros_like(px)
        for k in range(3):
            a = turn + k * np.pi / 3
            d = np.maximum(d, np.abs(px * np.cos(a) + py * np.sin(a)))
        d /= np.cos(np.pi / 6)
        inside = np.clip((r - d) / soft + .5, 0, 1)
        edge = np.exp(-((d - r) / (soft * 1.5)) ** 2)
        self.add(inside * .75 + edge * .5, color, gain)

    def ring(self, cx, cy, r, w, color, gain):
        self.add(np.exp(-((self._d(cx, cy) - r) / w) ** 2), color, gain)

    def rainbow(self, cx, cy, r, w, gain):
        """A halo split into colours: red outside, blue inside."""
        d = self._d(cx, cy)
        for i, spread in enumerate((1.04, 1.0, .96)):
            band = np.exp(-((d - r * spread) / w) ** 2)
            self.rgb[..., i] += band * gain

    def spikes(self, cx, cy, n, length, width, color, gain, turn=0.0):
        """Diffraction spikes off the aperture blades: thin lines through
        the source, fading with distance."""
        px, py = X - cx * W, Y - cy * H
        for k in range(n):
            a = turn + k * np.pi / n
            along = np.abs(px * np.cos(a) + py * np.sin(a)) / W
            across = np.abs(-px * np.sin(a) + py * np.cos(a))
            line = np.exp(-(across / width) ** 2) * np.exp(-along / length)
            self.add(line, color, gain)

    def rays(self, cx, cy, n, length, color, gain):
        """Soft sun rays: uneven spokes fanning out of the source."""
        px, py = (X - cx * W) / W, (Y - cy * H) / W
        theta = np.arctan2(py, px)
        d = np.hypot(px, py)
        phase = self.rng.uniform(0, 6.28, 3)
        spokes = (.5 + .5 * np.cos(n * theta + phase[0])) ** 6 * .7 \
            + (.5 + .5 * np.cos((n + 5) * theta + phase[1])) ** 10 * .5 \
            + (.5 + .5 * np.cos((2 * n + 3) * theta + phase[2])) ** 14 * .4
        self.add(spokes * np.exp(-d / length) * np.clip(d / .03, 0, 1), color, gain)

    def streak(self, cx, cy, length, height, color, gain):
        """Anamorphic streak: a thin horizontal line of light."""
        dx = np.abs(X - cx * W) / W
        dy = (Y - cy * H) / W
        self.add(np.exp(-(dy / height) ** 2) * np.exp(-dx / length), color, gain)

    def ghosts(self, sx, sy, items):
        """Ghosts strung along the line from the source through the centre
        of the frame (t = 1 is the centre, past it they mirror over)."""
        for t, shape, r, color, gain in items:
            cx = sx + t * (.5 - sx) * 1.0
            cy = sy + t * (.5 - sy) * 1.0
            if shape == "hex":
                self.hexagon(cx, cy, r, color, gain)
            elif shape == "ring":
                self.rainbow(cx, cy, r, r * .08, gain)
            else:
                self.disc(cx, cy, r, color, gain)

    def fade(self, cx, cy, inner=.36, outer=.49):
        """Fades everything out to nothing within a circle that fits the
        width, so a flare can be moved about without a cut edge showing."""
        d = self._d(cx, cy)
        t = np.clip((d - inner) / (outer - inner), 0, 1)
        self.rgb *= (1 - t * t * (3 - 2 * t))[..., None]

    def image(self):
        """Tone-maps the light (bright cores roll off instead of clipping),
        then splits it into colour + alpha for screen blending."""
        light = 1 - np.exp(-self.rgb * 1.15)
        a = light.max(axis=2)
        color = np.where(a[..., None] > 1e-4, light / np.maximum(a[..., None], 1e-4), 0)
        a = np.clip(a + (self.rng.random((H, W)).astype(np.float32) - .5) / 255, 0, 1)
        out = np.dstack([color * 255, a[..., None] * 255]).clip(0, 255).round().astype(np.uint8)
        return Image.fromarray(out, "RGBA")


# ------------------------------------------------------------ warm

def flare_glow(l):          # soft yellow backlight: the sun just behind the subject
    # Centered and faded out well inside the edges, like Sun and Star, so
    # it can be moved anywhere without a cut edge.
    l.bloom(.5, .5, .14, (1.0, .78, .36), .55)
    l.glow(.5, .5, .26, (1.0, .80, .40), .35)
    l.glow(.5, .5, .09, BUTTER, .45)
    l.fade(.5, .5)


def flare_sun(l):           # a sun: hot core, rays, warm halo
    l.glow(.5, .5, .035, WHITE, 2.4)
    l.glow(.5, .5, .12, CREAM, .9)
    l.bloom(.5, .5, .2, GOLD, .55)
    l.rays(.5, .5, 9, .3, BUTTER, .45)
    l.fade(.5, .5)


def flare_dusk(l):          # sun on the horizon: an orange veil from below
    l.glow(.10, .90, .05, CREAM, 1.8)
    l.bloom(.10, .90, .28, AMBER, .75)
    l.glow(.10, .90, .55, GOLD, .25)
    l.ghosts(.10, .90, [(.7, "disc", .035, GOLD, .10), (1.25, "disc", .08, AMBER, .07),
                        (1.6, "disc", .03, GOLD, .12)])


# ------------------------------------------------------------ monochrome

def flare_haze(l):          # bright overcast backlight washing in from the top
    l.bloom(.15, -.05, .45, WHITE, .75)
    l.glow(.15, -.05, .7, WHITE, .2)


def flare_orbs(l):          # out-of-focus highlights drifting across the frame
    rng = l.rng
    for _ in range(14):
        x, y = rng.uniform(.05, .95), rng.uniform(.05, .95)
        r = rng.uniform(.03, .11)
        l.disc(x, y, r, WHITE, rng.uniform(.08, .2), soft=.01, rim=.4)


def flare_star(l):          # a point of light caught by a stopped-down lens
    l.glow(.5, .5, .02, WHITE, 2.5)
    l.glow(.5, .5, .08, WHITE, .45)
    l.bloom(.5, .5, .12, WHITE, .25)
    l.spikes(.5, .5, 3, .26, 1.6, WHITE, 1.0, turn=.3)
    l.spikes(.5, .5, 3, .11, 1.0, WHITE, .5, turn=.3 + np.pi / 6)
    l.fade(.5, .5, inner=.3)


# ------------------------------------------------------------ lens

def flare_ghosts(l):        # the classic: a bright source and a line of coloured ghosts
    sx, sy = .22, .16
    l.glow(sx, sy, .03, WHITE, 2.4)
    l.glow(sx, sy, .10, CREAM, .6)
    l.bloom(sx, sy, .16, GOLD, .3)
    l.spikes(sx, sy, 3, .18, 1.4, CREAM, .5)
    l.ghosts(sx, sy, [(.45, "disc", .018, GREEN, .35), (.75, "hex", .045, VIOLET, .16),
                      (1.0, "disc", .012, AMBER, .4), (1.3, "hex", .09, CYAN, .08),
                      (1.55, "ring", .16, None, .12), (1.85, "disc", .03, ROSE, .2)])


def flare_streak(l):        # anamorphic: a blue line straight across the frame
    cx, cy = .58, .34
    l.glow(cx, cy, .025, WHITE, 2.2)
    l.glow(cx, cy, .09, COOL, .5)
    l.streak(cx, cy, .55, .006, COOL, 1.1)
    l.streak(cx, cy, .25, .02, CYAN, .35)
    l.ghosts(cx, cy, [(1.6, "disc", .03, COOL, .15), (2.0, "disc", .05, CYAN, .08)])


def flare_ring(l):          # a rainbow halo around the sun
    cx, cy = .70, .28
    l.glow(cx, cy, .03, WHITE, 2.2)
    l.bloom(cx, cy, .12, CREAM, .45)
    l.rainbow(cx, cy, .30, .022, .32)
    l.rainbow(cx, cy, .52, .04, .10)
    l.ghosts(cx, cy, [(1.4, "hex", .05, GREEN, .12), (1.8, "disc", .025, VIOLET, .25)])


FLARES = [("Glow", 401, flare_glow), ("Sun", 403, flare_sun), ("Dusk", 405, flare_dusk),
          ("Haze", 407, flare_haze), ("Orbs", 409, flare_orbs), ("Star", 411, flare_star),
          ("Ghosts", 413, flare_ghosts), ("Streak", 415, flare_streak), ("Ring", 417, flare_ring)]


def main():
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    root = os.path.join(ROOT, PACK)
    shutil.rmtree(root, ignore_errors=True)
    write_folder(root)
    photo = sample_photo()
    tiles = []
    for name, seed, build in FLARES:
        light = Light(seed)
        build(light)
        image = light.image()
        write_imageset(PACK, f"{PACK}_{name}", image)
        thumb = leak_thumbnail(image, photo)
        write_imageset(PACK, f"{PACK}_{name}_Thumb", thumb)
        tiles.append(thumb)
        print(f"{PACK}_{name}")
    if preview:
        sheet = Image.new("RGB", (len(tiles) * (TW + 10) + 10, TH + 20), (128, 128, 128))
        for i, t in enumerate(tiles):
            sheet.paste(t, (10 + i * (TW + 10), 10))
        sheet.save(preview)


if __name__ == "__main__":
    main()
