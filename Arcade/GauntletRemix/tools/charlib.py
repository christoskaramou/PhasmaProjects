# Character modelling helpers for Gauntlet Remix (game-local, built on meshlib.M).
# Figures: Y up, face +Z. Every helper returns an M with smooth normals computed from its faces.
import numpy as np
from meshlib import M, rotm, xform, PI

def _mk(V, F, uv=None):
    V = np.array(V, float); N = np.zeros_like(V)
    for a, b, c in F:
        fn = np.cross(V[b] - V[a], V[c] - V[a]); N[a] += fn; N[b] += fn; N[c] += fn
    ln = np.linalg.norm(N, axis=1); ln[ln < 1e-12] = 1; N = N / ln[:, None]
    m = M(); m.add(list(V), list(N), uv or [(0.5, 0.5)] * len(V), F); return m

def grid(rings, closed=True, cap0=True, cap1=True):
    """rings: list of K rings, each a list of n 3D points (same n). Skins them; optional fan caps."""
    K, n = len(rings), len(rings[0]); V = [p for r in rings for p in r]; F = []
    nn = n if closed else n - 1
    for k in range(K - 1):
        for i in range(nn):
            j = (i + 1) % n
            a, b, c, d = k * n + i, k * n + j, (k + 1) * n + i, (k + 1) * n + j
            F += [(a, c, d), (a, d, b)]
    for cap, k, flip in ((cap0, 0, True), (cap1, K - 1, False)):
        if not cap: continue
        ctr = np.mean(rings[k], axis=0); ci = len(V); V.append(ctr)
        for i in range(nn):
            j = (i + 1) % n
            F.append((ci, k * n + j, k * n + i) if flip else (ci, k * n + i, k * n + j))
    m = _mk(V, F)
    # orient faces outward-ish: flip all if the mesh normals point inward on average
    c = np.mean(np.array(m.V), axis=0)
    s = sum(np.dot(np.array(m.N[i]), np.array(m.V[i]) - c) for i in range(len(m.V)))
    if s < 0: m.N = [-np.array(x) for x in m.N]; m.F = [(a, c2, b) for a, b, c2 in m.F]
    return m

def lathe(prof, n=22, c=(0, 0, 0), sx=1.0, sz=1.0, R=None, wob=None, cap0=True, cap1=True, zoff=None):
    """surface of revolution: prof = [(y, r), ...] bottom->top. sx/sz squash the section; wob(y, ang)->radius factor;
    zoff(y)->z shift of the ring centre (for leaning shapes)."""
    rings = []
    for y, r in prof:
        ring = []
        for i in range(n):
            a = 2 * PI * i / n; f = wob(y, a) if wob else 1.0
            ring.append(np.array([np.cos(a) * r * sx * f, y, np.sin(a) * r * sz * f + (zoff(y) if zoff else 0)]))
        rings.append(ring)
    m = grid(rings, True, cap0 and prof[0][1] > 1e-4, cap1 and prof[-1][1] > 1e-4)
    return xform(m, c, R)

def ell(c, r, n=20, k=12, R=None):
    prof = [(np.cos(PI * (1 - j / k)) * r[1], max(np.sin(PI * j / k), 0) * 1.0) for j in range(k + 1)]
    m = lathe([(y, s) for y, s in prof], n, (0, 0, 0), r[0], r[2], cap0=False, cap1=False)
    return xform(m, c, R)

def _frames(P):
    P = np.array(P, float); T = np.gradient(P, axis=0); T /= np.linalg.norm(T, axis=1)[:, None]
    up = np.array([0, 1.0, 0]) if abs(T[0][1]) < 0.9 else np.array([1.0, 0, 0])
    Nn = np.cross(T[0], up); Nn /= np.linalg.norm(Nn); out = []
    for i in range(len(P)):
        if i > 0:
            Nn = Nn - T[i] * np.dot(Nn, T[i]); Nn /= np.linalg.norm(Nn)
        out.append((T[i], Nn, np.cross(T[i], Nn)))
    return P, out

def sweep(P, radii, n=10, sq=1.0, caps=True):
    """tube along polyline P with per-point radius (sq squashes the section along the binormal)."""
    P, fr = _frames(P)
    if np.isscalar(radii): radii = [radii] * len(P)
    rings = []
    for p, (T, Nn, B), r in zip(P, fr, radii):
        r = max(r, 1e-4)
        rings.append([p + (Nn * np.cos(2 * PI * i / n) + B * np.sin(2 * PI * i / n) * sq) * r for i in range(n)])
    return grid(rings, True, caps, caps)

def arc(c, r, a0, a1, k=8, plane='xy'):
    pts = []
    for t in np.linspace(a0, a1, k):
        if plane == 'xy': pts.append((c[0] + np.cos(t) * r, c[1] + np.sin(t) * r, c[2]))
        elif plane == 'yz': pts.append((c[0], c[1] + np.sin(t) * r, c[2] + np.cos(t) * r))
        else: pts.append((c[0] + np.cos(t) * r, c[1], c[2] + np.sin(t) * r))
    return pts

def plate(poly2d, thick, c=(0, 0, 0), R=None, bevel=0.25):
    """thin plate from a 2D outline (in XY) with thickness along Z, bevelled rim (blades, wings, shields)."""
    P = np.array(poly2d, float); cen = P.mean(0); n = len(P)
    inner = cen + (P - cen) * (1 - bevel)
    rings = [[np.array([q[0], q[1], -thick / 2 * 0.2]) for q in inner], [np.array([q[0], q[1], -thick / 2]) for q in P],
             [np.array([q[0], q[1], thick / 2]) for q in P], [np.array([q[0], q[1], thick / 2 * 0.2]) for q in inner]]
    # skin rim; caps are fans at the inner rings
    m = grid([rings[0], rings[1], rings[2], rings[3]], True, True, True)
    return xform(m, c, R)

def boxr(c, s, r=0.25, n=6):
    """rounded box as a squashed superellipsoid-ish lathe (chunky armour plates, boots)."""
    hx, hy, hz = np.array(s) / 2
    prof = []
    for j in range(n + 1):
        t = -PI / 2 + PI * j / n
        y = np.sign(np.sin(t)) * abs(np.sin(t)) ** (1 - r) * hy
        rr = abs(np.cos(t)) ** (1 - r)
        prof.append((y, max(rr, 0.0)))
    def wob(y, a):
        ca, sa = abs(np.cos(a)), abs(np.sin(a))
        return 1.0 / max((ca ** (2 / (1 - r + 1e-3)) + sa ** (2 / (1 - r + 1e-3))) ** ((1 - r) / 2), 1e-3)
    return lathe(prof, 16, c, hx, hz, wob=wob, cap0=False, cap1=False)

def cone(c, r, h, n=14, R=None): return lathe([(0, r), (h, 0.0)], n, c, R=R)
def cyl(c, r, h, n=14, r1=None, R=None): return lathe([(0, r), (h, r if r1 is None else r1)], n, c, R=R)
def horn(base, d, L, r, curl=0.6, k=8, n=8):
    """curved tapering horn from base along direction d curling upward."""
    d = np.array(d, float); d /= np.linalg.norm(d); up = np.array([0, 1.0, 0]); P = []
    for t in np.linspace(0, 1, k):
        dd = d * (1 - curl * t * 0.6) + up * curl * t; dd /= np.linalg.norm(dd)
        P.append(np.array(base) + dd * L * t + up * curl * L * 0.3 * t * t)
    return sweep(P, [r * (1 - t) + 0.003 for t in np.linspace(0, 1, k)], n)
