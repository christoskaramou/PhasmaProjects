# Procedural meshes for Tempest Remix -> meshsrc/*.obj
# Convention: local +Y is "up" of a part; tube depth is +Z in game space.
import numpy as np, os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'meshsrc')
os.makedirs(OUT, exist_ok=True)

class M:
    def __init__(s): s.V, s.N, s.UV, s.F = [], [], [], []
    def add(s, V, N, UV, F):
        b = len(s.V); s.V += list(V); s.N += list(N); s.UV += list(UV)
        s.F += [(a + b, c + b, d + b) for a, c, d in F]; return s
    def __iadd__(s, o): return s.add(o.V, o.N, o.UV, o.F)

def rotm(rx=0, ry=0, rz=0):
    cx, sx, cy, sy, cz, sz = np.cos(rx), np.sin(rx), np.cos(ry), np.sin(ry), np.cos(rz), np.sin(rz)
    X = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Y = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Z = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Z @ Y @ X

def xform(m, c=(0, 0, 0), R=None, mirror_x=False, sx=1, sy=1, sz=1):
    o = M(); V = np.array(m.V, float); N = np.array(m.N, float)
    V = V * np.array([sx, sy, sz])
    if R is not None: V = V @ R.T; N = N @ R.T
    if mirror_x: V[:, 0] *= -1; N[:, 0] *= -1
    V = V + np.array(c); o.V, o.N, o.UV, o.F = list(V), list(N), list(m.UV), list(m.F); return o

def ellipsoid(c, r, nu=24, nv=14, R=None):
    m = M(); V, N, UV, F = [], [], [], []
    r = np.array(r, float)
    for j in range(nv + 1):
        th = np.pi * j / nv
        for i in range(nu + 1):
            ph = 2 * np.pi * i / nu
            d = np.array([np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph)])
            p = d * r; n = d / r; n /= np.linalg.norm(n)
            V.append(p); N.append(n); UV.append((i / nu, j / nv))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i; b = a + 1; cc = a + nu + 1; d = cc + 1
            F += [(a, b, d), (a, d, cc)]
    m.add(V, N, UV, F); return xform(m, c, R)

def tube(c, r0, r1, h, n=20, R=None, caps=True, axis='y'):
    m = M(); V, N, UV, F = [], [], [], []
    sl = (r0 - r1) / max(h, 1e-6)
    for j, (y, r) in enumerate(((0, r0), (h, r1))):
        for i in range(n + 1):
            a = 2 * np.pi * i / n; d = np.array([np.cos(a), 0, np.sin(a)])
            nn = d + np.array([0, sl, 0]); nn /= np.linalg.norm(nn) + 1e-9
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
    P = np.array(poly, float); n = len(P); m = M()
    cen = P.mean(0)
    inner = cen + (P - cen) * (1 - bevel) if bevel > 0 else P
    for z, s, Q in ((z1, 1, inner), (z0, -1, inner)):
        V = [np.array([cen[0], cen[1], z])] + [np.array([q[0], q[1], z]) for q in Q]
        F = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
        m.add(V, [np.array([0, 0, s])] * len(V), [(0.5, 0.5)] * len(V), F)
    rings = [(inner, z0), (P, z0 + (z1 - z0) * 0.25), (P, z1 - (z1 - z0) * 0.25), (inner, z1)] if bevel > 0 else [(P, z0), (P, z1)]
    for k in range(len(rings) - 1):
        (A, za), (B, zb) = rings[k], rings[k + 1]
        for i in range(n):
            j = (i + 1) % n
            a0, a1 = np.array([*A[i], za]), np.array([*A[j], za])
            b0, b1 = np.array([*B[i], zb]), np.array([*B[j], zb])
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
            if np.linalg.norm(fn) < 1e-7: continue   # zero-area tris make PhasmaCook split the mesh (mesh 0 invisible)
            if np.dot(fn, N[a] + N[b] + N[c]) < 0: b, c = c, b
            fo.write(f'f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n')
    print(name, len(V), 'verts', len(m.F), 'tris')

