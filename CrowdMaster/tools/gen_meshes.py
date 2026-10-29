# Crowd Master meshes. Y up, track runs along +Z, units face +Z. Writes meshsrc/*.obj
import numpy as np, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *


def stube(c, r0, r1, h, n=48):
    """seamless tapered cylinder (no duplicated UV-seam column): far backdrop meshes are untextured,
    and the duplicated seam vertices drew a dark crack along the silhouette under lavapipe"""
    m = M(); V, N, UV, F = [], [], [], []
    sl = (r0 - r1) / h
    for j, (y, r) in enumerate(((0, r0), (h, r1))):
        for i in range(n):
            a = 2 * np.pi * i / n; d = np.array([np.cos(a), 0, np.sin(a)])
            nn = d + np.array([0, sl, 0]); nn /= np.linalg.norm(nn)
            V.append(d * r + np.array([0, y, 0])); N.append(nn); UV.append((0.5, j))
    for i in range(n):
        k = (i + 1) % n
        F += [(i, k, k + n), (i, k + n, i + n)]
    m.add(V, N, UV, F)
    for y, r, sg_ in ((0, r0, -1), (h, r1, 1)):
        V2 = [np.array([0, y, 0])] + [np.array([np.cos(2 * np.pi * i / n) * r, y, np.sin(2 * np.pi * i / n) * r]) for i in range(n)]
        m.add(V2, [np.array([0, sg_, 0])] * len(V2), [(0.5, 0.5)] * len(V2), [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)])
    return xform(m, np.array(c, float), None)

def ballp(c, r, nu=12, nv=8): return ellipsoid(c, (r, r, r), nu, nv)
def sg(a, b, r0, r1=None, n=10): return seg(a, b, r0, r1 if r1 is not None else r0, n)

def stickman(pose, ph=0.0):
    """pose: run|idle|cheer|climb ; ph run phase (radians)"""
    m = M(); lean = 0.0
    if pose == 'run':
        sw = 0.75 * np.sin(ph); lean = 0.10
        legs = [(0.075, sw), (-0.075, -sw)]; arms = [(0.23, -sw * 0.9), (-0.23, sw * 0.9)]
    else:
        legs = [(0.075, 0.0), (-0.075, 0.0)]; arms = [(0.23, 0.0), (-0.23, 0.0)]
    hip = np.array([0, 0.50, 0.0]); neck = np.array([0, 0.86, lean])
    m += sg(hip, neck, 0.115, 0.1)
    m += ballp(hip, 0.115, 12, 7)
    m += ballp(neck, 0.1, 10, 6)
    m += ballp(neck + np.array([0, 0.17, lean * 0.4]), 0.165, 16, 11)
    for x, a in legs:
        h = hip + np.array([x, 0, 0])
        bend = 0.25 + (0.9 * max(0.0, -a) if pose == 'run' else 0.0)
        if pose == 'run': bend = 0.25 + 0.8 * max(0.0, np.sin(a * 2.0 + 0.6))
        k = h + 0.25 * np.array([0, -np.cos(a), np.sin(a)])
        f = k + 0.25 * np.array([0, -np.cos(a - bend), np.sin(a - bend)])
        if pose != 'run': k = h + np.array([x * 0.15, -0.25, 0]); f = k + np.array([x * 0.2, -0.24, 0.02])
        m += sg(h, k, 0.072, 0.064); m += ballp(k, 0.064, 8, 5); m += sg(k, f, 0.064, 0.056)
        m += ellipsoid(f + np.array([0, 0.0, 0.04]), (0.062, 0.045, 0.095), 9, 5)
    sh = neck + np.array([0, -0.04, 0])
    for x, a in arms:
        s = sh + np.array([x * 0.55, 0, 0])
        if pose == 'run':
            e = s + 0.2 * np.array([x * 0.6, -np.cos(a), np.sin(a)]); h = e + 0.19 * np.array([0, -np.cos(a + 1.2) * 0.6, np.sin(a + 1.2)])
        elif pose == 'cheer':
            e = s + np.array([x * 0.9, 0.16, 0.02]); h = e + np.array([x * 0.25, 0.17, 0.0])
        elif pose == 'climb':
            e = s + np.array([x * 0.4, 0.18, 0.06]); h = e + np.array([x * 0.1, 0.2, 0.02])
        else:
            e = s + np.array([x * 0.45, -0.18, 0.02]); h = e + np.array([x * 0.15, -0.17, 0.05])
        m += ballp(s, 0.06, 8, 5); m += sg(s, e, 0.058, 0.052); m += ballp(e, 0.052, 8, 5); m += sg(e, h, 0.052, 0.046); m += ballp(h, 0.058, 8, 5)
    return m

