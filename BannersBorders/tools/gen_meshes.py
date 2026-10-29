# Banners & Borders prop / figure meshes. Y up, figures face +Z, ~1 unit tall (scaled in game).
# Smooth rounded tabletop-miniature shapes coloured through the shared palette atlas.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
from palette import uv
import numpy as np
rng = np.random.default_rng(11)

def C(m, name):
    u = uv(name); m.UV = [u] * len(m.V); return m
def sq(c, r, e=0.5, nu=None, nv=None, R=None, col=None):
    mr = max(r)
    if nu is None: nu, nv = (10, 8) if mr < 0.1 else (14, 10) if mr < 0.5 else (18, 12)
    m = M(); V, N, UV, F = [], [], [], []; r = np.array(r, float); p2 = 2.0 / e
    for j in range(nv + 1):
        th = PI * j / nv
        for i in range(nu + 1):
            ph = 2 * PI * i / nu
            d = np.array([np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph)])
            p = np.sign(d) * np.abs(d) ** e * r
            g = np.sign(p) * np.abs(p / r) ** (p2 - 1) / r
            ln = np.linalg.norm(g); n = g / ln if ln > 1e-9 else d
            V.append(p); N.append(n); UV.append((i / nu, j / nv))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i; b = a + 1; cc = a + nu + 1; d = cc + 1
            F += [(a, b, d), (a, d, cc)]
    m.add(V, N, UV, F); m = xform(m, c, R)
    return C(m, col) if col else m
def B(c, r, col, nu=14, nv=10): return C(ellipsoid(c, (r, r, r) if np.isscalar(r) else r, nu, nv), col)
def S(p0, p1, r0, r1, col, n=12): return C(seg(p0, p1, r0, r1, n), col)
def cone(p0, p1, r, col, n=12): return C(seg(p0, p1, r, 0.001, n), col)
def T(R0, r, col, c=(0, 0, 0), Rm=None, nu=28, nv=8): return C(torus(R0, r, nu, nv, c, Rm), col)
def cyl(c, r0, r1, h, col, n=16): return C(tube(c, r0, r1, h, n), col)
FLAT = rotm(rx=PI / 2)

# ------------------------------------------------------------------ soldier miniature (chibi, spear + round shield)
def soldier(f, bearer=False):
    fc, fd, fl = f'f{f}', f'f{f}d', f'f{f}l'
    m = M()
    m += cyl((0, 0, 0), 0.2, 0.2, 0.05, fd, 18)                       # mini base disc
    for x in (-0.07, 0.07):
        m += S((x, 0.05, 0), (x, 0.24, 0), 0.055, 0.05, fd, 8)          # legs
        m += sq((x, 0.07, 0.03), (0.06, 0.04, 0.08), 0.5, col='wood_d')
    m += sq((0, 0.38, 0), (0.15, 0.17, 0.12), 0.6, col=fc)              # tunic
    m += sq((0, 0.28, 0), (0.155, 0.03, 0.125), 0.4, col='wood_d')      # belt
    m += B((0, 0.62, 0.01), 0.15, 'skin', 18, 12)                       # head
    for x in (-0.05, 0.05): m += B((x, 0.63, 0.135), (0.02, 0.026, 0.012), 'black', 8, 6)
    m += B((0, 0.69, -0.005), (0.16, 0.11, 0.165), 'steel', 18, 10)     # helmet
    m += S((0, 0.76, -0.12), (0, 0.84, 0.06), 0.03, 0.04, fc, 8)        # crest
    m += B((0, 0.8, 0.02), (0.035, 0.07, 0.12), fl, 10, 8)
    # shield on the left arm (faces forward-left), spear in the right hand
    m += C(xform(tube((0, 0, 0), 0.16, 0.16, 0.035, 22), (0.17, 0.38, 0.08), rotm(rx=PI / 2, ry=-0.5)), fc)
    m += C(xform(torus(0.16, 0.022, 22, 6), (0.17, 0.38, 0.08), rotm(rx=PI / 2, ry=-0.5) @ rotm(rx=PI / 2)), 'gold')
    m += B((0.19, 0.38, 0.12), 0.04, 'gold', 8, 6)
    m += S((-0.16, 0.45, 0.0), (-0.18, 0.33, 0.1), 0.045, 0.04, fc, 8)
    m += B((-0.18, 0.33, 0.1), 0.045, 'skin', 8, 6)
    if bearer:
        m += S((-0.19, 0.05, 0.1), (-0.19, 1.55, 0.1), 0.025, 0.022, 'wood', 8)
        m += B((-0.19, 1.57, 0.1), 0.045, 'gold', 10, 8)
        # banner cloth: swallow-tail flag
        V = []; N = []; F = []
        W, H, n = 0.62, 0.42, 8
        for i in range(n + 1):
            u = i / n; wave = 0.05 * np.sin(u * PI * 1.6)
            for j in range(3):
                v = j / 2; y = 1.5 - v * H - (0.08 * u * (1 if j == 1 else 0)) - (u * 0.06 if j == 2 else 0)
                if j == 1 and i == n: y = 1.5 - H * 0.5; 
                V.append((-0.19 - u * W, y, 0.1 + wave)); N.append((0, 0, 1))
        for i in range(n):
            for j in range(2):
                a = i * 3 + j; b = a + 3
                F += [(a, b, b + 1), (a, b + 1, a + 1)]
        cl = M(); cl.add(V, N, [(0, 0)] * len(V), F)
        cl2 = M(); cl2.add(V, [(0, 0, -1)] * len(V), [(0, 0)] * len(V), [(a, c, b) for a, b, c in F])
        m += C(cl, fc); m += C(cl2, fc)
        m += S((-0.19, 1.5, 0.1), (-0.19 - W, 1.5, 0.1), 0.012, 0.012, 'gold', 6)
        m += sq((-0.19 - W * 0.4, 1.31, 0.112), (0.07, 0.07, 0.01), 0.5, col='white')
    else:
        m += S((-0.19, 0.08, 0.12), (-0.19, 1.0, 0.12), 0.018, 0.016, 'wood', 8)
        m += cone((-0.19, 0.98, 0.12), (-0.19, 1.13, 0.12), 0.04, 'steel', 8)
    return m

