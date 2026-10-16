# Procedural meshes for Defender Remix -> meshsrc/*.obj (cooked to .pemesh by cook_all.sh)
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
            if np.linalg.norm(fn) < 1e-9: continue
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

# ---- player ship: sleek fighter pointing +X, viewed from the side (XY), depth Z
def ship():
    body = U(ellipsoid((0.1, 0, 0), (1.6, 0.32, 0.42), 32, 16),
             slab([(-1.3, 0.1), (-0.2, 0.25), (-0.5, 0.75), (-1.45, 0.85)], -0.07, 0.07, 0.12),          # tail fin
             both(lambda: xform(slab([(-1.1, 0.0), (0.4, 0.0), (-0.3, 1.5), (-1.2, 1.45)], -0.05, 0.05, 0.1), (0, -0.05, 0), rotm(rx=PI / 2))))  # wings (along Z)
    metal = U(tube((-1.75, 0, 0), 0.26, 0.3, 0.55, R=RX), both(lambda: tube((-0.6, -0.1, 0.65), 0.1, 0.07, 1.2, R=RX)),
              tube((1.6, 0, 0), 0.08, 0.02, 0.5, R=RX))
    accent = U(both(lambda: xform(slab([(-1.05, 0.0), (-0.2, 0.0), (-0.75, 1.0), (-1.15, 1.0)], 0.06, 0.1, 0.0), (0, -0.05, 0), rotm(rx=PI / 2))),
               slab([(-1.2, 0.55), (-0.6, 0.45), (-0.7, 0.62), (-1.3, 0.75)], -0.1, 0.1, 0.0),
               ellipsoid((0.6, -0.2, 0), (0.7, 0.08, 0.44), 24, 8))
    glass = ellipsoid((0.55, 0.2, 0), (0.6, 0.2, 0.25), 24, 12)
    glow = U(ellipsoid((-2.3, 0, 0), (0.06, 0.24, 0.24), 16, 10), both(lambda: ellipsoid((-1.22, -0.1, 0.65), (0.04, 0.07, 0.07), 10, 6)))
    return dict(body=body, metal=metal, accent=accent, glass=glass, glow=glow)

# ---- lander: green saucer-ish pod with legs and a claw, yellow dome
def lander():
    body = U(ellipsoid((0, 0, 0), (0.95, 0.45, 0.95), 28, 14), torus(0.95, 0.12, 40, 8, Rm=rotm(rx=PI / 2)))
    accent = U(*[tube((0, -0.1, 0), 0.07, 0.05, 1.0, R=rotm(rx=0.0) @ rotm(rz=PI * 0.8) @ rotm(ry=a)) for a in ()],
               *[xform(tube((0, 0, 0), 0.07, 0.05, 1.05), (0.6 * np.cos(a), -0.2, 0.6 * np.sin(a)), rotm(ry=-a) @ rotm(rz=-2.7)) for a in np.linspace(0, 2 * PI, 4, endpoint=False) + PI / 4],
               *[ellipsoid((1.05 * np.cos(a), -1.05, 1.05 * np.sin(a)), (0.13, 0.06, 0.13), 10, 6) for a in np.linspace(0, 2 * PI, 4, endpoint=False) + PI / 4],
               tube((0, -0.9, 0), 0.06, 0.2, 0.5))
    eye = U(ellipsoid((0, 0.35, 0), (0.55, 0.42, 0.55), 24, 12))
    glow = U(*[ellipsoid((0.95 * np.cos(a), 0, 0.95 * np.sin(a)), (0.12, 0.12, 0.12), 10, 6) for a in np.linspace(0, 2 * PI, 8, endpoint=False)])
    return dict(body=body, accent=accent, eye=eye, glow=glow)

# ---- mutant: spiky aggressive crystal
def mutant():
    body = U(ellipsoid((0, 0, 0), (0.7, 0.7, 0.7), 20, 12))
    spikes = []
    for i, a in enumerate(np.linspace(0, 2 * PI, 8, endpoint=False)):
        for zz in (-0.35, 0.35):
            spikes.append(xform(tube((0, 0, 0), 0.22, 0.0, 0.85, n=8), (0, 0, zz), rotm(rz=a)))
    accent = U(*spikes)
    eye = both(lambda: ellipsoid((0.28, 0.18, 0.55), (0.16, 0.12, 0.1), 12, 8))
    return dict(body=body, accent=accent, eye=eye)

