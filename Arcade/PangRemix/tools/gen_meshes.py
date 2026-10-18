# Procedural meshes for Pang Remix -> meshsrc/*.obj (cooked by cook_all.sh)
# Units: playfield is 48 x 26 units (floor y=0). Player faces +X, ~2.6 units tall. Thickness along Z.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
S = {}
def put(n, m): S[n] = m

# ------------------------------------------------------------------ player (safari hunter with harpoon gun)
# Modelled on the arcade sprite: big-headed explorer in a cream pith helmet, khaki safari shirt with chest pockets,
# khaki shorts, white socks, brown lace-up boots, olive backpack, harpoon gun. Pivots are unchanged (rig in 05_render).
HR = rotm(rx=PI / 2)                       # torus lying flat (axis = Y)
# head group pivot = neck (0, 1.95, 0); face looks along +X
put('pl_skin', U(ellipsoid((0.04, 0.36, 0), (0.34, 0.36, 0.33), 26, 16),            # head
                 ellipsoid((0.39, 0.32, 0), (0.07, 0.06, 0.065), 12, 8),           # nose
                 ellipsoid((0.0, 0.34, 0.33), (0.065, 0.095, 0.035), 10, 7),        # ears
                 ellipsoid((0.0, 0.34, -0.33), (0.065, 0.095, 0.035), 10, 7),
                 seg((0, -0.14, 0), (0, 0.1, 0), 0.13, 0.13, 14)))                 # neck
put('pl_eyew', U(ellipsoid((0.315, 0.42, 0.12), (0.045, 0.085, 0.065), 12, 8), ellipsoid((0.315, 0.42, -0.12), (0.045, 0.085, 0.065), 12, 8)))
put('pl_eye', U(ellipsoid((0.35, 0.42, 0.125), (0.025, 0.06, 0.042), 10, 6), ellipsoid((0.35, 0.42, -0.125), (0.025, 0.06, 0.042), 10, 6)))
put('pl_mouth', U(ellipsoid((0.345, 0.215, 0), (0.018, 0.02, 0.07), 12, 6)))
put('pl_hair', U(ellipsoid((-0.1, 0.34, 0), (0.26, 0.27, 0.315), 16, 10),
                 seg((0.33, 0.535, 0.06), (0.31, 0.55, 0.19), 0.022, 0.018, 8), seg((0.33, 0.535, -0.06), (0.31, 0.55, -0.19), 0.022, 0.018, 8)))
put('pl_helmet', U(ellipsoid((0, 0.6, 0), (0.39, 0.31, 0.38), 26, 14),                # dome
                   ellipsoid((0.02, 0.52, 0), (0.6, 0.05, 0.57), 30, 8),              # wide brim
                   ellipsoid((0.02, 0.5, 0), (0.56, 0.035, 0.53), 30, 6)))            # brim underside lip
put('pl_hband', U(torus(0.385, 0.045, 32, 6, c=(0, 0.565, 0), Rm=HR), ball((0, 0.905, 0), 0.055, 10, 7)))
# torso pivot = hips (0, 1.0, 0)
def sx(y, z=0.0, rx=0.33, cy=0.52, ry=0.5, rz=0.34):
    t = 1 - ((y - cy) / ry) ** 2 - (z / rz) ** 2
    return rx * np.sqrt(max(t, 0.0))
put('pl_shirt', U(ellipsoid((0, 0.52, 0), (0.33, 0.5, 0.34), 24, 16),
                  ball((0, 0.8, 0.29), 0.15, 12, 8), ball((0, 0.8, -0.29), 0.15, 12, 8),         # shoulders
                  *[xform(bbox((0, 0, 0), (0.05, 0.15, 0.15), 0.02), (0.21, 0.92, z), rotm(rx=-0.45 * np.sign(z), rz=-0.5)) for z in (0.1, -0.1)],  # collar
                  *[box((sx(0.6, z) + 0.005, 0.6, z), (0.04, 0.16, 0.13)) for z in (0.15, -0.15)]))  # chest pockets
put('pl_trim', U(*[box((sx(0.69, z) + 0.025, 0.69, z), (0.04, 0.05, 0.145)) for z in (0.15, -0.15)],   # pocket flaps
                 *[seg((sx(y0) - 0.005, y0, 0), (sx(y1) - 0.005, y1, 0), 0.026, 0.026, 8) for y0, y1 in ((0.22, 0.45), (0.45, 0.68), (0.68, 0.86))],  # placket
                 *[xform(bbox((0, 0, 0), (0.16, 0.05, 0.1), 0.02), (0, 0.9, z), None) for z in (0.29, -0.29)]))  # epaulettes
