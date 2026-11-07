"""Kite Hill meshes and scene. The hills, village, windmill tower, sky and clouds are a pre-rendered backdrop
(tools/make_backdrop.py); this writes what moves in 3D on top of it: the kites (four billowed cloth panels on a
bowed cross spar, the bridle, the tail's ribbon bows), the flying lines, the ribbon gates (a wrapped ring on a pole,
streamers), the kite flyer and the windmill's sails, plus the quad that shows the backdrop and
Assets/Scenes/main.pescene with the camera, the sun and one hidden template node per mesh variant (the game clones
them with add_mesh_ref and colours them per variant).

    python tools/gen_meshes.py [path/to/PhasmaCook.exe]      (--scene-only: rewrite the scene, no cook)

Engine axes: X right, Y up, Z toward the camera. A kite's nose is +Y and its face looks +Z (at the camera); the
game spins it about Z to its heading. The camera numbers live in tools/kh_common.py and kitehill_world.lua (W.CAM).
"""
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import kh_common as K  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
OBJECTS = os.path.join(ROOT, "Assets", "Objects")
SCENE = os.path.join(ROOT, "Assets", "Scenes", "main.pescene")
CAM_POS, CAM_LOOK, VFOV = K.CAM_POS, K.CAM_LOOK, K.VFOV
BACK_D, BACK_ASPECT = K.BACK_D, K.BACK_ASPECT


# ------------------------------------------------------------------ mesh helpers (from Echo Chamber's tools)
class M:
    def __init__(s):
        s.V, s.N, s.F = [], [], []

    def add(s, V, N, F):
        b = len(s.V)
        s.V += [np.asarray(v, float) for v in V]
        s.N += [np.asarray(n, float) for n in N]
        s.F += [(a + b, c + b, d + b) for a, c, d in F]
        return s

    def __iadd__(s, o):
        return s.add(o.V, o.N, o.F)


def U(*ms):
    o = M()
    for m in ms:
        o += m
    return o


def moved(m, c=(0, 0, 0), R=None):
    o = M()
    V, N = np.array(m.V), np.array(m.N)
    if R is not None:
        V, N = V @ R.T, N @ R.T
    o.V, o.N, o.F = list(V + np.array(c, float)), list(N), list(m.F)
    return o


def rot(axis, a):
    c, s = math.cos(a), math.sin(a)
    if axis == "x":
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == "y":
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def smooth_profile(pts, sub=4):
    """Catmull-Rom through (r, y) points; keeps the end points."""
    P = [np.array(p, float) for p in pts]
    out = []
    for i in range(len(P) - 1):
        p0, p1, p2, p3 = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
        for k in range(sub):
            t = k / sub
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-1])
    return out


def lathe(profile, segs=48, sharp=()):
    """Revolve a (r, y) polyline around +Y. Normals from the profile: n = (dy, -dr), so walk the outside
    upward and the inside downward. Indices in `sharp` get split normals (hard edges)."""
    P = [np.array(p, float) for p in profile]
    n = len(P)
    seg_n = []
    for i in range(n - 1):
        d = P[i + 1] - P[i]
        L = np.linalg.norm(d)
        seg_n.append(np.array([d[1], -d[0]]) / L if L > 1e-9 else np.array([1.0, 0.0]))
    m = M()
    # Each profile point becomes one ring (two rings at sharp points).
    rings = []
    for i in range(n):
        if i in sharp and 0 < i < n - 1:
            rings.append((P[i], seg_n[i - 1], i - 0.5))
            rings.append((P[i], seg_n[i], i + 0.5))
        else:
            a = seg_n[i - 1] if i > 0 else seg_n[0]
            b = seg_n[i] if i < n - 1 else seg_n[-1]
            nn = a + b
            nn = nn / np.linalg.norm(nn) if np.linalg.norm(nn) > 1e-9 else a
            rings.append((P[i], nn, i))
    V, N, F = [], [], []
    for p, nn, _ in rings:
        for k in range(segs + 1):
            a = 2 * math.pi * k / segs
            ca, sa = math.cos(a), math.sin(a)
            V.append((p[0] * ca, p[1], p[0] * sa))
            N.append((nn[0] * ca, nn[1], nn[0] * sa))
    for j in range(len(rings) - 1):
        if rings[j][0][0] == rings[j + 1][0][0] and rings[j][0][1] == rings[j + 1][0][1]:
            continue  # split ring pair at a sharp point: no faces between them
        for k in range(segs):
            a = j * (segs + 1) + k
            b, c, d = a + 1, a + segs + 1, a + segs + 2
            F += [(a, c, d), (a, d, b)]
    return m.add(V, N, F)


