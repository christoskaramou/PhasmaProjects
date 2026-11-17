"""The sea's small-scale chop: a looping normal-map flipbook and a colour detail map, one repeat = RIPPLE_P units.
Shared by tools/scene.py (Blender target) and tools/gen_assets.py (game). numpy only.

Two ripple layers in one map so the near water does not read as one repeated cell pattern:
  fine wind chop    wavelengths 0.08 - 0.6 units, around the wind direction, slopes ~ k^-1.25 (as fine as the
                    phase-0 target's 4-unit map: its mid-sea glitter is short horizontal dashes)
  cross chop        wavelengths 1.8 - 5.3 units, ~70 degrees off the wind, broader and slower
The fine layer is multiplied by a slow patchy envelope (calm and rough patches several units across), so glints gather
where the chop is rough and in the lamps' reflection paths instead of covering the water evenly.
Every wave has an integer number of cycles per repeat (seamless tiling) and turns an integer number of times per loop
(seamless loop); deep-water dispersion picks the turns (short waves turn faster).
"""
import math
import os

import numpy as np
from PIL import Image

import uw_common as U

TILT = 0.0                # (18:5x a -0.06 tilt lived here; 21:5x it moved into the sea mesh's near normals, uw_sea.tile,
                          # so it can fade with distance)
N = 1536                  # texels per repeat (96 per unit)
SLOPE = 0.30              # rms surface slope of the ripple layers (the engine ignores normal_scale: GBufferPS.hlsl:83-88)
WIND = math.radians(90)   # wave vectors across the view (crests along x): glints stretch into horizontal dashes


def _comps(rng, wind=None, spread=0.8):
    P = U.RIPPLE_P
    WIND = globals()["WIND"] if wind is None else wind
    out = []
    # fine wind chop: (kx, ky, amplitude, phase, turns, layer)
    for _ in range(120):
        lam = math.exp(rng.uniform(math.log(0.08), math.log(0.6)))
        ang = WIND + rng.normal(0, spread)
        k = P / lam
        kx, ky = int(round(k * math.cos(ang))), int(round(k * math.sin(ang)))
        if kx == 0 and ky == 0:
            continue
        kk = math.hypot(kx, ky)
        turns = int(np.clip(round(math.sqrt(kk / 10.0) * 1.4), 1, 3)) * (1 if rng.random() < 0.85 else -1)
        out.append((kx, ky, kk ** -1.25, rng.uniform(0, 2 * math.pi), turns, 0))
    # coarser cross chop
    for _ in range(26):
        lam = rng.uniform(1.8, 5.3)
        ang = WIND + math.radians(70) + rng.normal(0, 0.35)
        k = P / lam
        kx, ky = int(round(k * math.cos(ang))), int(round(k * math.sin(ang)))
        if kx == 0 and ky == 0:
            continue
        kk = math.hypot(kx, ky)
        out.append((kx, ky, 0.5 * kk ** -1.25, rng.uniform(0, 2 * math.pi), 1 if rng.random() < 0.8 else -1, 1))
    return out


def _envelope(rng, n):
    """Patchy calm / rough envelope in 0.3 .. 1, periodic, features 3 - 8 units."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
    e = np.zeros((n, n), np.float32)
    for _ in range(14):
        kx, ky = int(rng.integers(-5, 6)), int(rng.integers(-5, 6))
        if kx == 0 and ky == 0:
            continue
        e += np.sin(2 * np.pi * (kx * x + ky * y) + rng.uniform(0, 6.3)) / math.hypot(kx, ky) ** 0.5
    e = (e - e.mean()) / e.std()
    return 0.3 + 0.7 / (1 + np.exp(-1.6 * e))


def frames(rng, n=N, nframes=None, wind=None, spread=0.8, slope=None, tilt=TILT):
    """Yield (k, rgba float array) for each loop frame. tilt: a constant slope added along v (the view's depth axis):
    the flat water's mirror direction moves off the bright horizon band onto the darker sky above it."""
    nframes = nframes or U.RIPPLE_FRAMES
    comps = _comps(rng, wind, spread)
    SLOPE = globals()["SLOPE"] if slope is None else slope
    env = _envelope(rng, n)
    P = U.RIPPLE_P
    y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
    # rms slope of the raw sum, to scale to SLOPE
    var = sum(0.5 * (a * 2 * math.pi * math.hypot(kx, ky) / P) ** 2 for kx, ky, a, _ph, _t, _l in comps)
    s = SLOPE / math.sqrt(var)
    for f in range(nframes):
        gx = [np.zeros((n, n), np.float32), np.zeros((n, n), np.float32)]
        gy = [np.zeros((n, n), np.float32), np.zeros((n, n), np.float32)]
        for kx, ky, a, ph, turns, layer in comps:
            c = np.cos(2 * np.pi * (kx * x + ky * y) + ph + 2 * np.pi * turns * f / nframes)
            w = a * 2 * np.pi / P * s
            gx[layer] += w * kx * c
            gy[layer] += w * ky * c
        sx = gx[0] * env + gx[1]
        sy = gy[0] * env + gy[1] + tilt
        nx, ny = -sx, sy                     # same channel convention as the phase-1 maps
        ln = np.sqrt(nx * nx + ny * ny + 1)
        yield f, np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, 1 / ln * 0.5 + 0.5, np.ones_like(nx)], -1)