put('pl_button', U(*[ball((sx(y) + 0.02, y, 0), 0.03, 8, 6) for y in (0.32, 0.52, 0.72)],
                   *[ball((sx(0.69, z) + 0.05, 0.68, z), 0.022, 8, 6) for z in (0.15, -0.15)]))
put('pl_belt', U(seg((0, 0.05, 0), (0, 0.19, 0), 0.35, 0.35, 26)))
put('pl_buckle', U(bbox((0.35, 0.12, 0), (0.04, 0.13, 0.16), 0.2)))
put('pl_shorts', U(ellipsoid((0, 0.0, 0), (0.36, 0.25, 0.35), 22, 12)))
put('pl_pack', U(bbox((-0.4, 0.55, 0), (0.24, 0.58, 0.46), 0.25), bbox((-0.53, 0.42, 0), (0.06, 0.22, 0.3), 0.3)))
put('pl_packflap', U(bbox((-0.41, 0.8, 0), (0.28, 0.15, 0.48), 0.3)))
put('pl_strap', U(*[U(seg((-0.28, 0.86, z), (0.05, 0.98, z), 0.03, 0.03, 8), seg((0.05, 0.98, z), (sx(0.82, z) + 0.01, 0.82, z), 0.03, 0.03, 8),
                      seg((sx(0.82, z) + 0.01, 0.82, z), (sx(0.42, z) + 0.01, 0.42, z), 0.03, 0.03, 8)) for z in (0.17, -0.17)]))
# arm pivot = shoulder, hangs -Y
put('pl_sleeve', U(seg((0, 0.06, 0), (0.02, -0.3, 0), 0.15, 0.13, 14), torus(0.13, 0.04, 16, 6, c=(0.02, -0.29, 0), Rm=HR)))
put('pl_hand', U(seg((0.02, -0.3, 0), (0.04, -0.58, 0), 0.085, 0.075, 12), ellipsoid((0.05, -0.68, 0), (0.1, 0.12, 0.09), 12, 8),
                 ellipsoid((0.13, -0.63, 0), (0.04, 0.06, 0.04), 8, 6)))
# leg pivot = hip joint
put('pl_shortleg', U(seg((0, 0.04, 0), (0, -0.27, 0), 0.17, 0.165, 14), torus(0.165, 0.03, 16, 6, c=(0, -0.26, 0), Rm=HR)))
put('pl_leg', seg((0, -0.2, 0), (0, -0.52, 0), 0.115, 0.1, 12))
put('pl_sock', U(seg((0, -0.47, 0), (0, -0.64, 0), 0.11, 0.115, 12), torus(0.112, 0.03, 14, 6, c=(0, -0.48, 0), Rm=HR)))
put('pl_boot', U(seg((0, -0.6, 0), (0, -0.86, 0), 0.14, 0.145, 14), ellipsoid((0.1, -0.86, 0), (0.25, 0.11, 0.155), 16, 9)))
put('pl_sole', U(ellipsoid((0.09, -0.945, 0), (0.27, 0.04, 0.165), 16, 6)))
put('pl_lace', U(*[seg((0.13, y, -0.06), (0.13, y, 0.06), 0.014, 0.014, 6) for y in (-0.68, -0.74, -0.8)]))
# harpoon gun (held vertically, pivot at grip), muzzle up
put('pl_gun', U(seg((0, -0.1, 0), (0, 0.78, 0), 0.085, 0.078, 14), torus(0.095, 0.03, 16, 6, c=(0, 0.74, 0), Rm=HR),
                tube((0, 0.8, 0), 0.05, 0.0, 0.16, 10), seg((0.11, 0.2, 0), (0.11, 0.48, 0), 0.04, 0.04, 10),
                seg((0, 0.3, 0), (0.11, 0.3, 0), 0.02, 0.02, 6), seg((0, 0.42, 0), (0.11, 0.42, 0), 0.02, 0.02, 6)))
put('pl_gunwood', U(bbox((0, -0.05, 0), (0.18, 0.24, 0.18), 0.2), bbox((-0.02, -0.28, 0), (0.15, 0.26, 0.15), 0.25),
                    xform(bbox((0, 0, 0), (0.08, 0.2, 0.1), 0.2), (0.13, 0.0, 0), rotm(rz=0.3))))

