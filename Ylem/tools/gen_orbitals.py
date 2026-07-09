#!/usr/bin/env python3
# gen_orbitals.py — bake real hydrogenic orbitals to RGBA PNGs for Ylem's "Orbital cloud"
# atom view, one per (n, l, |m|). Each texture is the 2D |psi|^2 cross-section (the xz-plane
# slice, phi=0) of the exact analytic hydrogenic orbital psi_{n,l,m} — the actual probability
# of finding the electron, with true radial nodes (n-l-1) and the angular lobes set by (l,m).
# Coloured with a hot map (blue 0 -> yellow -> red 1, scaled to each orbital's own max), like
# the "Orbitals of the Outermost Electrons" chart. The game picks the outermost electron's
# (n,l,m) by Hund's rule and draws orbital_<n><l>_m<|m|>.png. +m and -m share |psi|^2 magnitude
# (they differ only by a rotation about z), so we key on |m|. Multi-electron atoms use the
# hydrogen approximation (no screening) — standard for this visualization. numpy only.
import os, glob, zlib, struct
import numpy as np

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets", "Textures")
RES = 256
LCHAR = {0: "s", 1: "p", 2: "d", 3: "f"}
# (n, l) subshells in Madelung fill order — the set any element's outermost shell can be.
SUBSHELLS = [(1, 0), (2, 0), (2, 1), (3, 0), (3, 1), (4, 0), (3, 2), (4, 1), (5, 0), (4, 2),
             (5, 1), (6, 0), (4, 3), (5, 2), (6, 1), (7, 0), (5, 3), (6, 2), (7, 1)]

# hot colormap control points (probability 0 -> 1): deep blue -> blue -> cyan -> yellow -> red.
CM_T = np.array([0.0, 0.30, 0.55, 0.78, 1.0])
CM_C = np.array([[20, 40, 120], [40, 120, 230], [60, 210, 210], [240, 220, 60], [235, 50, 30]], float)


def genlaguerre(k, alpha, x):  # generalized Laguerre L_k^alpha via recurrence
    if k == 0:
        return np.ones_like(x)
    Lkm1 = np.ones_like(x)
    Lk = 1.0 + alpha - x
    for m in range(1, k):
        Lk, Lkm1 = ((2 * m + 1 + alpha - x) * Lk - (m + alpha) * Lkm1) / (m + 1), Lk
    return Lk


def radial(n, l, r):  # hydrogenic R_{nl} shape (a0 = 1; normalization dropped)
    rho = 2.0 * r / n
    return np.exp(-rho / 2.0) * rho ** l * genlaguerre(n - l - 1, 2 * l + 1, rho)


def angular(l, mm, c, s):  # |P_l^|m|| angular part (c=cos theta, s=sin theta); consts dropped
    return {
        (0, 0): np.ones_like(c),
        (1, 0): c, (1, 1): s,
        (2, 0): 0.5 * (3 * c * c - 1.0), (2, 1): s * c, (2, 2): s * s,
        (3, 0): 0.5 * (5 * c ** 3 - 3.0 * c), (3, 1): s * (5 * c * c - 1.0), (3, 2): s * s * c, (3, 3): s ** 3,
    }[(l, mm)]


def fit_extent(n, l):  # half-width framing the VISIBLE lobes, not the faint 99.5% tail: the
    r = np.linspace(1e-4, n * n * 4.0 + 30.0, 4000)   # outermost r where the radial density is
    dp = (radial(n, l, r) * r) ** 2                    # still > 4% of its peak (so the bright
    idx = np.where(dp > 0.04 * dp.max())[0]            # orbital fills the tile instead of ~20%)
    return (r[idx[-1]] if len(idx) else 5.0) * 1.3     # +margin so the halo fades out before the edge


def hot(t):  # (H,W) in [0,1] -> (H,W,3) uint8 via the hot colormap
    flat = t.ravel()
    ch = [np.interp(flat, CM_T, CM_C[:, k]).reshape(t.shape) for k in range(3)]
    return np.clip(np.dstack(ch), 0, 255).astype(np.uint8)


def write_png(path, rgba):  # minimal RGBA PNG (color type 6, 8-bit)
    h, w, _ = rgba.shape
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw.extend(rgba[y].tobytes())

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def make(n, l, mm):
    L = fit_extent(n, l)
    ax = np.linspace(-L, L, RES)
    X, Z = np.meshgrid(ax, ax)            # X horizontal, Z vertical (polar axis)
    r = np.sqrt(X * X + Z * Z) + 1e-6
    c = np.clip(Z / r, -1.0, 1.0)
    s = np.sqrt(np.clip(1.0 - c * c, 0.0, 1.0))
    psi = radial(n, l, r) * angular(l, mm, c, s)
    dens = psi * psi                      # 2D probability-density slice |psi|^2
    dens /= (dens.max() or 1.0)           # scale to this orbital's own max (poster convention)
    tcol = np.power(dens, 0.5)            # colour index: peak -> red
    a = np.power(dens, 0.28)             # alpha: strong lift so the cloud reads as filled to its edge
    rr = np.sqrt(X * X + Z * Z) / L      # radial vignette: fade alpha smoothly to 0 before the tile
    win = np.clip((1.0 - rr) / 0.18, 0.0, 1.0)   # border so the halo is never cut off at the edge
    a = a * (win * win * (3.0 - 2.0 * win))       # (smoothstep window, 1 in the core -> 0 at r=L)
    a[a < 0.006] = 0.0                   # clean transparent background
    rgba = np.dstack([hot(tcol), (a * 255).astype(np.uint8)])
    write_png(os.path.join(OUT, "orbital_%d%s_m%d.png" % (n, LCHAR[l], mm)), np.flipud(rgba).copy())
    print("wrote orbital_%d%s_m%d.png" % (n, LCHAR[l], mm))


os.makedirs(OUT, exist_ok=True)
for f in glob.glob(os.path.join(OUT, "orbital_*.png")):  # clear the old m=0-only set
    os.remove(f)
count = 0
for (n, l) in SUBSHELLS:
    for mm in range(l + 1):               # |m| = 0..l (each distinct shape; +/-m share magnitude)
        make(n, l, mm)
        count += 1
print("done: %d orbital textures" % count)