def U(*ms):
    o = M()
    for m in ms: o += m
    return o

def both(fn):
    m = fn(); o = M(); o += m; o += xform(m, mirror_x=True); return o

PI = np.pi

# ---- rail segment: unit beam along +X from 0..1, circular cross-section ----
def rail_seg(r=0.045, n=12):
    m = M(); V, N, UV, F = [], [], [], []
    for j, x in enumerate((0.0, 1.0)):
        for i in range(n + 1):
            a = 2 * np.pi * i / n
            d = np.array([0, np.cos(a), np.sin(a)])
            V.append(np.array([x, 0, 0]) + d * r); N.append(d); UV.append((x, i / n))
    for i in range(n):
        F += [(i, i + 1, i + n + 2), (i, i + n + 2, i + n + 1)]
    m.add(V, N, UV, F)
    return m

# ---- player claw (Tempest classic claw, modern solid) ----
def claw_body():
    # central hub + twin prongs reaching "forward" (+Y toward tube center/rim inward)
    hub = ellipsoid((0, 0, 0), (0.28, 0.22, 0.22), 20, 12)
    spine = tube((0, -0.15, 0), 0.16, 0.08, 0.55, n=14)
    return U(hub, spine)

def claw_prong():
    # one prong on +X; mirrored in game for the other side
    return U(
        slab([(0.12, -0.05), (0.55, 0.15), (0.85, 0.55), (0.7, 0.7), (0.35, 0.35), (0.15, 0.1)], -0.07, 0.07, 0.15),
        tube((0.55, 0.4, 0), 0.07, 0.03, 0.45, n=10, R=rotm(rz=-0.9)),
        ellipsoid((0.82, 0.72, 0), (0.08, 0.1, 0.08), 12, 8),
    )

def claw_glow():
    return U(
        ellipsoid((0, 0.05, 0.18), (0.14, 0.1, 0.06), 12, 8),
        both(lambda: ellipsoid((0.55, 0.5, 0.05), (0.06, 0.12, 0.05), 10, 6)),
    )

def claw_metal():
    return U(
        torus(0.22, 0.035, 28, 8, Rm=rotm(rx=PI / 2)),
        both(lambda: tube((0.2, -0.05, 0), 0.04, 0.03, 0.35, n=8, R=rotm(rz=0.4))),
    )

# ---- flipper (V / chevron that flips between lanes) ----
def flipper_body():
    return U(
        slab([(-0.55, -0.15), (0, 0.55), (0.55, -0.15), (0.35, -0.35), (0, 0.15), (-0.35, -0.35)], -0.08, 0.08, 0.12),
        ellipsoid((0, 0.15, 0), (0.18, 0.2, 0.14), 14, 10),
    )

def flipper_edge():
    return U(
        both(lambda: tube((0.25, 0.05, 0), 0.04, 0.02, 0.55, n=8, R=rotm(rz=-1.0))),
        both(lambda: ellipsoid((0.5, -0.2, 0), (0.08, 0.08, 0.08), 10, 6)),
    )

# ---- tanker (armoured diamond that splits into two flippers) ----
def tanker_body():
    return U(
        ellipsoid((0, 0, 0), (0.42, 0.55, 0.35), 20, 12),
        slab([(-0.5, 0), (0, 0.7), (0.5, 0), (0, -0.55)], -0.12, 0.12, 0.1),
    )

def tanker_armor():
    return U(
        torus(0.38, 0.05, 28, 8, Rm=rotm(rx=PI / 2)),
        both(lambda: ellipsoid((0.35, 0.1, 0.15), (0.1, 0.18, 0.08), 10, 6)),
        ellipsoid((0, 0.5, 0.2), (0.15, 0.1, 0.08), 10, 6),
    )

# ---- spiker (cone creature that leaves spikes) ----
def spiker_body():
    return U(
        tube((0, -0.4, 0), 0.32, 0.02, 0.95, n=16),
        ellipsoid((0, -0.35, 0), (0.28, 0.18, 0.28), 16, 10),
    )

