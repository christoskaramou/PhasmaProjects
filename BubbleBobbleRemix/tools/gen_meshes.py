# Procedural meshes for Bubble Bobble Remix -> meshsrc/*.obj. Playfield = XY plane (1 unit = 1 tile), camera on +Z, actors face +X.
import numpy as np
from meshlib import *
import levels

def planar_uv(m, s=0.25):
    V, N = np.array(m.V), np.array(m.N); uv = []
    for p, n in zip(V, N):
        a = np.abs(n)
        if a[2] >= a[0] and a[2] >= a[1]: uv.append((p[0] * s, p[1] * s))
        elif a[1] >= a[0]: uv.append((p[0] * s, p[2] * s))
        else: uv.append((p[2] * s, p[1] * s))
    m.UV = uv; return m

# ---- levels: beveled blocks + a glowing top trim per span
for i, lv in enumerate(levels.L):
    blk, trim = M(), M()
    for x0, y0, x1, y1 in levels.solids(lv):
        blk += bbox(((x0 + x1) / 2, (y0 + y1) / 2, 0), (x1 - x0, y1 - y0, 1.6), 0.06)
        if y1 - y0 < 2:   # platforms: front-top glow strip
            trim += bbox(((x0 + x1) / 2, y1 - 0.06, 0.82), (x1 - x0 - 0.1, 0.1, 0.08), 0.0)
        else:            # walls: vertical inner glow line
            xe = x1 - 0.06 if x0 < 0 else x0 + 0.06
            trim += bbox((xe, (y0 + y1) / 2, 0.82), (0.08, y1 - y0 - 0.2, 0.08), 0.0)
    save(f'level{i}', planar_uv(blk)); save(f'trim{i}', trim)
# back panel behind each level (cave wall) - one shared mesh with tile UVs
save('backwall', planar_uv(bbox((0, 13, -1.6), (28, 26, 0.4), 0.0), 0.125))

# ---- dragon (Bub). feet at y=0, ~1.7 tall, faces +X
body = U(ellipsoid((0, 0.55, 0), (0.46, 0.45, 0.42), 24, 14), ellipsoid((0.12, 1.12, 0), (0.5, 0.44, 0.44), 26, 16),
         ellipsoid((0.52, 1.02, 0), (0.26, 0.2, 0.28), 18, 12), seg((-0.3, 0.42, 0), (-0.78, 0.22, 0), 0.2, 0.04, 14),
         ellipsoid((0.3, 0.62, 0.36), (0.14, 0.1, 0.1), 12, 8), ellipsoid((0.3, 0.62, -0.36), (0.14, 0.1, 0.1), 12, 8),
         ellipsoid((-0.05, 1.5, 0.3), (0.1, 0.12, 0.06), 10, 8), ellipsoid((-0.05, 1.5, -0.3), (0.1, 0.12, 0.06), 10, 8))
save('dragon_body', body)
save('dragon_belly', U(ellipsoid((0.2, 0.52, 0), (0.32, 0.36, 0.34), 20, 12), ellipsoid((0.55, 0.92, 0), (0.22, 0.1, 0.24), 16, 8)))
sp = M()
for k in range(6):
    a = 0.35 + k * 0.42
    p = np.array([0.12 - 0.5 * np.cos(a) * 0.95, 1.12 + 0.44 * np.sin(a) * 0.98 if k < 3 else 0.55 + 0.5 * np.sin(a), 0])
    if k >= 3: p = np.array([-0.38 - (k - 3) * 0.08, 0.95 - (k - 3) * 0.3, 0])
    d = p - np.array([0.05, 0.8 if k >= 3 else 1.12, 0]); d /= np.linalg.norm(d)
    sp += seg(p - d * 0.05, p + d * (0.26 - k * 0.02), 0.11, 0.0, 10)
save('dragon_spikes', sp)
save('dragon_eye', U(ellipsoid((0.4, 1.3, 0.19), (0.12, 0.18, 0.1), 14, 10), ellipsoid((0.4, 1.3, -0.19), (0.12, 0.18, 0.1), 14, 10)))
save('dragon_pupil', U(ball((0.5, 1.3, 0.2), 0.065, 10, 8), ball((0.5, 1.3, -0.2), 0.065, 10, 8)))
save('dragon_foot', ellipsoid((0.08, 0.08, 0), (0.22, 0.1, 0.13), 14, 8))

