# Procedural meshes for Bomberman Remix -> meshsrc/*.obj
# Ground = XZ plane (Y up). One grid cell = 2 units. Characters face +Z (toward the camera) at yaw 0.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
S = {}
def put(n, m): S[n] = m
def bx(c, s, b=0.0): return bbox(c, s, b) if b > 0 else box(c, s)
RZ = rotm(rx=PI / 2)          # slab extrusion along Z -> along Y

# ------------------------------------------------------------------ Bomberman (white helmet, pink face, blue suit)
# head pivot = neck (0, 1.0, 0)
put('bm_helmet', U(ellipsoid((0, 0.42, 0), (0.5, 0.46, 0.48), 26, 16)))
put('bm_face', U(ellipsoid((0, 0.38, 0.24), (0.38, 0.29, 0.31), 22, 12)))
put('bm_eye', U(ellipsoid((0.13, 0.42, 0.53), (0.055, 0.12, 0.04), 10, 8), ellipsoid((-0.13, 0.42, 0.53), (0.055, 0.12, 0.04), 10, 8)))
put('bm_antenna', U(seg((0, 0.84, 0), (0, 1.06, 0), 0.035, 0.03, 8)))
put('bm_knob', U(ball((0, 1.13, 0), 0.11, 12, 8)))
# body pivot = hips (0, 0.42, 0)
put('bm_body', U(ellipsoid((0, 0.3, 0), (0.36, 0.34, 0.3), 22, 12)))
put('bm_belt', U(seg((0, 0.05, 0), (0, 0.15, 0), 0.34, 0.34, 22), bx((0, 0.1, 0.33), (0.16, 0.12, 0.04))))
# arm pivot = shoulder, hangs -Y
put('bm_arm', U(seg((0, 0, 0), (0, -0.26, 0), 0.09, 0.08, 10)))
put('bm_glove', U(ball((0, -0.34, 0), 0.13, 12, 8)))
# leg pivot = hip joint (y 0.42), boots touch y=0
put('bm_leg', U(seg((0, 0, 0), (0, -0.25, 0), 0.1, 0.09, 10)))
put('bm_boot', U(ellipsoid((0, -0.32, 0.05), (0.15, 0.11, 0.2), 12, 8)))

# ------------------------------------------------------------------ bomb
put('bomb', U(ball((0, 0.62, 0), 0.62, 26, 16)))
put('bomb_cap', U(seg((0, 1.12, 0), (0, 1.3, 0), 0.16, 0.16, 12)))
put('bomb_fuse', U(seg((0, 1.28, 0), (0.08, 1.48, 0), 0.04, 0.035, 6), seg((0.08, 1.48, 0), (0.2, 1.56, 0), 0.035, 0.03, 6)))
put('bomb_shine', U(ellipsoid((-0.25, 0.95, 0.36), (0.12, 0.08, 0.05), 10, 6, R=rotm(rz=0.6))))

# ------------------------------------------------------------------ arena: floor, hard pillars, soft bricks, border, exit
put('floor', box((0, -0.25, 0), (1, 0.5, 1)))                       # scaled to the field; texture holds the checker
put('pillar', bbox((0, 0.65, 0), (1.96, 1.3, 1.96), 0.08))
put('pillar_top', bbox((0, 1.32, 0), (1.7, 0.08, 1.7), 0.2))
put('brick', bbox((0, 0.62, 0), (1.9, 1.24, 1.9), 0.04))
# brick debris chunk (centred, tumbles when a soft block breaks)
put('brick_chunk', bbox((0, 0, 0), (0.42, 0.3, 0.36), 0.12))
put('border', bbox((0, 1.0, 0), (1.98, 2.0, 1.98), 0.06))
put('door_frame', U(bx((-0.7, 0.75, 0), (0.25, 1.5, 0.5)), bx((0.7, 0.75, 0), (0.25, 1.5, 0.5)), bx((0, 1.55, 0), (1.65, 0.3, 0.55)),
                    bx((0, 0.04, 0.0), (1.9, 0.08, 1.9))))
put('door', U(bx((0, 0.72, -0.05), (1.15, 1.3, 0.12))))
put('door_light', U(bx((0, 0.72, 0.03), (0.9, 1.05, 0.04))))