def rbox(c, size, r, nseg=3):
    """Rounded box centred at c with full size `size` and edge radius r."""
    h = np.array(size, float) / 2
    r = min(r, *h)
    inner = h - r

    def coords(hh, ii):
        if r <= 0:
            return [-hh, hh]
        return sorted(set(round(v, 6) for v in list(np.linspace(-hh, -ii, nseg + 1)) + list(np.linspace(ii, hh, nseg + 1))))

    ax = [coords(h[i], inner[i]) for i in range(3)]
    m = M()
    for axis in range(3):
        u, v = [a for a in range(3) if a != axis]
        for sgn in (-1, 1):
            V, N, F = [], [], []
            us, vs = ax[u], ax[v]
            for vv in vs:
                for uu in us:
                    p = np.zeros(3)
                    p[axis], p[u], p[v] = sgn * h[axis], uu, vv
                    q = np.clip(p, -inner, inner)
                    d = p - q
                    L = np.linalg.norm(d)
                    nrm = d / L if L > 1e-9 else np.eye(3)[axis] * sgn
                    V.append(q + nrm * r if r > 0 else p)
                    N.append(nrm)
            nu = len(us)
            for j in range(len(vs) - 1):
                for i in range(nu - 1):
                    a = j * nu + i
                    F += [(a, a + 1, a + nu + 1), (a, a + nu + 1, a + nu)]
            m.add(V, N, F)
    return moved(m, c)


def tube(p0, p1, r, n=20, caps=True):
    p0, p1 = np.array(p0, float), np.array(p1, float)
    d = p1 - p0
    L = np.linalg.norm(d)
    prof = [(0.0, 0.0), (r, 0.0), (r, L), (0.0, L)] if caps else [(r, 0.0), (r, L)]
    m = lathe(prof, n, sharp=(1, 2) if caps else ())
    y = np.array([0, 1.0, 0])
    k = d / L
    v = np.cross(y, k)
    s, c = np.linalg.norm(v), np.dot(y, k)
    if s < 1e-9:
        R = np.eye(3) if c > 0 else rot("x", math.pi)
    else:
        v = v / s
        K = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
        R = np.eye(3) + s * K + (1 - c) * K @ K
    return moved(m, p0, R)


def torus(R0, r, nu=48, nv=12, c=(0, 0, 0), Rm=None, arc=2 * math.pi):
    V, N, F = [], [], []
    for j in range(nv + 1):
        b = 2 * math.pi * j / nv
        for i in range(nu + 1):
            a = arc * i / nu
            d = np.array([math.cos(a), 0, math.sin(a)])
            nn = d * math.cos(b) + np.array([0, math.sin(b), 0])
            V.append(d * R0 + nn * r)
            N.append(nn)
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i
            F += [(a, a + 1, a + nu + 2), (a, a + nu + 2, a + nu + 1)]
    return moved(M().add(V, N, F), c, Rm)


def ball(c, r, nu=24, nv=14):
    prof = [(r * math.sin(math.pi * k / nv), -r * math.cos(math.pi * k / nv)) for k in range(nv + 1)]
    return moved(lathe(prof, nu), c)


def save_obj(path, m):
    V, N = np.array(m.V), np.array(m.N)
    with open(path, "w") as fo:
        fo.write("o mesh\n")
        for p in V:
            fo.write("v %.5f %.5f %.5f\n" % tuple(p))
        fo.write("vt 0 0\n")
        for nn in N:
            L = np.linalg.norm(nn)
            nn = nn / L if L > 1e-9 else np.array([0, 1.0, 0])
            fo.write("vn %.5f %.5f %.5f\n" % tuple(nn))
        tris = 0
        for a, b, c in m.F:
            fn = np.cross(V[b] - V[a], V[c] - V[a])
            if np.linalg.norm(fn) < 1e-9:
                continue  # degenerate (PhasmaCook splits on them)
            if np.dot(fn, N[a] + N[b] + N[c]) < 0:
                b, c = c, b
            fo.write(f"f {a+1}/1/{a+1} {b+1}/1/{b+1} {c+1}/1/{c+1}\n")
            tris += 1
    return len(V), tris



