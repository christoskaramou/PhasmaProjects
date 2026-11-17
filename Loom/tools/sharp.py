"""Sharpness (variance of the Laplacian of grey) per region, live shot vs target.png: depth-of-field parity."""
import sys
import numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert("L"), float)
t = Image.open(sys.argv[2] if len(sys.argv) > 2 else "../.concepts/next/loom/target.png").convert("L")
H = a.shape[0]
o = (t.height - H) // 2
t = np.asarray(t.crop((0, o, t.width, o + H)), float)
REG = {"warp_top": (600, 20, 1900, 200), "fell_trav": (900, 230, 1500, 520), "houses": (60, 520, 700, 900), "bridge": (800, 400, 1250, 600),
       "near_mid": (700, 900, 1500, 1150), "bottom": (300, 1150, 2000, 1360)}
def lap(x):
    return float(np.var(x[1:-1, 1:-1] * 4 - x[:-2, 1:-1] - x[2:, 1:-1] - x[1:-1, :-2] - x[1:-1, 2:]))
for k, (x0, y0, x1, y1) in REG.items():
    print("%-9s live %7.1f  target %7.1f" % (k, lap(a[y0:y1, x0:x1]), lap(t[y0:y1, x0:x1])))