for col in ('b', 'r', 'g', 'v', 'y', 'w'):
    for i in range(4): save(f'man_{col}{i}', stickman('run', i * np.pi / 2))
    save(f'man_{col}i', stickman('idle')); save(f'man_{col}c', stickman('cheer'))

# boss king (scaled at runtime), crown and club
k = stickman('idle'); save('king', k)
crown = U(tube((0, 0, 0), 0.16, 0.18, 0.1, 16), *[seg((0.17 * np.cos(a), 0.09, 0.17 * np.sin(a)), (0.19 * np.cos(a), 0.2, 0.19 * np.sin(a)), 0.03, 0.005, 6) for a in np.linspace(0, 2 * PI, 7)[:-1]])
save('crown', crown)
save('club', U(seg((0, 0, 0), (0, 0.55, 0), 0.03, 0.05, 8), ellipsoid((0, 0.62, 0), (0.09, 0.14, 0.09), 10, 7)))

# generic bevelled unit cubes, one per material family (material is per mesh source)
for nm, bev in [('trk', 0.0), ('trk2', 0.0), ('rail', 0.12), ('side', 0.0), ('step0', 0.03), ('step1', 0.03), ('step2', 0.03), ('step3', 0.03), ('step4', 0.03),
                ('oil', 0.0), ('mud', 0.0), ('gravel', 0.0), ('thorn', 0.0), ('ice', 0.0), ('warn', 0.05), ('glassb', 0.04), ('glassr', 0.04), ('glassp', 0.04),
                ('white', 0.1), ('metal', 0.08), ('stone', 0.08), ('wood', 0.08), ('gold', 0.1), ('dark', 0.0), ('water', 0.0), ('sand', 0.0), ('grass', 0.0),
                ('redpaint', 0.08), ('finish', 0.0), ('cloth', 0.0)]:
    save('c_' + nm, bbox((0, 0, 0), (1, 1, 1), bev) if bev > 0 else box((0, 0, 0), (1, 1, 1)))

# gate posts
save('post', U(tube((0, 0, 0), 0.2, 0.17, 3.2, 16), ballp((0, 3.25, 0), 0.24, 12, 8)))
save('post_warn', U(tube((0, 0, 0), 0.2, 0.17, 3.2, 16), ballp((0, 3.25, 0), 0.24, 12, 8)))
save('lamp', ballp((0, 0, 0), 0.5, 14, 10))
# spinner: post + bar (bar along X, centred on origin)
save('spin_post', U(tube((0, 0, 0), 0.35, 0.3, 1.3, 18), ellipsoid((0, 1.3, 0), (0.42, 0.18, 0.42), 16, 8)))
save('spin_bar', U(seg((-4.3, 0, 0), (4.3, 0, 0), 0.2, 0.2, 14), ballp((-4.3, 0, 0), 0.24), ballp((4.3, 0, 0), 0.24)))
# saw blade in XY plane (spins about Z), radius 1.1
star = []
for i in range(48):
    a = 2 * PI * i / 48; r = 1.1 if i % 2 == 0 else 0.92
    star.append((r * np.cos(a), r * np.sin(a)))
saw = slab(star, -0.05, 0.05, 0.0); saw += tube((0, 0, -0.12), 0.25, 0.25, 0.24, 16, R=rotm(rx=PI / 2)) if False else M()
save('saw', saw)
save('saw_hub', tube((0, -0.12, 0), 0.26, 0.26, 0.24, 16, R=rotm(rx=PI / 2)))
# hammer: pivot at origin, hangs down -Y 4.2 m, head along Z
save('hammer_handle', seg((0, 0, 0), (0, -4.0, 0), 0.12, 0.12, 10))
save('hammer_head', U(seg((0, -4.3, -1.0), (0, -4.3, 1.0), 0.75, 0.75, 22), ellipsoid((0, -4.3, -1.0), (0.72, 0.72, 0.12), 16, 6), ellipsoid((0, -4.3, 1.0), (0.72, 0.72, 0.12), 16, 6)))
# spike roller along X (length 1 unit -> scaled), radius 0.7 with cones
roll = seg((-0.5, 0, 0), (0.5, 0, 0), 0.6, 0.6, 20)
save('roller', roll)
sp = M()
for i in range(7):
    x = -0.42 + i * 0.14
    for j in range(8):
        a = 2 * PI * j / 8 + (i % 2) * PI / 8; d = np.array([0, np.cos(a), np.sin(a)])
        sp += seg(np.array([x, 0, 0]) + d * 0.55, np.array([x, 0, 0]) + d * 1.0, 0.09, 0.0, 6)
