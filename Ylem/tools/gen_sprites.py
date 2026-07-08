#!/usr/bin/env python3
# gen_sprites.py — the source of Ylem's particle sprites (Assets/Textures/*.png).
# White RGBA so runtime_ui image_tint multiplies them to any colour. Re-run to
# retune the falloff; the PNGs are committed, this script documents how.
import math, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Assets", "Textures")
os.makedirs(OUT, exist_ok=True)
N = 128
C = (N - 1) / 2.0


def smoothstep(a, b, x):
    if a == b:
        return 0.0 if x < a else 1.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def build(fn, name):
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    px = img.load()
    for y in range(N):
        for x in range(N):
            r = math.hypot(x - C, y - C) / C  # 0 at centre, 1 at edge
            a = max(0.0, min(1.0, fn(r)))
            px[x, y] = (255, 255, 255, int(a * 255 + 0.5))
    img.save(os.path.join(OUT, name))
    print("wrote", name)


# dot: bright core, soft halo — the electron / proton / nucleus glow.
build(lambda r: (1.0 - smoothstep(0.18, 1.0, r)) ** 1.25, "dot.png")

# ring: a soft gaussian annulus at r~0.78 — the shell rings + shockwave.
build(lambda r: math.exp(-((r - 0.78) / 0.12) ** 2), "ring.png")
