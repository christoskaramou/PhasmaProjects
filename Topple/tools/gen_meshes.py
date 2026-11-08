"""Topple meshes and scene. The table, room, lamp and chalk board are a pre-rendered backdrop
(tools/make_backdrop.py); this writes the toys that are built, knocked over and animated in 3D (dominoes and
their pips, bells on gallows, springs, rockets on launch rails, marble chutes, trees, building blocks, the
starter arrow; the houses are Tripo models from tools/make_houses.py), the quad that shows the backdrop, and Assets/Scenes/main.pescene with the camera,
the desk lamp's lights and one hidden template node per mesh variant (the game clones them with add_mesh_ref).

    python tools/gen_meshes.py [path/to/PhasmaCook.exe]      (--scene-only: rewrite the scene, no cook)

Engine axes: X right, Y up, Z toward the camera. Every toy faces +X with its origin on the felt (y = 0); the
game yaws it about Y. Table units: a domino is 1.0 tall, 0.5 wide, 0.15 thick. The camera numbers here, in
topple_world.lua (W.CAM) and in tools/backdrop_scene.py must stay identical, or the toys will not sit on the
pictured felt.
"""
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OBJECTS = os.path.join(ROOT, "Assets", "Objects")
SCENE = os.path.join(ROOT, "Assets", "Scenes", "main.pescene")
CAM_POS, CAM_LOOK, VFOV = (12.53, 13.65, 19.93), (-0.6, 0.0, -3.6), 29.84
LAMP_POS, LAMP_AIM = (-9.0, 11.5, 3.0), (-1.0, 0.0, -2.5)
BACK_D, BACK_ASPECT = 90.0, 3456 / 1440


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


# ------------------------------------------------------------------ toys (forward = +X, origin on the felt)
DOM_T, DOM_H, DOM_W = 0.15, 1.0, 0.5


def domino():
    return rbox((0, DOM_H / 2, 0), (DOM_T, DOM_H, DOM_W), 0.03, 3)


# Pip patterns: (top half, bottom half) on both broad faces, with the divider bar.
PATTERNS = [(1, 2), (3, 4), (5, 6), (2, 5), (4, 1), (6, 3), (3, 3), (5, 2), (6, 6), (4, 4)]
PIP_AT = {1: [(0, 0)], 2: [(-1, 1), (1, -1)], 3: [(-1, 1), (0, 0), (1, -1)], 4: [(-1, 1), (1, 1), (-1, -1), (1, -1)],
          5: [(-1, 1), (1, 1), (0, 0), (-1, -1), (1, -1)], 6: [(-1, 1), (1, 1), (-1, 0), (1, 0), (-1, -1), (1, -1)]}


def pips(k):
    top, bot = PATTERNS[k]
    m = M()
    for sx in (1, -1):
        x0 = sx * (DOM_T / 2 - 0.003)
        x1 = sx * (DOM_T / 2 + 0.006)
        for val, yc in ((top, 0.75), (bot, 0.25)):
            for du, dv in PIP_AT[val]:
                z, y = du * 0.12 * sx, yc + dv * 0.12
                m += tube((x0, y, z), (x1, y, z), 0.036, 14)
        m += rbox((sx * DOM_T / 2, 0.5, 0), (0.012, 0.02, 0.4), 0.004, 1)
    return m