save('spikes', sp)
# coin (disc in XY plane, faces Z)
save('coin', U(tube((0, -0.06, 0), 0.4, 0.4, 0.12, 22, R=rotm(rx=PI / 2))))
# chest
save('chest', U(bbox((0, 0.45, 0), (1.6, 0.9, 1.1), 0.08), ellipsoid((0, 0.9, 0), (0.8, 0.35, 0.55), 18, 8)))
# decor
save('trunk', tube((0, 0, 0), 0.22, 0.14, 2.2, 10))
save('foliage', U(ellipsoid((0, 2.6, 0), (1.3, 1.1, 1.3), 14, 9), ellipsoid((0.5, 3.3, 0.2), (0.9, 0.8, 0.9), 12, 8), ellipsoid((-0.4, 3.4, -0.3), (0.8, 0.75, 0.8), 12, 8)))
save('pine', U(tube((0, 1.2, 0), 1.4, 0.0, 2.2, 14), tube((0, 2.4, 0), 1.1, 0.0, 2.0, 14), tube((0, 3.5, 0), 0.8, 0.0, 1.6, 14)))
rk = ellipsoid((0, 0.3, 0), (1.0, 0.75, 0.9), 9, 6); V = np.array(rk.V); rr = np.random.default_rng(3)
V *= (0.85 + 0.3 * rr.random((len(V), 1))); rk.V = list(V); save('rock', rk)
# islands: ONE shared dome surface. 'beach' (sand) is the whole dome; 'island' (grass) is the top of the SAME dome,
# pushed out along the surface normal by ISL_OFF, with a wavy edge. Both are placed with the same transform, so the
# grass lies a constant few cm above the sand everywhere. (The old grass and sand were two different ellipsoids,
# offset and scaled differently, crossing at a grazing angle: their 28x12 facets interleaved in a jagged band that
# read as z-fighting at every island edge.)
ISL_C, ISL_R = np.array([0, -1.0, 0]), np.array([1.0, 1.4, 1.0])
ISL_OFF = 0.012   # unit space; islands are scaled r=8..17 (x/z) and 0.35r (y) -> 3.4..7 cm on top, 10-20 cm at the rim
def isl_dome(nu, nv, th_max=None, off=0.0):
    m = M(); V, N, UV, F = [], [], [], []
    for j in range(nv + 1):
        for i in range(nu + 1):
            ph = 2 * np.pi * i / nu
            tm = np.pi if th_max is None else th_max(ph)
            th = tm * j / nv
            d = np.array([np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph)])
            n = d / ISL_R; n /= np.linalg.norm(n)
            V.append(ISL_C + d * ISL_R + n * off); N.append(n); UV.append((i / nu, th / np.pi))  # same UVs as the old 28x12 sphere
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i; b = a + 1; c = a + nu + 1; e = c + 1
            F += [(a, c, e), (a, e, b)]
    m.add(V, N, UV, F)
    return m
# grass edge: polar angle ~44 deg (grass ~70% of the waterline radius) with a lumpy outline
save('island', isl_dome(64, 10, lambda ph: 0.77 + 0.07 * np.sin(3 * ph + 0.4) + 0.04 * np.sin(7 * ph + 1.3), ISL_OFF))
save('mountain', stube((0, 0, 0), 1.0, 0.05, 1.0, 48))
# snow cap: the top of the mountain cone (r = 1 - 0.95 y), grown outward by SNOW_OFF so it never shares or crosses
# the cone's surface (the old cap sat 2.5% INSIDE the cone with a top disc coplanar with the cone's tip).
# Pines reuse it, fitted to their top cone in tree() (03b_build.lua).
SNOW_OFF = 0.025
save('snowcap', stube((0, 0.70, 0), 1 - 0.95 * 0.70 + SNOW_OFF, 1 - 0.95 * 1.01 + SNOW_OFF, 0.31, 48))
save('bush', U(ballp((0, 0.3, 0), 0.4, 10, 7), ballp((0.3, 0.25, 0.1), 0.3, 8, 6), ballp((-0.25, 0.22, -0.1), 0.28, 8, 6)))
th = M()
for i in range(10):
    a = 2 * PI * i / 10; th += seg((0, 0.2, 0), (0.45 * np.cos(a), 0.55 + 0.15 * (i % 3), 0.45 * np.sin(a)), 0.05, 0.0, 5)
