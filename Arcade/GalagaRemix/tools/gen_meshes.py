# Procedural meshes for Galaga Remix -> meshsrc/*.obj (cooked to .pemesh by cook_all.sh)
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

# ------------------------------------------------------------------ player fighter (white/red Galaga fighter)
def fighter():
    body = U(ellipsoid((0, 0.05, 0), (0.36, 1.2, 0.36)),
             tube((0, 1.05, 0), 0.2, 0.025, 0.75, R=None),
             both(lambda: slab([(0.22, 0.45), (1.25, -0.45), (1.3, -0.85), (0.28, -0.7)], -0.07, 0.07, 0.12)),
             both(lambda: slab([(0.18, -0.55), (0.55, -1.05), (0.5, -1.25), (0.15, -1.05)], -0.05, 0.05, 0.1)))
    metal = U(both(lambda: tube((0.55, -1.15, -0.02), 0.2, 0.15, 0.95)),
              both(lambda: tube((0.55, -0.2, -0.02), 0.15, 0.04, 0.35, caps=False)),
              both(lambda: ellipsoid((0.95, -0.1, 0.0), (0.06, 0.55, 0.06))))      # wing cannons
    accent = U(both(lambda: slab([(1.18, -0.15), (1.42, -0.3), (1.45, -1.15), (1.2, -1.0)], -0.16, 0.16, 0.15)),
               both(lambda: slab([(0.45, 0.12), (1.0, -0.4), (1.0, -0.55), (0.45, -0.1)], 0.07, 0.11, 0.0)),
               xform(slab([(0.0, -0.3), (0.0, -1.2), (0.55, -1.25), (0.5, -0.9)], -0.05, 0.05, 0.1), (0, 0, 0), rotm(ry=-PI / 2)),
               ellipsoid((0, 1.0, 0), (0.205, 0.1, 0.205)))
    glass = ellipsoid((0, 0.42, 0.22), (0.19, 0.48, 0.2))
    glow = U(both(lambda: ellipsoid((0.55, -1.17, -0.02), (0.15, 0.05, 0.15))), ellipsoid((0, -1.15, 0), (0.12, 0.05, 0.12)))
    return dict(body=body, metal=metal, accent=accent, glass=glass, glow=glow)

# ------------------------------------------------------------------ Zako (bee): yellow segmented body, blue stripes, glassy wings
def bee():
    def ring(y, rx, rz, w=0.065):
        t = torus(1.0, w / rx * 1.0, 36, 8, Rm=rotm(rx=PI / 2)); V = np.array(t.V); V[:, 0] *= rx; V[:, 2] *= rz; V[:, 1] *= 1.0
        t.V = list(V + np.array([0, y, 0])); return t
    body = U(ellipsoid((0, 0.72, 0), (0.4, 0.36, 0.34)), ellipsoid((0, 0.15, 0), (0.34, 0.36, 0.3)),
             ellipsoid((0, -0.6, 0), (0.46, 0.66, 0.4)))
    accent = U(ring(-0.35, 0.43, 0.38), ring(-0.68, 0.4, 0.34), ring(-0.98, 0.28, 0.24),
               both(lambda: tube((0.14, 0.98, 0.1), 0.035, 0.02, 0.55, R=rotm(rz=-0.5))),
               both(lambda: ellipsoid((0.43, 1.42, 0.1), (0.08, 0.08, 0.08))),
               tube((0, -1.55, 0), 0.0, 0.11, 0.35),
               both(lambda: tube((0.3, 0.1, -0.05), 0.04, 0.03, 0.45, R=rotm(rz=-2.2))),   # legs
               both(lambda: tube((0.28, -0.15, -0.05), 0.04, 0.03, 0.45, R=rotm(rz=-2.6))))
    eye = both(lambda: ellipsoid((0.2, 0.86, 0.2), (0.13, 0.14, 0.11)))
    wing = U(ellipsoid((0.82, 0.38, 0.12), (0.72, 0.26, 0.035), R=rotm(rz=0.42)),
             ellipsoid((0.7, -0.05, 0.1), (0.55, 0.2, 0.03), R=rotm(rz=-0.2)))
    return dict(body=body, accent=accent, eye=eye, wing=wing)

# ------------------------------------------------------------------ Goei (butterfly): red body, big blue/white wings
def butterfly():
    body = U(ellipsoid((0, 0.72, 0), (0.3, 0.3, 0.28)), ellipsoid((0, -0.15, 0), (0.27, 0.78, 0.26)))
    accent = U(*[torus(1.0, 0.25, 30, 6, c=(0, y, 0), Rm=rotm(rx=PI / 2)) for y in ()],
               both(lambda: tube((0.1, 0.92, 0.08), 0.03, 0.02, 0.6, R=rotm(rz=-0.35))),
               both(lambda: ellipsoid((0.31, 1.47, 0.08), (0.07, 0.07, 0.07))),
               ellipsoid((0, -0.3, 0.2), (0.11, 0.5, 0.1)), ellipsoid((0, -0.9, 0.0), (0.12, 0.2, 0.12)))
    eye = both(lambda: ellipsoid((0.15, 0.84, 0.17), (0.1, 0.11, 0.09)))
    wing = U(slab([(0.15, 0.3), (0.85, 1.05), (1.45, 1.0), (1.55, 0.35), (1.0, -0.15), (0.2, -0.05)], -0.035, 0.035, 0.12),
             slab([(0.2, -0.15), (0.95, -0.25), (1.2, -0.75), (0.85, -1.15), (0.25, -0.65)], -0.03, 0.03, 0.12))
    wingtrim = U(ellipsoid((1.05, 0.62, 0.05), (0.26, 0.2, 0.025)), ellipsoid((0.8, -0.6, 0.045), (0.18, 0.15, 0.02)))
    return dict(body=body, accent=accent, eye=eye, wing=wing, wingtrim=wingtrim)

