# Procedural meshes for 1942 Remix -> meshsrc/*.obj   (units ~ metres/2; planes face +Z, wings along X, Y up)
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
S = {}
def put(n, m): S[n] = m
RY = rotm(ry=-PI / 2)
def side(poly, x0, x1, b=0.0): return xform(slab(poly, x0, x1, b), (0, 0, 0), RY)     # profile in (z, y), across X
RXF = rotm(rx=PI / 2)
def flat(poly, y0, y1, b=0.0): return xform(slab(poly, -y1, -y0, b), (0, 0, 0), RXF)  # planform in (x, z), thickness in Y
def quad(p, uv, n):
    m = M(); m.add([np.array(q, float) for q in p], [np.array(n, float)] * 4, uv, [(0, 1, 2), (0, 2, 3)]); return m
def cyl_z(c, r, l, n=16): return xform(tube((0, -l / 2, 0), r, r, l, n), c, rotm(rx=PI / 2))
def wing(span, zr0, zr1, zt0, zt1, y=0.0, t=0.05, xr=0.0):
    return flat([(xr, zr0), (span, zt0), (span, zt1), (xr, zr1), (-xr, zr1), (-span, zt1), (-span, zt0), (-xr, zr0)][::1], y - t / 2, y + t / 2, 0.25)
def wing2(span, zr0, zr1, zt0, zt1, y=0.0, t=0.05):
    a = flat([(0, zr0), (span, zt0), (span, zt1), (0, zr1)], y - t / 2, y + t / 2, 0.2)
    return U(a, xform(a, mirror_x=True))
def blades(c, r, n=3, w=0.05):
    out = []
    for k in range(n):
        a = 2 * PI * k / n + 0.3
        p = np.array(c, float); d = np.array([np.cos(a), np.sin(a), 0])
        out.append(seg(tuple(p), tuple(p + d * r), w, w * 0.6, 6))
    return U(*out, ball(c, w * 1.4, 8, 6))

# ---------------- P-38 Lightning ("Super Ace"): twin booms, central nacelle, twin fins
p38 = U(*[ellipsoid((s * 0.42, 0, -0.1), (0.1, 0.1, 0.82), 16, 10) for s in (1, -1)],
        *[ellipsoid((s * 0.42, 0.01, 0.36), (0.14, 0.14, 0.34), 16, 10) for s in (1, -1)],
        ellipsoid((0, 0.03, 0.22), (0.15, 0.13, 0.5), 16, 10),
        wing2(1.18, -0.12, 0.3, 0.02, 0.2, 0.0, 0.05),
        flat([(-0.48, -0.9), (0.48, -0.9), (0.48, -0.76), (-0.48, -0.76)], -0.02, 0.02))
put('p38_body', p38)
put('p38_fin', U(*[side([(-0.95, 0.0), (-0.95, 0.3), (-0.85, 0.32), (-0.72, 0.05), (-0.72, 0.0)], s * 0.42 - 0.02, s * 0.42 + 0.02) for s in (1, -1)]))
put('p38_glass', U(ellipsoid((0, 0.13, 0.28), (0.085, 0.08, 0.2), 14, 8)))
put('p38_mark', U(*[cyl_z((s * 0.75, 0.035, 0.12), 0.0, 0.0) if False else flat([(s * 0.75 + 0.09 * np.cos(a), 0.12 + 0.09 * np.sin(a)) for a in np.linspace(0, 2 * PI, 13)[:-1]], 0.02, 0.035) for s in (1, -1)]))
put('p38_prop', U(blades((0, 0, 0), 0.28, 3, 0.035)))
# ---------------- A6M Zero (light grey-green) and the red formation leader variant
def zero_parts():
    return U(ellipsoid((0, 0, -0.05), (0.12, 0.12, 0.72), 16, 10),
             wing2(0.95, -0.2, 0.26, -0.06, 0.12, -0.03, 0.045),
             wing2(0.36, -0.7, -0.55, -0.66, -0.58, 0.02, 0.03),
             side([(-0.75, 0.02), (-0.75, 0.26), (-0.66, 0.27), (-0.5, 0.05)], -0.015, 0.015))
