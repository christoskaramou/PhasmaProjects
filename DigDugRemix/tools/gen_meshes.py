# Procedural meshes for Dig Dug Remix -> meshsrc/*.obj (cooked by cook_all.sh)
# Playfield = XY plane (side view), camera looks down -Z, characters face +X, 1 tile = 2 units.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *

# ---------------- digger (white suit, blue trim, glowing visor, pump gun)
def digger():
    suit = U(ellipsoid((0, -0.05, 0), (0.4, 0.46, 0.36), 28, 18),
             tube((-0.16, -0.85, 0), 0.13, 0.15, 0.45), tube((0.16, -0.85, 0), 0.13, 0.15, 0.45),
             tube((0.05, 0.12, 0.32), 0.1, 0.11, 0.42, R=rotm(rz=-1.35)),        # arm reaching forward (to gun)
             tube((0.0, 0.12, -0.32), 0.1, 0.11, 0.4, R=rotm(rz=-1.1)),
             ellipsoid((-0.36, -0.02, 0), (0.16, 0.3, 0.24), 16, 10))           # backpack
    trim = U(superq((0, 0.55, 0), (0.42, 0.4, 0.42), 0.75, 32, 20),                # helmet
             tube((0, 0.88, 0), 0.03, 0.02, 0.32), ellipsoid((0, 1.22, 0), (0.07, 0.07, 0.07), 10, 8),
             torus(0.41, 0.06, 40, 8, c=(0, -0.3, 0), Rm=rotm(rx=PI / 2)),         # belt
             superq((-0.13, -0.92, 0), (0.17, 0.09, 0.17), 0.5, 16, 10), superq((0.22, -0.92, 0), (0.2, 0.09, 0.17), 0.5, 16, 10),
             ellipsoid((0.43, 0.12, 0.32), (0.11, 0.11, 0.11), 12, 8))            # glove
    visor = U(ellipsoid((0.16, 0.55, 0.0), (0.3, 0.24, 0.34), 28, 16))
    gun = U(tube((0.36, 0.1, 0.3), 0.07, 0.07, 0.62, R=rotm(rz=-PI / 2)), tube((0.36, 0.1, 0.3), 0.12, 0.1, 0.2, R=rotm(rz=-PI / 2)),
            tube((0.97, 0.1, 0.3), 0.09, 0.03, 0.14, R=rotm(rz=-PI / 2)), tube((0.36, 0.1, 0.3), 0.05, 0.05, 0.3))
    save('dig_suit', suit); save('dig_trim', trim); save('dig_visor', visor); save('dig_gun', gun)
digger()

# ---------------- Pooka (red balloon body, yellow goggles with white rims, little feet)
def pooka():
    body = superq((0, 0, 0), (0.72, 0.7, 0.62), 0.92, 40, 26)
    lens = U(ellipsoid((0.5, 0.18, 0.3), (0.16, 0.2, 0.17), 18, 12), ellipsoid((0.38, 0.18, 0.5), (0.15, 0.19, 0.16), 18, 12))
    rim = U(torus(0.19, 0.045, 28, 8, c=(0.5, 0.18, 0.3), Rm=rotm(ry=PI / 2 - 0.55)), torus(0.18, 0.045, 28, 8, c=(0.38, 0.18, 0.5), Rm=rotm(ry=PI / 2 - 1.0)),
            torus(0.62, 0.035, 48, 6, c=(0, 0.18, 0), Rm=rotm(rx=PI / 2)))   # goggle strap
    feet = U(superq((-0.25, -0.68, 0.1), (0.2, 0.1, 0.18), 0.6, 14, 8), superq((0.28, -0.68, 0.1), (0.22, 0.1, 0.18), 0.6, 14, 8))
    save('pooka_body', body); save('pooka_lens', lens); save('pooka_rim', rim); save('pooka_feet', feet)
pooka()

# ---------------- Fygar (green dragon: long body, snout, back wings, eyes, belly, claws)
def fygar():
    body = U(superq((-0.05, 0, 0), (0.72, 0.55, 0.5), 0.85, 36, 22), superq((0.62, 0.12, 0), (0.42, 0.3, 0.32), 0.8, 26, 16),
             tube((-0.7, -0.15, 0), 0.22, 0.02, 0.6, R=rotm(rz=PI / 2 + 0.5)))     # tail
    belly = U(superq((0.05, -0.2, 0.18), (0.5, 0.3, 0.36), 0.9, 24, 14), superq((0.75, 0.0, 0.08), (0.3, 0.12, 0.25), 0.8, 16, 10))
    wing = U(slab([(-0.3, 0.35), (-0.05, 0.95), (0.05, 0.75), (0.2, 0.9), (0.25, 0.4)], -0.04, 0.04, 0.1))
    eye = U(ellipsoid((0.62, 0.36, 0.22), (0.12, 0.14, 0.1), 16, 10))
    pupil = U(ellipsoid((0.7, 0.37, 0.29), (0.05, 0.08, 0.05), 10, 8))
    feet = U(superq((-0.35, -0.55, 0.15), (0.2, 0.12, 0.16), 0.6, 14, 8), superq((0.3, -0.55, 0.15), (0.2, 0.12, 0.16), 0.6, 14, 8),
             tube((0.95, 0.2, 0.12), 0.05, 0.0, 0.18, R=rotm(rz=-0.6)), tube((0.95, 0.2, -0.12), 0.05, 0.0, 0.18, R=rotm(rz=-0.6)))
    save('fygar_body', body); save('fygar_belly', belly); save('fygar_wing', wing); save('fygar_eye', eye); save('fygar_pupil', pupil); save('fygar_feet', feet)