# ---- Zen-chan (wind-up robot). feet at y=0, ~1.4 tall
def superell(c, r, e=0.35, nu=28, nv=18):
    m = M(); V, N, UV, F = [], [], [], []
    sp = lambda x, p: np.sign(x) * np.abs(x) ** p
    for j in range(nv + 1):
        th = np.pi * j / nv
        for i in range(nu + 1):
            ph = 2 * np.pi * i / nu
            p = np.array([sp(np.sin(th), e) * sp(np.cos(ph), e), sp(np.cos(th), e), sp(np.sin(th), e) * sp(np.sin(ph), e)]) * r
            n = np.array([sp(np.sin(th), 2 - e) * sp(np.cos(ph), 2 - e) / r[0], sp(np.cos(th), 2 - e) / r[1], sp(np.sin(th), 2 - e) * sp(np.sin(ph), 2 - e) / r[2]])
            ln = np.linalg.norm(n); n = n / ln if ln > 1e-9 else np.array([0, np.sign(np.cos(th)), 0])
            V.append(p); N.append(n); UV.append((i / nu, j / nv))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i; b = a + 1; cc = a + nu + 1; d = cc + 1
            F += [(a, b, d), (a, d, cc)]
    m.add(V, N, UV, F); return xform(m, c)
save('zen_body', superell((0, 0.7, 0), (0.52, 0.5, 0.45), 0.4))
save('zen_visor', superell((0.46, 0.8, 0), (0.15, 0.22, 0.36), 0.45))
save('zen_eye', U(ellipsoid((0.61, 0.82, 0.15), (0.03, 0.1, 0.065), 10, 8), ellipsoid((0.61, 0.82, -0.15), (0.03, 0.1, 0.065), 10, 8)))
save('zen_feet', U(ellipsoid((0.05, 0.1, 0.24), (0.22, 0.1, 0.14), 12, 8), ellipsoid((0.05, 0.1, -0.24), (0.22, 0.1, 0.14), 12, 8)))
save('zen_key', U(seg((0.05, 0, 0), (-0.3, 0, 0), 0.05, 0.05, 10), xform(torus(0.14, 0.045, 20, 8), (-0.33, 0, 0.16), rotm(rx=PI / 2)),
                  xform(torus(0.14, 0.045, 20, 8), (-0.33, 0, -0.16), rotm(rx=PI / 2))))
# ---- Monsta (flying whale ghost). centered at y=0.6
save('monsta_body', U(ellipsoid((0, 0.65, 0), (0.6, 0.48, 0.44), 26, 16), xform(slab([(0, -0.18), (0.45, -0.35), (0.38, 0), (0.45, 0.35), (0, 0.18)], -0.06, 0.06, 0.2), (-0.92, 0.7, 0), rotm(rz=PI))))
save('monsta_eye', U(ellipsoid((0.43, 0.82, 0.18), (0.1, 0.13, 0.08), 12, 8), ellipsoid((0.43, 0.82, -0.18), (0.1, 0.13, 0.08), 12, 8)))
save('monsta_fin', U(xform(slab([(0, 0), (0.35, 0.05), (0.15, 0.32)], -0.04, 0.04, 0.2), (0.0, 0.92, 0)), ellipsoid((0.15, 0.35, 0.4), (0.18, 0.06, 0.12), 10, 6), ellipsoid((0.15, 0.35, -0.4), (0.18, 0.06, 0.12), 10, 6)))
# ---- Baron von Blubba (hurry-up ghost whale). ~2.6 wide
save('baron_body', U(ellipsoid((0, 1.0, 0), (1.25, 0.95, 0.9), 30, 18), xform(slab([(0, -0.3), (0.8, -0.7), (0.65, 0), (0.8, 0.7), (0, 0.3)], -0.1, 0.1, 0.2), (-1.85, 1.1, 0), rotm(rz=PI)),
                     ellipsoid((0.3, 0.2, 0.55), (0.35, 0.12, 0.2), 12, 8), ellipsoid((0.3, 0.2, -0.55), (0.35, 0.12, 0.2), 12, 8)))
