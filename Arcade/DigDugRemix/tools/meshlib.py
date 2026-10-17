# mesh helpers (from Galaga Remix tools)
# Conventions: playfield is the XY plane, camera looks down -Z, ships point toward +Y, thickness along Z.
import numpy as np, os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'meshsrc')
os.makedirs(OUT, exist_ok=True)

class M:
    def __init__(s): s.V, s.N, s.UV, s.F = [], [], [], []
    def add(s, V, N, UV, F):
        b = len(s.V); s.V += list(V); s.N += list(N); s.UV += list(UV); s.F += [(a + b, c + b, d + b) for a, c, d in F]; return s
    def __iadd__(s, o): return s.add(o.V, o.N, o.UV, o.F)

def rotm(rx=0, ry=0, rz=0):
    cx, sx, cy, sy, cz, sz = np.cos(rx), np.sin(rx), np.cos(ry), np.sin(ry), np.cos(rz), np.sin(rz)
    X = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]]); Y = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Z = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]); return Z @ Y @ X

def xform(m, c=(0, 0, 0), R=None, mirror_x=False):
    o = M(); V = np.array(m.V, float); N = np.array(m.N, float)
    if R is not None: V = V @ R.T; N = N @ R.T
    if mirror_x: V[:, 0] *= -1; N[:, 0] *= -1
    V = V + np.array(c); o.V, o.N, o.UV, o.F = list(V), list(N), list(m.UV), list(m.F); return o

def ellipsoid(c, r, nu=24, nv=14, R=None, squash_back=1.0):
    m = M(); V, N, UV, F = [], [], [], []
    r = np.array(r, float)
    for j in range(nv + 1):
        th = np.pi * j / nv
        for i in range(nu + 1):
            ph = 2 * np.pi * i / nu
            d = np.array([np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph)])
            p = d * r
            if p[2] < 0: p[2] *= squash_back
            n = d / r; n /= np.linalg.norm(n)
            V.append(p); N.append(n); UV.append((i / nu, j / nv))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i; b = a + 1; cc = a + nu + 1; d = cc + 1
            F += [(a, b, d), (a, d, cc)]
    m.add(V, N, UV, F)
    return xform(m, c, R)

def tube(c, r0, r1, h, n=20, R=None, caps=True):
    """tapered cylinder along +Y from c (radius r0) to c+h (radius r1)"""
    m = M(); V, N, UV, F = [], [], [], []
    sl = (r0 - r1) / h
    for j, (y, r) in enumerate(((0, r0), (h, r1))):
        for i in range(n + 1):
            a = 2 * np.pi * i / n; d = np.array([np.cos(a), 0, np.sin(a)])
            nn = d + np.array([0, sl, 0]); nn /= np.linalg.norm(nn)
            V.append(d * r + np.array([0, y, 0])); N.append(nn); UV.append((i / n, j))
    for i in range(n):
        F += [(i, i + 1, i + n + 2), (i, i + n + 2, i + n + 1)]
    m.add(V, N, UV, F)
    if caps:
        for y, r, s in ((0, r0, -1), (h, r1, 1)):
            if r <= 1e-4: continue
            V2 = [np.array([0, y, 0])] + [np.array([np.cos(2 * np.pi * i / n) * r, y, np.sin(2 * np.pi * i / n) * r]) for i in range(n)]
            F2 = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
            m.add(V2, [np.array([0, s, 0])] * len(V2), [(0.5, 0.5)] * len(V2), F2)
    return xform(m, c, R)

def slab(poly, z0, z1, bevel=0.0):
    """extrude a convex/star-shaped 2D polygon (XY) between z0..z1 with a chamfered rim"""
    P = np.array(poly, float); n = len(P); m = M()
    cen = P.mean(0)
    inner = cen + (P - cen) * (1 - bevel) if bevel > 0 else P
    for z, s, Q in ((z1, 1, inner), (z0, -1, inner)):
        V = [np.array([cen[0], cen[1], z])] + [np.array([q[0], q[1], z]) for q in Q]
        F = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
        m.add(V, [np.array([0, 0, s])] * len(V), [(0.5, 0.5)] * len(V), F)
    zm0, zm1 = z0 + (z1 - z0) * 0.3, z1 - (z1 - z0) * 0.3
    rings = [(inner, z0), (P, zm0), (P, zm1), (inner, z1)] if bevel > 0 else [(P, z0), (P, z1)]
    for k in range(len(rings) - 1):
        (A, za), (B, zb) = rings[k], rings[k + 1]
        for i in range(n):
            j = (i + 1) % n
            a0, a1 = np.array([*A[i], za]), np.array([*A[j], za]); b0, b1 = np.array([*B[i], zb]), np.array([*B[j], zb])
            fn = np.cross(a1 - a0, b0 - a0); ln = np.linalg.norm(fn)
            if ln < 1e-9: continue
            fn /= ln
            out = np.array([*(P[i] + P[j]) / 2 - cen, 0])
            if np.dot(fn, out) < 0: fn = -fn
            m.add([a0, a1, b1, b0], [fn] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 1, 2), (0, 2, 3)])
    return m

def torus(R0, r, nu=40, nv=10, c=(0, 0, 0), Rm=None):
    m = M(); V, N, UV, F = [], [], [], []
    for j in range(nv + 1):
        b = 2 * np.pi * j / nv
        for i in range(nu + 1):
            a = 2 * np.pi * i / nu
            d = np.array([np.cos(a), np.sin(a), 0])
            n = d * np.cos(b) + np.array([0, 0, np.sin(b)])
            V.append(d * R0 + n * r); N.append(n); UV.append((i / nu, j / nv))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i; b2 = a + 1; cc = a + nu + 1; d = cc + 1
            F += [(a, b2, d), (a, d, cc)]
    m.add(V, N, UV, F); return xform(m, c, Rm)

