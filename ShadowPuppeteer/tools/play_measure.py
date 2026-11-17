"""Puppet-to-ground gap in the live runs (tools/play_capture.py): for each shot, the ground's top under the puppet's
feet (from the same frame with the puppet hidden) against the puppet's lowest drawn pixel (where the two frames differ).

    python tools/play_measure.py RUN_DIR
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sp_common as G  # noqa: E402

D = sys.argv[1]
R = json.load(open(os.path.join(D, "runs.json")))
W, H = 2560, 1369
out = {}
for run, shots in R["runs"].items():
    rows = []
    for s in shots:
        p = s["status"].split()
        x, y, mode = float(p[3]), float(p[5]), p[7]
        a = np.asarray(Image.open(os.path.join(D, s["shot"])).convert("RGB"), float)
        b = np.asarray(Image.open(os.path.join(D, s["shot"].replace(".png", "_ground.png"))).convert("RGB"), float)
        fx, fy = G.to_pixel((x, G.SY, y), W, H)
        hf = 0.06                                                   # the whole stride (feet spread)
        x0, _ = G.to_pixel((x - hf, G.SY, y), W, H)
        x1, _ = G.to_pixel((x + hf, G.SY, y), W, H)
        diff = np.abs(a - b).sum(2) > 30                            # puppet pixels
        lum = 0.2126 * b[..., 0] + 0.7152 * b[..., 1] + 0.0722 * b[..., 2]
        gaps, ground = [], []
        for c in range(int(round(x0)), int(round(x1)) + 1):
            # the drawn ground's top in this column: the lit-to-dark edge nearest the feet row (puppet hidden)
            lit = np.median(lum[int(fy) - 70:int(fy) - 30, max(0, c - 90):c - 50])
            g = None
            for r in range(int(fy) - 8, int(fy) + 9):
                if lum[r, c] < 0.72 * lit and lum[r + 1, c] < 0.72 * lit and lum[r - 1, c] >= 0.72 * lit:
                    g = r
                    break
            if g is None:
                continue
            ground.append(g - fy)
            col = diff[g - 40:g + 1, c]                             # puppet pixels down to the ground's top row
            if col.any():
                pb = g - 40 + int(np.nonzero(col)[0].max())
                gaps.append(g - 1 - pb)                              # 0: foot on the ground; >0 floating; <0 sunk
        rows.append({"shot": s["shot"], "mode": mode, "x": x, "y": y,
                     "gap_px": None if not gaps else int(min(gaps)),
                     "drawn_ground_vs_rules_px": None if not ground else round(float(np.median(ground)), 1)})
        print("%-14s %-6s x %7.3f y %6.3f  foot-to-ground gap %s px, drawn ground top vs rules %s px"
              % (s["shot"], mode, x, y, rows[-1]["gap_px"], rows[-1]["drawn_ground_vs_rules_px"]))
    out[run] = rows
json.dump(out, open(os.path.join(D, "gaps.json"), "w"), indent=1)