def spiker_ring():
    return U(
        torus(0.28, 0.04, 24, 8, c=(0, -0.15, 0), Rm=rotm(rx=PI / 2)),
        torus(0.18, 0.035, 20, 6, c=(0, 0.15, 0), Rm=rotm(rx=PI / 2)),
    )

# ---- fuseball (sparkly orb riding the rails) ----
def fuseball_core():
    return ellipsoid((0, 0, 0), (0.32, 0.32, 0.32), 24, 14)

def fuseball_tendril():
    return U(
        both(lambda: tube((0.15, 0, 0), 0.04, 0.01, 0.55, n=8, R=rotm(rz=-0.6))),
        both(lambda: tube((0.1, 0.1, 0), 0.035, 0.01, 0.45, n=8, R=rotm(rz=0.9, rx=0.4))),
        torus(0.38, 0.03, 28, 6, Rm=rotm(rx=0.7)),
    )

# ---- pulsar (bar that spans adjacent lanes and pulses) ----
def pulsar_body():
    return U(
        tube((0, 0, 0), 0.12, 0.12, 1.0, n=14, R=rotm(rz=-PI / 2)),  # along X, length 1
        ellipsoid((0.5, 0, 0), (0.14, 0.14, 0.14), 12, 8),
        ellipsoid((-0.0, 0, 0), (0.14, 0.14, 0.14), 12, 8),
    )

def pulsar_glow():
    return U(
        ellipsoid((0.25, 0, 0), (0.4, 0.08, 0.08), 12, 8),
        torus(0.2, 0.04, 20, 6, c=(0.25, 0, 0), Rm=rotm(ry=PI / 2)),
    )

# ---- spike left on a lane ----
def spike():
    return U(
        tube((0, 0, 0), 0.08, 0.0, 0.7, n=10),
        ellipsoid((0, 0.05, 0), (0.1, 0.06, 0.1), 10, 6),
    )

# ---- player zapper bolt ----
def bolt():
    return U(
        ellipsoid((0, 0, 0), (0.07, 0.07, 0.55), 12, 10),
        ellipsoid((0, 0, 0.2), (0.12, 0.12, 0.12), 10, 6),
    )

# ---- explosion / debris ----
def shard():
    return slab([(0, 0.4), (-0.25, -0.2), (0.3, -0.25)], -0.05, 0.05, 0.15)

def ring():
    return torus(1.0, 0.04, 48, 8)

def orb():
    return ellipsoid((0, 0, 0), (0.5, 0.5, 0.5), 20, 12)

def hub():
    # far-end hub disc
    return U(
        tube((0, -0.05, 0), 1.0, 0.85, 0.1, n=48, R=rotm(rx=PI / 2), caps=True),
        torus(0.95, 0.06, 48, 8, Rm=rotm(rx=PI / 2)),
        ellipsoid((0, 0, 0), (0.25, 0.25, 0.15), 16, 10),
    )

def node_ball():
    return ellipsoid((0, 0, 0), (0.12, 0.12, 0.12), 14, 10)

# ---- write all ----
save('claw_body', claw_body())
save('claw_prong', claw_prong())
save('claw_prongR', xform(claw_prong(), mirror_x=True))
save('claw_glow', claw_glow())
save('claw_metal', claw_metal())
save('flipper_body', flipper_body())
save('flipper_edge', flipper_edge())
save('tanker_body', tanker_body())
save('tanker_armor', tanker_armor())
save('spiker_body', spiker_body())
save('spiker_ring', spiker_ring())
save('fuseball_core', fuseball_core())
save('fuseball_tendril', fuseball_tendril())
save('pulsar_body', pulsar_body())
save('pulsar_glow', pulsar_glow())
save('spike', spike())
save('bolt', bolt())
save('shard', shard())
save('ring', ring())
save('orb', orb())
save('hub', hub())
save('rail', rail_seg(0.05, 14))
save('rail_glow', rail_seg(0.028, 10))
save('node', node_ball())
print('meshes ok')
