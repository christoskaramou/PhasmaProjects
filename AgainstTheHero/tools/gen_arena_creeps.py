#!/usr/bin/env python
"""Generate chunky-cartoon farm-pest sprites for the Hero Arena cast.

Three new enemies that fill role gaps and exercise the projectile system:
  beetle      — armored swarm tank (knockback-resistant)
  corn_mortar — long-range heavy lobber
  wasp        — fast ranged flier

Writes PNGs into Assets/Textures/modes/spud_fields/ next to the original cast.
Deterministic (seeded). Run: python tools/gen_arena_creeps.py
"""
import random
from PIL import ImageDraw
from _arena_art import canvas, outlined, capsule, eye, brow, save, PAL, INK


# ---------------------------------------------------------------------------
# beetle — armored swarm tank (ladybug-ish red dome, black spots, stubby legs)
# ---------------------------------------------------------------------------
def gen_beetle():
    random.seed(41)
    W, H = 272, 248
    fig = canvas(W, H)
    d = ImageDraw.Draw(fig)
    cx = W / 2.0
    # six stubby legs first (under the shell silhouette)
    for sx in (-1, 1):
        for ly in (0.46, 0.60, 0.74):
            x0 = cx + sx * 76
            y0 = H * ly
            capsule(d, x0, y0, x0 + sx * 44, y0 + 20, 15, INK)
    # domed shell (kept clear of the bottom edge for a transparent margin)
    d.ellipse([cx - 102, H * 0.26, cx + 102, H * 0.86], fill=PAL["red"])
    d.ellipse([cx - 102, H * 0.56, cx + 102, H * 0.88], fill=PAL["red_dk"])
    # head segment on top
    d.ellipse([cx - 58, H * 0.07, cx + 58, H * 0.46], fill=(40, 36, 40, 255))
    fig = outlined(fig, 8)
    d = ImageDraw.Draw(fig)
    d.line([cx, H * 0.30, cx, H * 0.84], fill=INK, width=7)
    for (sx, sy, sr) in [(-0.42, 0.52, 19), (0.46, 0.50, 21), (-0.30, 0.74, 15),
                         (0.32, 0.76, 16), (0.0, 0.64, 14)]:
        x = cx + sx * 102
        y = H * sy
        d.ellipse([x - sr, y - sr, x + sr, y + sr], fill=INK)
    eye(d, cx - 26, H * 0.27, 22, look=(0.0, 0.25))
    eye(d, cx + 26, H * 0.27, 22, look=(0.0, 0.25))
    brow(d, cx - 26, H * 0.13, 40, 9, +18)
    brow(d, cx + 26, H * 0.13, 40, 9, -18)
    capsule(d, cx - 16, H * 0.42, cx - 24, H * 0.48, 9, INK)
    capsule(d, cx + 16, H * 0.42, cx + 24, H * 0.48, 9, INK)
    save(fig, "beetle.png")


# ---------------------------------------------------------------------------
# corn_mortar — long-range arcing lobber (a cob-creature that hurls mini cobs)
# ---------------------------------------------------------------------------
def gen_corn_mortar():
    random.seed(42)
    W, H = 212, 318
    fig = canvas(W, H)
    d = ImageDraw.Draw(fig)
    cx = W / 2.0
    for sx in (-1, 1):
        bx, by = cx + sx * 22, H * 0.86
        tx, ty = cx + sx * 86, H * 0.58
        d.polygon([(bx, by), (tx, ty), (cx + sx * 30, H * 0.96)], fill=PAL["husk"])
    capsule(d, cx + 40, H * 0.50, cx + 88, H * 0.40, 22, PAL["green"])
    d.rounded_rectangle([cx - 64, H * 0.16, cx + 64, H * 0.90], radius=62, fill=PAL["corn"])
    d.ellipse([cx + 74, H * 0.30, cx + 110, H * 0.44], fill=PAL["amber"])
    fig = outlined(fig, 8)
    d = ImageDraw.Draw(fig)
    for ky in range(0, 9):
        yy = H * 0.22 + ky * (H * 0.62 / 8.0)
        d.line([cx - 58, yy, cx + 58, yy], fill=PAL["corn_dk"], width=4)
    for kx in range(-2, 3):
        xx = cx + kx * 26
        d.line([xx, H * 0.20, xx, H * 0.86], fill=PAL["corn_dk"], width=4)
    eye(d, cx - 24, H * 0.30, 21, look=(0.1, 0.1))
    eye(d, cx + 24, H * 0.30, 21, look=(0.1, 0.1))
    brow(d, cx - 24, H * 0.18, 38, 8, +14)
    brow(d, cx + 24, H * 0.18, 38, 8, -14)
    d.ellipse([cx - 18, H * 0.40, cx + 18, H * 0.50], fill=INK)
    d.ellipse([cx - 10, H * 0.41, cx + 10, H * 0.47], fill=PAL["red_dk"])
    save(fig, "corn_mortar.png")


# ---------------------------------------------------------------------------
# wasp — fast ranged flier (striped abdomen, wings, stinger, angry eyes)
# ---------------------------------------------------------------------------
def gen_wasp():
    random.seed(43)
    W, H = 312, 214
    fig = canvas(W, H)
    d = ImageDraw.Draw(fig)
    cx, cy = W / 2.0, H * 0.54
    for sx in (-1, 1):
        d.ellipse([cx + sx * 18 - (0 if sx > 0 else 120), cy - 96,
                   cx + sx * 18 + (120 if sx > 0 else 0), cy - 6], fill=PAL["wing"])
    d.ellipse([cx - 96, cy - 44, cx + 70, cy + 60], fill=PAL["yellow"])
    d.ellipse([cx + 40, cy - 40, cx + 120, cy + 40], fill=(52, 46, 44, 255))
    d.polygon([(cx - 96, cy + 6), (cx - 150, cy + 18), (cx - 96, cy + 30)], fill=PAL["yellow_dk"])
    for lx in (-0.2, 0.1, 0.4):
        x = cx + lx * 120
        capsule(d, x, cy + 50, x - 18, cy + 86, 11, INK)
    fig = outlined(fig, 7)
    d = ImageDraw.Draw(fig)
    for sxp in (-0.42, -0.16, 0.10):
        x = cx + sxp * 166
        d.line([x, cy - 38, x, cy + 54], fill=INK, width=15)
    for sx in (-1, 1):
        wx = cx + sx * 60
        d.line([cx + sx * 18, cy - 30, wx, cy - 70], fill=(150, 180, 200, 200), width=3)
    eye(d, cx + 74, cy - 8, 19, look=(0.3, 0.1))
    eye(d, cx + 100, cy - 4, 16, look=(0.3, 0.1))
    brow(d, cx + 74, cy - 26, 34, 8, -20)
    save(fig, "wasp.png")


if __name__ == "__main__":
    gen_beetle()
    gen_corn_mortar()
    gen_wasp()
    print("done")
