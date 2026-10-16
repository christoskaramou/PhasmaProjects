# Procedural meshes for Robotron Remix -> meshsrc/*.obj (cooked to .pemesh by cook_all.sh)
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
# ------------------------------------------------------------------ Robotron Remix meshes
# Top-down arena: XY is the floor plane, +Z points up to the camera. Characters face +Y.
def box(c, s, R=None):
    """axis box centred at c with half sizes s (flat normals)"""
    m = M(); c = np.array(c, float); s = np.array(s, float)
    for ax in range(3):
        for sg in (-1, 1):
            n = np.zeros(3); n[ax] = sg
            u = np.zeros(3); u[(ax + 1) % 3] = 1; v = np.zeros(3); v[(ax + 2) % 3] = 1
            P = [n * s + (a * u + b * v) * s for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            m.add(P, [n] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 1, 2), (0, 2, 3)])
    return xform(m, c, R)
def bbox(c, s, b=0.2):
    """rounded-looking box: core box + slightly smaller ellipsoid edges"""
    return U(box(c, (s[0] - b * s[0], s[1], s[2] - b * s[2])), box(c, (s[0], s[1] - b * s[1], s[2] - b * s[2])),
             box(c, (s[0] - b * s[0], s[1] - b * s[1], s[2])))
def capsule_z(c, r, h, n=16):
    return U(tube(c, r, r, h, n, R=rotm(rx=PI / 2), caps=False), ellipsoid(c, (r, r, r), n, 8),
             ellipsoid((c[0], c[1], c[2] + h), (r, r, r), n, 8))
Z = lambda x, y, z: (x, y, z)
# hero: armoured suit, glowing visor, twin-barrel blaster
def hero():
    body = U(ellipsoid((0, 0, 1.0), (0.42, 0.3, 0.55)),                         # torso
             ellipsoid((0, 0, 1.75), (0.27, 0.27, 0.28)),                       # helmet
             both(lambda: capsule_z((0.18, 0, 0.12), 0.11, 0.45)),              # legs
             both(lambda: ellipsoid((0.5, 0.05, 1.15), (0.14, 0.14, 0.35))))     # arms
    metal = U(both(lambda: ellipsoid((0.4, 0, 1.38), (0.2, 0.2, 0.14))),        # shoulder pads
              ellipsoid((0, -0.28, 1.05), (0.26, 0.12, 0.3)),                    # backpack
              both(lambda: box((0.18, 0.04, 0.08), (0.12, 0.17, 0.07))),         # boots
              tube((0.3, 0.1, 1.0), 0.09, 0.08, 0.72, 14))                       # blaster barrel (along +Y)
    glow = U(ellipsoid((0, 0.17, 1.78), (0.19, 0.12, 0.08)),                    # visor
             ellipsoid((0, 0.27, 1.0), (0.1, 0.05, 0.1)),                        # chest core
             ellipsoid((0.3, 0.84, 1.0), (0.07, 0.05, 0.07)),                    # muzzle
             both(lambda: ellipsoid((0.12, -0.38, 1.0), (0.05, 0.04, 0.16))))    # jet vents
    return dict(body=body, metal=metal, glow=glow)
# grunt: squat red robot, yellow chest plate, cyclops eye, claws
def grunt():
    body = U(bbox((0, 0, 0.95), (0.48, 0.36, 0.42)), bbox((0, 0, 1.55), (0.3, 0.28, 0.2)),
             both(lambda: box((0.22, 0, 0.3), (0.12, 0.14, 0.3))),
             both(lambda: box((0.62, 0.05, 1.0), (0.1, 0.12, 0.32))))
    accent = U(box((0, 0.36, 0.95), (0.3, 0.03, 0.22)), both(lambda: box((0.62, 0.15, 0.62), (0.13, 0.13, 0.08))),
               tube((0, 0, 1.7), 0.03, 0.02, 0.4, 8, R=rotm(rx=PI / 2)), box((0, 0, 0.05), (0.42, 0.22, 0.05)))
    eye = U(ellipsoid((0, 0.28, 1.58), (0.18, 0.06, 0.07)), ellipsoid((0, 0, 2.12), (0.07, 0.07, 0.07)))
    return dict(body=body, accent=accent, eye=eye)