def sweep(points, r, n=10):
    """A tube of radius r along a polyline (no caps): the spring's coil."""
    P = [np.array(p, float) for p in points]
    V, N, F = [], [], []
    for i, p in enumerate(P):
        t = P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]
        t /= np.linalg.norm(t)
        ref = np.array([0, 1.0, 0]) if abs(t[1]) < 0.9 else np.array([1.0, 0, 0])
        u = np.cross(t, ref); u /= np.linalg.norm(u)
        v = np.cross(t, u)
        for k in range(n + 1):
            a = 2 * math.pi * k / n
            d = u * math.cos(a) + v * math.sin(a)
            V.append(p + d * r)
            N.append(d)
    for i in range(len(P) - 1):
        for k in range(n):
            a = i * (n + 1) + k
            F += [(a, a + n + 1, a + n + 2), (a, a + n + 2, a + 1)]
    return M().add(V, N, F)


def flat(polys, centre):
    """Flat-shaded polygons (fan triangulated), normals pointing away from `centre`."""
    m = M()
    c = np.array(centre, float)
    for poly in polys:
        P = [np.array(p, float) for p in poly]
        n = np.cross(P[1] - P[0], P[2] - P[0])
        n /= np.linalg.norm(n)
        if np.dot(n, np.mean(P, 0) - c) < 0:
            n = -n
        m.add(P, [n] * len(P), [(0, i, i + 1) for i in range(1, len(P) - 1)])
    return m


def smooth(V, F, hint=None):
    """Mesh with area-weighted vertex normals (flipped to agree with `hint` when given)."""
    V = [np.asarray(v, float) for v in V]
    N = [np.zeros(3) for _ in V]
    for a, b, c in F:
        n = np.cross(V[b] - V[a], V[c] - V[a])
        for i in (a, b, c):
            N[i] += n
    out = []
    for n in N:
        L = np.linalg.norm(n)
        n = n / L if L > 1e-12 else np.array([0, 0, 1.0])
        if hint is not None and np.dot(n, hint) < 0:
            n = -n
        out.append(n)
    return M().add(V, out, F)


def scaled(m, s, c=(0, 0, 0)):
    s = np.array(s, float)
    o = M()
    o.V = [np.asarray(v) * s + np.array(c, float) for v in m.V]
    o.N = [(lambda n: n / max(1e-12, np.linalg.norm(n)))(np.asarray(n) / s) for n in m.N]
    o.F = list(m.F)
    return o


def two_sided(m, off=0.003):
    """The same sheet facing both ways (streamers turn as they flutter)."""
    back = M()
    back.V = [np.asarray(v) - np.asarray(n) * off for v, n in zip(m.V, m.N)]
    back.N = [-np.asarray(n) for n in m.N]
    back.F = [(a, c, b) for a, b, c in m.F]
    return U(m, back)


# ------------------------------------------------------------------ the kite (nose +Y, face +Z, spars crossing at the origin)
NOSE, TAIL, CROSS_Y, HALF_W, BOW = 1.05, -1.0, 0.3, 0.85, 0.2


def bow_z(x):
    """The cross spar is bowed back (away from the wind), so the wing tips sit behind the spine."""
    return -BOW * (x / HALF_W) ** 2