# ------------------------------------------------------------------ explosion pieces (opaque, emissive)
put('fl_core', U(ball((0, 0.6, 0), 0.75, 20, 12)))
put('fl_arm', U(seg((0, 0.6, -1.0), (0, 0.6, 1.0), 0.48, 0.48, 16)))            # along Z, 2 units = one cell
put('fl_end', U(seg((0, 0.6, -1.0), (0, 0.6, 0.55), 0.48, 0.12, 16)))           # tip points +Z
put('fl_inner', U(seg((0, 0.6, -1.0), (0, 0.6, 1.0), 0.26, 0.26, 12)))
put('debris', U(bbox((0, 0, 0), (0.35, 0.22, 0.3), 0.15)))

# ------------------------------------------------------------------ power-up panels (top face carries the icon texture)
for k in ('bombs', 'fire', 'speed', 'wallpass', 'detonator', 'bombpass', 'flamepass', 'mystery'):
    put('pu_' + k, U(xform(slab([(-0.8, -0.8), (0.8, -0.8), (0.8, 0.8), (-0.8, 0.8)], -0.12, 0.12, 0.25), (0, 0.16, 0), rotm(rx=-PI / 2))))

# ------------------------------------------------------------------ enemies (one body mesh each -> own colour)
put('en_eye', U(ellipsoid((0.2, 0.0, 0), (0.13, 0.16, 0.08), 12, 8), ellipsoid((-0.2, 0.0, 0), (0.13, 0.16, 0.08), 12, 8)))
put('en_pupil', U(ball((0.2, 0.0, 0.06), 0.065, 8, 6), ball((-0.2, 0.0, 0.06), 0.065, 8, 6)))
put('en_ballom', U(ball((0, 0.85, 0), 0.72, 26, 16), seg((0, 0.1, 0), (0, 0.18, 0), 0.08, 0.14, 10)))                 # balloon
put('en_onil', U(ellipsoid((0, 0.7, 0), (0.66, 0.62, 0.62), 24, 14), seg((0, 1.2, 0), (0, 1.62, 0), 0.28, 0.0, 14)))    # onion drop
put('en_dahl', U(seg((0, 0.1, 0), (0, 1.35, 0), 0.6, 0.6, 22), torus(0.62, 0.06, 26, 6, c=(0, 0.45, 0), Rm=rotm(rx=PI / 2)),
                 torus(0.62, 0.06, 26, 6, c=(0, 1.05, 0), Rm=rotm(rx=PI / 2))))                                                # barrel
put('en_minvo', U(ball((0, 0.8, 0), 0.62, 24, 14),
                  *[seg((0.55 * np.cos(a), 0.8 + 0.55 * np.sin(a) * 0.9, 0), (0.95 * np.cos(a), 0.8 + 0.95 * np.sin(a) * 0.9, 0), 0.14, 0.0, 8)
                    for a in np.linspace(0, 2 * PI, 9)[:-1]]))                                                                 # spiky sun
put('en_doria', U(ellipsoid((0, 0.55, 0), (0.78, 0.55, 0.7), 24, 12), ellipsoid((0, 1.0, 0), (0.45, 0.35, 0.42), 18, 10)))  # blob
put('en_ovape', U(ellipsoid((0, 0.9, 0), (0.6, 0.62, 0.55), 22, 14), seg((0, 0.15, 0), (0, 0.9, 0), 0.62, 0.58, 22),
                  *[ball((0.45 * np.cos(a), 0.18, 0.45 * np.sin(a)), 0.2, 8, 6) for a in np.linspace(0, 2 * PI, 7)[:-1]]))   # ghost
put('en_pass', U(ellipsoid((0, 0.8, 0), (0.68, 0.6, 0.6), 24, 14), ball((0.48, 1.32, 0), 0.2, 10, 7), ball((-0.48, 1.32, 0), 0.2, 10, 7),
                 ellipsoid((0, 0.62, 0.48), (0.3, 0.2, 0.2), 14, 8)))                                                          # tiger head
put('en_pontan', U(xform(slab([(0.72 * np.cos(a), 0.72 * np.sin(a)) for a in np.linspace(0, 2 * PI, 33)[:-1]], -0.16, 0.16, 0.2), (0, 0.85, 0))))  # coin
put('en_stripe', U(*[xform(torus(0.62, 0.05, 24, 5, c=(0, 0, 0), Rm=None), (0, 0.85 + 0.25 * k, 0), rotm(rx=PI / 2 + 0.25)) for k in (-1, 0, 1)]))
put('shadow', U(xform(slab([(np.cos(a), np.sin(a)) for a in np.linspace(0, 2 * PI, 25)[:-1]], -0.01, 0.01), (0, 0, 0), rotm(rx=PI / 2))))
put('ring', torus(1.0, 0.05, 36, 6, Rm=rotm(rx=PI / 2)))

for n, m in S.items(): save(n, m)
