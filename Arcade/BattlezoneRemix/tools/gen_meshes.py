# Procedural meshes for Battlezone Remix -> meshsrc/*.obj (cooked by cook_all.sh)
# Ground plane is XZ, Y up. Tanks face +Z. Drop zero-area tris before PhasmaCook.
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

def xform(m, c=(0, 0, 0), R=None, sx=1, sy=1, sz=1):
    o = M(); V = np.array(m.V, float); N = np.array(m.N, float)
    V = V * np.array([sx, sy, sz])
    if R is not None: V = V @ R.T; N = N @ R.T
    V = V + np.array(c); o.V, o.N, o.UV, o.F = list(V), list(N), list(m.UV), list(m.F); return o

def box(c, hx, hy, hz, R=None):
    """axis-aligned box centered at c with half-extents"""
    m = M()
    # 8 corners
    corners = np.array([[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]], float)
    corners *= np.array([hx, hy, hz])
    faces = [
        ([0,1,2,3], (0,0,-1)), ([4,7,6,5], (0,0,1)),
        ([0,4,5,1], (0,-1,0)), ([2,6,7,3], (0,1,0)),
        ([0,3,7,4], (-1,0,0)), ([1,5,6,2], (1,0,0)),
    ]
    for idx, n in faces:
        n = np.array(n, float)
        V = [corners[i] for i in idx]
        m.add(V, [n]*4, [(0,0),(1,0),(1,1),(0,1)], [(0,1,2),(0,2,3)])
    return xform(m, c, R)

def cyl(c, r0, r1, h, n=16, R=None, axis='y', caps=True):
    """tapered cylinder along +Y (or rotated) from y=0 to y=h"""
    m = M(); V, N, UV, F = [], [], [], []
    sl = (r0 - r1) / max(1e-6, h)
    for j, (y, r) in enumerate(((0.0, r0), (h, r1))):
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
            V2 = [np.array([0, y, 0])] + [np.array([np.cos(2*np.pi*i/n)*r, y, np.sin(2*np.pi*i/n)*r]) for i in range(n)]
            F2 = [(0, 1+i, 1+(i+1)%n) for i in range(n)]
            m.add(V2, [np.array([0, s, 0])] * len(V2), [(0.5, 0.5)] * len(V2), F2)
    Rm = R
    if axis == 'z': Rm = (rotm(rx=np.pi/2) if R is None else R @ rotm(rx=np.pi/2))
    elif axis == 'x': Rm = (rotm(rz=-np.pi/2) if R is None else R @ rotm(rz=-np.pi/2))
    return xform(m, c, Rm)

def cone(c, r, h, n=16, R=None):
    return cyl(c, r, 0.001, h, n=n, R=R, caps=True)

def sphere(c, r, nu=16, nv=10, R=None, squash=(1,1,1)):
    m = M(); V, N, UV, F = [], [], [], []
    for j in range(nv + 1):
        th = np.pi * j / nv
        for i in range(nu + 1):
            ph = 2 * np.pi * i / nu
            d = np.array([np.sin(th)*np.cos(ph), np.cos(th), np.sin(th)*np.sin(ph)])
            p = d * r * np.array(squash, float)
            nrm = d / np.array(squash, float); nrm /= np.linalg.norm(nrm) + 1e-9
            V.append(p); N.append(nrm); UV.append((i/nu, j/nv))
    for j in range(nv):
        for i in range(nu):
            a = j*(nu+1)+i; b=a+1; cc=a+nu+1; d=cc+1
            F += [(a,b,d),(a,d,cc)]
    m.add(V, N, UV, F)
    return xform(m, c, R)

def U(*ms):
    o = M()
    for m in ms: o += m
    return o

def save(name, m):
    V, N = np.array(m.V, float), np.array(m.N, float)
    kept = []
    for a, b, c in m.F:
        fn = np.cross(V[b] - V[a], V[c] - V[a])
        if np.linalg.norm(fn) < 1e-9: continue
        if np.dot(fn, N[a] + N[b] + N[c]) < 0: b, c = c, b
        kept.append((a, b, c))
    with open(os.path.join(OUT, name + '.obj'), 'w') as fo:
        fo.write(f'o {name}\n')
        for p in V: fo.write('v %.5f %.5f %.5f\n' % tuple(p))
        for t in m.UV: fo.write('vt %.5f %.5f\n' % tuple(t))
        for n in N: fo.write('vn %.5f %.5f %.5f\n' % tuple(n))
        for a, b, c in kept:
            fo.write(f'f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n')
    print(name, len(V), 'verts', len(kept), 'tris')