fygar()

# ---------------- world pieces
for v in range(3):
    save(f'dirt{v}', roundbox((0.53, 0.53, 0.55), 0.17, 7, noise=0.035, seed=v + 1))
save('pebble', superq((0, 0, 0), (0.5, 0.36, 0.4), 0.7, 12, 8, noise=0.12, seed=9))
save('rock', superq((0, 0, 0), (0.95, 0.85, 0.8), 0.7, 40, 26, noise=0.09, seed=4))
save('rock_crack', U(*[tube((0.0, -0.1 + 0.25 * k, 0.6), 0.025, 0.015, 0.5, R=rotm(rz=0.6 * (-1) ** k, rx=0.2)) for k in range(3)]))
save('shard', slab([(0, 0.5), (-0.4, -0.3), (0.45, -0.25)], -0.12, 0.12, 0.2))
save('ring', torus(1.0, 0.05, 64, 8))
save('orb', ellipsoid((0, 0, 0), (0.5, 0.5, 0.5), 20, 12))
# harpoon: hose segment along +X (0..1) + arrow tip
save('hose', tube((0, 0, 0), 0.07, 0.07, 1.0, n=12, R=rotm(rz=-PI / 2), caps=False))
save('harpoon', U(tube((0, 0, 0), 0.16, 0.0, 0.4, n=16, R=rotm(rz=-PI / 2)), tube((-0.15, 0, 0), 0.09, 0.09, 0.16, n=12, R=rotm(rz=-PI / 2)),
                  tube((0.05, 0.0, 0), 0.03, 0.0, 0.3, n=6, R=rotm(rz=-PI / 2 - 2.4)), tube((0.05, 0.0, 0), 0.03, 0.0, 0.3, n=6, R=rotm(rz=-PI / 2 + 2.4))))
# fygar flame: teardrop along +X (0..1)
save('flame', U(ellipsoid((0.5, 0, 0), (0.55, 0.28, 0.28), 24, 14)))
save('flame_core', U(ellipsoid((0.4, 0, 0), (0.45, 0.14, 0.14), 18, 10)))
# surface flower
save('fl_stem', U(tube((0, 0, 0), 0.05, 0.04, 0.9, n=10), slab([(0, 0.35), (0.35, 0.55), (0.45, 0.45), (0.05, 0.3)], -0.03, 0.03, 0.1)))
save('fl_petal', U(*[ellipsoid((0.22 * np.cos(a), 0.95 + 0.22 * np.sin(a), 0), (0.17, 0.1, 0.06), 12, 8, R=rotm(rz=a)) for a in np.linspace(0, 2 * PI, 7)[:-1]]))
save('fl_center', ellipsoid((0, 0.95, 0.04), (0.11, 0.11, 0.08), 14, 10))
save('grass', U(*[tube((x, 0, z), 0.05, 0.0, h, n=5, R=rotm(rz=t)) for x, z, h, t in
                   [(-0.4, 0.1, 0.5, 0.2), (-0.2, -0.1, 0.7, -0.1), (0, 0.15, 0.55, 0.15), (0.2, 0, 0.75, -0.2), (0.4, -0.1, 0.5, 0.1), (-0.05, -0.2, 0.6, 0.0)]]))
# bonus vegetables: carrot, mushroom
save('carrot', U(tube((0, -0.6, 0), 0.02, 0.32, 1.1, n=20)))
save('carrot_top', U(*[ellipsoid((0.12 * np.sin(a), 0.75, 0.1 * np.cos(a)), (0.08, 0.3, 0.05), 10, 8, R=rotm(rz=0.4 * np.sin(a))) for a in np.linspace(0, 2 * PI, 6)[:-1]]))
save('mush_cap', superq((0, 0.25, 0), (0.6, 0.35, 0.6), 0.8, 28, 14, flat_back=None))
save('mush_stem', tube((0, -0.45, 0), 0.22, 0.18, 0.6, n=18))
save('heart', U(ellipsoid((-0.18, 0.1, 0), (0.25, 0.25, 0.15), 14, 10), ellipsoid((0.18, 0.1, 0), (0.25, 0.25, 0.15), 14, 10),
                slab([(-0.42, 0.05), (0.42, 0.05), (0, -0.45)], -0.13, 0.13, 0.1)))

def gem():
    m = M(); n = 6; top = np.array([0, 0.55, 0]); bot = np.array([0, -0.55, 0])
    ring = [np.array([0.32 * np.cos(2 * PI * i / n), 0.05, 0.32 * np.sin(2 * PI * i / n)]) for i in range(n)]
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        for tri in ((top, a, b), (bot, b, a)):
            fn = np.cross(tri[1] - tri[0], tri[2] - tri[0]); fn /= np.linalg.norm(fn)
            if np.dot(fn, sum(tri) / 3) < 0: fn = -fn
            m.add(list(tri), [fn] * 3, [(0, 0), (1, 0), (0, 1)], [(0, 1, 2)])
    return m
save('gem', gem())
