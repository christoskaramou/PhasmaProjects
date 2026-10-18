# Procedural meshes for Gauntlet Remix -> meshsrc/*.obj  (world: X across, Y up, Z north; figures face +Z)
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
S = {}
def put(n, m): S[n] = m
RXF = rotm(rx=PI / 2)
def flat(poly, y0, y1, b=0.0): return xform(slab(poly, -y1, -y0, b), (0, 0, 0), RXF)
def rect(w, d, cx=0, cz=0): return [(cx - w / 2, cz - d / 2), (cx + w / 2, cz - d / 2), (cx + w / 2, cz + d / 2), (cx - w / 2, cz + d / 2)]
def circ(r, n=16, cx=0, cz=0): return [(cx + np.cos(a) * r, cz + np.sin(a) * r) for a in np.linspace(0, 2 * PI, n + 1)[:-1]]
def cylY(c, r, h, n=16, r1=None): return tube(c, r, r if r1 is None else r1, h, n)
# ---------------------------------------------------------------- level tiles
put('wall', flat(rect(1.0, 1.0), 0.0, 1.0, 0.06))
put('floor', flat(rect(1.0, 1.0), -0.02, 0.0))
put('door', U(*[seg((x, 0.0, 0), (x, 0.9, 0), 0.05, 0.05, 8) for x in (-0.36, -0.12, 0.12, 0.36)],
               seg((-0.45, 0.15, 0), (0.45, 0.15, 0), 0.05, 0.05, 8), seg((-0.45, 0.75, 0), (0.45, 0.75, 0), 0.05, 0.05, 8)))
put('exit', U(flat(rect(0.86, 0.86), 0.0, 0.03, 0.1)))
put('exit_steps', U(*[flat(rect(0.7 - k * 0.12, 0.16, 0, -0.28 + k * 0.17), 0.03, 0.05 + 0.0 * k, 0.1) for k in range(4)]))
put('shadow', flat(circ(0.5, 20), 0.0, 0.004))
# trap / stun floor plates (textured), and the gold-rimmed frame that marks an "exit to level N"
put('trap_tile', flat(rect(0.9, 0.9), 0.0, 0.012, 0.05))
put('stun_tile', flat(rect(0.9, 0.9), 0.0, 0.012, 0.05))
put('exit_rim', U(flat(rect(1.0, 0.07, 0, 0.465), 0.0, 0.06, 0.02), flat(rect(1.0, 0.07, 0, -0.465), 0.0, 0.06, 0.02),
                 flat(rect(0.07, 0.86, 0.465, 0), 0.0, 0.06, 0.02), flat(rect(0.07, 0.86, -0.465, 0), 0.0, 0.06, 0.02),
                 *[ball((sx * 0.465, 0.07, sz * 0.465), 0.06, 8, 5) for sx in (1, -1) for sz in (1, -1)]))
# ---------------------------------------------------------------- items
put('key', U(torus(0.1, 0.03, 14, 6, c=(0, 0.3, -0.12)), seg((0, 0.3, -0.02), (0, 0.3, 0.22), 0.025, 0.025, 6), box((0.05, 0.3, 0.17), (0.08, 0.03, 0.04))))
put('food_plate', flat(circ(0.3, 20), 0.0, 0.03, 0.3))
put('food_ham', U(ellipsoid((0, 0.13, 0), (0.18, 0.11, 0.13), 14, 9), seg((0.15, 0.12, 0), (0.28, 0.14, 0), 0.03, 0.03, 6), ball((0.29, 0.14, 0), 0.04, 8, 5)))
put('potion', U(ellipsoid((0, 0.16, 0), (0.15, 0.15, 0.15), 14, 9), cylY((0, 0.27, 0), 0.05, 0.12, 10)))
put('potion_cork', cylY((0, 0.38, 0), 0.06, 0.05, 10))
put('chest', U(bbox((0, 0.14, 0), (0.5, 0.28, 0.34), 0.1)))
put('chest_lid', U(xform(tube((0, -0.25, 0), 0.17, 0.17, 0.5, 14), (0, 0.28, 0), rotm(rz=-PI / 2))))
put('chest_band', U(box((-0.15, 0.22, 0), (0.05, 0.46, 0.36)), box((0.15, 0.22, 0), (0.05, 0.46, 0.36))))
put('gen', U(flat(rect(0.86, 0.86), 0.0, 0.5, 0.15), flat(rect(0.6, 0.6), 0.5, 0.62, 0.2)))
put('gen_bones', U(*[seg((np.cos(a) * 0.25, 0.62, np.sin(a) * 0.25), (np.cos(a + 2) * 0.22, 0.66, np.sin(a + 2) * 0.22), 0.035, 0.03, 6) for a in (0.3, 1.5, 2.9, 4.4)],
                   ball((0, 0.72, 0), 0.12, 10, 7)))
# heroes and monsters: see gen_chars.py (rigged, multi-material)
# ---------------------------------------------------------------- projectiles
put('p_axe', U(flat([(0, 0.2), (0.17, 0.0), (0, -0.2), (-0.17, 0.0)], -0.03, 0.03, 0.2), seg((0, 0, -0.2), (0, 0, 0.2), 0.02, 0.02, 5)))
put('p_sword', U(flat([(0, 0.24), (0.04, -0.1), (-0.04, -0.1)], -0.015, 0.015), flat(rect(0.18, 0.04, 0, -0.12), -0.02, 0.02)))
put('p_fire', ellipsoid((0, 0, 0), (0.13, 0.13, 0.13), 12, 8))
put('p_arrow', U(seg((0, 0, -0.22), (0, 0, 0.18), 0.012, 0.012, 5), tube((0, 0.18, 0), 0.04, 0.0, 0.08, 6) if False else xform(tube((0, 0, 0), 0.04, 0.0, 0.08, 6), (0, 0, 0.18), rotm(rx=PI / 2))))
put('p_rock', ellipsoid((0, 0, 0), (0.1, 0.09, 0.1), 8, 6))
put('p_dfire', ellipsoid((0, 0, 0), (0.12, 0.12, 0.12), 10, 7))
for n, m in S.items(): save(n, m)
print(len(S), 'meshes')