def bell():
    """Hangs from its crown at the origin; mouth 1.0 below."""
    outer = smooth_profile([(0.48, 0.0), (0.47, 0.035), (0.41, 0.13), (0.33, 0.33), (0.27, 0.56), (0.235, 0.78),
                            (0.2, 0.9), (0.13, 0.98), (0.0, 1.0)], 4)
    th = 0.04
    inner = []
    for i, p in enumerate(outer):
        a, b = outer[max(i - 1, 0)], outer[min(i + 1, len(outer) - 1)]
        d = b - a
        nn = np.array([d[1], -d[0]]) / max(1e-9, np.linalg.norm(d))
        q = p - nn * th
        inner.append(np.array([max(0.0, q[0]), q[1]]))
    inner = inner[::-1]                                   # inside walked downward, then the lip, then outside upward
    li, lo = inner[-1], outer[0]
    cen, rad = (li + lo) / 2, np.linalg.norm(lo - li) / 2
    lip = [cen + rad * np.array([-math.cos(math.pi * k / 8), -math.sin(math.pi * k / 8)]) for k in range(1, 8)]
    prof = inner + lip + list(outer)
    m = lathe([(p[0], p[1]) for p in prof], 56)
    m += ball((0, 0.1, 0), 0.085, 18, 10)                 # clapper
    m += torus(0.06, 0.018, 24, 8, (0, 1.03, 0), rot("x", math.pi / 2))   # crown loop
    return moved(m, (0, -1.04, 0))


def gallows():
    m = M()
    for z in (-0.62, 0.62):
        m += tube((0, 0, z), (0, 2.32, z), 0.06, 14)
        m += rbox((0, 0.04, z), (0.5, 0.08, 0.16), 0.02, 2)
    m += rbox((0, 2.32, 0), (0.16, 0.16, 1.48), 0.03, 2)
    m += tube((0, 2.16, 0), (0, 2.26, 0), 0.02, 8)
    return m


def spring_base():
    return lathe([(0.0, 0.0), (0.38, 0.0), (0.395, 0.03), (0.39, 0.08), (0.37, 0.1), (0.0, 0.1)], 40, sharp=(1,))


def spring_coil():
    pts = [(0.22 * math.cos(t), 0.1 + 0.7 * t / (6.5 * 2 * math.pi), 0.22 * math.sin(t)) for t in np.linspace(0, 6.5 * 2 * math.pi, 160)]
    return sweep(pts, 0.032, 10)


def spring_cap():
    return lathe([(0.0, 0.0), (0.31, 0.0), (0.325, 0.03), (0.31, 0.075), (0.0, 0.08)], 40)


def rocket_body():
    return lathe(smooth_profile([(0.0, 0.1), (0.15, 0.1), (0.16, 0.16), (0.16, 0.95), (0.0, 0.95)], 2), 32, sharp=(2,))


def rocket_band():
    return lathe([(0.0, 0.54), (0.168, 0.54), (0.168, 0.7), (0.0, 0.7)], 32, sharp=(1, 2))


def rocket_nose():
    return lathe(smooth_profile([(0.0, 0.94), (0.168, 0.94), (0.15, 1.08), (0.1, 1.22), (0.035, 1.32), (0.0, 1.35)], 3), 32, sharp=(1,))


def rocket_fins():
    m = M()
    for a in (0, 2 * math.pi / 3, 4 * math.pi / 3):
        m += moved(rbox((0.21, 0.19, 0), (0.2, 0.36, 0.028), 0.012, 1), (0, 0, 0), rot("y", a))
    m += lathe([(0.0, 0.0), (0.1, 0.0), (0.12, 0.1), (0.0, 0.1)], 20)
    return m


ROCKET_TILT = 25.0      # degrees toward +X on the launcher


def launcher():
    m = rbox((0, 0.025, 0), (0.62, 0.05, 0.62), 0.015, 2)
    R = rot("z", -math.radians(ROCKET_TILT))
    for z in (-0.13, 0.13):
        m += moved(rbox((0, 0.55, 0), (0.04, 1.0, 0.04), 0.01, 1), (0, 0.04, z), R)
    return m


CHUTE_L, CHUTE_TOP, CHUTE_BOT = 1.8, 1.0, 0.12