# ---- bomber: rotating box-cube with bands
def bomber():
    body = bbox((0, 0, 0), (1.2, 1.2, 1.2), 0.25)
    accent = U(torus(0.9, 0.08, 40, 6), torus(0.9, 0.08, 40, 6, Rm=rotm(rx=PI / 2)))
    glow = U(*[ellipsoid(tuple(v), (0.18, 0.18, 0.18), 10, 6) for v in [(0.62, 0, 0), (-0.62, 0, 0), (0, 0.62, 0), (0, -0.62, 0), (0, 0, 0.62), (0, 0, -0.62)]])
    return dict(body=body, accent=accent, glow=glow)

# ---- baiter: long flat fast saucer
def baiter():
    body = U(ellipsoid((0, 0, 0), (1.6, 0.25, 0.7), 32, 10))
    accent = U(ellipsoid((0, 0.18, 0), (0.6, 0.25, 0.4), 20, 10), torus(1.0, 0.06, 48, 6, Rm=rotm(rx=PI / 2)) )
    glow = U(*[ellipsoid((x, 0, 0.62), (0.1, 0.08, 0.06), 8, 6) for x in (-1.0, -0.5, 0, 0.5, 1.0)],
             *[ellipsoid((x, 0, -0.62), (0.1, 0.08, 0.06), 8, 6) for x in (-1.0, -0.5, 0, 0.5, 1.0)])
    return dict(body=body, accent=accent, glow=glow)

# ---- pod: purple spore; swarmer: tiny dart
def pod():
    body = ellipsoid((0, 0, 0), (0.8, 0.8, 0.8), 24, 14)
    accent = U(*[ellipsoid((0.75 * np.cos(a), 0.75 * np.sin(a), 0), (0.22, 0.22, 0.22), 10, 6) for a in np.linspace(0, 2 * PI, 6, endpoint=False)],
               ellipsoid((0, 0, 0.75), (0.22, 0.22, 0.22), 10, 6), ellipsoid((0, 0, -0.75), (0.22, 0.22, 0.22), 10, 6))
    return dict(body=body, accent=accent)
def swarmer():
    body = U(ellipsoid((0, 0, 0), (0.55, 0.25, 0.25), 16, 8), both(lambda: xform(slab([(-0.4, 0), (0.2, 0), (-0.45, 0.45)], -0.03, 0.03, 0.0), (0, 0, 0), rotm(rx=PI / 2))))
    glow = ellipsoid((-0.55, 0, 0), (0.12, 0.12, 0.12), 10, 6)
    return dict(body=body, glow=glow)

# ---- humanoid (astronaut)
def human():
    body = U(ellipsoid((0, 0.1, 0), (0.22, 0.35, 0.18), 14, 10), both(lambda: tube((0.1, -0.65, 0), 0.08, 0.09, 0.5)),
             both(lambda: xform(tube((0, 0, 0), 0.06, 0.05, 0.42), (0.22, 0.32, 0), rotm(rz=2.7))))
    visor = U(ellipsoid((0, 0.62, 0), (0.2, 0.2, 0.2), 14, 10))
    glow = ellipsoid((0, 0.58, 0.12), (0.13, 0.09, 0.08), 12, 8)
    return dict(body=body, visor=visor, glow=glow)

for kind, fn in (('ship', ship), ('lander', lander), ('mutant', mutant), ('bomber', bomber), ('baiter', baiter), ('pod', pod), ('swarmer', swarmer), ('human', human)):
    for part, m in fn().items(): save(f'{kind}_{part}', m)

