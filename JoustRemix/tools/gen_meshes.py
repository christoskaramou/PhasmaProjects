# Procedural meshes for Joust Remix -> meshsrc/*.obj (cooked to .pemesh by cook_all.sh)
# Conventions: playfield is the XY plane, camera looks down -Z, riders face +X, thickness along Z.
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
            if np.linalg.norm(fn) < 1e-7: continue  # drop degenerate tris (PhasmaCook splits on them)
            if np.dot(fn, N[a] + N[b] + N[c]) < 0: b, c = c, b
            fo.write(f'f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n')
    print(name, len(V), 'verts', len(m.F), 'tris')

def both(part_fn):
    m = part_fn(); o = M(); o += m; o += xform(m, mirror_x=True); return o
PI = np.pi
def U(*ms):
    o = M()
    for m in ms: o += m
    return o
def box(c, s):
    hx, hy, hz = np.array(s) / 2
    return slab([(c[0]-hx, c[1]-hy), (c[0]+hx, c[1]-hy), (c[0]+hx, c[1]+hy), (c[0]-hx, c[1]+hy)], c[2]-hz, c[2]+hz, 0.0)
def bbox(c, s, b=0.15):
    hx, hy, hz = np.array(s) / 2
    return slab([(c[0]-hx, c[1]-hy), (c[0]+hx, c[1]-hy), (c[0]+hx, c[1]+hy), (c[0]-hx, c[1]+hy)], c[2]-hz, c[2]+hz, b)
RX = rotm(rz=-PI / 2)   # tube along +Y -> along +X

RZ = lambda a: rotm(rz=a)
def seg(p0, p1, r0, r1, n=14):
    """tapered tube from p0 to p1"""
    p0, p1 = np.array(p0, float), np.array(p1, float); d = p1 - p0; L = np.linalg.norm(d); d /= L
    y = np.array([0, 1.0, 0]); v = np.cross(y, d); s = np.linalg.norm(v); c = np.dot(y, d)
    if s < 1e-8: R = np.eye(3) if c > 0 else rotm(rx=PI)
    else:
        k = v / s; K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]]); R = np.eye(3) + s * K + (1 - c) * K @ K
    return tube(p0, r0, r1, L, n=n, R=R)
def ball(c, r, nu=14, nv=9): return ellipsoid(c, (r, r, r), nu, nv)

# ---------------- mounts (face +X, feet at y=-1.0, ~2.6 tall)
def bird(kind):
    buzz = kind == 'buzzard'
    body = U(ellipsoid((0, 0.55, 0), (0.95, 0.58, 0.55) if not buzz else (1.0, 0.5, 0.52), 28, 16))
    if not buzz:   # ostrich: tall S-neck, round head, flat beak, plume tail
        pts = [(0.7, 0.85), (0.95, 1.35), (0.95, 1.85), (1.1, 2.2)]
        for a, b in zip(pts[:-1], pts[1:]): body += seg((*a, 0), (*b, 0), 0.2, 0.17)
        for p in pts[1:-1]: body += ball((*p, 0), 0.18)
        body += ellipsoid((1.18, 2.25, 0), (0.3, 0.22, 0.2), 16, 10)
        beak = U(xform(ellipsoid((0, 0, 0), (0.32, 0.07, 0.11), 14, 8), (1.5, 2.2, 0)))
        tail = U(*[xform(ellipsoid((0, 0, 0), (0.55, 0.12, 0.06), 14, 8), (-1.05, 0.95 + 0.12 * i, 0.12 * i), rotm(rz=0.5 + 0.18 * i)) for i in (-1, 0, 1)])
        eye = U(ball((1.27, 2.33, 0.17), 0.055, 10, 6), ball((1.27, 2.33, -0.17), 0.055, 10, 6))
    else:          # buzzard: hunched, low snaking neck, hooked beak, ragged tail, ruff
        pts = [(0.75, 0.75), (1.1, 1.15), (1.35, 1.4)]
        for a, b in zip(pts[:-1], pts[1:]): body += seg((*a, 0), (*b, 0), 0.19, 0.14)
        body += ball((1.1, 1.15, 0), 0.16)
        body += ellipsoid((1.5, 1.45, 0), (0.3, 0.2, 0.19), 16, 10)
        body += torus(0.28, 0.12, 24, 8, c=(0.75, 0.8, 0), Rm=rotm(ry=PI / 2) @ rotm(rx=0) @ rotm(rz=0.6))
        beak = U(xform(ellipsoid((0, 0, 0), (0.3, 0.1, 0.09), 14, 8), (1.82, 1.4, 0), rotm(rz=-0.35)), xform(tube((0, 0, 0), 0.07, 0.0, 0.22, n=8), (2.05, 1.32, 0), rotm(rz=PI * 0.85)))
        tail = U(*[xform(slab([(0, -0.1), (0.9, -0.05), (0.95, 0.06), (0, 0.1)], -0.04, 0.04, 0.15), (-0.8, 0.75, 0.1 * i), rotm(rz=PI + 0.25 + 0.15 * i)) for i in (-1, 0, 1)])
        eye = U(ball((1.62, 1.52, 0.16), 0.05, 10, 6), ball((1.62, 1.52, -0.16), 0.05, 10, 6))
    return body, beak, tail, eye