def boat(f):
    fc, fd = f'f{f}', f'f{f}d'
    m = M()
    m += sq((0, 0.12, 0), (0.24, 0.12, 0.55), 0.55, col='wood')
    m += sq((0, 0.21, 0), (0.2, 0.04, 0.5), 0.5, col='wood_d')
    m += sq((0, 0.25, 0.0), (0.26, 0.03, 0.57), 0.35, col=fd)
    m += S((0, 0.2, 0.05), (0, 1.05, 0.05), 0.022, 0.02, 'wood_d', 8)
    m += sq((0, 0.7, 0.07), (0.3, 0.27, 0.025), 0.35, col=fc)
    m += sq((0, 0.7, 0.085), (0.1, 0.1, 0.01), 0.5, col='white')
    m += cone((0, 1.05, 0.05), (0, 1.2, 0.05), 0.04, 'gold', 6)
    for z in (-0.25, 0.25): m += B((0, 0.33, z), 0.08, 'skin', 8, 6); m += B((0, 0.38, z), (0.085, 0.05, 0.085), 'steel', 8, 6)
    return m

def flag(f):
    fc = f'f{f}'
    m = M()
    m += cyl((0, 0, 0), 0.12, 0.1, 0.06, 'stone_d', 14)
    m += S((0, 0.05, 0), (0, 2.0, 0), 0.035, 0.03, 'wood_d', 8)
    m += B((0, 2.03, 0), 0.06, 'gold', 10, 8)
    V, N, F = [], [], []; n = 10; W, H = 1.0, 0.62
    for i in range(n + 1):
        u = i / n; wave = 0.09 * np.sin(u * PI * 2.0) * u
        for j in range(2):
            V.append((-u * W, 1.95 - j * H - 0.04 * u, wave)); N.append((0, 0, 1))
    for i in range(n):
        a = i * 2; F += [(a, a + 2, a + 3), (a, a + 3, a + 1)]
    cl = M(); cl.add(V, N, [(0, 0)] * len(V), F)
    cl2 = M(); cl2.add(V, [(0, 0, -1)] * len(V), [(0, 0)] * len(V), [(a, c, b) for a, b, c in F])
    m += C(cl, fc); m += C(cl2, fc)
    m += B((-0.45, 1.64, 0.0), (0.13, 0.13, 0.03), 'white' if f else 'stone_d', 10, 8)
    return m

