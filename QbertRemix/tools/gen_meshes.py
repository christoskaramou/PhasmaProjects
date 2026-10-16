# Procedural meshes for Q*bert Remix -> meshsrc/*.obj (cooked to .pemesh by cook_all.sh)
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
            if np.linalg.norm(fn) < 1e-9: continue          # degenerate (pole) triangles make assimp split off a line mesh
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

# ================= Q*bert Remix meshes. World: Y up. Characters face +Z, origin at their feet.
def rsquare(h, r, seg=5):
    P = []
    for k, (cx, cy) in enumerate(((h - r, h - r), (-h + r, h - r), (-h + r, -h + r), (h - r, -h + r))):
        for i in range(seg + 1):
            a = PI / 2 * k + PI / 2 * i / seg; P.append((cx + r * np.cos(a), cy + r * np.sin(a)))
    return P
RX = rotm(rx=-PI / 2)          # slab Z -> world Y
def box(h, y0, y1, r, bevel):
    return xform(slab(rsquare(h, r), y0, y1, bevel), R=RX)
save('cube_body', box(0.5, -0.5, 0.47, 0.07, 0.05))
save('cube_top', box(0.43, 0.46, 0.52, 0.1, 0.18))
save('cube_rim', xform(slab(rsquare(0.5, 0.07), 0.44, 0.475, 0.0), R=RX))
# Q*bert
def qbert():
    body = ellipsoid((0, 0.5, 0), (0.33, 0.31, 0.33), 32, 20)
    Rs = rotm(rx=PI / 2 - 0.35)
    snout = tube((0, 0.0, 0), 0.105, 0.15, 0.36, 24, R=Rs, caps=False)
    snout = xform(snout, c=(0, 0.42, 0.18))
    tip = ellipsoid((0, 0, 0), (0.155, 0.155, 0.06), 24, 10)
    tip = xform(tip, R=rotm(rx=-0.35), c=(0, 0.42 - 0.36 * np.sin(0.35) * 0 , 0))
    d = np.array([0, -np.sin(0.35), np.cos(0.35)]) * 0.36 + np.array([0, 0.42, 0.18])
    tip = xform(ellipsoid((0, 0, 0), (0.155, 0.155, 0.05), 24, 10), c=tuple(d), R=rotm(rx=-0.35))
    nost = xform(ellipsoid((0, 0, 0), (0.1, 0.1, 0.03), 20, 8), c=tuple(d + np.array([0, -0.02, 0.035])), R=rotm(rx=-0.35))
    eyes = U(ellipsoid((0.13, 0.66, 0.2), (0.105, 0.125, 0.09), 20, 12), ellipsoid((-0.13, 0.66, 0.2), (0.105, 0.125, 0.09), 20, 12))
    pup = U(ellipsoid((0.14, 0.655, 0.285), (0.045, 0.055, 0.03), 14, 8), ellipsoid((-0.14, 0.655, 0.285), (0.045, 0.055, 0.03), 14, 8))
    legs, feet = M(), M()
    for sx in (1, -1):
        legs += tube((0.13 * sx, 0.05, 0), 0.045, 0.05, 0.25, 12)
        feet += ellipsoid((0.14 * sx, 0.05, 0.07), (0.1, 0.055, 0.16), 18, 10)
    save('qb_body', U(body, snout, tip)); save('qb_eye', eyes); save('qb_dark', U(pup, nost)); save('qb_feet', U(legs, feet))
qbert()
save('ball', ellipsoid((0, 0.3, 0), (0.3, 0.3, 0.3), 32, 20))
save('ball_small', ellipsoid((0, 0.2, 0), (0.2, 0.2, 0.2), 28, 16))
# Coily: helix spring + head
def helix(r0, rt, turns, h, n=220, m=10):
    o = M(); V, N, UV, F = [], [], [], []
    for j in range(n + 1):
        t_ = j / n; a = 2 * PI * turns * t_
        c = np.array([r0 * np.cos(a), h * t_, r0 * np.sin(a)])
        T = np.array([-r0 * np.sin(a) * 2 * PI * turns, h, r0 * np.cos(a) * 2 * PI * turns]); T /= np.linalg.norm(T)
        Nn = np.array([np.cos(a), 0, np.sin(a)]); B = np.cross(T, Nn)
        for i in range(m + 1):
            b = 2 * PI * i / m; d = Nn * np.cos(b) + B * np.sin(b)
            V.append(c + d * rt); N.append(d); UV.append((t_, i / m))
    for j in range(n):
        for i in range(m):
            a = j * (m + 1) + i; F += [(a, a + 1, a + m + 2), (a, a + m + 2, a + m + 1)]
    o.add(V, N, UV, F); return o
save('coily_spring', xform(helix(0.17, 0.06, 4.5, 0.55), c=(0, 0.04, 0)))
head = U(ellipsoid((0, 0.82, 0), (0.25, 0.26, 0.25), 28, 18), ellipsoid((0, 0.74, 0.17), (0.17, 0.09, 0.15), 20, 10))
save('coily_head', head)
save('coily_eye', U(ellipsoid((0.1, 0.94, 0.17), (0.08, 0.1, 0.07), 16, 10), ellipsoid((-0.1, 0.94, 0.17), (0.08, 0.1, 0.07), 16, 10)))
save('coily_dark', U(ellipsoid((0.105, 0.94, 0.235), (0.035, 0.05, 0.02), 12, 8), ellipsoid((-0.105, 0.94, 0.235), (0.035, 0.05, 0.02), 12, 8),
                     ellipsoid((0, 0.715, 0.3), (0.11, 0.025, 0.03), 16, 8)))
save('egg', ellipsoid((0, 0.32, 0), (0.27, 0.32, 0.27), 32, 20))
# Slick / Sam: little gremlin + shades
save('sam_body', U(ellipsoid((0, 0.3, 0), (0.22, 0.26, 0.2), 24, 14), ellipsoid((0.1, 0.05, 0.05), (0.07, 0.05, 0.11), 12, 8), ellipsoid((-0.1, 0.05, 0.05), (0.07, 0.05, 0.11), 12, 8)))
save('sam_shades', U(ellipsoid((0.08, 0.38, 0.17), (0.075, 0.05, 0.04), 14, 8), ellipsoid((-0.08, 0.38, 0.17), (0.075, 0.05, 0.04), 14, 8), tube((0, 0.38, 0.19), 0.012, 0.012, 0.1, 6, R=rotm(rz=PI / 2), caps=False)))
# escape disc (flat, Y up)
save('disc_ring', torus(0.36, 0.06, 48, 12, Rm=rotm(rx=PI / 2)))
save('disc_core', xform(slab([(0.33 * np.cos(a), 0.33 * np.sin(a)) for a in np.linspace(0, 2 * PI, 48, endpoint=False)], -0.03, 0.03, 0.4), R=RX))
save('shock', torus(1.0, 0.035, 64, 8, Rm=rotm(rx=PI / 2)))
save('shard', xform(slab([(0.12, 0), (-0.06, 0.1), (-0.06, -0.1)], -0.03, 0.03, 0.2), R=RX))
save('star', ellipsoid((0, 0, 0), (0.5, 0.5, 0.5), 10, 6))
