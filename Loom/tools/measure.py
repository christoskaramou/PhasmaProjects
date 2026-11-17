"""Region comparison of a live Loom screenshot (2560x1369) against target.png (cropped to 16:9 window rows).
    python tools/measure.py shot.png [target.png]"""
import sys
import numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert("RGB"), float)
tp = sys.argv[2] if len(sys.argv) > 2 else "../.concepts/next/loom/target.png"
t = Image.open(tp).convert("RGB")
H = a.shape[0]
o = (t.height - H) // 2
t = np.asarray(t.crop((0, o, t.width, o + H)), float)
REG = {"all": (0, 0, 2560, H), "meadow_mid": (1500, 600, 2000, 800), "cloth_near": (300, 1000, 1100, 1290), "river": (1150, 700, 1350, 900),
       "fell_row": (640, 255, 1600, 300), "hill_left": (380, 280, 700, 420), "houses": (60, 520, 700, 900), "reed_warp": (600, 20, 1900, 200)}
for k, (x0, y0, x1, y1) in REG.items():
    A, T = a[y0:y1, x0:x1], t[y0:y1, x0:x1]
    print("%-11s MAD %5.1f  mean live %s target %s" % (k, np.abs(A - T).mean(), A.reshape(-1, 3).mean(0).round(0), T.reshape(-1, 3).mean(0).round(0)))