# ---- terrain: one mountain tile (length 40 along X), rocky ridge; tiles repeat
rng = np.random.default_rng(3)
def ridge(L=40.0, n=80, depth=6.0, base=-3.0, amp=6.0, seed=0, nz=6):
    r = np.random.default_rng(seed)
    xs = np.linspace(-L / 2, L / 2, n + 1)
    k = np.arange(1, 7)
    ph = r.uniform(0, 2 * PI, 6); am = amp / k ** 1.1 * r.uniform(0.5, 1.0, 6)
    h = sum(am[i] * (0.5 + 0.5 * np.sin(2 * PI * k[i] * (xs + L / 2) / L + ph[i])) for i in range(6))
    h = np.abs(h); h = h / h.max() * amp
    zs = np.linspace(-depth / 2, depth / 2, nz + 1)
    m = M(); V, N, UV, F = [], [], [], []
    for j, z in enumerate(zs):
        prof = np.cos((z / (depth / 2)) * PI / 2) ** 0.7
        for i, x in enumerate(xs):
            V.append(np.array([x, base + h[i] * prof + r.normal() * 0.08 * prof, z])); N.append(np.array([0, 1.0, 0])); UV.append((i / n, j / nz))
    V = np.array(V)
    G = V.reshape(nz + 1, n + 1, 3)
    NN = np.zeros_like(G)
    dx = np.gradient(G, axis=1); dz = np.gradient(G, axis=0)
    NN = np.cross(dz, dx); NN /= np.linalg.norm(NN, axis=2, keepdims=True)
    NN[NN[..., 1] < 0] *= -1
    for j in range(nz):
        for i in range(n):
            a = j * (n + 1) + i; b = a + 1; c = a + n + 1; d = c + 1
            F += [(a, b, d), (a, d, c)]
    m.add(list(V), list(NN.reshape(-1, 3)), UV, F); return m, xs, h
mt, xs, h = ridge(seed=1); save('mountain', mt)
mt2, _, _ = ridge(seed=5, amp=9.0, depth=8.0, base=-3.0); save('mountain_far', mt2)
# glowing ridge line (thin tube following crest)
def crest(xs, h, base=-3.0):
    o = M()
    for i in range(len(xs) - 1):
        p0 = np.array([xs[i], base + h[i], 0]); p1 = np.array([xs[i + 1], base + h[i + 1], 0]); d = p1 - p0; L = np.linalg.norm(d)
        ang = np.arctan2(d[1], d[0])
        o += xform(tube((0, 0, 0), 0.07, 0.07, L, n=6, caps=False), p0, rotm(rz=ang - PI / 2))
    return o
save('crest', crest(xs, h))
save('ground', bbox((0, -4.5, 0), (40.0, 3.0, 14.0), 0.0))
# city: a cluster of tower blocks on a 40-wide tile
city = M(); win = M()
for i in range(14):
    x = -18 + i * 2.8 + rng.uniform(-0.4, 0.4); w = rng.uniform(1.0, 2.0); hh = rng.uniform(1.5, 5.5); z = rng.uniform(-2, 1)
    city += bbox((x, -3 + hh / 2, z), (w, hh, w), 0.05)
    for fy in np.arange(-2.6, -3 + hh - 0.3, 0.55):
        for fx in np.linspace(x - w / 2 + 0.25, x + w / 2 - 0.25, max(1, int(w / 0.5))):
            if rng.random() < 0.6: win += box((fx, fy, z + w / 2 + 0.01), (0.18, 0.22, 0.02))
save('city', city); save('citywin', win)
# props
save('laser', U(tube((-3, 0, 0), 0.07, 0.07, 6.0, n=10, R=RX)))
save('bullet', U(ellipsoid((0, 0, 0), (0.22, 0.22, 0.22), 12, 8)))
save('mine', U(ellipsoid((0, 0, 0), (0.18, 0.18, 0.18), 10, 6), *[xform(tube((0, 0, 0), 0.06, 0.0, 0.32, n=6), (0, 0, 0), rotm(rz=a)) for a in np.linspace(0, 2 * PI, 6, endpoint=False)]))
save('shard', slab([(0, 0.5), (-0.4, -0.3), (0.45, -0.25)], -0.08, 0.08, 0.2))
save('ring', torus(1.0, 0.045, 64, 8))
save('star', ellipsoid((0, 0, 0), (0.5, 0.5, 0.5), 8, 5))
save('orb', ellipsoid((0, 0, 0), (0.5, 0.5, 0.5), 20, 12))
save('planet', ellipsoid((0, 0, 0), (1, 1, 1), 64, 40))
save('beam', tube((0, 0, 0), 0.3, 0.3, 1.0, n=24, caps=False))
