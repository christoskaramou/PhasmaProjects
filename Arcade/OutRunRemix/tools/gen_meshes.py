# Procedural meshes for Out Run Remix -> meshsrc/*.obj   (metres; cars face +Z, Y up)
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
S = {}
def put(n, m): S[n] = m
RY = rotm(ry=-PI / 2)          # side profile drawn in (z, y), extruded across X
def side(poly, x0, x1, b=0.0): return xform(slab(poly, x0, x1, b), (0, 0, 0), RY)
def quad(p, uv, n):
    m = M(); m.add([np.array(q, float) for q in p], [np.array(n, float)] * 4, uv, [(0, 1, 2), (0, 2, 3)]); return m
def cyl_x(c, r, w, n=20):      # cylinder along X centred at c
    return xform(tube((0, -w / 2, 0), r, r, w, n), c, rotm(rz=PI / 2))

# ------------------------------------------------------------------ Ferrari Testarossa Spider (red)
prof = [(-2.25, 0.32), (-2.27, 0.62), (-2.15, 0.92), (-0.75, 0.98), (-0.55, 0.8), (0.55, 0.78), (0.75, 0.84),
        (1.6, 0.68), (2.2, 0.5), (2.3, 0.36), (2.2, 0.26), (-2.15, 0.26)]
body = U(side(prof, -0.97, 0.97, 0.12))
put('car_body', body)
put('car_under', U(bbox((0, 0.24, 0), (1.8, 0.1, 4.3), 0.2)))
put('car_strake', U(*[bx for s in (1, -1) for k in range(5) for bx in [box((s * 0.985, 0.52 + k * 0.075, -0.75), (0.04, 0.03, 1.5))]]))
put('car_grille', U(box((0, 0.66, -2.26), (1.75, 0.22, 0.05)), *[box((0, 0.57 + k * 0.05, -2.285), (1.7, 0.012, 0.02)) for k in range(4)]))
put('car_tail', U(box((0, 0.66, -2.29), (1.78, 0.05, 0.03)), box((0.72, 0.66, -2.3), (0.3, 0.12, 0.03)), box((-0.72, 0.66, -2.3), (0.3, 0.12, 0.03))))
put('car_head', U(box((0.62, 0.5, 2.27), (0.34, 0.07, 0.05)), box((-0.62, 0.5, 2.27), (0.34, 0.07, 0.05))))
put('car_glass', U(xform(bbox((0, 0, 0), (1.5, 0.34, 0.04), 0.1), (0, 0.97, 0.62), rotm(rx=-0.95))))
put('car_frame', U(xform(box((0, 0, 0), (1.56, 0.04, 0.06)), (0, 1.13, 0.5), rotm(rx=-0.95)),
                   seg((0.76, 0.82, 0.78), (0.74, 1.12, 0.52), 0.025, 0.025, 6), seg((-0.76, 0.82, 0.78), (-0.74, 1.12, 0.52), 0.025, 0.025, 6)))
put('car_seat', U(*[bbox((s * 0.4, 0.72, -0.25), (0.52, 0.12, 0.55), 0.3) for s in (1, -1)],
                  *[xform(bbox((0, 0, 0), (0.48, 0.4, 0.12), 0.3), (s * 0.4, 0.9, -0.54), rotm(rx=0.25)) for s in (1, -1)]))
put('car_cabin', U(box((0, 0.66, 0.0), (1.7, 0.06, 1.15))))
put('car_wheelin', U(box((0, 0.84, 0.35), (1.55, 0.12, 0.25)), seg((0.4, 0.86, 0.3), (0.4, 0.95, 0.12), 0.02, 0.02, 6),
                     torus(0.17, 0.025, 18, 6, c=(0.4, 0.98, 0.1), Rm=rotm(rx=-1.0))))
put('car_mirror', U(*[ellipsoid((s * 1.02, 0.95, 0.45), (0.1, 0.06, 0.05), 10, 6) for s in (1, -1)]))
put('car_tire', U(cyl_x((0, 0, 0), 0.34, 0.3, 22)))
put('car_rim', U(cyl_x((0, 0, 0), 0.22, 0.32, 5), cyl_x((0, 0, 0), 0.08, 0.34, 10)))
put('car_shadow', U(xform(slab([(np.cos(a) * 0.95, np.sin(a) * 2.15) for a in np.linspace(0, 2 * PI, 29)[:-1]], -0.01, 0.01), (0, 0, 0), rotm(rx=PI / 2))))
# driver (dark hair, white shirt) and passenger (blonde, white blouse)
def figure_parts(sx, drive):
    sk, sh = [], []
    sk.append(ellipsoid((sx, 1.39, -0.37), (0.1, 0.125, 0.115), 16, 12))                     # head
    sk.append(seg((sx, 1.2, -0.4), (sx, 1.3, -0.38), 0.05, 0.045, 8))                        # neck
    sh.append(ellipsoid((sx, 1.0, -0.4), (0.18, 0.22, 0.12), 16, 12))                       # torso
    sh.append(ellipsoid((sx, 1.16, -0.41), (0.235, 0.075, 0.115), 16, 8))                   # shoulders
    for k in (-1, 1):
        sho = (sx + k * 0.22, 1.15, -0.41)
        if drive:
            elb, hand = (sx + k * 0.27, 1.0, -0.15), (sx + k * 0.15, 1.02, 0.08)
        else:
            elb, hand = (sx + k * 0.26, 0.93, -0.22), (sx + k * 0.1, 0.88, -0.02)
        sh.append(seg(sho, elb, 0.055, 0.045, 8))
        sk.append(seg(elb, hand, 0.042, 0.035, 8)); sk.append(ellipsoid(hand, (0.04, 0.035, 0.05), 8, 6))
    return sk, sh