# ------------------------------------------------------------------ buildings (neutral stone; ownership shows on tile + flag)
def tower(c, r, h, roof='roof', crenel=False):
    m = M(); x, y, z = c
    m += cyl((x, y, z), r, r * 0.92, h, 'stone', 18)
    if crenel:
        m += cyl((x, y + h, z), r * 1.12, r * 1.12, 0.12, 'stone', 18)
        for i in range(8):
            a = 2 * PI * i / 8; m += sq((x + np.cos(a) * r * 1.05, y + h + 0.17, z + np.sin(a) * r * 1.05), (0.06, 0.07, 0.06), 0.4, col='stone')
    else:
        m += cone((x, y + h - 0.02, z), (x, y + h + r * 1.9, z), r * 1.22, roof, 18)
    for i in range(3):
        a = 2 * PI * (i + 0.3) / 3; m += sq((x + np.cos(a) * r * 0.95, y + h * 0.6, z + np.sin(a) * r * 0.95), (0.035, 0.07, 0.035), 0.5, col='black')
    return m
def wall(p0, p1, h, th=0.13):
    p0, p1 = np.array(p0, float), np.array(p1, float); d = p1 - p0; L = np.linalg.norm(d); a = np.arctan2(d[0], d[2])
    c = (p0 + p1) / 2
    m = sq((c[0], h / 2, c[2]), (th, h / 2, L / 2), 0.25, R=rotm(ry=a), col='stone')
    k = max(2, int(L / 0.22))
    for i in range(k):
        t = (i + 0.5) / k; p = p0 + d * t
        m += sq((p[0], h + 0.05, p[2]), (0.045, 0.05, 0.045), 0.4, col='stone')
    return m
def capital():
    m = M()
    m += sq((0, 0.04, 0), (1.05, 0.08, 1.05), 0.3, col='stone_d')
    pts = [(-0.75, -0.75), (0.75, -0.75), (0.75, 0.75), (-0.75, 0.75)]
    for i in range(4):
        a, b = pts[i], pts[(i + 1) % 4]; m += wall((a[0], 0, a[1]), (b[0], 0, b[1]), 0.42)
        m += tower((a[0], 0, a[1]), 0.18, 0.62, 'roof')
    m += sq((0, 0.55, 0), (0.42, 0.55, 0.42), 0.25, col='stone')
    m += tower((0, 1.0, 0), 0.24, 0.45, 'roof_d')
    m += sq((0, 0.18, 0.77), (0.13, 0.18, 0.04), 0.3, col='wood_d')
    m += B((0, 1.92, 0), 0.07, 'gold', 10, 8)
    return m
def fort():
    m = M()
    m += cyl((0, -0.02, 0), 0.95, 1.05, 0.08, 'stone_d', 28)
    n = 5
    for i in range(n):
        a0 = 2 * PI * i / n; a1 = 2 * PI * (i + 1) / n; r = 0.75
        p0 = (np.cos(a0) * r, 0, np.sin(a0) * r); p1 = (np.cos(a1) * r, 0, np.sin(a1) * r)
        m += wall(p0, p1, 0.32, 0.12)
        m += tower(p0, 0.15, 0.45, crenel=True)
    m += tower((0, 0, 0), 0.26, 0.75, crenel=True)
    return m
def house(c, s=1.0, ry=0.0, roof='roof'):
    x, y, z = c; R = rotm(ry=ry)
    m = sq((0, 0.16 * s, 0), (0.2 * s, 0.16 * s, 0.15 * s), 0.25, col='cream')
    rf = M()
    for sgn in (-1, 1):
        rf += sq((0, 0.36 * s, sgn * 0.085 * s), (0.23 * s, 0.025 * s, 0.12 * s), 0.3, R=rotm(rx=sgn * 0.62), col=roof)
    m += rf
    m += sq((0, 0.12 * s, 0.152 * s), (0.04 * s, 0.07 * s, 0.01 * s), 0.5, col='wood_d')
    return xform(m, (x, y, z), R)