PI = np.pi

# ---- player tank parts
def tank_hull():
    # low armored hull facing +Z
    return U(
        box((0, 0.55, 0), 1.1, 0.45, 1.6),
        box((0, 0.95, -0.15), 0.85, 0.22, 1.0),      # upper deck
        box((0, 0.35, 1.35), 0.7, 0.25, 0.35),       # front glacis stub
        box((0, 0.7, -1.55), 0.55, 0.35, 0.25),      # rear
    )

def tank_tread():
    # one side tread unit (place at +/- X)
    return U(
        box((0, 0.35, 0), 0.28, 0.35, 1.7),
        cyl((-0.05, 0.35, 1.35), 0.32, 0.32, 0.35, n=12, axis='x'),
        cyl((-0.05, 0.35, -1.35), 0.32, 0.32, 0.35, n=12, axis='x'),
        cyl((-0.05, 0.35, 0.45), 0.22, 0.22, 0.3, n=10, axis='x'),
        cyl((-0.05, 0.35, -0.45), 0.22, 0.22, 0.3, n=10, axis='x'),
    )

def tank_turret():
    return U(
        cyl((0, 0, 0), 0.85, 0.75, 0.55, n=20),
        box((0, 0.35, 0.2), 0.55, 0.2, 0.7),
        sphere((0, 0.55, -0.2), 0.28, nu=12, nv=8),
    )

def tank_barrel():
    return U(
        cyl((0, 0, 0), 0.14, 0.11, 2.2, n=12, axis='z'),
        cyl((0, 0, 2.05), 0.18, 0.18, 0.25, n=12, axis='z'),
        cyl((0, 0, -0.15), 0.22, 0.18, 0.3, n=12, axis='z'),
    )

def tank_hatch():
    return U(cyl((0, 0, 0), 0.28, 0.28, 0.12, n=14), box((0, 0.08, 0.15), 0.08, 0.06, 0.12))

def tank_glow():
    # muzzle tip + running lights
    return U(
        sphere((0, 0, 0), 0.12, nu=10, nv=6),
        box((0.9, 0, 0), 0.06, 0.06, 0.06),
        box((-0.9, 0, 0), 0.06, 0.06, 0.06),
    )

# ---- enemy tank (blockier, taller)
def enemy_hull():
    return U(
        box((0, 0.5, 0), 1.0, 0.4, 1.4),
        box((0, 0.85, 0), 0.7, 0.25, 0.9),
        box((0, 0.4, 1.2), 0.6, 0.3, 0.3),
    )

def enemy_turret():
    return U(
        box((0, 0.2, 0), 0.7, 0.35, 0.7),
        cone((0, 0.55, 0), 0.35, 0.35, n=8),
    )

def enemy_barrel():
    return cyl((0, 0, 0), 0.1, 0.08, 1.6, n=10, axis='z')

def enemy_tread():
    return U(
        box((0, 0.3, 0), 0.25, 0.3, 1.5),
        cyl((-0.02, 0.3, 1.2), 0.28, 0.28, 0.28, n=10, axis='x'),
        cyl((-0.02, 0.3, -1.2), 0.28, 0.28, 0.28, n=10, axis='x'),
    )

# ---- super tank (heavier, angular)
def super_hull():
    return U(
        box((0, 0.6, 0), 1.3, 0.55, 1.8),
        box((0, 1.1, -0.2), 1.0, 0.3, 1.2),
        box((0, 0.5, 1.5), 0.9, 0.4, 0.4),
        box((0.9, 0.9, 0.5), 0.15, 0.4, 0.5),
        box((-0.9, 0.9, 0.5), 0.15, 0.4, 0.5),
    )

def super_turret():
    return U(
        box((0, 0.25, 0), 0.9, 0.4, 0.9),
        box((0, 0.55, 0), 0.5, 0.2, 0.5),
    )

def super_barrel():
    return U(
        cyl((0, 0.1, 0), 0.16, 0.12, 2.4, n=12, axis='z'),
        cyl((0, -0.15, 0.2), 0.1, 0.08, 1.8, n=10, axis='z'),
    )