save('thornspk', th)
# castle pieces
save('tower', U(tube((0, 0, 0), 1.6, 1.5, 7.0, 24), *[bbox((1.5 * np.cos(a), 7.3, 1.5 * np.sin(a)), (0.6, 0.7, 0.6), 0.1) for a in np.linspace(0, 2 * PI, 9)[:-1]]))
save('roof', tube((0, 7.0, 0), 1.9, 0.0, 3.0, 24))
save('flag', box((0.5, 0, 0), (1.0, 0.6, 0.04)))
save('pole', tube((0, 0, 0), 0.05, 0.05, 2.0, 8))
# breakables + assists
cg = M()
for i in range(14):
    a = 2 * PI * i / 14; cg += seg((1.3 * np.cos(a), 0.1, 1.0 * np.sin(a)), (1.3 * np.cos(a), 2.1, 1.0 * np.sin(a)), 0.07, 0.07, 7)
cg += torus(1.0, 0.1, 28, 6, c=(0, 0.12, 0), Rm=rotm(rx=PI / 2) @ np.diag([1.3, 1.0, 1.0]) if False else rotm(rx=PI / 2))
cg += torus(1.0, 0.1, 28, 6, c=(0, 2.1, 0), Rm=rotm(rx=PI / 2))
cg += ellipsoid((0, 2.2, 0), (1.15, 0.35, 1.15), 18, 7)
V = np.array(cg.V); V[:, 0] *= np.where(np.abs(V[:, 1] - 2.15) < 0.4, 1.0, 1.0); cg.V = list(V)
save('cage', cg)
save('crate', U(bbox((0, 0.6, 0), (1.2, 1.2, 1.2), 0.1), bbox((0, 0.6, 0.61), (1.25, 0.18, 0.04), 0.0), bbox((0, 0.6, -0.61), (1.25, 0.18, 0.04), 0.0)))
dome = M(); Vd, Nd, UVd, Fd = [], [], [], []
nu, nv = 20, 6
for j in range(nv + 1):
    th = (PI / 2) * j / nv
    for i in range(nu + 1):
        ph = 2 * PI * i / nu; d = np.array([np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph)])
        Vd.append(d * np.array([1.6, 0.9, 1.6])); Nd.append(d); UVd.append((i / nu, j / nv))
for j in range(nv):
    for i in range(nu):
        a = j * (nu + 1) + i; Fd += [(a, a + 1, a + nu + 2), (a, a + nu + 2, a + nu + 1)]
dome.add(Vd, Nd, UVd, Fd)
ch = U(xform(dome, (0, 3.0, 0)), *[seg((1.55 * np.cos(a), 3.0, 1.55 * np.sin(a)), (0.3 * np.cos(a), 1.2, 0.3 * np.sin(a)), 0.02, 0.02, 4) for a in np.linspace(0, 2 * PI, 7)[:-1]])
save('chute', ch)
save('beach', isl_dome(64, 24))   # sand: the full dome the grass cap sits on
save('mesa', U(stube((0, 0, 0), 1.0, 0.82, 0.8, 40), stube((0, 0.8, 0), 0.82, 0.7, 0.2, 40)))
# rounded rails / track lips: cylinders along Z (scale z only keeps them round)
save('railr', seg((0, 0, -0.5), (0, 0, 0.5), 1.0, 1.0, 20))
save('palm', U(seg((0, 0, 0), (0.25, 1.6, 0), 0.2, 0.17, 10), seg((0.25, 1.6, 0), (0.6, 3.2, 0), 0.17, 0.13, 10), ballp((0.6, 3.3, 0), 0.2, 8, 6)))
save('fronds', U(*[ellipsoid((0.6 + 0.9 * np.cos(a), 3.2, 0.9 * np.sin(a)), (0.9, 0.08, 0.3), 10, 5, R=rotm(ry=-a) @ rotm(rz=-0.35)) for a in np.linspace(0, 2 * PI, 8)[:-1]]))
save('cactus', U(seg((0, 0, 0), (0, 2.4, 0), 0.32, 0.3, 14), ballp((0, 2.4, 0), 0.3, 12, 8), seg((0.3, 1.0, 0), (0.75, 1.0, 0), 0.18, 0.18, 10),
    seg((0.75, 1.0, 0), (0.75, 1.8, 0), 0.18, 0.16, 10), ballp((0.75, 1.8, 0), 0.16), seg((-0.3, 1.3, 0), (-0.65, 1.3, 0), 0.16, 0.16, 10),
    seg((-0.65, 1.3, 0), (-0.65, 1.9, 0), 0.16, 0.14, 10), ballp((-0.65, 1.9, 0), 0.14)))