def chute():
    ang = math.atan2(CHUTE_TOP - CHUTE_BOT, CHUTE_L)
    R = rot("z", -ang)
    mid_y = (CHUTE_TOP + CHUTE_BOT) / 2
    m = moved(rbox((0, 0, 0), (CHUTE_L / math.cos(ang), 0.06, 0.58), 0.02, 2), (0, mid_y, 0), R)
    for z in (-0.3, 0.3):
        m += moved(rbox((0, 0.08, 0), (CHUTE_L / math.cos(ang), 0.14, 0.04), 0.015, 1), (0, mid_y, z), R)
    for x, z in ((-0.72, -0.24), (-0.72, 0.24), (0.15, -0.24), (0.15, 0.24)):
        h = CHUTE_TOP - (x + CHUTE_L / 2) * math.tan(ang)
        m += tube((x, 0, z), (x, h - 0.03, z), 0.035, 10)
    m += rbox((-CHUTE_L / 2 + 0.03, CHUTE_TOP + 0.08, 0), (0.06, 0.2, 0.58), 0.02, 2)      # stop at the top
    return m


def tree_trunk():
    return tube((0, 0, 0), (0, 0.62, 0), 0.09, 12)


def tree_top():
    return lathe(smooth_profile([(0.0, 0.42), (0.5, 0.5), (0.4, 0.9), (0.24, 1.4), (0.0, 1.85)], 3), 28)


def block():
    return rbox((0, 0.28, 0), (0.56, 0.56, 0.56), 0.05, 3)


def arrow():
    """The starter marker: a flat brass chevron on the felt pointing +X."""
    pts = [(0.5, 0.012, 0.0), (-0.1, 0.012, 0.3), (0.06, 0.012, 0.0), (-0.1, 0.012, -0.3)]
    return flat([[pts[0], pts[1], pts[2]], [pts[0], pts[2], pts[3]]], (0, -1, 0))


MESHES = {
    "domino": domino, "bell": bell, "gallows": gallows, "spring_base": spring_base, "spring_coil": spring_coil,
    "spring_cap": spring_cap, "rocket_body": rocket_body, "rocket_band": rocket_band, "rocket_nose": rocket_nose,
    "rocket_fins": rocket_fins, "launcher": launcher, "chute": chute, "tree_trunk": tree_trunk, "tree_top": tree_top,
    "block": block, "arrow": arrow,
}
for _k in range(len(PATTERNS)):
    MESHES[f"pips_{_k}"] = (lambda k: lambda: pips(k))(_k)