def sail_panel(tip, side, n=10):
    """One of the four cloth panels: tip (nose or tail), the cross spar's end on `side`, and the crossing point.
    Billowed back between its spars, with a scalloped hem along its free edge."""
    A = np.array([0.0, tip])
    B = np.array([side * HALF_W, CROSS_Y])
    C = np.array([0.0, CROSS_Y])
    V, idx = [], {}
    for i in range(n + 1):
        for j in range(n + 1 - i):
            l0, l1 = i / n, j / n
            l2 = 1 - l0 - l1
            p = A * l0 + B * l1 + C * l2
            p = p + (C - p) * 0.13 * 4 * l0 * l1 * (1 - l2) ** 3          # the hem curves in between its corners
            z = bow_z(p[0]) - 0.55 * l0 * l1 * (0.6 + 1.6 * l2)           # the cloth bellies back between the spars
            idx[(i, j)] = len(V)
            V.append((p[0], p[1], z))
    F = []
    for i in range(n):
        for j in range(n - i):
            a, b, c = idx[(i, j)], idx[(i + 1, j)], idx[(i, j + 1)]
            F.append((a, b, c))
            if (i + 1, j + 1) in idx:
                F.append((b, idx[(i + 1, j + 1)], c))
    return smooth(V, F, np.array([0, 0, 1.0]))


def kite_spars():
    m = tube((0, NOSE + 0.02, 0.012), (0, TAIL - 0.02, 0.012), 0.022, 8)
    pts = [(x, CROSS_Y, bow_z(x) + 0.012) for x in np.linspace(-HALF_W - 0.02, HALF_W + 0.02, 17)]
    m += sweep(pts, 0.02, 8)
    # Bridle: two cords from the spine to the towing point in front of the kite.
    tow = (0.0, 0.15, 0.55)
    m += tube((0, 0.82, 0.02), tow, 0.007, 5)
    m += tube((0, -0.55, 0.02), tow, 0.007, 5)
    return m


def tail_bow():
    """A ribbon bow tied on the tail string: two puffed lobes and a knot."""
    m = M()
    for sx in (-1, 1):
        lobe = scaled(ball((0, 0, 0), 1.0, 16, 10), (0.1, 0.055, 0.02), (sx * 0.08, 0, 0))
        m += moved(lobe, (0, 0, 0), rot("z", sx * 0.25))
    m += ball((0, 0, 0.0), 0.028, 10, 8)
    return m


def unit_line():
    """A cord of radius 1 and length 1 along +X (scaled per use)."""
    return tube((0, 0, 0), (1, 0, 0), 1.0, 6, caps=False)


# ------------------------------------------------------------------ the gates (ring in the XY plane, radius 1, scaled per heat)
RING_R = 0.055


def ring():
    return torus(1.0, RING_R, 96, 10, (0, 0, 0), rot("x", math.pi / 2))


def ring_wrap(turns=11, band=3.0, rows=8):
    """A ribbon wound round the ring (curved across its width, so it hugs the tube)."""
    V, N, F = [], [], []
    S = 720
    rr = RING_R + 0.008
    z = np.array([0, 0, 1.0])
    for k in range(S + 1):
        u = 2 * math.pi * k / S
        d = np.array([math.cos(u), math.sin(u), 0.0])
        v = turns * u
        for j in range(rows + 1):
            dv = band * (j / rows - 0.5)
            nn = d * math.cos(v + dv) + z * math.sin(v + dv)
            V.append(d + nn * rr)
            N.append(nn)
    w = rows + 1
    for k in range(S):
        for j in range(rows):
            a = k * w + j
            F += [(a, a + w, a + w + 1), (a, a + w + 1, a + 1)]
    return M().add(V, N, F)


def streamer(length=1.8, width=0.12):
    """A ribbon hanging from the ring (origin at its knot), a gentle S down its length."""
    V, F = [], []
    S = 24
    for k in range(S + 1):
        t = k / S
        y = -length * t
        x = 0.12 * math.sin(t * 5.0) * t
        z = 0.05 * math.sin(t * 3.0 + 1.0)
        tw = 0.6 * t
        for s in (-1, 1):
            V.append((x + s * width / 2 * math.cos(tw), y, z + s * width / 2 * math.sin(tw)))
    for k in range(S):
        a = 2 * k
        F += [(a, a + 1, a + 3), (a, a + 3, a + 2)]
    return two_sided(smooth(V, F, np.array([0, 0, 1.0])))


def pole():
    """Height 1 (scaled per gate), standing on the origin."""
    return tube((0, 0.0, 0), (0, 1.0, 0), 0.075, 10)


