# Procedural meshes for Marble Madness Remix (marble, enemies, props) + the six courses (tools/courses.py)
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
S = {}
def put(n, m): S[n] = m
R = 0.45
put('marble', ellipsoid((0, 0, 0), (R, R, R), 28, 18))
put('steelie', ellipsoid((0, 0, 0), (R * 1.05, R * 1.05, R * 1.05), 24, 16))
put('shadow', xform(slab([(np.cos(a), np.sin(a)) for a in np.linspace(0, 2 * PI, 25)[:-1]], -0.005, 0.005), (0, 0, 0), rotm(rx=PI / 2)))
# marble muncher ("slinky"): stacked coils + a head with a mouth rim
put('mun_coil', U(*[torus(0.32 - 0.02 * k, 0.07, 18, 8, c=(0, 0.1 + k * 0.13, 0), Rm=rotm(rx=PI / 2)) for k in range(5)]))
put('mun_head', U(ellipsoid((0, 0.8, 0), (0.3, 0.22, 0.3), 16, 10)))
put('mun_eye', U(ball((0.12, 0.9, 0.22), 0.07, 8, 6), ball((-0.12, 0.9, 0.22), 0.07, 8, 6)))
# acid slime puddle (flattened blob)
g = np.random.default_rng(4); a = np.linspace(0, 2 * PI, 25)[:-1]; k = 1 + 0.18 * np.sin(3 * a + 1) + 0.1 * np.cos(5 * a)
put('acid', U(xform(slab([(0.85 * k[i] * np.cos(a[i]), 0.85 * k[i] * np.sin(a[i])) for i in range(len(a))], -0.06, 0.06, 0.5), (0, 0.06, 0), rotm(rx=PI / 2)),
              *[ellipsoid((x, 0.1, z), (0.22, 0.12, 0.22), 10, 6) for x, z in g.uniform(-0.45, 0.45, (4, 2))]))
# hammer: post + arm + mallet head
put('ham_post', U(box((0, 1.2, -1.1), (0.3, 2.4, 0.3)), box((0, 0.05, -1.1), (0.7, 0.1, 0.7))))
put('ham_head', U(xform(tube((0, -0.55, 0), 0.42, 0.42, 1.1, 20), (0, 0, 0), rotm(rz=PI / 2)), box((0, 0.0, -0.6), (0.14, 0.14, 1.2))))
# goal flag and pole, start chute ring
put('flag_pole', U(seg((0, 0, 0), (0, 2.6, 0), 0.05, 0.04, 8), ball((0, 2.65, 0), 0.08, 8, 6)))
put('flag_cloth', U(slab([(0.05, 1.9), (1.0, 2.15), (0.05, 2.45)], -0.015, 0.015)))
put('chute', U(torus(0.75, 0.12, 28, 8, c=(0, 0, 0), Rm=rotm(rx=PI / 2)), tube((0, 0.1, 0), 0.8, 0.8, 1.6, 24, caps=False)))
put('shard', U(slab([(0, 0.12), (0.1, -0.06), (-0.1, -0.06)], -0.02, 0.02)))
put('floor', xform(slab([(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)], 0.0, 0.01), (0, 0, 0), rotm(rx=PI / 2)))
for n, m in S.items(): save(n, m)