save('baron_eye', U(ball((0.95, 1.35, 0.35), 0.16, 12, 8), ball((0.95, 1.35, -0.35), 0.16, 12, 8)))
save('baron_brow', U(seg((0.75, 1.62, 0.15), (1.05, 1.5, 0.5), 0.07, 0.05, 8), seg((0.75, 1.62, -0.15), (1.05, 1.5, -0.5), 0.07, 0.05, 8),
                     xform(slab([(-0.4, 0), (0.4, 0), (0.3, -0.12), (-0.3, -0.12)], -0.05, 0.05, 0.2), (1.08, 0.75, 0), rotm(ry=PI / 2))))

# ---- bubble: front rim ring, a thin tilted band, back hemisphere shell (inside), specular highlight
save('bubble_ring', torus(1.0, 0.075, 56, 10))
save('bubble_band', xform(torus(0.97, 0.022, 48, 6), (0, 0, 0), rotm(rx=1.15, ry=0.3)))
sh = ellipsoid((0, 0, 0), (0.98, 0.98, 0.98), 32, 18)
V = np.array(sh.V); keep = set(i for i, p in enumerate(V) if p[2] <= 0.05)
sh.F = [f for f in sh.F if all(i in keep for i in f)]; sh.N = [-np.array(n) for n in sh.N]
save('bubble_shell', sh)
save('bubble_hl', U(xform(ellipsoid((0, 0, 0), (0.24, 0.1, 0.05), 14, 8), (-0.45, 0.55, 0.62), rotm(rz=0.75)), ball((-0.2, 0.75, 0.62), 0.06, 8, 6)))

# ---- fruit
save('cherry', U(ball((-0.22, 0.25, 0), 0.26, 16, 10), ball((0.22, 0.2, 0.05), 0.26, 16, 10)))
save('cherry_stem', U(seg((-0.22, 0.45, 0), (0.05, 1.0, 0), 0.035, 0.03, 8), seg((0.22, 0.4, 0.05), (0.05, 1.0, 0), 0.035, 0.03, 8), xform(ellipsoid((0, 0, 0), (0.2, 0.05, 0.1), 10, 6), (0.2, 1.0, 0), rotm(rz=0.4))))
save('peach', ellipsoid((0, 0.45, 0), (0.42, 0.44, 0.4), 22, 14))
save('leaf', U(xform(ellipsoid((0, 0, 0), (0.25, 0.05, 0.12), 12, 6), (0.18, 0.92, 0), rotm(rz=0.5)), seg((0, 0.82, 0), (0.02, 1.0, 0), 0.03, 0.025, 6)))
gem = M(); top = np.array([0, 0.95, 0]); bot = np.array([0, 0.0, 0]); ring = [np.array([np.cos(a) * 0.42, 0.6, np.sin(a) * 0.42]) for a in np.linspace(0, 2 * PI, 9)[:-1]]
crown = [np.array([np.cos(a) * 0.24, 0.85, np.sin(a) * 0.24]) for a in np.linspace(0, 2 * PI, 9)[:-1] + PI / 8]
def tri(a, b, c):
    n = np.cross(b - a, c - a); n /= np.linalg.norm(n); gem.add([a, b, c], [n] * 3, [(0, 0)] * 3, [(0, 1, 2)])
for k in range(8):
    a, b = ring[k], ring[(k + 1) % 8]; c0, c1 = crown[k - 1], crown[k]
    tri(bot, b, a); tri(a, b, c1); tri(a, c1, c0); tri(c0, c1, top)
save('gem', gem)
bn = M(); pts = [(np.cos(a) * 0.5, np.sin(a) * 0.5 + 0.55) for a in np.linspace(-2.4, -0.7, 7)]
for (a, b), r in zip(zip(pts[:-1], pts[1:]), [0.08, 0.13, 0.16, 0.16, 0.13, 0.08]): bn += seg((*a, 0), (*b, 0), r, r * 0.9, 12); bn += ball((*b, 0), r * 0.9, 12, 8)
save('banana', bn)
# ---- star (sparkle debris + HUD-free life icon)
st = []
for k in range(10): a = PI / 2 + k * PI / 5; r = 0.5 if k % 2 == 0 else 0.22; st.append((np.cos(a) * r, np.sin(a) * r))
save('star', slab(st, -0.1, 0.1, 0.3))
save('orb', ball((0, 0, 0), 0.5, 16, 10))