def pole_knot():
    """The ring's lashing on top of the pole: a short wrapped collar."""
    m = tube((0, -0.16, 0), (0, 0.04, 0), 0.095, 12)
    m += torus(0.095, 0.02, 16, 6, (0, -0.12, 0))
    m += torus(0.095, 0.02, 16, 6, (0, -0.02, 0))
    return m


# ------------------------------------------------------------------ the kite flyer (feet at the origin, facing -Z: toward the gates)
def flyer_legs():
    m = M()
    for sx in (-1, 1):
        m += tube((sx * 0.1, 0.08, 0), (sx * 0.095, 0.86, 0), 0.075, 12)
        m += rbox((sx * 0.1, 0.05, -0.04), (0.13, 0.1, 0.26), 0.04, 2)
    return m


def flyer_body():
    return lathe(smooth_profile([(0.0, 0.78), (0.17, 0.8), (0.165, 0.98), (0.19, 1.25), (0.2, 1.38), (0.16, 1.46),
                                 (0.06, 1.5), (0.0, 1.51)], 3), 24)


def flyer_head():
    m = ball((0, 1.63, 0), 0.115, 20, 12)
    m += tube((0, 1.48, 0), (0, 1.56, 0), 0.05, 10)
    return m


def flyer_hat():
    m = lathe([(0.0, 1.705), (0.25, 1.70), (0.255, 1.715), (0.0, 1.725)], 32)
    m += lathe(smooth_profile([(0.0, 1.71), (0.12, 1.71), (0.115, 1.78), (0.09, 1.83), (0.0, 1.84)], 2), 24)
    return m


def flyer_band():
    return lathe([(0.0, 1.72), (0.122, 1.72), (0.124, 1.76), (0.0, 1.76)], 24, sharp=(1, 2))


def flyer_arm():
    """Shoulder at the origin, hanging down -Y (the game swings it up toward the kite)."""
    m = tube((0, 0, 0), (0, -0.56, 0), 0.052, 10)
    m += ball((0, -0.6, 0), 0.055, 12, 8)
    return m


def flyer_spool():
    """The line's wooden spool, held across the hands."""
    m = lathe([(0.0, -0.09), (0.07, -0.09), (0.07, -0.07), (0.045, -0.06), (0.045, 0.06), (0.07, 0.07), (0.07, 0.09),
               (0.0, 0.09)], 18, sharp=(1, 2, 3, 4, 5, 6))
    return moved(m, (0, 0, 0), rot("z", math.pi / 2))


# ------------------------------------------------------------------ the windmill's sails (hub at the origin, in the XY plane, facing +Z)
ARM, ARM_IN, SAIL_W = 5.2, 1.0, 0.95


def mill_frame():
    m = tube((0, 0, -0.5), (0, 0, 0.35), 0.38, 16)
    m += ball((0, 0, 0.35), 0.2, 12, 8)
    for k in range(4):
        R = rot("z", math.pi / 4 + k * math.pi / 2)
        arm = rbox((ARM / 2, 0, 0.12), (ARM, 0.16, 0.14), 0.03, 1)
        arm += rbox(((ARM + ARM_IN) / 2, SAIL_W, 0.12), (ARM - ARM_IN, 0.07, 0.07), 0.02, 1)
        for x in np.linspace(ARM_IN, ARM, 9):
            arm += rbox((x, SAIL_W / 2, 0.12), (0.06, SAIL_W, 0.06), 0.015, 1)
        m += moved(arm, (0, 0, 0), R)
    return m


def mill_cloth():
    m = M()
    for k in range(4):
        R = rot("z", math.pi / 4 + k * math.pi / 2)
        V, F = [], []
        nx, ny = 12, 3
        for i in range(nx + 1):
            for j in range(ny + 1):
                x = ARM_IN + 0.05 + (ARM - ARM_IN - 0.1) * i / nx
                y = 0.06 + (SAIL_W - 0.1) * j / ny
                z = 0.06 - 0.06 * math.sin(math.pi * j / ny)
                V.append((x, y, z))
        for i in range(nx):
            for j in range(ny):
                a = i * (ny + 1) + j
                F += [(a, a + ny + 1, a + ny + 2), (a, a + ny + 2, a + 1)]
        m += moved(two_sided(smooth(V, F, np.array([0, 0, 1.0])), 0.01), (0, 0, 0), R)
    return m