dsk, dsh = figure_parts(0.4, True); psk, psh = figure_parts(-0.4, False)
put('drv_skin', U(*dsk, *psk))
put('drv_shirt', U(*dsh, *psh))
put('drv_hair', U(ellipsoid((0.4, 1.445, -0.39), (0.108, 0.085, 0.122), 16, 8), ellipsoid((0.4, 1.39, -0.445), (0.098, 0.09, 0.07), 12, 8)))
put('pas_hair', U(ellipsoid((-0.4, 1.445, -0.385), (0.112, 0.09, 0.126), 16, 8), ellipsoid((-0.4, 1.27, -0.475), (0.125, 0.17, 0.065), 14, 10),
                  *[seg((-0.4 + dx, 1.38, -0.49), (-0.4 + dx * 1.8, 1.2, -0.68), 0.05, 0.015, 6) for dx in (-0.07, 0, 0.07)]))

# ------------------------------------------------------------------ traffic
put('tr_beetle', U(ellipsoid((0, 0.85, 0), (0.8, 0.6, 1.9), 22, 14), ellipsoid((0, 0.55, 1.2), (0.82, 0.3, 0.65), 14, 8),
                   ellipsoid((0, 0.55, -1.2), (0.82, 0.3, 0.65), 14, 8), box((0, 0.36, 0), (1.5, 0.12, 3.6))))
put('tr_vette', U(side([(-2.1, 0.3), (-2.1, 0.75), (-1.0, 0.85), (-0.6, 1.2), (0.4, 1.22), (0.9, 0.8), (2.15, 0.6), (2.2, 0.32)], -0.88, 0.88, 0.1)))
put('tr_cab', U(bbox((0, 1.5, 1.6), (2.3, 2.3, 2.0), 0.08)))
put('tr_box', U(bbox((0, 1.95, -1.6), (2.4, 2.9, 5.2), 0.03)))
put('tr_glass', U(box((0, 1.08, 0.45), (1.25, 0.32, 0.5))))
put('tr_wind', U(box((0, 2.05, 2.61), (2.0, 0.7, 0.04)), box((1.16, 2.05, 1.9), (0.04, 0.6, 0.9)), box((-1.16, 2.05, 1.9), (0.04, 0.6, 0.9))))
put('tr_lamp', U(box((0.62, 0.6, -2.12), (0.3, 0.12, 0.04)), box((-0.62, 0.6, -2.12), (0.3, 0.12, 0.04))))

# ------------------------------------------------------------------ road (unit pieces placed per 5 m segment; z 0..1 forward)
def upn(m):
    m.N = [np.array([0.0, 1.0, 0.0]) for _ in m.N]; return m
put('road', upn(U(quad([(-0.5, 0, 0), (-0.5, 0, 1), (0.5, 0, 1), (0.5, 0, 0)], [(0, 0), (0, 1), (1, 1), (1, 0)], (0, 1, 0)),
              box((0, -0.17, 0.5), (1, 0.3, 1)))))   # body top 2 cm under the surface quad (was coplanar -> z-fight)
put('rumble_r', U(box((0, -0.06, 0.5), (1, 0.16, 1.0))))
put('rumble_w', U(box((0, -0.06, 0.5), (1, 0.16, 1.0))))
put('ground', upn(U(quad([(-0.5, 0, 0), (-0.5, 0, 1), (0.5, 0, 1), (0.5, 0, 0)], [(0, 0), (0, 1), (1, 1), (1, 0)], (0, 1, 0)),
                box((0, -0.43, 0.5), (1, 0.8, 1.0)))))   # body top 3 cm under the surface quad (was coplanar)