# Materials live on mesh entries (nodes sharing one entry share one material): every colour of a toy is its own
# entry over the same cooked file. Template node names are "T_" + variant.
PAINTS = ["brick", "mustard", "sage", "navy", "cream"]
VARIANTS = {
    "domino": [f"domino_{p}" for p in PAINTS],
    "block": [f"block_{p}" for p in ("mustard", "sage", "navy", "brick")],
}
for _k in range(len(PATTERNS)):
    VARIANTS[f"pips_{_k}"] = [f"pips_{_k}_dark", f"pips_{_k}_light"]


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
    sc["nodes"].append({"name": "Camera_0", "parent": -1, "local_matrix": look_matrix(CAM_POS, CAM_LOOK), "component_flags": 8,
                        "camera": {"projection": "perspective", "fovx": 1.2, "near_plane": 0.1, "far_plane": 300.0, "speed": 3.5,
                                   "euler": [0.0, 3.14159, 0.0]}})
    # The desk lamp: a warm spot for the pool of light and a directional along it for the toys' own shadows; a soft
    # fill from above the camera (the concept's overhead and front fills) so the faces we see are not left dark.
    sc["nodes"].append({"name": "Lamp", "parent": -1, "local_matrix": look_matrix(LAMP_POS, LAMP_AIM), "component_flags": 2,
                        "light": {"type": "spot", "color": [1.0, 0.84, 0.66, 4.5], "range": 60.0, "params": [32.0, 50.0, 0.0, 0.0]}})
    sc["nodes"].append({"name": "Key", "parent": -1, "local_matrix": look_matrix(LAMP_POS, LAMP_AIM), "component_flags": 2,
                        "light": {"type": "directional", "color": [1.0, 0.86, 0.7, 0.8]}})
    sc["nodes"].append({"name": "Fill", "parent": -1, "local_matrix": look_matrix((10.0, 16.0, 20.0), (0.0, 0.0, -3.0)), "component_flags": 2,
                        "light": {"type": "directional", "color": [1.0, 0.93, 0.84, 0.55]}})
    sc["nodes"].append({"name": "T_backdrop", "parent": -1, "local_matrix": I, "component_flags": 0, "mesh_refs": [0]})
    for s in names:
        sc["sources"].append({"path": f"../Objects/{s}.pemesh"})
        src = len(sc["sources"]) - 1
        for v in VARIANTS.get(s, [s]):
            sc["meshes"].append({"source": src, "source_mesh": 0})
            sc["nodes"].append({"name": "T_" + v, "parent": -1, "local_matrix": HIDDEN, "component_flags": 0, "mesh_refs": [len(sc["meshes"]) - 1]})
    # Table Run's houses (tools/make_houses.py: Tripo models, cooked with their textures applied at runtime).
    import make_houses
    for name in make_houses.NAMES:
        if os.path.exists(os.path.join(OBJECTS, name + ".pemesh")):
            sc["sources"].append({"path": f"../Objects/{name}.pemesh"})
            sc["meshes"].append({"source": len(sc["sources"]) - 1, "source_mesh": 0})
            sc["nodes"].append({"name": "T_" + name, "parent": -1, "local_matrix": HIDDEN, "component_flags": 0, "mesh_refs": [len(sc["meshes"]) - 1]})
    # Free Build's room (tools/gen_room.py): one hidden template per piece, and the table lamp's light (dark until
    # Free Build switches it on; Free Build re-aims Key as the sun, since directional light 0 casts the shadows).
    import gen_room
    for name in gen_room.ROOM_NAMES:
        if os.path.exists(os.path.join(OBJECTS, name + ".pemesh")):
            sc["sources"].append({"path": f"../Objects/{name}.pemesh"})
            sc["meshes"].append({"source": len(sc["sources"]) - 1, "source_mesh": 0})
            sc["nodes"].append({"name": "T_" + name, "parent": -1, "local_matrix": HIDDEN, "component_flags": 0, "mesh_refs": [len(sc["meshes"]) - 1]})
    lamp = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, *gen_room.E(*gen_room.LAMP_AT), 1.0]
    sc["nodes"].append({"name": "RoomLamp", "parent": -1, "local_matrix": lamp, "component_flags": 2,
                        "light": {"type": "point", "color": [1.0, 0.72, 0.42, 0.0], "radius": 60.0}})
    sc["lights"] = []
    sc["cameras"] = [{"name": "Camera_0", "position": list(CAM_POS), "euler": [0.0, 3.14159, 0.0], "fovx": 1.2, "projection": "perspective",
                      "near_plane": 0.1, "far_plane": 300.0, "speed": 3.5, "node_index": 0}]
    sc["active_camera"] = 0
    sc["scene_scripts"] = {"on_play": ["Assets/Scripts/topple.lua"]}
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


def main():
    names = sorted(MESHES)
    if "--scene-only" not in sys.argv:
        cook = find_cook()
        os.makedirs(OBJECTS, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="topple-meshes-") as tmp:
            lines = []
            src = os.path.join(tmp, "backdrop.obj")
            backdrop_obj(src)
            lines.append(f"{src}\t{os.path.join(OBJECTS, 'backdrop.pemesh')}\n")
            for name in names:
                src = os.path.join(tmp, name + ".obj")
                nv, nt = save_obj(src, MESHES[name]())
                print(f"{name:16s} {nv:6d} verts {nt:6d} tris")
                lines.append(f"{src}\t{os.path.join(OBJECTS, name + '.pemesh')}\n")
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