put('zero_body', zero_parts())
put('red_body', zero_parts())
put('zero_cowl', U(cyl_z((0, 0, 0.6), 0.125, 0.14, 16)))
put('zero_glass', U(ellipsoid((0, 0.1, 0.05), (0.075, 0.075, 0.2), 12, 8)))
put('zero_mark', U(*[flat([(s * 0.6 + 0.08 * np.cos(a), 0.04 + 0.08 * np.sin(a)) for a in np.linspace(0, 2 * PI, 13)[:-1]], 0.0, 0.012) for s in (1, -1)]))
put('zero_prop', U(blades((0, 0, 0.69), 0.26, 3, 0.03)))
# ---------------- medium bomber (twin engines) and Ayako heavy bomber (four engines)
put('mid_body', U(ellipsoid((0, 0, 0), (0.28, 0.27, 1.6), 18, 10),
                  wing2(2.3, -0.3, 0.45, -0.05, 0.22, 0.0, 0.08),
                  wing2(0.8, -1.5, -1.2, -1.42, -1.28, 0.05, 0.05),
                  side([(-1.6, 0.05), (-1.6, 0.6), (-1.42, 0.62), (-1.1, 0.1)], -0.03, 0.03),
                  *[ellipsoid((s * 0.95, -0.02, 0.35), (0.18, 0.17, 0.62), 14, 8) for s in (1, -1)]))
put('mid_glass', U(ellipsoid((0, 0.12, 1.25), (0.16, 0.14, 0.3), 12, 8), ellipsoid((0, 0.22, 0.75), (0.12, 0.1, 0.22), 12, 8)))
put('mid_prop', U(*[blades((s * 0.95, -0.02, 0.98), 0.4, 3, 0.04) for s in (1, -1)]))
put('big_body', U(ellipsoid((0, 0, 0), (0.55, 0.52, 3.3), 20, 12),
                  wing2(4.8, -0.6, 0.9, -0.1, 0.45, 0.0, 0.14),
                  wing2(1.6, -3.1, -2.5, -2.95, -2.65, 0.1, 0.08),
                  side([(-3.3, 0.1), (-3.3, 1.25), (-2.95, 1.3), (-2.3, 0.2)], -0.05, 0.05),
                  *[ellipsoid((x, -0.04, 0.75), (0.26, 0.25, 0.85), 14, 8) for x in (-3.0, -1.6, 1.6, 3.0)]))
put('big_glass', U(ellipsoid((0, 0.25, 2.6), (0.3, 0.26, 0.55), 12, 8), *[ball((0, 0.5, z), 0.16, 10, 6) for z in (0.6, -1.4)]))
put('big_prop', U(*[blades((x, -0.04, 1.62), 0.6, 3, 0.05) for x in (-3.0, -1.6, 1.6, 3.0)]))
# ---------------- shots, POW, shadows
put('shot', U(ellipsoid((0, 0, 0), (0.06, 0.06, 0.3), 8, 6)))
put('ebul', U(ball((0, 0, 0), 0.17, 12, 8)))
# enemy bullet glow parts: a hot core and a flat 4-point star (spins in the render) so enemy fire reads as round + spiky,
# never as the player's elongated yellow tracers
put('ebul_core', U(ball((0, 0, 0), 0.1, 10, 7)))
star = []
for k in range(8):
    a = k * PI / 4; r = 0.42 if k % 2 == 0 else 0.13
    star.append((r * np.cos(a), r * np.sin(a)))
put('ebul_star', flat(star, -0.015, 0.015))
oct_ = [(0.55 * np.cos(a + PI / 8), 0.55 * np.sin(a + PI / 8)) for a in np.linspace(0, 2 * PI, 9)[:-1]]
for c in ('red', 'green', 'white', 'gray', 'yellow', 'orange'):
    put('pow_' + c, flat(oct_, -0.07, 0.07, 0.25))
put('shadow', flat([(np.cos(a), np.sin(a)) for a in np.linspace(0, 2 * PI, 25)[:-1]], 0, 0.01))
# ---------------- aircraft carrier (deck along Z)
CL = 13.0
hull = side([(-CL, 0.0), (-CL, 1.3), (CL - 1.5, 1.3), (CL, 1.1), (CL - 2.5, 0.0)], -1.6, 1.6, 0.05)
put('carrier_hull', U(hull))
put('carrier_deck', flat([(-2.2, -CL - 0.3), (2.2, -CL - 0.3), (2.2, CL - 0.6), (1.4, CL + 0.4), (-1.4, CL + 0.4), (-2.2, CL - 0.6)], 1.3, 1.42))
put('carrier_island', U(box((-1.95, 2.2, 1.0), (0.8, 1.6, 3.4)), box((-1.95, 3.3, 1.4), (0.5, 0.8, 1.2)), seg((-1.95, 3.6, 0.9), (-1.95, 5.0, 0.9), 0.06, 0.04, 6),
                        box((-1.95, 4.4, 0.9), (0.9, 0.06, 0.06))))
