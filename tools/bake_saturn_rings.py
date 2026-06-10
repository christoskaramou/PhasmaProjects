"""Bake the 1-D Saturn ring strip (radius -> color+alpha) into a flat 2048x2048 RGBA
annulus PNG so the rings render on a plain `plane` primitive with planar UVs."""
import os

import numpy as np
from PIL import Image

TEX = os.path.join(os.path.dirname(__file__), "..", "Assets", "Textures", "Solar")
strip_img = Image.open(os.path.join(TEX, "2k_saturn_ring_alpha.png")).convert("RGBA")
strip = np.array(strip_img)
print("strip shape:", strip.shape)

# The strip is 1-D: radial profile along its long axis.
if strip.shape[0] <= strip.shape[1]:
    row = strip[strip.shape[0] // 2]          # horizontal strip
else:
    row = strip[:, strip.shape[1] // 2]       # vertical strip

SIZE = 2048
INNER_KM, OUTER_KM = 74500.0, 140220.0        # C-ring inner edge -> F ring
inner_frac = INNER_KM / OUTER_KM

yy, xx = np.mgrid[0:SIZE, 0:SIZE]
r = np.hypot(xx - SIZE / 2 + 0.5, yy - SIZE / 2 + 0.5) / (SIZE / 2)   # 1.0 = outer edge
t = (r - inner_frac) / (1.0 - inner_frac)
idx = np.clip((t * (len(row) - 1)).astype(int), 0, len(row) - 1)
out = row[idx]
out[(r < inner_frac) | (r > 1.0)] = 0          # transparent hole + corners

Image.fromarray(out.astype(np.uint8), "RGBA").save(os.path.join(TEX, "saturn_rings.png"))
print("wrote saturn_rings.png")