# hulk: hulking indestructible green brute
def hulk():
    body = U(ellipsoid((0, 0, 1.25), (0.75, 0.5, 0.7)), ellipsoid((0, 0.08, 2.05), (0.32, 0.3, 0.26)),
             both(lambda: capsule_z((0.32, 0, 0.0), 0.2, 0.6)),
             both(lambda: capsule_z((0.95, 0.05, 0.55), 0.2, 0.85)))
    accent = U(both(lambda: ellipsoid((0.72, 0, 1.75), (0.34, 0.32, 0.22))), box((0, 0.42, 1.2), (0.42, 0.08, 0.3)),
               both(lambda: ellipsoid((0.95, 0.1, 0.45), (0.27, 0.27, 0.2))))
    eye = both(lambda: ellipsoid((0.13, 0.33, 2.1), (0.08, 0.05, 0.05)))
    return dict(body=body, accent=accent, eye=eye)
# human (last human family): one mesh, three colour variants
def human():
    body = U(ellipsoid((0, 0, 0.95), (0.27, 0.18, 0.42)), both(lambda: capsule_z((0.12, 0, 0.1), 0.08, 0.45)),
             both(lambda: capsule_z((0.33, 0, 0.75), 0.065, 0.42)))
    skin = U(ellipsoid((0, 0, 1.58), (0.18, 0.18, 0.2)), both(lambda: ellipsoid((0.33, 0, 0.7), (0.07, 0.07, 0.07))))
    hair = ellipsoid((0, -0.03, 1.7), (0.19, 0.19, 0.13))
    return dict(body=body, skin=skin, hair=hair)
# enforcer / spheroid / electrode / brain
def spheroid():
    core = ellipsoid((0, 0, 1.2), (0.55, 0.55, 0.55), 28, 16)
    ring = torus(0.85, 0.07, 48, 8, c=(0, 0, 1.2))
    return dict(core=core, ring=ring)
def enforcer():
    body = U(ellipsoid((0, 0, 1.2), (0.4, 0.4, 0.22)), tube((0, 0, 1.1), 0.12, 0.3, 0.3, 16, R=rotm(rx=-PI / 2)))
    fins = U(*[slab([(0.3, -0.06), (0.75, -0.1), (0.75, 0.1), (0.3, 0.06)], 1.15, 1.25, 0.1) for _ in range(1)])
    fins = U(*[xform(fins, R=rotm(rz=a)) for a in (0, 2 * PI / 3, 4 * PI / 3)])
    eye = ellipsoid((0, 0, 1.42), (0.15, 0.15, 0.08))
    return dict(body=body, fins=fins, eye=eye)
def electrode():
    pts = []
    for i in range(8):
        a = 2 * PI * i / 8; r = 0.62 if i % 2 == 0 else 0.28; pts.append((np.cos(a) * r, np.sin(a) * r))
    star = slab(pts, 0.2, 0.55, 0.15)
    core = ellipsoid((0, 0, 0.4), (0.2, 0.2, 0.25))
    return dict(star=star, core=core)
def brain():
    body = U(ellipsoid((0, 0, 1.0), (0.32, 0.22, 0.45)), both(lambda: capsule_z((0.13, 0, 0.1), 0.08, 0.45)))
    lobes = U(*[ellipsoid((x, y, 1.75 + 0.05 * np.cos(x * 9)), (0.22, 0.24, 0.2)) for x, y in ((-0.17, 0.05), (0.17, 0.05), (0, -0.15))])
    eye = both(lambda: ellipsoid((0.1, 0.2, 1.3), (0.06, 0.04, 0.05)))
    return dict(body=body, lobes=lobes, eye=eye)
for kind, fn in (('hero', hero), ('grunt', grunt), ('hulk', hulk), ('human', human), ('spheroid', spheroid),
                 ('enforcer', enforcer), ('electrode', electrode), ('brain', brain)):
    for part, m in fn().items(): save(f'{kind}_{part}', m)
# props
save('bolt', capsule_z((0, 0, 0), 0.07, 1.0, 10) if False else ellipsoid((0, 0, 0), (0.08, 0.75, 0.08), 12, 10))
save('orb', ellipsoid((0, 0, 0), (0.5, 0.5, 0.5), 20, 12))
save('shard', slab([(0, 0.5), (-0.4, -0.3), (0.45, -0.25)], -0.08, 0.08, 0.2))
save('ring', torus(1.0, 0.045, 64, 8))
save('cube', box((0, 0, 0), (0.5, 0.5, 0.5)))
save('tile', U(box((0, 0, -0.1), (0.48, 0.48, 0.1))))
save('rail', U(box((0, 0, 0), (0.5, 0.5, 0.5))))