# ---- flying saucer
def saucer_body():
    return U(
        sphere((0, 0, 0), 1.0, nu=24, nv=12, squash=(1.6, 0.28, 1.6)),
        cyl((0, 0.1, 0), 0.55, 0.35, 0.45, n=16),
        sphere((0, 0.5, 0), 0.4, nu=14, nv=8),
    )

def saucer_rim():
    # ring of panels
    parts = []
    for i in range(12):
        a = 2 * PI * i / 12
        parts.append(box((1.4*np.cos(a), 0, 1.4*np.sin(a)), 0.25, 0.08, 0.35, R=rotm(ry=-a)))
    return U(*parts)

def saucer_glow():
    return sphere((0, -0.15, 0), 0.35, nu=12, nv=8)

# ---- guided missile
def missile_body():
    return U(
        cyl((0, 0, 0), 0.18, 0.18, 1.4, n=12, axis='z'),
        cone((0, 0, 1.4), 0.18, 0.45, n=12),
        box((0.28, 0, 0.2), 0.22, 0.03, 0.25),
        box((-0.28, 0, 0.2), 0.22, 0.03, 0.25),
        box((0, 0.28, 0.2), 0.03, 0.22, 0.25),
        box((0, -0.28, 0.2), 0.03, 0.22, 0.25),
    )

def missile_glow():
    return sphere((0, 0, 0), 0.2, nu=10, nv=6)

# ---- shell / projectile
def shell_body():
    return U(cyl((0, 0, 0), 0.08, 0.08, 0.35, n=8, axis='z'), cone((0, 0, 0.35), 0.08, 0.15, n=8))

def shell_glow():
    return sphere((0, 0, 0), 0.12, nu=8, nv=6)

# ---- mountains (several silhouettes)
def mountain(seed, w=40, h=18, d=8, peaks=5):
    rng = np.random.default_rng(seed)
    m = M()
    # front silhouette polyline extruded in Z
    xs = np.linspace(-w/2, w/2, peaks * 4 + 1)
    ys = np.zeros_like(xs)
    for k in range(peaks):
        cx = -w/2 + (k + 0.5) * w / peaks
        ph = h * (0.45 + 0.55 * rng.random())
        width = w / peaks * (0.4 + 0.5 * rng.random())
        ys += ph * np.exp(-((xs - cx) / width) ** 2)
    ys = np.maximum(ys, 0.5)
    # build prism: front and back faces + sides
    z0, z1 = -d/2, d/2
    n = len(xs)
    # top strip quad chain
    for i in range(n - 1):
        a = np.array([xs[i], ys[i], z0]); b = np.array([xs[i+1], ys[i+1], z0])
        c = np.array([xs[i+1], ys[i+1], z1]); d = np.array([xs[i], ys[i], z1])
        fn = np.cross(b - a, d - a); ln = np.linalg.norm(fn)
        if ln < 1e-9: continue
        fn /= ln
        if fn[1] < 0: fn = -fn; b, d = d, b
        m.add([a, b, c, d], [fn]*4, [(0,0),(1,0),(1,1),(0,1)], [(0,1,2),(0,2,3)])
    # front face (down to ground)
    for i in range(n - 1):
        a = np.array([xs[i], 0, z0]); b = np.array([xs[i+1], 0, z0])
        c = np.array([xs[i+1], ys[i+1], z0]); d = np.array([xs[i], ys[i], z0])
        m.add([a, b, c, d], [np.array([0,0,-1])]*4, [(0,0),(1,0),(1,1),(0,1)], [(0,1,2),(0,2,3)])
    for i in range(n - 1):
        a = np.array([xs[i], 0, z1]); b = np.array([xs[i], ys[i], z1])
        c = np.array([xs[i+1], ys[i+1], z1]); d = np.array([xs[i+1], 0, z1])
        m.add([a, b, c, d], [np.array([0,0,1])]*4, [(0,0),(1,0),(1,1),(0,1)], [(0,1,2),(0,2,3)])
    return m

# ---- ground patch, crater, rock, radar dish bits
def ground_tile():
    # flat quad with slight thickness, large
    return box((0, -0.05, 0), 40, 0.05, 40)

def crater():
    # shallow bowl as ring + depressed disk approximation
    parts = [cyl((0, 0.02, 0), 2.2, 1.6, 0.15, n=20)]
    parts.append(cyl((0, 0.0, 0), 1.5, 0.8, 0.08, n=16))
    return U(*parts)