def town():
    m = M()
    m += cyl((0, -0.02, 0), 0.75, 0.8, 0.06, 'sand', 24)
    m += house((-0.3, 0.04, 0.15), 1.2, 0.3); m += house((0.3, 0.04, 0.2), 1.0, -0.4, 'roof_d'); m += house((0.0, 0.04, -0.3), 1.1, 1.4)
    m += tower((0.05, 0.04, 0.0), 0.11, 0.7, 'roof')    # bell tower
    m += B((0.45, 0.25, -0.35), (0.16, 0.2, 0.16), 'leaf', 10, 8); m += S((0.45, 0.0, -0.35), (0.45, 0.1, -0.35), 0.04, 0.04, 'trunk', 6)
    return m
def port():
    m = M()
    m += cyl((0, -0.02, 0), 0.8, 0.85, 0.06, 'sand', 24)
    m += cyl((0.25, 0.04, 0), 0.2, 0.15, 1.05, 'white', 18)
    for y in (0.3, 0.65): m += cyl((0.25, y, 0), 0.19, 0.18, 0.12, 'f2', 18)
    m += cyl((0.25, 1.09, 0), 0.13, 0.13, 0.2, 'glass', 12)
    m += cone((0.25, 1.28, 0), (0.25, 1.5, 0), 0.17, 'roof_d', 14)
    m += sq((-0.35, 0.08, 0.35), (0.12, 0.04, 0.5), 0.3, col='wood')
    for z in (0.0, 0.3, 0.6, 0.85): m += S((-0.47, -0.2, z), (-0.47, 0.14, z), 0.03, 0.03, 'wood_d', 6); m += S((-0.23, -0.2, z), (-0.23, 0.14, z), 0.03, 0.03, 'wood_d', 6)
    m += house((-0.35, 0.04, -0.3), 1.0, 0.2)
    return m
def mine():
    m = M()
    m += sq((0, 0.25, -0.15), (0.7, 0.45, 0.55), 0.8, col='rock')
    m += sq((0.25, 0.45, -0.3), (0.35, 0.4, 0.35), 0.8, col='rock_d')
    m += sq((0, 0.2, 0.36), (0.2, 0.22, 0.05), 0.3, col='coal')
    for x in (-0.22, 0.22): m += S((x, 0.0, 0.42), (x, 0.47, 0.42), 0.04, 0.04, 'wood', 6)
    m += S((-0.26, 0.47, 0.42), (0.26, 0.47, 0.42), 0.045, 0.045, 'wood', 6)
    m += sq((0.45, 0.12, 0.55), (0.14, 0.1, 0.18), 0.4, col='wood_d')
    for i in range(5): m += B((0.45 + rng.uniform(-0.08, 0.08), 0.24, 0.55 + rng.uniform(-0.1, 0.1)), 0.06, 'gold', 8, 6)
    for x in (0.4, 0.5): m += S((x, 0.01, 0.2), (x, 0.01, 0.95), 0.012, 0.012, 'steel', 5)
    return m

# ------------------------------------------------------------------ scenery
def tree(s=1.0, seed=0):
    r = np.random.default_rng(seed); m = S((0, 0, 0), (0, 0.35 * s, 0), 0.06 * s, 0.05 * s, 'trunk', 8)
    for i in range(3):
        m += B((r.uniform(-0.1, 0.1) * s, (0.45 + 0.1 * i) * s, r.uniform(-0.1, 0.1) * s), (0.22 * s, 0.2 * s, 0.22 * s), 'leaf' if i % 2 == 0 else 'leaf_d', 12, 8)
    return m
def pine(s=1.0):
    m = S((0, 0, 0), (0, 0.2 * s, 0), 0.05 * s, 0.05 * s, 'trunk', 8)
    for i, (y, r) in enumerate(((0.15, 0.27), (0.38, 0.21), (0.58, 0.14))):
        m += C(seg((0, y * s, 0), (0, (y + 0.32) * s, 0), r * s, 0.01, 12), 'pine')
    return m
def peak(seed=1):
    r = np.random.default_rng(seed); m = M()
    for k in range(3):
        x, z = r.uniform(-0.5, 0.5), r.uniform(-0.3, 0.3); h = r.uniform(0.7, 1.1) * (1.0 if k == 0 else 0.7); rad = r.uniform(0.45, 0.6)
        m += C(seg((x, 0, z), (x, h, z), rad, 0.02, 10), 'rock')
        m += C(seg((x, h * 0.68, z), (x, h * 1.0, z), rad * 0.33, 0.015, 10), 'snow')
    return m
