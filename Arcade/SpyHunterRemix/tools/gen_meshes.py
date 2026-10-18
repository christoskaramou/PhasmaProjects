# Procedural meshes for Spy Hunter Remix -> meshsrc/*.obj  (world: X across, Y up, Z forward; vehicles face +Z)
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
S = {}
def put(n, m): S[n] = m
RXF = rotm(rx=PI / 2)
RY = rotm(ry=-PI / 2)
def flat(poly, y0, y1, b=0.0): return xform(slab(poly, -y1, -y0, b), (0, 0, 0), RXF)
def side(poly, x0, x1, b=0.0): return xform(slab(poly, x0, x1, b), (0, 0, 0), RY)    # profile in (z, y), across X
def rect(w, d, cx=0, cz=0): return [(cx - w / 2, cz - d / 2), (cx + w / 2, cz - d / 2), (cx + w / 2, cz + d / 2), (cx - w / 2, cz + d / 2)]
def wheel(x, z, r=0.17, w=0.14): return xform(tube((0, -w / 2, 0), r, r, w, 14), (x, r, z), rotm(rz=-PI / 2))
def wheels(hx, zf, zb, r=0.17): return U(*[wheel(sx * hx, z, r) for sx in (-1, 1) for z in (zf, zb)])
def car(L, Wd, H, cab=(0.2, 0.55), cabH=0.3, nose=0.25):
    # body profile (z, y) extruded across x; cabin glass separately
    hl = L / 2
    body = side([(-hl, 0.14), (hl, 0.14), (hl, 0.14 + H * 0.6), (hl - nose, 0.14 + H), (-hl + 0.1, 0.14 + H), (-hl, 0.14 + H * 0.8)], -Wd / 2, Wd / 2, 0.15)
    z0, z1 = -hl + L * cab[0], -hl + L * cab[1]
    glass = side([(z0, 0.14 + H - 0.02), (z1, 0.14 + H - 0.02), (z1 - 0.12, 0.14 + H + cabH), (z0 + 0.08, 0.14 + H + cabH)], -Wd / 2 + 0.07, Wd / 2 - 0.07, 0.1)
    return body, glass
b, g = car(1.5, 0.78, 0.22, (0.15, 0.5), 0.2, 0.45); put('int_body', b); put('int_glass', g); put('int_wheel', wheels(0.36, 0.48, -0.5))
put('int_gun', U(seg((-0.18, 0.3, 0.55), (-0.18, 0.3, 0.85), 0.03, 0.03, 6), seg((0.18, 0.3, 0.55), (0.18, 0.3, 0.85), 0.03, 0.03, 6)))
b, g = car(1.5, 0.8, 0.3, (0.25, 0.65), 0.28); put('civ_body', b); put('civ_glass', g); put('civ_wheel', wheels(0.37, 0.45, -0.45))
put('truck_cab', U(flat(rect(0.9, 0.7, 0, 0.75), 0.14, 0.95, 0.1)))
put('truck_box', U(flat(rect(0.94, 1.6, 0, -0.45), 0.2, 1.15, 0.05)))
put('truck_wheel', wheels(0.4, 0.8, -0.8, 0.2))
put('van_box', U(flat(rect(0.98, 2.0, 0, -0.35), 0.22, 1.25, 0.05)))
put('van_ramp', U(xform(flat(rect(0.8, 0.9), -0.03, 0.03), (0, 0.15, -1.75), rotm(rx=-0.25))))
b, g = car(1.6, 0.86, 0.26, (0.3, 0.62), 0.24, 0.3); put('sw_body', b); put('sw_glass', g)
put('sw_blade', U(*[flat([(0, 0), (0.06, 0.3), (-0.06, 0.3)], -0.02, 0.02) for _ in range(1)], torus(0.1, 0.03, 10, 5, Rm=rotm(rz=PI / 2))))
b, g = car(1.7, 0.95, 0.42, (0.3, 0.6), 0.22, 0.2); put('rl_body', b); put('rl_glass', g)
put('rl_plate', U(flat(rect(1.0, 0.12, 0, 0.86), 0.14, 0.6, 0.2), side([(-0.7, 0.2), (0.7, 0.2), (0.7, 0.55), (-0.7, 0.55)], 0.47, 0.52), side([(-0.7, 0.2), (0.7, 0.2), (0.7, 0.55), (-0.7, 0.55)], -0.52, -0.47)))
b, g = car(2.1, 0.82, 0.26, (0.2, 0.75), 0.24, 0.3); put('enf_body', b); put('enf_glass', g); put('enf_wheel', wheels(0.37, 0.7, -0.7))
put('heli_body', U(ellipsoid((0, 0, 0.2), (0.45, 0.42, 0.7), 16, 10), seg((0, 0.05, -0.4), (0, 0.15, -1.6), 0.12, 0.05, 8),
                   flat([(-0.02, -1.5), (0.02, -1.5), (0.02, -1.7), (-0.02, -1.7)], 0.1, 0.5), seg((-0.35, -0.42, 0.5), (-0.35, -0.42, -0.3), 0.03, 0.03, 5), seg((0.35, -0.42, 0.5), (0.35, -0.42, -0.3), 0.03, 0.03, 5)))
