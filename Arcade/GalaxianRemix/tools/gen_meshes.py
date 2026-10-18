# Procedural meshes for Galaxian Remix -> meshsrc/*.obj
# World: X across the field, Y up toward the camera, Z up the screen. The Galaxip faces +Z; aliens are modelled facing
# +Z as well and the game turns them to face down the screen.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import *
S = {}
def put(n, m): S[n] = m
RXF = rotm(rx=PI / 2)
def flat(poly, y0, y1, b=0.0): return xform(slab(poly, -y1, -y0, b), (0, 0, 0), RXF)   # poly in (x, z), thickness along Y
def mirror(poly): return [(-x, z) for x, z in reversed(poly)]
def wings(poly, y0, y1, b=0.2): return U(flat(poly, y0, y1, b), flat(mirror(poly), y0, y1, b))

# ---- Galaxip (the player's ship): white hull, red wing panels, blue canopy, twin rear engines
put('gx_body', U(flat([(0, 0.62), (0.13, 0.3), (0.16, -0.38), (-0.16, -0.38), (-0.13, 0.3)], -0.08, 0.14, 0.25),
                 wings([(0.14, 0.05), (0.55, -0.18), (0.58, -0.42), (0.15, -0.36)], -0.03, 0.06, 0.2),
                 seg((0.56, 0.0, -0.45), (0.56, 0.0, 0.05), 0.035, 0.03, 8), seg((-0.56, 0.0, -0.45), (-0.56, 0.0, 0.05), 0.035, 0.03, 8)))
put('gx_accent', U(wings([(0.2, -0.04), (0.47, -0.2), (0.49, -0.34), (0.21, -0.3)], 0.06, 0.08, 0.15),
                   flat([(0, 0.6), (0.05, 0.45), (-0.05, 0.45)], 0.14, 0.16)))
put('gx_glass', ellipsoid((0, 0.13, 0.12), (0.09, 0.08, 0.17), 12, 8))
put('gx_engine', U(seg((0.1, 0.02, -0.36), (0.1, 0.02, -0.44), 0.06, 0.05, 10), seg((-0.1, 0.02, -0.36), (-0.1, 0.02, -0.44), 0.06, 0.05, 10)))
# the missile that sits on the nose until fired, and in flight
put('pshot', U(seg((0, 0, -0.18), (0, 0, 0.14), 0.035, 0.035, 8), xform(tube((0, 0, 0), 0.035, 0.0, 0.1, 8), (0, 0, 0.14), rotm(rx=PI / 2))))
# ---- aliens: body, wings (scaled to flap), eyes. Sizes roughly 1.0 wide.
def bug(L, Wd, head, tail=0.0):
    b = U(ellipsoid((0, 0.06, -0.05), (Wd * 0.28, 0.16, L * 0.36), 14, 9),
          ball((0, 0.08, L * 0.32), head, 12, 8),
          seg((0.06, 0.05, L * 0.42), (0.16, 0.05, L * 0.62), 0.025, 0.012, 6), seg((-0.06, 0.05, L * 0.42), (-0.16, 0.05, L * 0.62), 0.025, 0.012, 6))
    if tail > 0: b = U(b, xform(tube((0, 0, 0), 0.07, 0.0, tail, 10), (0, 0.04, -L * 0.36), rotm(rx=-PI / 2)))
    return b
def eyes(L, head, r=0.05): return U(ball((0.07, 0.14, L * 0.32 + head * 0.55), r, 8, 6), ball((-0.07, 0.14, L * 0.32 + head * 0.55), r, 8, 6))
# drone (blue): simple bug with rounded wings
put('drone_body', bug(0.8, 1.0, 0.13)); put('drone_eye', eyes(0.8, 0.13))
put('drone_wing', wings([(0.12, 0.1), (0.42, 0.22), (0.52, 0.0), (0.44, -0.2), (0.14, -0.15)], 0.02, 0.06))
# emissary (purple): rounder body, wider swept wings
put('purple_body', bug(0.82, 1.15, 0.14)); put('purple_eye', eyes(0.82, 0.14))
put('purple_wing', wings([(0.14, 0.12), (0.5, 0.3), (0.6, 0.02), (0.5, -0.22), (0.16, -0.16)], 0.02, 0.06))
# hornet (red escort): pointed tail and sharp wings
put('red_body', bug(0.86, 1.05, 0.13, 0.22)); put('red_eye', eyes(0.86, 0.13))
put('red_wing', wings([(0.12, 0.14), (0.58, 0.32), (0.5, 0.02), (0.56, -0.24), (0.14, -0.12)], 0.02, 0.06))
# flagship (yellow body, red wings, crest)
put('flag_body', U(bug(1.0, 1.3, 0.17), flat([(0, 0.58), (0.1, 0.4), (0, 0.3), (-0.1, 0.4)], 0.18, 0.26, 0.2)))
put('flag_eye', eyes(1.0, 0.17, 0.06))
put('flag_wing', wings([(0.16, 0.16), (0.6, 0.42), (0.74, 0.1), (0.64, -0.26), (0.18, -0.2)], 0.02, 0.07))
# alien bomb: a short glowing dart
put('bomb', U(seg((0, 0, -0.16), (0, 0, 0.12), 0.05, 0.03, 8), ball((0, 0, -0.16), 0.05, 8, 5)))
# wave flag and reserve-ship markers (bottom of the field)
put('wflag_pole', seg((0, 0, -0.3), (0, 0, 0.3), 0.02, 0.02, 6))
put('wflag_cloth', flat([(0.0, 0.3), (0.32, 0.18), (0.0, 0.06)], -0.015, 0.015))
# background: planet and stars (separate meshes per star colour so each keeps its own material)
put('planet', ellipsoid((0, 0, 0), (1, 1, 1), 48, 28))
put('planet_ring', torus(1.7, 0.25, 96, 12, Rm=rotm(rx=PI / 2)))
for c in ('w', 'b', 'y', 'r'): put('star_' + c, ball((0, 0, 0), 0.05, 6, 4))
put('field_line', flat(rect(1.0, 1.0) if False else [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)], -0.01, 0.0))
for n, m in S.items(): save(n, m)
print(len(S), 'meshes')