def cloud():
    m = M()
    for (x, y, z, r) in ((0, 0, 0, 1.0), (1.0, -0.15, 0.2, 0.75), (-1.0, -0.2, -0.1, 0.8), (0.4, 0.35, -0.3, 0.7), (-0.5, 0.2, 0.4, 0.6), (1.7, -0.3, 0, 0.45), (-1.7, -0.35, 0.1, 0.45)):
        m += B((x, y, z), (r * 1.1, r * 0.7, r), 'cloud', 16, 10)
    return m

save('capital', capital()); save('fort', fort()); save('town', town()); save('port', port()); save('mine', mine())
save('tree', tree(1.0, 1)); save('tree2', tree(0.85, 4)); save('pine', pine()); save('peak', peak(1)); save('peak2', peak(5)); save('cloud', cloud())
for f in range(1, 6):
    save(f'sol_{f}', soldier(f)); save(f'ber_{f}', soldier(f, True)); save(f'boat_{f}', boat(f))
for f in range(0, 6): save(f'flag_{f}', flag(f))
# selection ring / target ring / drag chevron / pip (glow materials set in Lua)
save('ring_sel', T(1.0, 0.05, 'white_g', (0, 0, 0), None, 48, 6))
save('ring_tgt', T(1.0, 0.05, 'white_g', (0, 0, 0), None, 48, 6))
def chev():
    m = M()
    for s in (-1, 1): m += sq((s * 0.17, 0, -0.05), (0.06, 0.03, 0.26), 0.4, R=rotm(ry=s * 0.75), col='white_g')
    return m
save('chev', chev())
# send-path dots: domed puck (dot / dot_bad, separate templates so each gets its own glow material) on a wider flat rim
save('dot', B((0, 0.05, 0), (0.17, 0.08, 0.17), 'white_g', 24, 10))
save('dot_bad', B((0, 0.05, 0), (0.17, 0.08, 0.17), 'white_g', 24, 10))
save('dot_rim', cyl((0, 0, 0), 0.235, 0.225, 0.05, 'white_g', 32))
save('ice', U(*[C(seg((np.cos(a) * 0.3, 0, np.sin(a) * 0.3), (np.cos(a) * 0.5, 1.0 + 0.3 * np.sin(a * 3), np.sin(a) * 0.5), 0.22, 0.01, 6), 'ice') for a in np.linspace(0, 2 * PI, 7)[:-1]], C(seg((0, 0, 0), (0, 1.5, 0), 0.3, 0.01, 6), 'ice')))
save('shell', U(B((0, 0, 0), 0.22, 'coal', 12, 8), B((0, 0, -0.25), (0.1, 0.1, 0.2), 'fire_g', 8, 6)))
def crate():
    m = sq((0, 0, 0), (0.3, 0.3, 0.3), 0.25, col='wood')
    for s in (-1, 1): m += sq((0, 0, s * 0.3), (0.31, 0.05, 0.02), 0.4, col='wood_d'); m += sq((s * 0.3, 0, 0), (0.02, 0.05, 0.31), 0.4, col='wood_d')
    m += sq((0, 1.0, 0), (0.75, 0.32, 0.75), 0.9, col='white'); m += sq((0, 0.98, 0), (0.6, 0.3, 0.6), 0.9, col='f1')
    for a in range(4):
        x, z = np.cos(a * PI / 2 + PI / 4) * 0.55, np.sin(a * PI / 2 + PI / 4) * 0.55; m += S((x * 0.5, 0.3, z * 0.5), (x, 0.85, z), 0.01, 0.01, 'white', 4)
    return m
save('crate', crate())
save('bar', sq((0, 0, 0), (0.5, 0.5, 0.5), 0.2, 24, 16, col='wood'))
save('blob', C(tube((0, 0, 0), 1.0, 1.0, 0.01, 28), 'black'))
def plane():
    m = M(); m.add([(-0.5, 0, -0.5), (0.5, 0, -0.5), (0.5, 0, 0.5), (-0.5, 0, 0.5)], [(0, 1, 0)] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 2, 1), (0, 3, 2)]); return m
save('deep', plane()); save('table', plane())
