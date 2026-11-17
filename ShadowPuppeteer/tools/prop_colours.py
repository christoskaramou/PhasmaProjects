"""Mean display colour of each prop, the lantern and the candle in a 2560x1369 frame (same windows as the targets)."""
import sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sp_common as G
from PIL import Image


def boxes(st, w=2560, h=1369):
    out = {}
    for n in G.PROPS:
        x0, z0, x1, z1 = G.bbox(n)
        x, y = st[n], G.PROPS[n]["y"]
        a = G.to_pixel((x + x0 * 0.5, y, z1 * 0.85), w, h); b = G.to_pixel((x + x1 * 0.5, y, max(0.02, z1 * 0.15)), w, h)
        out[n] = (int(a[0]), int(a[1]), int(b[0]), int(b[1]))
    lx, ly = st["lantern"]
    a = G.to_pixel((lx - 0.06, ly, 0.32), w, h); b = G.to_pixel((lx + 0.06, ly, 0.06), w, h)
    out["lantern"] = (int(a[0]), int(a[1]), int(b[0]), int(b[1]))
    cx, cy = G.CANDLE
    hh = 0.035 + 0.30 * st["candle"]
    a = G.to_pixel((cx - 0.035, cy, hh - 0.01), w, h); b = G.to_pixel((cx + 0.035, cy, 0.05), w, h)
    out["candle wax"] = (int(a[0]), int(a[1]), int(b[0]), int(b[1]))
    return out


def colours(path, st):
    im = np.asarray(Image.open(path).convert("RGB"), float)
    return {k: im[y0:y1, x0:x1].reshape(-1, 3).mean(0).round(1).tolist() for k, (x0, y0, x1, y1) in boxes(st).items()}


if __name__ == "__main__":
    st = G.STATE_B if len(sys.argv) > 3 and sys.argv[3] == "b" else G.STATE_A
    a, b = colours(sys.argv[1], st), colours(sys.argv[2], st)
    for k in a:
        print("%-11s game %-22s target %s" % (k, a[k], b[k]))
