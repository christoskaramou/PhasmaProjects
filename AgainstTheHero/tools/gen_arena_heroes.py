#!/usr/bin/env python
"""Generate chunky-cartoon hero-class sprites for the Hero Arena.

Matches hero_spud.png (spud torso, crested helmet/hat, googly eyes, weapon, stubby
legs). All hero sprites render on the same 1.6x2.2 quad, so they share a canvas
aspect for a consistent silhouette.

  hero_brawler — melee cleaver class (beefy, two-handed cleaver, red helm)
  hero_sower   — ranged scatter class (straw hat, gourd scattergun, green)

Writes into Assets/Textures/modes/spud_fields/. Run: python tools/gen_arena_heroes.py
"""
import random
from PIL import ImageDraw
from _arena_art import canvas, outlined, capsule, eye, brow, save, PAL, INK


def legs(d, cx, spread, y, h, w):
    for sx in (-1, 1):
        x = cx + sx * spread
        capsule(d, x, y, x, y + h, w, PAL["spud"])


# ---------------------------------------------------------------------------
# hero_brawler — melee cleaver
# ---------------------------------------------------------------------------
def gen_brawler():
    random.seed(51)
    W, H = 328, 416
    fig = canvas(W, H)
    d = ImageDraw.Draw(fig)
    cx = W / 2.0
    legs(d, cx, 48, H * 0.82, H * 0.12, 34)
    # cleaver (handle + big blade, raised on the right) — drawn under the fist
    capsule(d, cx + 118, H * 0.64, cx + 150, H * 0.28, 16, PAL["tan_dk"])
    d.polygon([(cx + 126, H * 0.30), (cx + 206, H * 0.18),
               (cx + 214, H * 0.40), (cx + 138, H * 0.47)], fill=PAL["steel"])
    # potato torso
    d.rounded_rectangle([cx - 118, H * 0.34, cx + 118, H * 0.86], radius=70, fill=PAL["spud"])
    d.rounded_rectangle([cx - 118, H * 0.62, cx + 118, H * 0.87], radius=62, fill=PAL["tan_dk"])
    # gauntlet fists
    d.ellipse([cx - 154, H * 0.52, cx - 96, H * 0.67], fill=(70, 62, 60, 255))
    d.ellipse([cx + 96, H * 0.50, cx + 152, H * 0.65], fill=(70, 62, 60, 255))
    # red helmet + spike crest
    d.rounded_rectangle([cx - 80, H * 0.15, cx + 80, H * 0.40], radius=42, fill=PAL["red"])
    d.polygon([(cx, H * 0.03), (cx - 22, H * 0.18), (cx + 22, H * 0.18)], fill=PAL["amber"])
    fig = outlined(fig, 9)
    d = ImageDraw.Draw(fig)
    # chest strap
    capsule(d, cx - 72, H * 0.47, cx + 72, H * 0.61, 24, PAL["red_dk"])
    # face under the helm brim
    eye(d, cx - 31, H * 0.32, 24, look=(0.0, 0.18))
    eye(d, cx + 31, H * 0.32, 24, look=(0.0, 0.18))
    brow(d, cx - 31, H * 0.255, 50, 11, +16)
    brow(d, cx + 31, H * 0.255, 50, 11, -16)
    # blade shine
    d.line([cx + 150, H * 0.38, cx + 200, H * 0.28], fill=(224, 230, 242, 255), width=4)
    save(fig, "hero_brawler.png")


# ---------------------------------------------------------------------------
# hero_sower — ranged scatter (gourd scattergun)
# ---------------------------------------------------------------------------
def gen_sower():
    random.seed(52)
    W, H = 328, 416
    fig = canvas(W, H)
    d = ImageDraw.Draw(fig)
    cx = W / 2.0
    legs(d, cx, 44, H * 0.82, H * 0.12, 32)
    # potato torso
    d.rounded_rectangle([cx - 110, H * 0.36, cx + 110, H * 0.86], radius=66, fill=PAL["spud"])
    d.rounded_rectangle([cx - 110, H * 0.62, cx + 110, H * 0.87], radius=58, fill=PAL["tan_dk"])
    # seed pouch on the belt
    d.ellipse([cx - 122, H * 0.58, cx - 70, H * 0.74], fill=PAL["green_dk"])
    # arm + gourd scattergun, leveled to the right
    capsule(d, cx + 70, H * 0.54, cx + 116, H * 0.55, 24, PAL["spud"])
    d.ellipse([cx + 86, H * 0.48, cx + 162, H * 0.62], fill=PAL["green"])
    d.rounded_rectangle([cx + 150, H * 0.49, cx + 206, H * 0.61], radius=14, fill=(72, 64, 62, 255))
    # wide-brim straw hat
    d.ellipse([cx - 112, H * 0.21, cx + 112, H * 0.34], fill=PAL["corn"])
    d.ellipse([cx - 56, H * 0.08, cx + 56, H * 0.27], fill=PAL["corn_dk"])
    fig = outlined(fig, 9)
    d = ImageDraw.Draw(fig)
    # hat band
    capsule(d, cx - 52, H * 0.245, cx + 52, H * 0.245, 13, PAL["green_dk"])
    # eyes under the brim
    eye(d, cx - 28, H * 0.41, 23, look=(0.12, 0.1))
    eye(d, cx + 28, H * 0.41, 23, look=(0.12, 0.1))
    brow(d, cx - 28, H * 0.35, 44, 10, +10)
    brow(d, cx + 28, H * 0.35, 44, 10, -10)
    # muzzle bore + a few seeds in the pouch
    d.ellipse([cx + 196, H * 0.515, cx + 210, H * 0.585], fill=INK)
    for sd in (-1, 0, 1):
        x = cx - 96 + sd * 13
        d.ellipse([x - 5, H * 0.62, x + 5, H * 0.65], fill=PAL["corn"])
    save(fig, "hero_sower.png")


if __name__ == "__main__":
    gen_brawler()
    gen_sower()
    print("done")