def leg(buzz):
    # pivot at hip (0,0,0); leg hangs to y=-1.25; toes forward
    k = (0.18, -0.6) if not buzz else (-0.15, -0.55)
    return U(seg((0, 0, 0), (*k, 0), 0.11, 0.07, 10), ball((*k, 0), 0.08, 10, 6), seg((*k, 0), (0.05, -1.2, 0), 0.06, 0.05, 10),
             *[seg((0.05, -1.2, 0), (0.05 + 0.32 * np.cos(a), -1.25, 0.32 * np.sin(a)), 0.045, 0.025, 6) for a in (-0.6, 0, 0.6)],
             seg((0.05, -1.2, 0), (-0.15, -1.24, 0), 0.04, 0.02, 6))

def wing(side, buzz):
    # pivot at shoulder; lies in XZ plane extending toward +z*side and back (-x); flap = rotate about X
    o = M()
    n = 6 if not buzz else 7
    for i in range(n):
        t = i / (n - 1)
        L = (1.25 if not buzz else 1.45) * (1.0 - 0.35 * abs(t - 0.35))
        a = -0.25 - 1.15 * t   # fan angle (radians) from +z toward -x
        dirv = np.array([np.sin(a) * 0.9, 0.0, np.cos(a) * side])
        p1 = dirv * L
        f = ellipsoid((0, 0, 0), (0.07 if not buzz else 0.055, 0.035, L * 0.55), 10, 8)
        yaw = np.arctan2(dirv[0], dirv[2])
        o += xform(f, p1 * 0.5, rotm(ry=yaw))
    o += ellipsoid((0, 0, 0.35 * side), (0.25, 0.09, 0.42), 14, 8)
    return o

# ---------------- knight (rides at saddle; origin = mount origin)
def knight():
    armor = U(ellipsoid((-0.1, 1.45, 0), (0.32, 0.42, 0.3), 18, 12),            # torso
              ball((-0.08, 2.05, 0), 0.25, 18, 12),                             # helmet
              ellipsoid((-0.1, 1.72, 0.3), (0.16, 0.12, 0.14), 12, 8), ellipsoid((-0.1, 1.72, -0.3), (0.16, 0.12, 0.14), 12, 8),
              seg((-0.05, 1.65, -0.32), (0.25, 1.35, -0.38), 0.08, 0.07, 10), seg((0.25, 1.35, -0.38), (0.5, 1.45, -0.3), 0.07, 0.06, 10),
              seg((-0.1, 1.1, 0.25), (0.2, 0.85, 0.5), 0.1, 0.08, 10), seg((-0.1, 1.1, -0.25), (0.2, 0.85, -0.5), 0.1, 0.08, 10))
    trim = U(xform(torus(0.25, 0.035, 28, 6), (-0.08, 2.03, 0), rotm(rx=PI / 2)),     # visor band
             xform(slab([(0, 0.4), (0.3, 0.25), (0.3, -0.25), (0, -0.45), (-0.3, -0.25), (-0.3, 0.25)], -0.05, 0.05, 0.2), (-0.15, 1.4, 0.42), rotm(ry=0.15)),   # shield
             ellipsoid((-0.1, 1.15, 0), (0.34, 0.08, 0.32), 16, 6))           # belt
    plume = U(*[seg((-0.1, 2.25, 0), (-0.1 - 0.5 * np.cos(a), 2.35 + 0.35 * np.sin(a), 0), 0.07, 0.02, 8) for a in (0.6, 0.9, 1.2)], ball((-0.1, 2.27, 0), 0.07))
    lance = U(seg((0.3, 1.38, -0.32), (3.0, 1.62, -0.32), 0.05, 0.04, 10), seg((0.15, 1.37, -0.32), (0.45, 1.39, -0.32), 0.13, 0.05, 12))
    tip = U(seg((3.0, 1.62, -0.32), (3.45, 1.66, -0.32), 0.06, 0.0, 10))
    return dict(armor=armor, trim=trim, plume=plume, lance=lance, tip=tip)

for kind in ('ostrich', 'buzzard'):
    body, beak, tail, eye = bird(kind); buzz = kind == 'buzzard'
    save(f'{kind}_body', U(body, tail)); save(f'{kind}_beak', U(beak, eye))
    save(f'{kind}_leg', leg(buzz)); save(f'{kind}_wingl', wing(1, buzz)); save(f'{kind}_wingr', wing(-1, buzz))
for part, m in knight().items(): save(f'knight_{part}', m)
