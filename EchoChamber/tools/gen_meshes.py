"""Echo Chamber meshes: lathed bells, horn and pedestals, rounded blocks. Writes OBJ, cooks them to
Assets/Objects/*.pemesh with PhasmaCook, and writes Assets/Scenes/main.pescene with one hidden template
node per mesh (the game clones them with add_mesh_ref).

    python tools/gen_meshes.py [path/to/PhasmaCook.exe]

Units are board cells; Y is up; each piece's origin is its cell centre on the floor. "Behind" is -Z
(the camera sits at +Z looking down the board).
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


# ------------------------------------------------------------------ pieces
def bell():
    s = 1.3
    outer = smooth_profile([(0.36 * s, 0.0), (0.35 * s, 0.025 * s), (0.31 * s, 0.06 * s), (0.26 * s, 0.13 * s), (0.225 * s, 0.23 * s),
                            (0.205 * s, 0.35 * s), (0.195 * s, 0.45 * s), (0.18 * s, 0.52 * s), (0.14 * s, 0.57 * s),
                            (0.07 * s, 0.6 * s), (0.0, 0.605 * s)], 4)
    th = 0.035
    # Inner surface: offset inward along the outer normals, walked downward.
    inner = []
    for i, p in enumerate(outer):
        a = outer[max(i - 1, 0)]
        b = outer[min(i + 1, len(outer) - 1)]
        d = b - a
        nn = np.array([d[1], -d[0]]) / max(1e-9, np.linalg.norm(d))
        q = p - nn * th
        inner.append(np.array([max(0.0, q[0]), q[1]]))
    inner = inner[::-1]
    # Lip: a half-round from the inner lip to the outer lip.
    li, lo = inner[-1], outer[0]
    cen, rad = (li + lo) / 2, np.linalg.norm(lo - li) / 2
    lip = [cen + rad * np.array([-math.cos(math.pi * k / 8), -math.sin(math.pi * k / 8)]) for k in range(1, 8)]
    prof = [p for p in inner if True] + lip + outer
    body = lathe(prof, 56)
    crown = torus(0.06, 0.02, 32, 10, c=(0, 0.605 * s + 0.07, 0), Rm=rot("x", math.pi / 2))
    clapper = U(ball((0, 0.09, 0), 0.07), tube((0, 0.12, 0), (0, 0.7, 0), 0.012, 10))
    return U(body, crown, clapper)


def yoke():
    zb = -0.22
    parts = []
    for sx in (-1, 1):
        parts.append(tube((0.47 * sx, 0, zb), (0.47 * sx, 1.52, zb), 0.04, 18))
        parts.append(moved(lathe([(0, 0), (0.085, 0), (0.09, 0.02), (0.085, 0.06), (0.05, 0.08), (0, 0.08)], 24, sharp=(1, 4)), (0.47 * sx, 0, zb)))
        parts.append(ball((0.47 * sx, 1.55, zb), 0.055, 16, 10))
    parts.append(tube((-0.5, 1.5, zb), (0.5, 1.5, zb), 0.04, 18))
    parts.append(rbox((0, 1.5, zb / 2), (0.08, 0.06, abs(zb) + 0.04), 0.015))
    parts.append(tube((0, 1.33, 0), (0, 1.52, 0), 0.016, 10))
    return U(*parts)


def horn():
    th = 0.018
    n = 16
    outer = [(0.07 + 0.30 * (t ** 2.2), 0.55 * t) for t in [i / n for i in range(n + 1)]]
    inner = [(r - th, y) for r, y in outer][::-1]
    rim = [(outer[-1][0] + 0.012, outer[-1][1] + 0.004), (outer[-1][0] - th * 0.5, outer[-1][1] + 0.014)]
    # Outside from throat to mouth, round the rim, inside back to the throat (normals face the axis).
    prof = [(p[0], p[1]) for p in outer] + rim + list(inner)
    m = lathe(prof, 48)
    # Lathe is around +Y; the horn fires along +X.
    return moved(m, (-0.02, 0.4, 0), rot("z", -math.pi / 2))


def cabinet():
    return U(rbox((-0.2, 0.42, 0), (0.42, 0.62, 0.62), 0.06), rbox((-0.12, 0.05, 0), (0.6, 0.1, 0.7), 0.03))


def pedestal(r=0.3, h=0.07):
    return lathe([(0, 0), (r, 0), (r + 0.01, 0.02), (r, h - 0.015), (r - 0.03, h), (0, h)], 48, sharp=(1, 4))


def reflector_frame():
    parts = [pedestal()]
    for sx in (-1, 1):
        parts.append(rbox((0.49 * sx, 0.39, 0), (0.06, 0.72, 0.09), 0.02))
    parts.append(rbox((0, 0.76, 0), (1.06, 0.05, 0.09), 0.02))
    parts.append(rbox((0, 0.1, 0), (0.98, 0.05, 0.08), 0.015))
    return U(*parts)


def mirror():
    return rbox((0, 0.44, 0), (0.92, 0.6, 0.045), 0.015)


def wall():
    parts = [rbox((0, 0.36, 0), (0.86, 0.72, 0.86), 0.06, 4), rbox((0, 0.735, 0), (0.7, 0.05, 0.7), 0.02)]
    for ang in range(4):
        R = rot("y", ang * math.pi / 2)
        for k in (-0.24, -0.08, 0.08, 0.24):
            parts.append(moved(rbox((k, 0.27, 0.44), (0.07, 0.4, 0.05), 0.015), (0, 0, 0), R))
    return U(*parts)


def tile():
    return rbox((0, -0.03, 0), (0.95, 0.06, 0.95), 0.025, 2)


def fork():
    """A tuning fork on a pedestal: two tines, the pulse splits in two."""
    parts = [pedestal(0.24, 0.06), tube((0, 0.05, 0), (0, 0.36, 0), 0.035, 18), ball((0, 0.36, 0), 0.045, 16, 10)]
    parts.append(moved(torus(0.13, 0.032, 24, 10, arc=math.pi), (0, 0.42, 0), rot("x", -math.pi / 2)))
    for sx in (-1, 1):
        parts.append(tube((0.13 * sx, 0.42, 0), (0.13 * sx, 0.95, 0), 0.032, 16))
        parts.append(ball((0.13 * sx, 0.95, 0), 0.032, 14, 8))
    return U(*parts)


def resonator():
    prof = smooth_profile([(0.27, 0.0), (0.27, 0.05), (0.2, 0.08), (0.08, 0.14), (0.06, 0.3), (0.1, 0.4), (0.0, 0.42)], 4)
    return U(lathe([(0, 0)] + prof, 48))


def damper():
    parts = [rbox((0, 0.17, 0), (0.72, 0.34, 0.72), 0.13, 4)]
    for x in (-0.17, 0.17):
        for z in (-0.17, 0.17):
            parts.append(ball((x, 0.335, z), 0.035, 12, 8))
    return U(*parts)


MESHES = {
    "bell": bell, "yoke": yoke, "horn": horn, "cabinet": cabinet, "reflector_frame": reflector_frame,
    "mirror": mirror, "wall": wall, "tile": tile, "fork": fork, "resonator": resonator, "damper": damper,
}


VARIANTS = {"bell": [f"bell_{i}" for i in range(1, 9)]}
for _p in ("reflector_frame", "mirror", "fork", "resonator", "damper"):
    VARIANTS[_p] = [_p + "_ghost", _p + "_hint"]


def find_cook():
    if len(sys.argv) > 1 and not sys.argv[1].startswith("--"):
        return sys.argv[1]
    eng = os.path.normpath(os.path.join(ROOT, "..", "..", "PhasmaEngine"))
    for b in ("build-ninja-physics", "build-ninja"):
        p = os.path.join(eng, b, "Release", "PhasmaCook.exe")
        if os.path.exists(p):
            return p
    raise SystemExit("PhasmaCook.exe not found; pass its path")


def write_scene(names):
    I = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, -1000.0, 0, 1.0]
    sc = {"sources": [], "meshes": [], "nodes": []}
    sc["nodes"].append({"name": "Camera_0", "parent": -1, "local_matrix": [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 17.5, 11.2, 1.0],
                        "component_flags": 8, "camera": {"projection": "perspective", "fovx": 1.2, "near_plane": 0.1, "far_plane": 1000.0,
                                                         "speed": 3.5, "euler": [0.3, 3.14159, 0.0]}})
    sc["nodes"].append({"name": "Sun", "parent": -1, "local_matrix": [1.0, 0, 0, 0, 0, -0.001745, -0.999997, 0, 0, 0.999997, -0.001745, 0, 0, 30.0, 0, 1.0],
                        "component_flags": 2, "light": {"type": "directional", "color": [1.0, 0.97, 0.9, 2.6]}})
    # Materials live on mesh entries, so nodes sharing one entry share one material. Pieces that need
    # their own look get their own entries over the same cooked file: one per bell (rung / idle / wrong)
    # and ghost / hint copies of every piece (translucent previews).
    for s in names:
        sc["sources"].append({"path": f"../Objects/{s}.pemesh"})
        src = len(sc["sources"]) - 1
        for v in [s] + VARIANTS.get(s, []):
            sc["meshes"].append({"source": src, "source_mesh": 0})
            sc["nodes"].append({"name": "T_" + v, "parent": -1, "local_matrix": I, "component_flags": 0, "mesh_refs": [len(sc["meshes"]) - 1]})
    sc["lights"] = []
    sc["cameras"] = [{"name": "Camera_0", "position": [0.0, 17.5, 11.2], "euler": [0.3, 3.14159, 0.0], "fovx": 1.2,
                      "projection": "perspective", "near_plane": 0.1, "far_plane": 1000.0, "speed": 3.5, "node_index": 0}]
    sc["active_camera"] = 0
    sc["scene_scripts"] = {"on_play": ["Assets/Scripts/echo.lua"]}
    os.makedirs(os.path.dirname(SCENE), exist_ok=True)
    with open(SCENE, "w") as f:
        json.dump(sc, f, indent=1)


def main():
    if "--scene-only" in sys.argv:
        write_scene(sorted(MESHES))
        print("scene:", SCENE)
        return
    cook = find_cook()
    os.makedirs(OBJECTS, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="echo-meshes-") as tmp:
        lines = []
        for name, fn in MESHES.items():
            src = os.path.join(tmp, name + ".obj")
            nv, nt = save_obj(src, fn())
            print(f"{name:16s} {nv:6d} verts {nt:6d} tris")
            lines.append(f"{src}\t{os.path.join(OBJECTS, name + '.pemesh')}\n")
        manifest = os.path.join(tmp, "batch.txt")
        with open(manifest, "w", encoding="utf-8") as f:
            f.writelines(lines)
        r = subprocess.run([cook, "--batch", manifest], cwd=os.path.dirname(cook), capture_output=True, text=True)
        cooked = [l for l in (r.stdout + r.stderr).splitlines() if "Cooked" in l or "ERROR" in l or "rror" in l]
        print("\n".join(cooked[-20:]))
        if r.returncode != 0:
            raise SystemExit(f"PhasmaCook failed ({r.returncode})")
    write_scene(sorted(MESHES))
    print("scene:", SCENE)


if __name__ == "__main__":
    main()