MESHES = {
    "sail_tl": lambda: sail_panel(NOSE, -1), "sail_tr": lambda: sail_panel(NOSE, 1),
    "sail_bl": lambda: sail_panel(TAIL, -1), "sail_br": lambda: sail_panel(TAIL, 1),
    "kite_spars": kite_spars, "tail_bow": tail_bow, "line": unit_line,
    "ring": ring, "ring_wrap": ring_wrap, "streamer": streamer, "pole": pole, "pole_knot": pole_knot,
    "flyer_legs": flyer_legs, "flyer_body": flyer_body, "flyer_head": flyer_head, "flyer_hat": flyer_hat,
    "flyer_band": flyer_band, "flyer_arm": flyer_arm, "flyer_spool": flyer_spool,
    "mill_frame": mill_frame, "mill_cloth": mill_cloth,
}

# Materials live on mesh entries (nodes sharing one entry share one material), so every colour a mesh shows at once
# needs its own entry over the same cooked file: one sail / bow set per kite (the game paints them per design), one
# ring wrap / streamer per gate state. Template node names are "T_" + variant.
KITES = 4
VARIANTS = {f"sail_{p}": [f"sail_{p}_{k}" for k in range(1, KITES + 1)] for p in ("tl", "tr", "bl", "br")}
VARIANTS.update({
    "tail_bow": [f"tail_bow_{k}" for k in range(1, KITES + 1)],
    "line": ["line", "tail_string"],
    "ring_wrap": ["ring_wrap_todo", "ring_wrap_next", "ring_wrap_done"],
    "streamer": ["streamer_todo", "streamer_next", "streamer_done"],
})


# ------------------------------------------------------------------ backdrop quad and scene
def camera_basis():
    p, t = np.array(CAM_POS), np.array(CAM_LOOK)
    f = t - p
    f /= np.linalg.norm(f)
    right = np.cross(f, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, f)
    return p, f, right, up


def backdrop_obj(path):
    """A quad perpendicular to the view axis at BACK_D that the camera sees edge to edge (2.4:1). On a plane
    of constant depth, interpolated UVs equal the projective ones, so the picture maps exactly."""
    p, f, right, up = camera_basis()
    hh = BACK_D * math.tan(math.radians(VFOV / 2))
    hw = hh * BACK_ASPECT
    c = p + f * BACK_D
    corners = [c - right * hw - up * hh, c + right * hw - up * hh, c + right * hw + up * hh, c - right * hw + up * hh]
    with open(path, "w") as fo:
        fo.write("o backdrop\n")
        for v in corners:
            fo.write("v %.6f %.6f %.6f\n" % tuple(v))
        for t in [(0, 0), (1, 0), (1, 1), (0, 1)]:
            fo.write("vt %.6f %.6f\n" % t)
        fo.write("vn %.6f %.6f %.6f\n" % tuple(-f))
        fo.write("f 1/1/1 2/2/1 3/3/1\nf 1/1/1 3/3/1 4/4/1\n")


def look_matrix(pos, target, up=(0, 1, 0)):
    """Column-major 4x4 whose local -Z points from pos to target (lights shine along local -Z)."""
    pos, target = np.array(pos, float), np.array(target, float)
    z = -(target - pos) / np.linalg.norm(target - pos)
    x = np.cross(up, z); x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return [*x, 0.0, *y, 0.0, *z, 0.0, *pos, 1.0]


