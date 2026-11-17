"""The floor's missing light (no GI in the engine: bounce off the lit paper, the lantern-lit seam bevels, the warm gaps)
measured in the Player and added to the floor's emissive. Run after a look capture (tools/look_capture.py):

    python tools/floor_calib.py SHOTS_DIR [gain]

For states A and B: d = inverse ACES(target) - inverse ACES(game) over the live floor (props, lantern, candle and puppet
masked out), linear pre-tone-map units = emissive units. Kept only where both states agree: the mean where light is
missing in both, the smaller darkening where both are too bright, 0 where they disagree (a prop's floor shadow in one
target, the lit side of a seam that flips with the lantern), so nothing that moves gets baked. Mapped into the WIDE
bake and accumulated into tools/floor_fix.png (floor rows only), which gen_meshes.emissive_bake adds to backdrop_em.png.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
SHOTS = sys.argv[1]
GAIN = float(sys.argv[2]) if len(sys.argv) > 2 else 0.8
REF = os.path.normpath(os.path.join(HERE, "..", "..", ".concepts", "next", "puppet"))
sys.argv = [sys.argv[0], SHOTS, REF]           # look_measure reads its dirs from argv
import look_measure as LM                     # noqa: E402
import engine_tone as T                       # noqa: E402
import sp_common as G                         # noqa: E402

FIX = os.path.join(HERE, "floor_fix.png")
LO, SPAN = -0.1, 0.4                          # 8-bit encoding of the linear delta


def floor_rows():
    import gen_meshes as GM
    return GM.paper_rect_wide()[3] + 3


def read_fix(shape):
    if not os.path.exists(FIX):
        return np.zeros(shape)
    return np.asarray(Image.open(FIX).convert("RGB"), float) / 255 * SPAN + LO


def main():
    regs = LM.regions()
    ds, ok = [], []
    for st, shot, ref in ((G.STATE_A, "A_clean.png", "target_2560x1369.png"), (G.STATE_B, "B_clean.png", "target_b_2560x1369.png")):
        g = LM.load(os.path.join(SHOTS, shot)) / 255.0
        t = LM.load(os.path.join(REF, ref)) / 255.0
        lin = lambda a: T.inv_aces(T.srgb_to_lin(a.reshape(-1, 3))).reshape(a.shape)
        d = lin(t) - lin(g)
        valid = regs["floor"] & ~ndimage.binary_dilation(LM.occluders(st), iterations=16)
        d = np.stack([ndimage.gaussian_filter(d[:, :, c], 0.7) for c in range(3)], -1)
        ds.append(d); ok.append(valid)
    dA, dB = ds
    both = ok[0] & ok[1]
    # mean only where the two states agree in size too (a prop's colour in one state is not floor light: the comb in
    # B baked a green and red patch into A's floor, 2026-11-13), else the smaller of the two
    lo, hi = np.minimum(dA, dB), np.maximum(dA, dB)
    agree = lo > 0.4 * hi
    d = np.where((dA > 0) & (dB > 0), np.where(agree, (dA + dB) / 2, lo), np.where((dA < 0) & (dB < 0), hi, 0.0))
    d = np.clip(d, -0.08, 0.25)                    # inverse ACES explodes near white: no single pixel runs away
    d[~both] = 0
    # fill the masked holes (props, lantern) from their surroundings, fading to 0 away from measured floor
    w = ndimage.gaussian_filter(both.astype(float), 20)
    fill = np.stack([ndimage.gaussian_filter(d[:, :, c] * both, 20) for c in range(3)], -1) / np.maximum(w, 1e-3)[:, :, None]
    fill *= np.clip(w / 0.5, 0, 1)[:, :, None]
    d = np.where(both[:, :, None], d, fill) * GAIN
    # into the WIDE bake's floor rows
    Wd, Hd = G.WIDE
    s = Hd / 1369.0
    y0 = floor_rows()
    yy, xx = np.mgrid[y0:Hd, 0:Wd].astype(float)
    sx, sy = 1280 + (xx - Wd / 2) / s, yy / s
    out = np.stack([ndimage.map_coordinates(d[:, :, c], [sy, sx], order=1, mode="constant", cval=0.0) for c in range(3)], -1)
    fix = read_fix(out.shape) + out
    Image.fromarray((np.clip((fix - LO) / SPAN, 0, 1) * 255 + 0.5).astype(np.uint8)).save(FIX)
    m = both
    print("floor fix: rows %d.. of the WIDE bake; this pass mean %s, max %s; accumulated mean %s" % (
        y0, d[m].mean(0).round(4).tolist(), d[m].max(0).round(3).tolist(), fix.reshape(-1, 3).mean(0).round(4).tolist()))


if __name__ == "__main__":
    main()