# ------------------------------------------------------------------ Boss Galaga: armoured green body, golden mandibles, violet wings
def boss():
    body = U(ellipsoid((0, 0.62, 0), (0.62, 0.52, 0.5)), ellipsoid((0, -0.2, 0), (0.58, 0.55, 0.46)),
             ellipsoid((0, -0.95, 0), (0.42, 0.45, 0.36)),
             both(lambda: ellipsoid((0.45, 0.1, 0.0), (0.3, 0.42, 0.3))))
    accent = U(both(lambda: tube((0.28, 1.0, 0.1), 0.12, 0.03, 0.75, R=rotm(rz=0.45))),     # mandibles
               both(lambda: tube((0.5, 0.85, 0.05), 0.09, 0.02, 0.6, R=rotm(rz=-0.6))),     # horns
               ellipsoid((0, 0.72, 0.38), (0.28, 0.18, 0.12)),                               # crest
               torus(1.0, 0.06, 40, 8, c=(0, -0.2, 0), Rm=rotm(rx=PI / 2)) if False else ellipsoid((0, -0.25, 0.4), (0.4, 0.1, 0.08)),
               ellipsoid((0, -0.6, 0.33), (0.3, 0.08, 0.07)),
               both(lambda: tube((0.35, -0.3, -0.05), 0.05, 0.03, 0.6, R=rotm(rz=-2.3))))
    eye = both(lambda: ellipsoid((0.27, 0.72, 0.3), (0.16, 0.13, 0.12)))
    wing = U(slab([(0.4, 0.4), (1.3, 0.95), (1.75, 0.55), (1.6, -0.2), (0.5, -0.25)], -0.04, 0.04, 0.12),
             slab([(0.45, -0.3), (1.35, -0.45), (1.4, -1.05), (0.6, -0.9)], -0.035, 0.035, 0.12))
    return dict(body=body, accent=accent, eye=eye, wing=wing)

for kind, fn in (('fighter', fighter), ('bee', bee), ('bfly', butterfly), ('boss', boss)):
    for part, m in fn().items():
        if part == 'wing' or part == 'wingtrim':
            save(f'{kind}_{part}', m)                        # +X wing; the game mirrors via a second mesh
            save(f'{kind}_{part}R', xform(m, mirror_x=True))
        else:
            save(f'{kind}_{part}', m)

# ------------------------------------------------------------------ props
save('bolt', U(ellipsoid((0, 0, 0), (0.08, 0.6, 0.08), 12, 10)))
save('ebolt', U(ellipsoid((0, 0, 0), (0.17, 0.34, 0.17), 14, 10), ellipsoid((0, 0, 0), (0.3, 0.1, 0.1), 10, 6)))
save('orb', ellipsoid((0, 0, 0), (0.5, 0.5, 0.5), 20, 12))
save('star', ellipsoid((0, 0, 0), (0.5, 0.5, 0.5), 8, 5))
save('shard', slab([(0, 0.5), (-0.4, -0.3), (0.45, -0.25)], -0.08, 0.08, 0.2))
save('ring', torus(1.0, 0.045, 64, 8))
def slats(n, r0, r1, w):
    """cone lattice of thin glowing ribbons from y=-1 (radius r0) to y=0 (radius r1): reads as a translucent beam"""
    m = M()
    for i in range(n):
        a = 2 * PI * i / n; d = np.array([np.cos(a), 0, np.sin(a)]); t = np.array([-np.sin(a), 0, np.cos(a)])
        p0, p1 = d * r0 + np.array([0, -1, 0]), d * r1
        V = [p0 - t * w, p0 + t * w, p1 + t * w * 0.3, p1 - t * w * 0.3]
        m.add(V, [d] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 1, 2), (0, 2, 3)])
    return m
save('beam', slats(28, 1.0, 0.18, 0.035))
save('beam2', slats(14, 0.6, 0.12, 0.05))
save('beamring', torus(1.0, 0.04, 56, 6, Rm=rotm(rx=PI / 2)))
save('planet', ellipsoid((0, 0, 0), (1, 1, 1), 64, 40))
def annulus(r0, r1, n=128, rings=6):
    m = M(); V, N, UV, F = [], [], [], []
    for j in range(rings + 1):
        r = r0 + (r1 - r0) * j / rings
        for i in range(n + 1):
            a = 2 * PI * i / n; V.append(np.array([np.cos(a) * r, 0, np.sin(a) * r])); N.append(np.array([0, 1, 0])); UV.append((i / n, j / rings))
    for j in range(rings):
        for i in range(n):
            a = j * (n + 1) + i; F += [(a, a + 1, a + n + 2), (a, a + n + 2, a + n + 1)]
    return m.add(V, N, UV, F)
save('planetring', annulus(1.35, 2.3))
# stage badge: pole + pennant + inner stripe
save('badge_pole', U(tube((0, -0.9, 0), 0.04, 0.04, 1.8), ellipsoid((0, 0.92, 0), (0.08, 0.08, 0.08))))
save('badge_flag', slab([(0.04, 0.85), (0.75, 0.55), (0.04, 0.2)], -0.05, 0.05, 0.08))
save('badge_stripe', slab([(0.1, 0.62), (0.45, 0.53), (0.1, 0.43)], 0.05, 0.08, 0.0))