# ------------------------------------------------------------------ balloons (one mesh per colour -> own material)
for c in ('red', 'blue', 'green', 'yellow', 'purple'):
    put('ball_' + c, ball((0, 0, 0), 1.0, 40, 26))
put('ball_shine', ellipsoid((-0.38, 0.42, 0.78), (0.2, 0.13, 0.05), 14, 8, R=rotm(rz=0.6)))
put('shadow', U(slab([(np.cos(a) , np.sin(a)) for a in np.linspace(0, 2 * PI, 33)[:-1]], -0.01, 0.01)))   # XY disc, rotated flat in game

# ------------------------------------------------------------------ harpoon wire (zig-zag along +Y, 1 unit), tip, vulcan shot
def zig(n=4, w=0.11, r=0.035):
    o = M(); pts = [(w * (1 if k % 2 else -1), k / n, 0) for k in range(n + 1)]
    for a, b in zip(pts[:-1], pts[1:]): o += seg(a, b, r, r, 8); o += ball(b, r, 8, 6)
    return o
put('wire', zig())
put('wire_tip', U(seg((0, 0, 0), (0, 0.55, 0), 0.2, 0.0, 14), seg((0, -0.25, 0), (0, 0.02, 0), 0.06, 0.06, 8)))
put('hook', U(seg((0, 0, 0), (0, 0.5, 0), 0.22, 0.0, 14), seg((-0.25, 0.1, 0), (0.25, 0.1, 0), 0.05, 0.05, 8)))
put('bullet', U(seg((0, -0.2, 0), (0, 0.25, 0), 0.09, 0.03, 10), ball((0, -0.2, 0), 0.09, 8, 6)))

# ------------------------------------------------------------------ blocks + frame + ladders (unit size, centred, scaled in game)
put('blk_steel', bbox((0, 0, 0), (1, 1, 1.2), 0.12))
for c in ('red', 'blue', 'yellow', 'green'):
    put('blk_glass_' + c, bbox((0, 0, 0), (1, 1, 1.2), 0.22))
put('frame', bbox((0, 0, 0), (1, 1, 1), 0.06))
put('floor', box((0, 0, 0), (1, 1, 1)))
# ladder rails stretch to the ladder height; rungs are separate unscaled pieces at a fixed pitch (placed in 03_stage)
put('ladder', U(seg((-0.5, 0, 0), (-0.5, 1.0, 0), 0.07, 0.07, 8), seg((0.5, 0, 0), (0.5, 1.0, 0), 0.07, 0.07, 8)))
put('rung', U(seg((-0.62, 0, 0), (0.62, 0, 0), 0.055, 0.055, 10)))
put('bg_plane', slab([(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)], -0.01, 0.0))

# ------------------------------------------------------------------ items (about 1 unit, base at y=0)
put('it_double', U(seg((-0.2, 0, 0), (-0.2, 0.6, 0), 0.05, 0.05, 8), seg((-0.2, 0.6, 0), (-0.2, 0.95, 0), 0.13, 0.0, 10),
                   seg((0.2, 0, 0), (0.2, 0.6, 0), 0.05, 0.05, 8), seg((0.2, 0.6, 0), (0.2, 0.95, 0), 0.13, 0.0, 10)))
put('it_power', U(seg((0, 0, 0), (0, 0.6, 0), 0.06, 0.06, 8), seg((0, 0.6, 0), (0, 0.98, 0), 0.18, 0.0, 12),
                  seg((-0.24, 0.66, 0), (0.24, 0.66, 0), 0.05, 0.05, 8)))
put('it_vulcan', U(bbox((0, 0.35, 0), (0.7, 0.3, 0.3), 0.2), seg((0.2, 0.35, 0), (0.62, 0.35, 0), 0.07, 0.07, 10), box((-0.15, 0.12, 0), (0.18, 0.3, 0.2))))
put('it_clock', U(seg((0, 0.45, -0.1), (0, 0.45, 0.1), 0.42, 0.42, 26, ) if False else xform(tube((0, 0, 0), 0.42, 0.42, 0.2, 26), (0, 0.45, -0.1), rotm(rx=PI / 2)),
                  ball((0, 0.92, 0), 0.08, 8, 6)))