# ---------------- ocean, islands, clouds, palms
put('ocean', quad([(-0.5, 0, -0.5), (-0.5, 0, 0.5), (0.5, 0, 0.5), (0.5, 0, -0.5)], [(0, 0), (0, 1), (1, 1), (1, 0)], (0, 1, 0)))
def blob(seed, r, n=28, rough=0.28):
    g = np.random.default_rng(seed); a = np.linspace(0, 2 * PI, n + 1)[:-1]; k = np.ones(n)
    for o in (2, 3, 5): k += g.uniform(-rough, rough) * np.cos(o * a + g.uniform(0, 6)) / (o / 2)
    return [(r[0] * k[i] * np.cos(a[i]), r[1] * k[i] * np.sin(a[i])) for i in range(n)]
for v in range(3):
    put(f'isl_reef{v}', flat(blob(10 + v, (7.5, 5.5)), -0.25, 0.02))
    put(f'isl_sand{v}', flat(blob(10 + v, (6.0, 4.3)), -0.2, 0.18, 0.15))
    put(f'isl_jungle{v}', U(flat(blob(20 + v, (4.3, 2.9), 28, 0.35), 0.1, 0.42, 0.3),
                            *[ellipsoid((x, 0.45, z), (1.0, 0.45, 0.9), 10, 6) for x, z in np.random.default_rng(30 + v).uniform(-2.4, 2.4, (7, 2)) * [1, 0.6]]))
def frond(a, l=1.1):
    d = np.array([np.cos(a), 0, np.sin(a)]); m = M()
    for k in range(5):
        t0, t1 = k / 5, (k + 1) / 5
        p0 = d * l * t0 + np.array([0, 0.25 * np.sin(PI * t0 * 0.9) - 0.5 * t0 * t0, 0]); p1 = d * l * t1 + np.array([0, 0.25 * np.sin(PI * t1 * 0.9) - 0.5 * t1 * t1, 0])
        w0, w1 = 0.2 * (1 - t0) + 0.03, 0.2 * (1 - t1) + 0.03
        s_ = np.cross(d, [0, 1, 0]); s_ /= np.linalg.norm(s_)
        q = [p0 - s_ * w0, p0 + s_ * w0, p1 + s_ * w1, p1 - s_ * w1]
        m.add(q, [np.array([0, 1, 0])] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 1, 2), (0, 2, 3)])
        m.add(q[::-1], [np.array([0, -1, 0])] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 1, 2), (0, 2, 3)])
    return m
put('palm_trunk', U(seg((0, 0, 0), (0.15, 1.3, 0), 0.08, 0.06, 8)))
put('palm_leaves', U(*[xform(frond(a), (0.15, 1.3, 0)) for a in np.linspace(0, 2 * PI, 8)[:-1]], ball((0.15, 1.28, 0), 0.1, 8, 6)))
for v in range(3):
    g = np.random.default_rng(50 + v)
    put(f'cloud{v}', U(*[ellipsoid((x, 0, z), (r, r * 0.45, r * 0.8), 12, 7) for x, z, r in zip(g.uniform(-3, 3, 7), g.uniform(-1.6, 1.6, 7), g.uniform(1.0, 2.0, 7))]))
put('wreck', U(box((0, 0, 0), (0.25, 0.08, 0.25))))
def flatten(m):
    o = M(); V = np.array(m.V, float) * np.array([1, 0.0, 1]) + np.array([0, 0.001, 0]); o.V = list(V)
    o.N = [np.array([0.0, 1.0, 0.0]) for _ in m.N]; o.UV = list(m.UV); o.F = list(m.F); return o
for nm in ('p38', 'zero', 'mid', 'big'):
    body = S[nm + '_body']
    put('sh_' + nm, flatten(body))
for n, m in S.items(): save(n, m)