# crash debris: small irregular shards (body panel / dark trim), thrown and tumbled by the crash FX
put('deb_red', U(slab([(0.0, 0.0), (0.34, 0.05), (0.42, 0.22), (0.18, 0.36), (-0.06, 0.2)], -0.02, 0.02),
                 xform(slab([(0.0, 0.0), (0.22, 0.02), (0.16, 0.2), (-0.04, 0.14)], -0.015, 0.015), (0.3, 0.05, 0.1), rotm(ry=1.1, rx=0.6))))
put('deb_dark', U(xform(box((0, 0, 0), (0.22, 0.12, 0.3)), (0, 0, 0), rotm(rx=0.4, rz=0.3)),
                  xform(box((0, 0, 0), (0.08, 0.3, 0.06)), (0.12, 0.1, 0.05), rotm(rz=-0.7))))
put('divider', U(box((0, 0.35, 0.5), (0.5, 0.7, 1.0))))
# horizon ring: inward-facing open cylinder, u around, v up
def ring():
    m = M(); V, N, UV, F = [], [], [], []; n = 64
    for j, y in enumerate((0.0, 1.0)):
        for i in range(n + 1):
            a = 2 * PI * i / n; V.append(np.array([np.cos(a), y, np.sin(a)])); N.append(np.array([-np.cos(a), 0, -np.sin(a)])); UV.append((i / n * 4, 1 - y))
    for i in range(n): F += [(i, i + n + 2, i + 1), (i, i + n + 1, i + n + 2)]
    m.add(V, N, UV, F); return m
put('horizon', ring())

# ------------------------------------------------------------------ scenery
def frond(a, l=3.2):
    d = np.array([np.cos(a), 0, np.sin(a)])
    pts = []
    m = M()
    for k in range(6):
        t0, t1 = k / 6, (k + 1) / 6
        p0 = d * l * t0 + np.array([0, 0.6 * np.sin(PI * t0 * 0.9) - 1.6 * t0 * t0, 0]); p1 = d * l * t1 + np.array([0, 0.6 * np.sin(PI * t1 * 0.9) - 1.6 * t1 * t1, 0])
        w0, w1 = 0.55 * (1 - t0) + 0.08, 0.55 * (1 - t1) + 0.08
        side_ = np.cross(d, [0, 1, 0]); side_ /= np.linalg.norm(side_)
        q = [p0 - side_ * w0, p0 + side_ * w0, p1 + side_ * w1, p1 - side_ * w1]
        m.add(q, [np.array([0, 1, 0])] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 1, 2), (0, 2, 3)])
        m.add(q[::-1], [np.array([0, -1, 0])] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 1, 2), (0, 2, 3)])
    return m
trunk = M(); pts = [(0.06 * np.sin(k * 0.5) + k * 0.06, k * 1.1, 0) for k in range(8)]
for a, b in zip(pts[:-1], pts[1:]): trunk += seg(a, b, 0.24 - a[1] * 0.012, 0.22 - b[1] * 0.012, 10)
put('palm_trunk', trunk)
top = np.array(pts[-1])
put('palm_leaves', U(*[xform(frond(a + 0.3 * (k % 2)), tuple(top), None) for k, a in enumerate(np.linspace(0, 2 * PI, 9)[:-1])],
                     ball(tuple(top - [0, 0.1, 0]), 0.35, 10, 7)))
put('bush', U(ellipsoid((0, 0.7, 0), (1.3, 0.8, 1.1), 14, 8), ellipsoid((0.8, 0.5, 0.3), (0.8, 0.55, 0.7), 12, 7), ellipsoid((-0.7, 0.55, -0.2), (0.85, 0.6, 0.8), 12, 7)))
put('rock', U(ellipsoid((0, 0.8, 0), (1.8, 1.2, 1.5), 9, 6), ellipsoid((1.2, 0.5, 0.5), (1.0, 0.7, 0.9), 8, 5)))
put('cliff', U(ellipsoid((0, 6, 0), (6, 9, 7), 10, 7), ellipsoid((4, 3.5, 2), (4, 5, 4), 9, 6), ellipsoid((-4, 4.5, -1), (4.5, 6.5, 5), 9, 6)))
put('pine_trunk', U(seg((0, 0, 0), (0, 2.2, 0), 0.3, 0.22, 10)))
put('pine_leaves', U(*[seg((0, 1.6 + k * 1.6, 0), (0, 4.4 + k * 1.6, 0), 2.2 - k * 0.5, 0.05, 14) for k in range(3)]))
put('pine_snow', U(*[seg((0, 1.6 + k * 1.6, 0), (0, 4.4 + k * 1.6, 0), 2.2 - k * 0.5, 0.05, 14) for k in range(3)]))
put('cactus', U(seg((0, 0, 0), (0, 3.6, 0), 0.32, 0.28, 12), ball((0, 3.6, 0), 0.28, 10, 6), seg((0.3, 1.5, 0), (0.9, 1.6, 0), 0.2, 0.2, 8),
                seg((0.9, 1.5, 0), (0.9, 2.7, 0), 0.2, 0.18, 8), ball((0.9, 2.7, 0), 0.18, 8, 5), seg((-0.3, 2.0, 0), (-0.8, 2.1, 0), 0.18, 0.18, 8),
                seg((-0.8, 2.0, 0), (-0.8, 3.0, 0), 0.18, 0.16, 8), ball((-0.8, 3.0, 0), 0.16, 8, 5)))