def write_scene(names):
    I = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]
    HIDDEN = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, -1000.0, 0, 1.0]
    sc = {"sources": [{"path": "../Objects/backdrop.pemesh"}], "meshes": [{"source": 0, "source_mesh": 0}], "nodes": []}
    cam = {"projection": "perspective", "fovx": 1.2, "near_plane": 0.2, "far_plane": 1200.0, "speed": 3.5, "euler": [0.0, 3.14159, 0.0]}
    sc["nodes"].append({"name": "Camera_0", "parent": -1, "local_matrix": look_matrix(CAM_POS, CAM_LOOK), "component_flags": 8, "camera": cam})
    # The sun up to the left behind the camera (as baked), and a soft sky fill from the right.
    s = K.sun()
    sun_at = (s[0] * 60, s[1] * 60, s[2] * 60 - 12)
    sc["nodes"].append({"name": "Sun", "parent": -1, "local_matrix": look_matrix(sun_at, (0.0, 0.0, -12.0)), "component_flags": 2,
                        "light": {"type": "directional", "color": [1.0, 0.92, 0.80, 2.6]}})
    sc["nodes"].append({"name": "Sky", "parent": -1, "local_matrix": look_matrix((4.0, 30.0, 30.0), (0.0, 4.0, -12.0)), "component_flags": 2,
                        "light": {"type": "directional", "color": [0.80, 0.88, 1.0, 0.5]}})
    sc["nodes"].append({"name": "T_backdrop", "parent": -1, "local_matrix": I, "component_flags": 0, "mesh_refs": [0]})
    for name in names:
        sc["sources"].append({"path": f"../Objects/{name}.pemesh"})
        src = len(sc["sources"]) - 1
        for v in VARIANTS.get(name, [name]):
            sc["meshes"].append({"source": src, "source_mesh": 0})
            sc["nodes"].append({"name": "T_" + v, "parent": -1, "local_matrix": HIDDEN, "component_flags": 0, "mesh_refs": [len(sc["meshes"]) - 1]})
    sc["lights"] = []
    sc["cameras"] = [{"name": "Camera_0", "position": list(CAM_POS), "euler": [0.0, 3.14159, 0.0], "fovx": 1.2, "projection": "perspective",
                      "near_plane": 0.2, "far_plane": 1200.0, "speed": 3.5, "node_index": 0}]
    sc["active_camera"] = 0
    sc["scene_scripts"] = {"on_play": ["Assets/Scripts/kitehill.lua"]}
    os.makedirs(os.path.dirname(SCENE), exist_ok=True)
    with open(SCENE, "w") as f:
        json.dump(sc, f, indent=1)


def find_cook():
    for a in sys.argv[1:]:
        if not a.startswith("--"):
            return a
    eng = os.path.normpath(os.path.join(ROOT, "..", "..", "PhasmaEngine"))
    for b in ("build-ninja-physics", "build-ninja"):
        p = os.path.join(eng, b, "Release", "PhasmaCook.exe")
        if os.path.exists(p):
            return p
    raise SystemExit("PhasmaCook.exe not found; pass its path")


def write_objs(folder, names=None):
    """Every mesh as OBJ (tools/make_icons.py renders the kite from these)."""
    out = {}
    for name in names or sorted(MESHES):
        path = os.path.join(folder, name + ".obj")
        out[name] = (path,) + save_obj(path, MESHES[name]())
    return out


def main():
    names = sorted(MESHES)
    if "--scene-only" not in sys.argv:
        cook = find_cook()
        os.makedirs(OBJECTS, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="kitehill-meshes-") as tmp:
            lines = []
            src = os.path.join(tmp, "backdrop.obj")
            backdrop_obj(src)
            lines.append(f"{src}\t{os.path.join(OBJECTS, 'backdrop.pemesh')}\n")
            for name, (path, nv, nt) in write_objs(tmp, names).items():
                print(f"{name:16s} {nv:6d} verts {nt:6d} tris")
                lines.append(f"{path}\t{os.path.join(OBJECTS, name + '.pemesh')}\n")
            manifest = os.path.join(tmp, "batch.txt")
            with open(manifest, "w", encoding="utf-8") as f:
                f.writelines(lines)
            r = subprocess.run([cook, "--batch", manifest], cwd=os.path.dirname(cook), capture_output=True, text=True)
            ok = f"{len(lines)} ok"
            if r.returncode != 0 or ok not in (r.stdout + r.stderr):
                print((r.stdout + r.stderr)[-3000:])
                raise SystemExit("PhasmaCook failed")
            print("cooked", len(lines), "meshes")
    write_scene(names)
    print("scene:", SCENE)


if __name__ == "__main__":
    main()