def detail(rng, n=1024):
    """Colour detail (multiplies the vertex colour): wind streaks plus broad lighter / darker patches, ~0.82 mean."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
    st = np.zeros((n, n), np.float32)
    for _ in range(80):
        kx = int(rng.integers(-12, 13))
        ky = int(rng.integers(16, 104))
        st += np.sin(2 * np.pi * (kx * x + ky * y) + rng.uniform(0, 6.3)) / ky ** 0.5
    st = (st - st.mean()) / st.std()
    patch = np.zeros((n, n), np.float32)
    for _ in range(12):
        kx, ky = int(rng.integers(-4, 5)), int(rng.integers(-4, 5))
        if kx or ky:
            patch += np.sin(2 * np.pi * (kx * x + ky * y) + rng.uniform(0, 6.3))
    patch = (patch - patch.mean()) / patch.std()
    return np.clip(0.80 + 0.10 * np.tanh(st * 1.3) + 0.07 * np.tanh(patch), 0.45, 1.0)


def _save(a, path):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path)


def make(out_dir, seed=11):
    rng = np.random.default_rng(seed)
    for f, nm in frames(rng):
        nm[..., :3] += (rng.random(nm[..., :3].shape) + rng.random(nm[..., :3].shape) - 1.0) / 255.0   # dither 8-bit
        _save(nm, os.path.join(out_dir, "sea_normal_%02d.png" % f))
    d = detail(rng)
    _save(np.dstack([d, d, d, np.ones_like(d)]), os.path.join(out_dir, "sea_detail.png"))
    for f in range(U.RIPPLE_FRAMES, 32):          # frames of an older, longer loop
        p = os.path.join(out_dir, "sea_normal_%02d.png" % f)
        if os.path.exists(p):
            os.remove(p)


if __name__ == "__main__":
    import sys
    make(sys.argv[1])


# ------------------------------------------------------------------ the game's depth-mapped maps (22:1x)
WORLD_W, WORLD_H = 1024, 2048      # u: RIPPLE_P units along x (repeats); v: once over uw_common.RIPPLE_V (ripple_v)
LOD_Q = (0.22, 0.50)               # cycles per screen pixel (1920 wide) over which a ripple fades out of the map
ROUGH_NEAR = 0.16                  # material roughness where every ripple is resolved; more where they are left out


def _world_rows(h):
    v = (np.arange(h) + 0.5) / h
    y = np.array([U.ripple_y(1.0 - vv) for vv in v], np.float64)       # image row 0 = top = v 1
    d = np.hypot(y - U.CAM_Y, U.CAM_Z)
    px_x = d * 2 * math.tan(math.atan(18.0 / U.LENS)) / 1920.0          # world units per pixel across
    px_y = px_x * d / U.CAM_Z                                             # and in depth (foreshortened)
    return y.astype(np.float32), px_x, px_y


def world_maps(out_dir, seed=11, slope=0.26, wind=WIND, spread=0.8, nframes=None, lod=None, prefix="sea_"):
    """sea_normal_NN.png (the loop), sea_detail.png and sea_rough.png (metallic-roughness: G = roughness, B = metallic
    0) for the depth-mapped UVs. Each ripple's amplitude fades where its screen frequency passes LOD_Q; the slope
    variance it leaves out becomes roughness (r^4 = r0^4 + 2 sigma^2, the GGX / Beckmann match)."""
    nframes = nframes or U.RIPPLE_FRAMES
    rng = np.random.default_rng(seed)
    comps = _comps(rng, wind, spread)
    P = U.RIPPLE_P
    W, H = WORLD_W, WORLD_H
    yrow, px_x, px_y = _world_rows(H)
    x = (np.arange(W, dtype=np.float32) + 0.5) / W * P
    var = sum(0.5 * (a * 2 * math.pi * math.hypot(kx, ky) / P) ** 2 for kx, ky, a, _ph, _t, _l in comps)
    s = slope / math.sqrt(var)
    # per-component fade by row, and the slope variance removed
    fades, removed = [], np.zeros(H)
    for kx, ky, a, ph, turns, layer in comps:
        Kx, Ky = 2 * math.pi * kx / P, 2 * math.pi * ky / P
        q = np.hypot(Kx * px_x, Ky * px_y) / (2 * math.pi)
        lq = lod or LOD_Q
        t = np.clip((q - lq[0]) / (lq[1] - lq[0]), 0, 1)
        f = 1 - t * t * (3 - 2 * t)
        fades.append(f.astype(np.float32))
        removed += 0.5 * (a * s * math.hypot(Kx, Ky)) ** 2 * (1 - f * f)
    rough = (ROUGH_NEAR ** 4 + 2 * removed) ** 0.25
    rr = np.repeat(rough[:, None], W, 1).astype(np.float32)
    Image.fromarray((np.dstack([np.zeros_like(rr), np.clip(rr, 0, 1), np.zeros_like(rr)]) * 255 + 0.5).astype(np.uint8),
                    "RGB").save(os.path.join(out_dir, prefix + "rough.png"))
    # envelope in world units (periodic along x with P)
    erng = np.random.default_rng(seed + 1)
    X, Y = np.meshgrid(x / P, yrow / P)
    env = np.zeros((H, W), np.float32)
    for _ in range(14):
        kx, ky = int(erng.integers(-5, 6)), int(erng.integers(-5, 6))
        if kx == 0 and ky == 0:
            continue
        env += (np.sin(2 * np.pi * (kx * X + ky * Y) + erng.uniform(0, 6.3)) / math.hypot(kx, ky) ** 0.5).astype(np.float32)
    env = (env - env.mean()) / env.std()
    env = 0.3 + 0.7 / (1 + np.exp(-1.6 * env))
    for f in range(nframes):
        gx = np.zeros((H, W), np.float32)
        gy = np.zeros((H, W), np.float32)
        for (kx, ky, a, ph, turns, layer), fd in zip(comps, fades):
            Kx, Ky = 2 * math.pi * kx / P, 2 * math.pi * ky / P
            c = np.cos(Kx * x[None, :] + Ky * yrow[:, None] + ph + 2 * np.pi * turns * f / nframes).astype(np.float32)
            w = (a * s * fd)[:, None] * (env if layer == 0 else 1.0)
            gx += w * Kx * c
            gy += w * Ky * c
        nx, ny = -gx, gy
        ln = np.sqrt(nx * nx + ny * ny + 1)
        nm = np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, 1 / ln * 0.5 + 0.5, np.ones_like(nx)], -1)
        nm[..., :3] += (rng.random(nm[..., :3].shape, np.float32) + rng.random(nm[..., :3].shape, np.float32) - 1.0) / 255.0
        _save(nm, os.path.join(out_dir, prefix + "normal_%02d.png" % f))
    # colour detail: the old periodic streaks and patches, evaluated at world points
    st = np.zeros((H, W), np.float32)
    drng = np.random.default_rng(seed + 2)
    for _ in range(80):
        kx = int(drng.integers(-12, 13))
        ky = int(drng.integers(16, 104))
        st += np.sin(2 * np.pi * (kx * X + ky * Y) + drng.uniform(0, 6.3)).astype(np.float32) / ky ** 0.5
    st = (st - st.mean()) / st.std()
    pt = np.zeros((H, W), np.float32)
    for _ in range(12):
        kx, ky = int(drng.integers(-4, 5)), int(drng.integers(-4, 5))
        if kx or ky:
            pt += np.sin(2 * np.pi * (kx * X + ky * Y) + drng.uniform(0, 6.3)).astype(np.float32)
    pt = (pt - pt.mean()) / pt.std()
    dd = np.clip(0.80 + 0.10 * np.tanh(st * 1.3) + 0.07 * np.tanh(pt), 0.45, 1.0)
    _save(np.dstack([dd, dd, dd, np.ones_like(dd)]), os.path.join(out_dir, prefix + "detail.png"))
    return rough