put('it_hands', U(box((0, 0.6, 0.13), (0.05, 0.3, 0.03)), box((0.1, 0.45, 0.13), (0.22, 0.05, 0.03))))
put('it_hourglass', U(seg((0, 0.05, 0), (0, 0.45, 0), 0.3, 0.04, 16), seg((0, 0.45, 0), (0, 0.85, 0), 0.04, 0.3, 16)))
put('it_hg_frame', U(box((0, 0.03, 0), (0.7, 0.06, 0.7)), box((0, 0.87, 0), (0.7, 0.06, 0.7)),
                     seg((0.3, 0, 0.3), (0.3, 0.9, 0.3), 0.03, 0.03, 6), seg((-0.3, 0, -0.3), (-0.3, 0.9, -0.3), 0.03, 0.03, 6)))
put('it_dynamite', U(seg((-0.18, 0, 0), (-0.18, 0.7, 0), 0.12, 0.12, 12), seg((0.06, 0, 0), (0.06, 0.7, 0), 0.12, 0.12, 12),
                     seg((0.3, 0, 0), (0.3, 0.7, 0), 0.12, 0.12, 12)))
put('it_fuse', U(seg((0.06, 0.7, 0), (0.1, 0.95, 0), 0.025, 0.025, 6)))
put('it_shield', U(torus(0.36, 0.08, 30, 8, c=(0, 0.45, 0)), ball((0, 0.45, 0), 0.18, 12, 8)))
put('it_life', U(ellipsoid((0, 0.3, 0), (0.36, 0.25, 0.34), 18, 10), ellipsoid((0, 0.22, 0), (0.55, 0.05, 0.52), 22, 6)))
put('fr_cherry', U(ball((-0.18, 0.2, 0), 0.2, 12, 8), ball((0.2, 0.22, 0), 0.2, 12, 8)))
put('fr_stem', U(seg((-0.18, 0.38, 0), (0.0, 0.85, 0), 0.025, 0.02, 6), seg((0.2, 0.4, 0), (0.0, 0.85, 0), 0.025, 0.02, 6),
                 ellipsoid((0.12, 0.86, 0), (0.16, 0.05, 0.08), 10, 6)))
put('fr_apple', U(ellipsoid((0, 0.36, 0), (0.36, 0.34, 0.36), 18, 12)))
put('fr_grape', U(*[ball((x, y, 0), 0.12, 10, 7) for x, y in ((-0.2, 0.6), (0, 0.62), (0.2, 0.6), (-0.1, 0.42), (0.1, 0.42), (0, 0.24))]))
put('shield_ring', torus(1.0, 0.05, 40, 8))
put('pop_ring', torus(1.0, 0.04, 40, 6))

# ------------------------------------------------------------------ animals: crab (walks the floor), bird (flies)
put('cr_body', U(ellipsoid((0, 0.45, 0), (0.6, 0.32, 0.42), 20, 12)))
put('cr_claw', U(ellipsoid((0.75, 0.6, 0.25), (0.25, 0.17, 0.14), 12, 8), ellipsoid((-0.75, 0.6, 0.25), (0.25, 0.17, 0.14), 12, 8),
                 seg((0.45, 0.5, 0.15), (0.65, 0.58, 0.22), 0.06, 0.06, 6), seg((-0.45, 0.5, 0.15), (-0.65, 0.58, 0.22), 0.06, 0.06, 6)))
put('cr_legs', U(*[seg((s * 0.4, 0.38, z), (s * 0.75, 0.0, z * 1.4), 0.045, 0.035, 6) for s in (1, -1) for z in (-0.22, 0, 0.22)]))
put('cr_eye', U(ball((0.17, 0.85, 0.3), 0.08, 8, 6), ball((-0.17, 0.85, 0.3), 0.08, 8, 6),
                seg((0.15, 0.65, 0.3), (0.17, 0.82, 0.3), 0.03, 0.03, 6), seg((-0.15, 0.65, 0.3), (-0.17, 0.82, 0.3), 0.03, 0.03, 6)))
put('bd_body', U(ellipsoid((0, 0, 0), (0.55, 0.32, 0.3), 18, 10), ball((0.5, 0.18, 0), 0.22, 12, 8)))
put('bd_beak', U(seg((0.68, 0.16, 0), (0.95, 0.12, 0), 0.07, 0.0, 8)))
put('bd_wing', U(slab([(-0.3, 0), (0.3, 0), (0.15, 0.03), (-0.2, 0.03)], -0.02, 0.02) if False else
                 xform(slab([(-0.3, 0.0), (0.3, 0.0), (0.1, 0.9), (-0.25, 0.75)], -0.03, 0.03), (0, 0, 0), rotm(rx=PI / 2))))

for n, m in S.items(): save(n, m)