def rock():
    return U(
        sphere((0, 0.4, 0), 0.7, nu=10, nv=6, squash=(1.2, 0.7, 0.9)),
        sphere((0.4, 0.25, 0.2), 0.35, nu=8, nv=5, squash=(1, 0.6, 0.8)),
    )

def pyramid():
    # classic battlezone obstacle
    m = M()
    top = np.array([0, 3.0, 0])
    base = [np.array([1.5,0,1.5]), np.array([-1.5,0,1.5]), np.array([-1.5,0,-1.5]), np.array([1.5,0,-1.5])]
    for i in range(4):
        a, b = base[i], base[(i+1)%4]
        fn = np.cross(b-a, top-a); fn /= np.linalg.norm(fn)+1e-9
        m.add([a,b,top], [fn]*3, [(0,0),(1,0),(0.5,1)], [(0,1,2)])
    m.add(base, [np.array([0,-1,0])]*4, [(0,0),(1,0),(1,1),(0,1)], [(0,1,2),(0,2,3)])
    return m

def cube_block():
    return box((0, 1.0, 0), 1.2, 1.0, 1.2)

def shard():
    return U(cone((0, 0, 0), 0.15, 0.6, n=5), box((0, 0.1, 0), 0.08, 0.08, 0.2))

def ring_mesh():
    # thin torus-like shock ring as cylinder shell
    m = M(); n = 28; R0, r = 1.0, 0.04
    for j in range(2):
        for i in range(n+1):
            a = 2*PI*i/n
            y = (j-0.5)*r*2
            V = np.array([np.cos(a)*R0, y, np.sin(a)*R0])
            N = np.array([np.cos(a), 0, np.sin(a)])
            m.add([V], [N], [(i/n, j)], [])
    # rebuild properly
    m = M(); V, N, UV, F = [], [], [], []
    for j in range(2):
        for i in range(n+1):
            a = 2*PI*i/n; y = (j-0.5)*0.08
            V.append(np.array([np.cos(a)*R0, y, np.sin(a)*R0]))
            N.append(np.array([np.cos(a), 0, np.sin(a)]))
            UV.append((i/n, j))
    for i in range(n):
        F += [(i, i+1, i+n+2), (i, i+n+2, i+n+1)]
    m.add(V, N, UV, F)
    return m

def orb():
    return sphere((0, 0, 0), 0.5, nu=12, nv=8)

# ---- radar HUD decoration (3D world radar dish near player? optional)
def radar_dish():
    return U(
        cyl((0, 0, 0), 0.15, 0.15, 0.8, n=10),
        sphere((0, 0.9, 0), 0.45, nu=12, nv=6, squash=(1, 0.35, 1)),
    )

# Generate all
save('player_hull', tank_hull())
save('player_tread', tank_tread())
save('player_turret', tank_turret())
save('player_barrel', tank_barrel())
save('player_hatch', tank_hatch())
save('player_glow', tank_glow())

save('enemy_hull', enemy_hull())
save('enemy_tread', enemy_tread())
save('enemy_turret', enemy_turret())
save('enemy_barrel', enemy_barrel())
save('enemy_glow', sphere((0,0,0), 0.1, nu=8, nv=5))

save('super_hull', super_hull())
save('super_tread', enemy_tread())  # reuse proportions, scaled in scene
save('super_turret', super_turret())
save('super_barrel', super_barrel())
save('super_glow', sphere((0,0,0), 0.14, nu=8, nv=5))

save('saucer_body', saucer_body())
save('saucer_rim', saucer_rim())
save('saucer_glow', saucer_glow())

save('missile_body', missile_body())
save('missile_glow', missile_glow())

save('shell_body', shell_body())
save('shell_glow', shell_glow())

for i in range(4):
    save(f'mountain_{i}', mountain(10+i, w=50+i*8, h=14+i*3, d=6+i, peaks=4+i))

save('ground', ground_tile())
save('crater', crater())
save('rock', rock())
save('pyramid', pyramid())
save('block', cube_block())
for i in range(6):
    save(f'shard_{i}', xform(shard(), R=rotm(rx=PI*0.2*i, ry=PI*0.3*i, rz=PI*0.1*i)))
for i in range(4):
    save(f'ring_{i}', ring_mesh())
for i in range(4):
    save(f'orb_{i}', orb())
save('radar', radar_dish())
print('meshes done')
