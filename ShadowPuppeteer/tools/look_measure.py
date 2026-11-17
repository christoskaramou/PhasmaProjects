"""Measure Player screenshots of the look slice against the Cycles targets and the shared geometry.

    python tools/look_measure.py SHOTS_DIR REF_DIR

SHOTS_DIR: A_2560x1369.png, A_2560x1369_1s.png, B_2560x1369.png (tools/look_capture.py).
REF_DIR:   target_2560x1369.png, target_b_2560x1369.png (tools/make_bakes.py), the same camera and window size.
Writes side_by_side_A.png / _B.png, crops_400.png and measure.json into SHOTS_DIR and prints the tables:
mean absolute difference per channel over the paper, floor and curtain regions; per prop shadow outline misplacement
(game vs target, px); IoU per prop of the game's shadows against the planar construction from sp_common.
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sp_common as G  # noqa: E402

SHOTS, REF = sys.argv[1], sys.argv[2]
W, H = 2560, 1369
TEX = os.path.join(HERE, "..", "Assets", "Textures")


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32)


def P(u, v, y=None):
    return G.to_pixel((u, G.SY if y is None else y, v), W, H)


def poly_mask(polys):
    """Pixels whose centre lies inside any polygon: exact crossing-number test at pixel centres (unbiased; a filled
    raster with inclusive edges grows every shape by about half a pixel, ~5 % of a ladder rail)."""
    m = np.zeros((H, W), bool)
    for poly in polys:
        P = np.asarray(poly, float)
        x0, x1 = max(0, int(P[:, 0].min()) - 1), min(W, int(P[:, 0].max()) + 2)
        y0, y1 = max(0, int(P[:, 1].min()) - 1), min(H, int(P[:, 1].max()) + 2)
        if x1 <= x0 or y1 <= y0:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1]
        px, py = xx + 0.5, yy + 0.5
        inside = np.zeros(px.shape, bool)
        for (ax, ay), (bx, by) in zip(P, np.roll(P, -1, axis=0)):
            if ay == by:
                continue
            cond = (ay > py) != (by > py)
            xi = ax + (py - ay) * (bx - ax) / (by - ay)
            inside ^= cond & (px < xi)
        m[y0:y1, x0:x1] |= inside
    return m


def shadow_polys(name, st):
    lx, ly = st["lantern"]
    x = st[name]
    py = G.PROPS[name]["y"]
    out = []
    for poly in G.silhouette(name):
        out.append([P(*G.project(lx, ly, py, x + px, pz)) for px, pz in poly])
    return out


def front_alpha():
    """Front card alpha (lantern at bake 0,0) mapped from the WIDE bake into the window."""
    a = np.asarray(Image.open(os.path.join(TEX, "front_0_0.png")).convert("RGBA"))[:, :, 3].astype(np.float32) / 255
    s = H / G.WIDE[1]
    ox = (W - G.WIDE[0] * s) / 2
    M = np.float32([[s, 0, ox], [0, s, 0]])
    return cv2.warpAffine(a, M, (W, H), flags=cv2.INTER_LINEAR)


def regions():
    u0, u1 = G.SCREEN_U
    v1 = G.SCREEN_V[1]
    paper = poly_mask([[P(u0, 0), P(u1, 0), P(u1, v1), P(u0, v1)]])
    paper = ndimage.binary_erosion(paper, iterations=4)
    fa = front_alpha()
    live = fa < 0.5
    bottom = P(0, 0)[1]
    yy, xx = np.mgrid[0:H, 0:W]
    floor = live & ~ndimage.binary_dilation(paper, iterations=6) & (yy > bottom + 3)
    floor = ndimage.binary_erosion(floor, iterations=3)
    x0, x1 = P(u0, 0)[0], P(u1, 0)[0]
    top = P(0, v1)[1]
    front_y = G.to_pixel((0, G.FLOOR_Y[0], 0), W, H)[1]
    curtain = (fa > 0.98) & ((xx < x0 - 60) | (xx > x1 + 60)) & (yy > top) & (yy < front_y)
    return {"paper": paper, "floor": floor, "curtains": curtain}


def occluders(st):
    """Screen boxes of everything drawn in front of the paper: props, lantern, candle, puppet; plus the paper pieces."""
    boxes = []
    for name in G.PROPS:
        x0, z0, x1, z1 = G.bbox(name)
        x, y = st[name], G.PROPS[name]["y"]
        pts = [G.to_pixel((x + a, y + d, b), W, H) for a in (x0, x1) for b in (z0, z1) for d in (-0.02, 0.02)]
        boxes.append(pts)
    lx, ly = st["lantern"]
    boxes.append([G.to_pixel((lx + a, ly + d, b), W, H) for a in (-0.11, 0.11) for b in (0, 0.45) for d in (-0.1, 0.1)])
    cx, cy = G.CANDLE
    boxes.append([G.to_pixel((cx + a, cy + d, b), W, H) for a in (-0.13, 0.17) for b in (0, 0.42) for d in (-0.13, 0.13)])
    pu, pv, _ = st["puppet"]
    boxes.append([P(pu + a, pv + b) for a in (-0.09, 0.09) for b in (-0.01, 0.32)])
    m = np.zeros((H, W), bool)
    for pts in boxes:
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        m[max(0, int(min(ys)) - 6):int(max(ys)) + 7, max(0, int(min(xs)) - 6):int(max(xs)) + 7] = True
    L = G.LEVEL
    pieces = [[P(u, v) for u, v in L[k]] for k in ("left_cliff", "right_cliff", "ledge")]
    dx, dz = L["door"]
    pieces.append([P(dx - 0.12, dz), P(dx + 0.12, dz), P(dx + 0.12, dz + 0.4), P(dx - 0.12, dz + 0.4)])
    a, b = L["pit"]
    pieces.append([P(a - 0.03, 0), P(b + 0.03, 0), P(b + 0.03, 0.17), P(a - 0.03, 0.17)])      # the thorns
    bx, bz = L["bonus"]
    pieces.append([P(bx - 0.08, bz - 0.08), P(bx + 0.08, bz - 0.08), P(bx + 0.08, bz + 0.08), P(bx - 0.08, bz + 0.08)])
    tx = -2.12                                                                                  # the paper tree
    pieces.append([P(tx - 0.2, 0.45), P(tx + 0.2, 0.45), P(tx + 0.2, 0.85), P(tx - 0.2, 0.85)])
    return m | ndimage.binary_dilation(poly_mask(pieces), iterations=4)


def lum(img):
    return 0.2126 * img[:, :, 0] + 0.7152 * img[:, :, 1] + 0.0722 * img[:, :, 2]


def measured_shadow(img, domain, pred):
    """Shadow pixels in domain: threshold half-way between the shadow's level (median inside the predicted shadow,
    eroded) and the lit paper's level (median in a ring 4..25 px outside it), in linear light: the penumbra's 50 % point
    is where half the flame is hidden, so a soft edge and a half-covered pixel both split evenly."""
    # in linear light (inverse of the display's sRGB encode and the engine's ACES): "50 %" = half the flame blocked
    import engine_tone as T
    lin = T.inv_aces(T.srgb_to_lin(img.reshape(-1, 3) / 255.0)).reshape(img.shape)
    L = lum(lin)
    core = ndimage.binary_erosion(pred, iterations=3) & domain
    ring = ndimage.binary_dilation(pred, iterations=25) & ~ndimage.binary_dilation(pred, iterations=4) & domain
    if core.sum() < 20 or ring.sum() < 20:
        return np.zeros_like(domain), 0
    t = (float(np.median(L[core])) + float(np.median(L[ring]))) / 2
    return (L < t) & domain, t


def edges(m, dom=None):
    """Pixels of m next to a pixel that is not m (inside dom: the borders of excluded areas are not outlines)."""
    other = ~m if dom is None else (~m & dom)
    return m & ndimage.binary_dilation(other)


def shadow_checks(game, target, st, tag):
    paper = regions()["paper"]
    occ = occluders(st)
    preds = {n: poly_mask(shadow_polys(n, st)) & paper for n in G.PROPS}
    out = {}
    for name, pred in preds.items():
        if pred.sum() < 200:
            out[name] = {"note": "shadow off the paper"}
            continue
        others = np.zeros_like(pred)
        for o, m in preds.items():
            if o != name:
                others |= m
        band = ndimage.binary_dilation(pred, iterations=25) & paper & ~occ
        domain = band & ~(ndimage.binary_dilation(others, iterations=6) & ~pred)
        mg, tg = measured_shadow(game, domain, pred)
        mt, tt = measured_shadow(target, domain, pred)
        inter, union = (mg & pred & domain).sum(), ((mg | pred) & domain).sum()
        near = ndimage.binary_dilation(edges(pred), iterations=8)   # outline edges only, not paper pieces or motes
        eg, et, ep = edges(mg, domain) & near, edges(mt, domain) & near, edges(pred, domain)
        dt_t = ndimage.distance_transform_edt(~et)
        dt_p = ndimage.distance_transform_edt(~ep)
        dg = dt_t[eg] if eg.any() else np.array([0.0])
        dgp = dt_p[eg] if eg.any() else np.array([0.0])
        dtp = dt_p[et] if et.any() else np.array([0.0])
        core = ndimage.binary_erosion(pred, iterations=5) & domain
        out[name] = {"grey_game": [round(float(c), 1) for c in game[core].mean(0)] if core.any() else None,
                     "grey_target": [round(float(c), 1) for c in target[core].mean(0)] if core.any() else None,
                     "iou_game_vs_planar": round(float(inter / max(union, 1)), 4),
                     "iou_target_vs_planar": round(float((mt & pred & domain).sum() / max(((mt | pred) & domain).sum(), 1)), 4),
                     "outline_game_vs_target_max_px": round(float(dg.max()), 1),
                     "outline_game_vs_target_p99_px": round(float(np.percentile(dg, 99)), 1),
                     "outline_game_vs_planar_max_px": round(float(dgp.max()), 1),
                     "outline_target_vs_planar_max_px": round(float(dtp.max()), 1),
                     "domain_px": int(domain.sum()), "thresholds": [float(tg), float(tt)]}
    return out


def mad(game, target, regs):
    out = {}
    for k, m in regs.items():
        d = np.abs(game - target)[m]
        out[k] = [round(float(c), 1) for c in d.mean(0)] + [int(m.sum())]
    return out


def side_by_side(game_path, target_path, out_path, label):
    a, b = Image.open(game_path).convert("RGB"), Image.open(target_path).convert("RGB")
    im = Image.new("RGB", (2 * W + 24, H + 64), (18, 14, 12))
    im.paste(a, (0, 64))
    im.paste(b, (W + 24, 64))
    d = ImageDraw.Draw(im)
    try:
        f = ImageFont.truetype("C:/Windows/Fonts/georgia.ttf", 34)
    except OSError:
        f = ImageFont.load_default()
    d.text((24, 14), "Player (engine), %s, 2560x1369" % label, fill=(230, 210, 180), font=f)
    d.text((W + 48, 14), "Cycles target, same camera and size", fill=(230, 210, 180), font=f)
    im.save(out_path)


def crops(shot, shot_1s, st, out_path):
    """400 % crops: a shadow edge, a curtain edge on the dark, the puppet, the lantern; a second later; |difference| x8."""
    a, b = np.asarray(Image.open(shot).convert("RGB")), np.asarray(Image.open(shot_1s).convert("RGB"))
    lx, ly = st["lantern"]
    pu, pv, _ = st["puppet"]
    cup = shadow_polys("cup", st)
    cu = np.mean([p[0] for poly in cup for p in poly])
    sx, sy = P(*G.project(lx, ly, G.PROPS["cup"]["y"], st["cup"] - 0.12, 0.24))
    spots = {"shadow edge (cup dome)": (sx, sy), "curtain edge on the dark": G.to_pixel((-2.0, -1.38, 1.6), W, H),
             "puppet": P(pu, pv + 0.15), "lantern": G.to_pixel((lx, ly, 0.22), W, H)}
    cw, ch, z = 140, 90, 4
    tiles = []
    stats = {}
    for name, (cx, cy) in spots.items():
        x0, y0 = int(cx - cw / 2), int(cy - ch / 2)
        ca, cb = a[y0:y0 + ch, x0:x0 + cw], b[y0:y0 + ch, x0:x0 + cw]
        diff = np.abs(ca.astype(int) - cb.astype(int))
        stats[name] = {"max_abs_diff_1s": int(diff.max()), "mean_abs_diff_1s": round(float(diff.mean()), 2), "at": [x0, y0]}
        row = [Image.fromarray(c).resize((cw * z, ch * z), Image.NEAREST) for c in (ca, cb, np.clip(diff * 8, 0, 255).astype(np.uint8))]
        tiles.append((name, row))
    im = Image.new("RGB", (3 * cw * z + 40, len(tiles) * (ch * z + 50)), (18, 14, 12))
    d = ImageDraw.Draw(im)
    try:
        f = ImageFont.truetype("C:/Windows/Fonts/georgia.ttf", 26)
    except OSError:
        f = ImageFont.load_default()
    for i, (name, row) in enumerate(tiles):
        y = i * (ch * z + 50)
        d.text((10, y + 10), "%s  (frame / one second later / |difference| x8, 400 %%)" % name, fill=(230, 210, 180), font=f)
        for j, t in enumerate(row):
            im.paste(t, (j * (cw * z + 20), y + 44))
    im.save(out_path)
    return stats


def main():
    res = {}
    regs = regions()
    for tag, shot, ref, st in (("A", "A_2560x1369.png", "target_2560x1369.png", G.STATE_A),
                               ("B", "B_2560x1369.png", "target_b_2560x1369.png", G.STATE_B)):
        gp, tp = os.path.join(SHOTS, shot), os.path.join(REF, ref)
        if not (os.path.exists(gp) and os.path.exists(tp)):
            print("missing", gp if not os.path.exists(gp) else tp)
            continue
        game, target = load(gp), load(tp)
        occ = occluders(st)                 # props, lantern, candle, puppet: compared separately (prop table)
        r2 = {k: (m & ~occ if k in ("paper", "floor") else m) for k, m in regs.items()}
        clean = os.path.join(SHOTS, tag + "_clean.png")       # particles off: the shadow measures
        gclean = load(clean) if os.path.exists(clean) else game
        res[tag] = {"mad": mad(game, target, r2), "shadows": shadow_checks(gclean, target, st, tag)}
        side_by_side(gp, tp, os.path.join(SHOTS, "side_by_side_%s.png" % tag), "state " + tag)
    a0, a1 = os.path.join(SHOTS, "A_clean.png"), os.path.join(SHOTS, "A_clean_1s.png")
    if os.path.exists(a1):
        res["crops"] = crops(a0, a1, G.STATE_A, os.path.join(SHOTS, "crops_400.png"))
    with open(os.path.join(SHOTS, "measure.json"), "w") as f:
        json.dump(res, f, indent=1)
    for tag in ("A", "B"):
        if tag not in res:
            continue
        print("state", tag, "MAD per channel (R, G, B; 0-255) and pixels:")
        for k, v in res[tag]["mad"].items():
            print("   %-9s %s" % (k, v))
        for n, s in res[tag]["shadows"].items():
            print("   %-7s %s" % (n, s))
    if "crops" in res:
        for k, v in res["crops"].items():
            print("   crop %-28s %s" % (k, v))


if __name__ == "__main__":
    main()