for k, (w, h, d) in enumerate(((10, 14, 10), (14, 22, 12), (8, 9, 12))):
    put('bld_%d' % k, U(box((0, h / 2, 0), (w, h, d))))
put('roof', U(xform(slab([(-6, 0), (6, 0), (0, 3.5)], -5.5, 5.5), (0, 9, 0), None)))
put('windmill', U(seg((0, 0, 0), (0, 8, 0), 2.0, 1.2, 12), seg((0, 8, 0), (0, 9.6, 0), 1.3, 0.1, 12)))
put('blades', U(*[xform(box((0, 3.3, 0), (0.7, 6.0, 0.1)), (0, 0, 0), rotm(rz=a)) for a in (0, PI / 2, PI, 3 * PI / 2)], cyl_x((0, 0, 0), 0.35, 0.5, 10)))
put('column', U(seg((0, 0, 0), (0, 7, 0), 0.65, 0.58, 16), box((0, 7.2, 0), (1.7, 0.4, 1.7)), box((0, 0.2, 0), (1.7, 0.4, 1.7))))
put('vine', U(bbox((0, 0.6, 0), (0.9, 1.2, 4.6), 0.4)))
put('lamp', U(seg((0, 0, 0), (0, 7, 0), 0.1, 0.08, 8), seg((0, 7, 0), (-1.4, 7.3, 0), 0.07, 0.06, 6), box((-1.5, 7.2, 0), (0.7, 0.18, 0.3))))
put('fence', U(box((0, 0.9, 0), (0.12, 0.12, 5.0)), box((0, 0.5, 0), (0.12, 0.12, 5.0)), box((0, 0.55, 0), (0.15, 1.1, 0.15))))
put('sign_post', U(seg((-1.1, 0, 0), (-1.1, 2.4, 0), 0.07, 0.07, 6), seg((1.1, 0, 0), (1.1, 2.4, 0), 0.07, 0.07, 6)))
put('sign_board', U(quad([(-1.5, 2.2, 0.05), (1.5, 2.2, 0.05), (1.5, 3.8, 0.05), (-1.5, 3.8, 0.05)], [(0, 0), (1, 0), (1, 1), (0, 1)], (0, 0, 1)),
                    box((0, 3.0, -0.02), (3.0, 1.6, 0.08))))
put('sign_board_r', U(quad([(-1.5, 2.2, 0.05), (1.5, 2.2, 0.05), (1.5, 3.8, 0.05), (-1.5, 3.8, 0.05)], [(0, 0), (1, 0), (1, 1), (0, 1)], (0, 0, 1)),
                      box((0, 3.0, -0.02), (3.0, 1.6, 0.08))))
# start / checkpoint / goal gantries: pillars + a banner whose front face carries the text texture
put('arch', U(box((-12.5, 4.5, 0), (1.2, 9, 1.2)), box((12.5, 4.5, 0), (1.2, 9, 1.2)), box((0, 9.4, 0), (26.2, 1.0, 1.4))))
for nm in ('ban_start', 'ban_check', 'ban_goal'):
    put(nm, U(quad([(-10, 7.2, 0.62), (10, 7.2, 0.62), (10, 8.9, 0.62), (-10, 8.9, 0.62)], [(0, 0), (1, 0), (1, 1), (0, 1)], (0, 0, 1)),
              box((0, 8.05, 0), (20, 1.7, 1.2))))
put('flagman', U(seg((0, 0, 0), (0, 1.0, 0), 0.14, 0.15, 8), ellipsoid((0, 1.35, 0), (0.25, 0.4, 0.18), 10, 8), ball((0, 1.95, 0), 0.17, 10, 7)))
put('flag', U(quad([(0.2, 2.0, 0), (1.2, 2.0, 0), (1.2, 2.6, 0), (0.2, 2.6, 0)], [(0, 0), (1, 0), (1, 1), (0, 1)], (0, 0, 1)),
              quad([(0.2, 2.6, 0), (1.2, 2.6, 0), (1.2, 2.0, 0), (0.2, 2.0, 0)], [(0, 1), (1, 1), (1, 0), (0, 0)], (0, 0, -1)),
              seg((0.2, 1.4, 0), (0.2, 2.65, 0), 0.03, 0.03, 6)))
for n, m in S.items(): save(n, m)
