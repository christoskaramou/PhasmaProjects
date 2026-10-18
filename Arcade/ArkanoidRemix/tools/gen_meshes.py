# Procedural meshes for Arkanoid Remix -> meshsrc/*.obj  (world: X across, Y up, Z up the field)
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
S = {}
def put(n, m): S[n] = m
RXF = rotm(rx=PI / 2)
def flat(poly, y0, y1, b=0.0): return xform(slab(poly, -y1, -y0, b), (0, 0, 0), RXF)
def rect(w, d): return [(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)]
def xcyl(c, r, l, n=20): return xform(tube((0, -l / 2, 0), r, r, l, n), c, rotm(rz=-PI / 2))
# bricks: one template per colour (material per mesh); bevelled top so each brick reads as a block
for c in ['W', 'O', 'C', 'G', 'R', 'B', 'P', 'Y', 'S', 'X']:
    put('brick_' + c, flat(rect(0.94, 0.44), 0.0, 0.36, 0.14))
# Vaus: silver hull with red end caps and blue light strip; laser cannons
put('vaus_mid', xcyl((0, 0.22, 0), 0.2, 1.0, 24))
put('vaus_strip', xcyl((0, 0.22, 0), 0.206, 0.5, 24))
put('vaus_cap', U(xcyl((0.06, 0.22, 0), 0.215, 0.12, 24), ellipsoid((0.12, 0.22, 0), (0.12, 0.2, 0.2), 16, 10)))
put('vaus_gun', U(seg((0, 0.3, -0.05), (0, 0.3, 0.32), 0.07, 0.05, 10), ball((0, 0.3, -0.05), 0.08, 10, 7)))
put('ball', ball((0, 0, 0), 0.15, 20, 14))
put('shadow', flat([(np.cos(a) * 0.5, np.sin(a) * 0.5) for a in np.linspace(0, 2 * PI, 25)[:-1]], 0.0, 0.004))
# capsules: coloured pill + a letter label on top, one pair per kind
for k in 'SCLEDBP':
    put('cap_' + k, U(xcyl((0, 0.2, 0), 0.16, 0.42, 20), ball((-0.21, 0.2, 0), 0.16, 14, 9), ball((0.21, 0.2, 0), 0.16, 14, 9)))
    q = M(); q.add([np.array(p, float) for p in [(-0.2, 0.365, -0.1), (0.2, 0.365, -0.1), (0.2, 0.365, 0.1), (-0.2, 0.365, 0.1)]],
                  [np.array((0, 1.0, 0))] * 4, [(1, 1), (0, 1), (0, 0), (1, 0)], [(0, 2, 1), (0, 3, 2)])
    put('lbl_' + k, q)
# frame: side pipes, top bar, enemy gates, corner blocks
put('wall_side', U(xform(tube((0, -0.5, 0), 0.32, 0.32, 1.0, 20), (0, 0.32, 0), RXF)))
put('wall_top', xcyl((0, 0.32, 0), 0.32, 1.0, 20))
put('wall_ring', U(*[xform(torus(0.36, 0.06, 20, 6), (0, 0.32, z), rotm(rx=0)) for z in (-0.5, 0.0, 0.5)]))
put('gate', U(flat(rect(1.6, 0.5), 0.0, 0.5, 0.2)))
put('gate_door', flat(rect(1.2, 0.3), 0.5, 0.56, 0.1))
put('corner', U(flat(rect(0.9, 0.9), 0.0, 0.7, 0.25)))
# corner elbow: a quarter-torus bend (bend radius ER) that joins a side pipe coming up from -Z to the top bar
# coming in from -X; the corner point of the two pipe centrelines is the origin. A second rotation covers the other corner.
ER = 0.7
def elbow(R=ER, r=0.32, na=18, nb=20):
    m = M(); V, N, UV, F = [], [], [], []
    O = np.array([-R, 0.32, -R])
    for i in range(na + 1):
        a = (PI / 2) * i / na
        u = np.array([np.cos(a), 0, np.sin(a)]); c = O + R * u
        for j in range(nb + 1):
            b = 2 * PI * j / nb
            n = np.cos(b) * u + np.sin(b) * np.array([0, 1.0, 0])
            V.append(c + r * n); N.append(n); UV.append((i / na, j / nb))
    for i in range(na):
        for j in range(nb):
            a0 = i * (nb + 1) + j; a1 = a0 + 1; b0 = a0 + nb + 1; b1 = b0 + 1
            F += [(a0, b0, b1), (a0, b1, a1)]
    m.add(V, N, UV, F); return m
put('wall_elbow', elbow())
# collar rings where the elbow meets each straight pipe
put('elbow_collar', U(xform(torus(0.36, 0.06, 20, 6), (0, 0.32, -ER), rotm(rx=0)), xform(torus(0.36, 0.06, 20, 6), (-ER, 0.32, 0), rotm(ry=PI / 2))))
put('warp', flat(rect(0.4, 1.4), 0.0, 0.5, 0.2))
put('floor', flat(rect(1, 1), -0.02, 0.0))
# enemies (drift down from the gates): cone, pyramid, molecule, cube
put('en_cone', U(tube((0, 0.0, 0), 0.26, 0.0, 0.5, 18), torus(0.24, 0.05, 18, 6, c=(0, 0.04, 0), Rm=rotm(rx=PI / 2))))
put('en_pyr', U(flat([(0, 0.3), (0.28, -0.18), (-0.28, -0.18)], 0.0, 0.5, 0.9)))
put('en_orb', U(ball((0, 0.25, 0), 0.16, 12, 8), ball((0.2, 0.2, 0.08), 0.12, 10, 7), ball((-0.16, 0.22, -0.12), 0.12, 10, 7), ball((0.02, 0.42, -0.08), 0.1, 10, 7)))
put('en_cube', bbox((0, 0.25, 0), (0.4, 0.4, 0.4), 0.2))
put('debris', bbox((0, 0, 0), (0.12, 0.08, 0.1), 0.2))
put('laser', U(seg((0, 0.3, -0.25), (0, 0.3, 0.25), 0.04, 0.04, 8)))
# DOH: a giant stone moai relief lying in the field, separate dark eyes and mouth
head = [(-1.6, 2.6), (1.6, 2.6), (1.9, 1.2), (1.8, -0.8), (1.3, -2.4), (0.6, -2.9), (-0.6, -2.9), (-1.3, -2.4), (-1.8, -0.8), (-1.9, 1.2)]
put('doh_head', flat(head, 0.0, 0.9, 0.12))
put('doh_brow', flat([(-1.5, 1.7), (1.5, 1.7), (1.5, 1.3), (-1.5, 1.3)], 0.9, 1.05, 0.2))
put('doh_nose', flat([(0, 1.2), (0.45, -0.9), (-0.45, -0.9)], 0.9, 1.25, 0.3))
put('doh_eye', U(flat([(-1.25, 1.2), (-0.35, 1.2), (-0.45, 0.65), (-1.15, 0.65)], 0.9, 0.96, 0.05), flat([(0.35, 1.2), (1.25, 1.2), (1.15, 0.65), (0.45, 0.65)], 0.9, 0.96, 0.05)))
put('doh_mouth', flat([(-0.8, -1.6), (0.8, -1.6), (0.65, -2.1), (-0.65, -2.1)], 0.9, 0.96, 0.05))
put('doh_shot', U(ellipsoid((0, 0.35, 0), (0.14, 0.14, 0.22), 12, 8)))
for n, m in S.items(): save(n, m)
print(len(S), 'meshes')
