"""Instant frames: shallower bottom edge (104 canvas pt instead of 220) and one
side trimmed at a slight angle, as if cut with scissors.

A one-off transform, run on the original Polaroid45 pack (margins
m080084080220, restore it from git before re-running); writes the frames under
the new margin name m080084080104. The base name, which saved collages use,
stays the same. Needs pillow + numpy:
    python3 Tools/make_instant_frames.py CollageStudio/Assets.xcassets/FramePacks/Polaroid45
"""
import glob, json, os, shutil, sys
import numpy as np
from PIL import Image

PACK = sys.argv[1]
NEW_B = 208                     # bottom margin, PNG px (104 canvas pt)
CARD_R = 1550                   # card's right edge (PNG px); left edge mirrors it
SHADOW = np.array([227, 238, 245, 250, 253, 255], float) / 255   # every 6 px out
# Which side is cut, and whether the cut is deepest at the top or bottom.
CUTS = {"Classic": ("right", "bottom"), "Cream": ("left", "top"), "Black": ("right", "top"),
        "Taped": ("left", "bottom"), "Blush": ("right", "bottom"), "Mint": ("left", "top")}
DEPTH = 40                      # PNG px trimmed at the deep end (20 canvas pt)

def reshape(im):
    H, W = im.shape[:2]
    a = im[:, W // 2, 3]
    win = np.where(a < 8)[0]
    y0, y1 = win.min(), win.max() + 1
    d = (H - y1) - NEW_B
    edge, keep = 24, 40
    mid = im[y0 + edge:y1 - edge]
    mid2 = np.array(Image.fromarray(mid).resize((W, mid.shape[0] + d), Image.LANCZOS))
    band = im[y1:]
    out = np.concatenate([im[:y0 + edge], mid2, im[y1 - edge:y1], band[:keep], band[-(NEW_B - keep):]])
    assert out.shape[0] == H
    return out

def cut_right(im, deep_at):
    H, W = im.shape[:2]
    out = im.astype(float)
    top, bottom = CARD_ROWS
    ys = np.arange(H)
    t = np.clip((ys - top) / max(bottom - top, 1), 0, 1)
    off = DEPTH * (t if deep_at == "bottom" else 1 - t)
    line = CARD_R - off                                  # new edge per row
    xs = np.arange(W)
    shadow_x = np.arange(len(SHADOW)) * 6
    for y in range(max(top - 30, 0), min(bottom + 31, H)):
        L = line[y]
        x0 = int(np.floor(L)) - 1
        seg = xs[x0:CARD_R + 40]
        dist = seg - L                                    # >0: outside the new edge
        if top <= y <= bottom:
            white = 255 * np.interp(np.clip(dist, 0, None), shadow_x, SHADOW)
        else:
            # Above / below the card: its top / bottom shadow, carried to the
            # new edge and fading out past it.
            base = out[y, max(int(np.floor(L)) - 2, 0), :3].mean()
            white = 255 - (255 - base) * np.clip(1 - np.clip(dist, 0, None) / 10, 0, 1)
        cover = np.clip(0.5 - dist, 0, 1)[:, None]        # 1 inside the card (antialiased)
        px = out[y, x0:CARD_R + 40, :3]
        out[y, x0:CARD_R + 40, :3] = px * cover + white[:, None] * (1 - cover)
        out[y, x0:CARD_R + 40, 3] = np.maximum(out[y, x0:CARD_R + 40, 3], 255 * (1 - cover[:, 0]))
    return np.clip(out, 0, 255).astype(np.uint8)

def cut(im, side, deep_at):
    if side == "left":
        return cut_right(im[:, ::-1], deep_at)[:, ::-1].copy()
    return cut_right(im, deep_at)

def thumb(im):
    H, W = im.shape[:2]
    g = np.linspace(0, 1, H)[:, None, None]
    sky = (1 - g) * np.array([122, 166, 216]) + g * np.array([214, 204, 168])
    sky = np.broadcast_to(sky, (H, W, 3))
    a = im[..., 3:4] / 255
    rgb = im[..., :3] * a + sky * (1 - a)
    return Image.fromarray(rgb.astype(np.uint8), "RGB").resize((180, 225), Image.LANCZOS)

def write(folder, name, image):
    d = os.path.join(PACK, name + ".imageset")
    os.makedirs(d, exist_ok=True)
    image.save(os.path.join(d, name + ".png"), optimize=True)
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": name + ".png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)

# The card's top and bottom rows, measured on the black card (on the light
# ones card and shadow are too close in tone); every colour shares them.
_black = reshape(np.array(Image.open(glob.glob(os.path.join(
    PACK, "Polaroid45_Black_m080084080220_r4x5.imageset", "*.png"))[0]).convert("RGBA")))
_rows = np.where(_black[:, CARD_R - 4, :3].mean(1) < 100)[0]
CARD_ROWS = (_rows.min(), _rows.max())
print("card rows", CARD_ROWS)

for src in sorted(glob.glob(os.path.join(PACK, "Polaroid45_*_m080084080220_r4x5.imageset"))):
    label = os.path.basename(src).split("_")[1]
    old = os.path.basename(src)[:-len(".imageset")]
    im = np.array(Image.open(os.path.join(src, old + ".png")).convert("RGBA"))
    im = cut(reshape(im), *CUTS[label])
    new = old.replace("m080084080220", "m080084080104")
    write(PACK, new, Image.fromarray(im, "RGBA"))
    write(PACK, new + "_Thumb", thumb(im))
    shutil.rmtree(src)
    shutil.rmtree(os.path.join(PACK, old + "_Thumb.imageset"), ignore_errors=True)
    print(new)
