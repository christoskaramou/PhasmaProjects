# Rebuild only the palette atlas (pal / pal_mr / pal_em) from palette.py, without touching other textures or audio.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import palette as P
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Textures')
S = P.SIZE; base = np.zeros((S, S, 3)); mr = np.zeros((S, S, 3)); em = np.zeros((S, S, 3)); mr[..., 0] = 255
for nm, (i, rgb, rough, metal, e) in P.SW.items():
    gx, gy = i % P.G, i // P.G; ys, xs = slice(gy * P.PX, (gy + 1) * P.PX), slice(gx * P.PX, (gx + 1) * P.PX)
    base[ys, xs] = np.array(rgb) * 255; mr[ys, xs, 1] = rough * 255; mr[ys, xs, 2] = metal * 255
    if e: em[ys, xs] = np.array(e) * 255
for a, nm in ((base, 'pal'), (mr, 'pal_mr'), (em, 'pal_em')):
    Image.fromarray(np.clip(a[::-1], 0, 255).astype(np.uint8)).save(os.path.join(T, nm + '.png'))
print(len(P.SW), 'swatches')