put('heli_glass', ellipsoid((0, 0.08, 0.55), (0.34, 0.28, 0.32), 12, 8))
put('heli_rotor', U(flat(rect(3.0, 0.12), 0.48, 0.51), flat(rect(0.12, 3.0), 0.48, 0.51), tube((0, 0.38, 0), 0.06, 0.06, 0.12, 8)))
put('boat_hull', U(flat([(0, 0.95), (0.42, 0.45), (0.42, -0.8), (-0.42, -0.8), (-0.42, 0.45)], 0.0, 0.32, 0.12)))
put('boat_deck', U(flat([(0, 0.6), (0.3, 0.2), (0.3, -0.6), (-0.3, -0.6), (-0.3, 0.2)], 0.32, 0.38, 0.2), flat(rect(0.45, 0.4, 0, -0.1), 0.38, 0.62, 0.2)))
put('eboat_hull', U(flat([(0, 1.0), (0.5, 0.5), (0.5, -0.9), (-0.5, -0.9), (-0.5, 0.5)], 0.0, 0.36, 0.12)))
put('eboat_deck', U(flat(rect(0.6, 0.7, 0, -0.2), 0.36, 0.7, 0.15), seg((0, 0.75, -0.2), (0, 1.2, -0.2), 0.03, 0.03, 5)))
put('torpedo', U(seg((0, 0.1, -0.4), (0, 0.1, 0.4), 0.07, 0.07, 10), ball((0, 0.1, 0.4), 0.07, 8, 5)))
put('barrel', xform(tube((0, -0.25, 0), 0.2, 0.2, 0.5, 14), (0, 0.2, 0), rotm(rz=PI / 2)))
put('bullet', U(seg((0, 0.3, -0.18), (0, 0.3, 0.18), 0.035, 0.03, 6)))
put('missile', U(seg((0, 0.35, -0.3), (0, 0.35, 0.3), 0.05, 0.05, 8), xform(tube((0, 0, 0), 0.05, 0.0, 0.14, 8), (0, 0.35, 0.3), rotm(rx=PI / 2)),
                 flat([(-0.14, -0.3), (0.14, -0.3), (0, -0.12)], 0.34, 0.36)))
put('bomb', ellipsoid((0, 0, 0), (0.14, 0.14, 0.2), 10, 7))
put('oil', flat([(np.cos(a) * (0.55 + 0.12 * np.sin(a * 5)), np.sin(a) * (0.7 + 0.1 * np.cos(a * 3))) for a in np.linspace(0, 2 * PI, 25)[:-1]], 0.0, 0.006))
put('crater', U(flat([(np.cos(a) * 0.6, np.sin(a) * 0.6) for a in np.linspace(0, 2 * PI, 19)[:-1]], 0.0, 0.008), torus(0.6, 0.08, 18, 6, Rm=rotm(rx=PI / 2))))
put('shadow', flat([(np.cos(a) * 0.5, np.sin(a) * 0.5) for a in np.linspace(0, 2 * PI, 21)[:-1]], 0.0, 0.004))
# world pieces: unit slabs scaled per slice
put('road', flat(rect(1.0, 1.0), -0.02, 0.0))
put('curb', flat(rect(1.0, 1.0), 0.0, 0.06, 0.2))
put('water', flat(rect(1.0, 1.0), -0.08, -0.04))
put('bank', flat(rect(1.0, 1.0), -0.3, 0.02))
put('ground', flat(rect(1.0, 1.0), -0.15, -0.14))
put('rail', U(flat(rect(0.08, 1.0), 0.0, 0.35), flat(rect(0.16, 1.0), 0.32, 0.4)))
put('tree_trunk', tube((0, 0, 0), 0.1, 0.07, 0.7, 8))
put('tree_top', U(ellipsoid((0, 1.0, 0), (0.55, 0.6, 0.55), 12, 8), ellipsoid((0.2, 1.35, 0.1), (0.35, 0.35, 0.35), 10, 6)))
put('pine', U(tube((0, 0.4, 0), 0.5, 0.0, 1.3, 10), tube((0, 0.0, 0), 0.08, 0.08, 0.45, 6)))
put('bush', U(ellipsoid((0, 0.18, 0), (0.35, 0.25, 0.35), 10, 6), ellipsoid((0.25, 0.14, 0.12), (0.22, 0.18, 0.22), 8, 5)))
put('house_wall', U(flat(rect(3.0, 2.2), 0.0, 1.6, 0.03)))
put('house_roof', U(side([(-1.2, 1.6), (1.2, 1.6), (0, 2.5)], -1.6, 1.6)))
put('boathouse', U(flat(rect(0.4, 3.0, -2.2, 0), 0.0, 2.0), flat(rect(0.4, 3.0, 2.2, 0), 0.0, 2.0), side([(-1.5, 2.0), (1.5, 2.0), (0, 2.9)], -2.6, 2.6)))
for n, m in S.items(): save(n, m)
print(len(S), 'meshes')
