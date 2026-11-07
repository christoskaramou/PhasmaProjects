"""Numbers shared by Kite Hill's tools (the Blender backdrop, the meshes and scene). Plain Python (no numpy), so
Blender's own interpreter can import it too.

Field coordinates: x right, y away from the camera, h up. Engine (x, y, z) = (x, h, -y); Blender (x, y, z) = (x, y, h).
The ground and the camera must match Assets/Scripts/kitehill_rules.lua (R.HILLS, R.BASE) and
kitehill_world.lua (W.CAM, W.SUN, W.MILL), or the 3D actors will not sit on the pictured hills.
"""
import math
import random

CAM_POS, CAM_LOOK, VFOV = (0.0, 4.0, 14.0), (0.0, 6.5, -20.0), 42.0      # engine axes
BACK_D, BACK_ASPECT = 400.0, 3456 / 1440
SUN_DIR = (-0.55, 0.62, 0.50)        # engine axes, toward the sun (up to the left, behind the camera)
PLANE_Y = 12.0

BASE = -0.6
HILLS = [
    (-6, -12, 1.6, 14, 9), (14, -6, 1.4, 9, 7),
    (-16, 26, 3.0, 12, 10), (6, 31, 2.6, 14, 9), (25, 22, 2.4, 10, 9),
    (-8, 48, 6.0, 16, 12), (17, 50, 7.0, 12, 12),
    (-40, 90, 14, 30, 20), (20, 112, 16, 40, 25), (62, 82, 12, 25, 20),
    (-75, 60, 9, 22, 18),
]


def ground(x, y):
    g = BASE
    for cx, cy, a, sx, sy in HILLS:
        dx, dy = (x - cx) / sx, (y - cy) / sy
        g += a * math.exp(-(dx * dx + dy * dy))
    return g


def sun():
    L = math.sqrt(sum(c * c for c in SUN_DIR))
    return tuple(c / L for c in SUN_DIR)


# The windmill on its hill: tower base (field), height, facing (field radians, the way its sails look).
MILL_X, MILL_Y = 18.0, 50.0
MILL_H = 7.2
MILL_FACE = math.radians(-90 - 28)     # toward the camera, turned a little to the left
MILL_BASE = ground(MILL_X, MILL_Y)


def mill_hub():
    """Field point of the sails' hub, in front of the cap."""
    fx, fy = math.cos(MILL_FACE), math.sin(MILL_FACE)
    return (MILL_X + fx * 1.75, MILL_Y + fy * 1.75, MILL_BASE + MILL_H + 0.55)


def path_points():
    """Centre line of the footpath from below the camera to the village: (x, y, width)."""
    pts = []
    for i in range(0, 61):
        t = i / 60
        y = -16 + t * 58
        x = 1.0 + 2.2 * math.sin(t * 5.0) - 6.0 * t * t
        w = 1.8 - 1.0 * t
        pts.append((x, y, w))
    return pts


def village(seed=4):
    """Whitewashed houses on the village hill and a few by the windmill: (x, y, w, d, h, yaw, roof)."""
    rnd = random.Random(seed)
    spots = []
    zones = [(-21, 6, 40, 56, 16), (5, 13, 44, 52, 4), (24, 31, 46, 55, 3), (-30, -22, 34, 44, 3)]
    for x0, x1, y0, y1, n in zones:
        made = 0
        for _ in range(600):
            if made >= n:
                break
            x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
            w, d = rnd.uniform(2.6, 3.8), rnd.uniform(2.4, 3.2)
            if any((x - s[0]) ** 2 + (y - s[1]) ** 2 < (max(w, d) / 2 + max(s[2], s[3]) / 2 + 0.8) ** 2 for s in spots):
                continue
            if (x - MILL_X) ** 2 + (y - MILL_Y) ** 2 < 5.5 ** 2:
                continue
            h = rnd.choice((2.4, 2.6, 2.8, 3.6))
            yaw = rnd.uniform(-12, 12) + rnd.choice((0, 0, 90))
            spots.append((x, y, w, d, h, yaw, rnd.choice(("terracotta", "terracotta", "rust"))))
            made += 1
    return spots


CHURCH = (-6.0, 50.5)


def trees(seed=9):
    """Round trees and cypresses on the far side of the valley (never in front of the kite plane): (x, y, kind, s)."""
    rnd = random.Random(seed)
    out = []
    houses = village()
    for _ in range(2000):
        if len(out) >= 120:
            break
        x, y = rnd.uniform(-70, 70), rnd.uniform(18, 95)
        if any((x - h[0]) ** 2 + (y - h[1]) ** 2 < 3.2 ** 2 for h in houses):
            continue
        if (x - MILL_X) ** 2 + (y - MILL_Y) ** 2 < 6 ** 2 or (x - CHURCH[0]) ** 2 + (y - CHURCH[1]) ** 2 < 6 ** 2:
            continue
        if any((x - t[0]) ** 2 + (y - t[1]) ** 2 < 2.0 ** 2 for t in out):
            continue
        out.append((x, y, "cypress" if rnd.random() < 0.3 else "round", rnd.uniform(0.8, 1.3)))
    return out