def save(name, m):
    V, N = np.array(m.V), np.array(m.N)
    with open(os.path.join(OUT, name + '.obj'), 'w') as fo:
        fo.write(f'o {name}\n')
        for p in V: fo.write('v %.5f %.5f %.5f\n' % tuple(p))
        for t in m.UV: fo.write('vt %.5f %.5f\n' % tuple(t))
        for n in N: fo.write('vn %.5f %.5f %.5f\n' % tuple(n))
        for a, b, c in m.F:
            fn = np.cross(V[b] - V[a], V[c] - V[a])
            if np.linalg.norm(fn) < 1e-6: continue          # degenerate (pole) triangles make assimp split off a line mesh
            if np.dot(fn, N[a] + N[b] + N[c]) < 0: b, c = c, b
            fo.write(f'f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n')
    print(name, len(V), 'verts', len(m.F), 'tris')

def both(part_fn):
    """part built on the +X side, mirrored to -X"""
    m = part_fn(); o = M(); o += m; o += xform(m, mirror_x=True); return o

PI = np.pi
def U(*ms):
    o = M()
    for m in ms: o += m
    return o


def renormal(m):
    V = np.array(m.V, float); N = np.zeros_like(V)
    for a, b, c in m.F:
        fn = np.cross(V[b] - V[a], V[c] - V[a]); N[a] += fn; N[b] += fn; N[c] += fn
    L = np.linalg.norm(N, axis=1, keepdims=True); L[L < 1e-12] = 1; m.N = list(N / L); return m

def superq(c, r, e=0.25, nu=28, nv=18, R=None, noise=0.0, seed=0, flat_back=None):
    """superellipsoid (e small = boxy, 1 = sphere); optional lumpy noise; smooth normals recomputed"""
    rng = np.random.default_rng(seed); m = M(); V, UV, F = [], [], []
    def sp(x, p): return np.sign(x) * np.abs(x) ** p
    ph = rng.uniform(0, 6.28, 6)
    for j in range(nv + 1):
        th = -np.pi / 2 + np.pi * j / nv
        for i in range(nu + 1):
            a = -np.pi + 2 * np.pi * i / nu
            p = np.array([sp(np.cos(th), e) * sp(np.cos(a), e), sp(np.sin(th), e), sp(np.cos(th), e) * sp(np.sin(a), e)]) * np.array(r, float)
            if noise:
                d = p / (np.linalg.norm(p) + 1e-9)
                k = (np.sin(d[0] * 5 + ph[0]) * np.sin(d[1] * 4 + ph[1]) + 0.6 * np.sin(d[2] * 6 + ph[2] + d[0] * 3) + 0.4 * np.sin(d[1] * 9 + ph[3] + d[2] * 7))
                p = p * (1 + noise * k)
            if flat_back is not None and p[2] < flat_back: p[2] = flat_back
            V.append(p); UV.append((i / nu, j / nv))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i; b = a + 1; cc = a + nu + 1; d = cc + 1
            F += [(a, b, d), (a, d, cc)]
    m.add(V, [np.zeros(3)] * len(V), UV, F); renormal(m)
    # weld seam normals: average normals of coincident verts
    Vn = np.round(np.array(m.V), 4); keys = {}
    for i, v in enumerate(map(tuple, Vn)): keys.setdefault(v, []).append(i)
    N = np.array(m.N)
    for ids in keys.values():
        if len(ids) > 1: n = N[ids].sum(0); n /= (np.linalg.norm(n) + 1e-9); N[ids] = n
    m.N = list(N)
    V = np.array(m.V); ctr = V.mean(0)
    if np.sum(np.einsum('ij,ij->i', N, V - ctr)) < 0: m.N = list(-N)
    return xform(m, c, R)

def roundbox(half=(0.5, 0.5, 0.5), rad=0.14, n=8, noise=0.0, seed=0):
    """rounded box from a subdivided cube (uniform, non-degenerate triangles), optional lumpy noise"""
    rng = np.random.default_rng(seed); ph = rng.uniform(0, 6.28, 4)
    h = np.array(half, float); inner = h - rad
    m = M()
    for ax in range(3):
        for sgn_ in (-1, 1):
            V, N, UV, F = [], [], [], []
            u_ax, v_ax = [a for a in range(3) if a != ax]
            for j in range(n + 1):
                for i in range(n + 1):
                    p = np.zeros(3); p[ax] = sgn_ * h[ax]
                    p[u_ax] = (-1 + 2 * i / n) * h[u_ax]; p[v_ax] = (-1 + 2 * j / n) * h[v_ax]
                    q = np.clip(p, -inner, inner); d = p - q; d /= (np.linalg.norm(d) + 1e-12)
                    pos = q + d * rad
                    if noise: pos = pos + d * noise * (np.sin(pos[0] * 7 + ph[0]) * np.sin(pos[1] * 6 + ph[1]) + 0.5 * np.sin(pos[2] * 9 + ph[2] + pos[0] * 4))
                    V.append(pos); N.append(d); UV.append((i / n, j / n))
            for j in range(n):
                for i in range(n):
                    a = j * (n + 1) + i; F += [(a, a + 1, a + n + 2), (a, a + n + 2, a + n + 1)]
            m.add(V, N, UV, F)
    return renormal(m)
