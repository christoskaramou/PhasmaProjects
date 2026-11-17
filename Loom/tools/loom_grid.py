"""Loom: the one grid and camera shared by the Blender bakes and (mirrored) by the Lua rules.

Blender axes, metres: +x right across the cloth, +y away from the weaver (toward the reed), +z up.
Engine axes (y up): engine = (x, z, -y); see to_engine(). Pure Python, no bpy.

Grid: COLS cells across, rows counted from the weaving edge (the fell) toward the weaver.
  col c (0..8) has its centre at x = (c - 4) * CELL.
  woven row r (0 = newest) spans y in [-(r+1)*CELL, -r*CELL], centre y = -(r + 0.5) * CELL.
  the row being woven (r = -1) spans y in [0, CELL]; its weft lies loose on the warp.
  Rows flow toward -y by one CELL per beat and fold down over the front (breast) beam at y = BEAM_Y.
"""
import math

CELL = 0.056                 # cell size and row pitch (m): square cells
COLS = 9
ENDS = 12                    # warp ends per cell (cells line up with warp groups); revision 2: finer, 4.7 mm
PICKS = 12                   # weft picks per row (a row is a band of weft)
THREAD = CELL / ENDS         # thread pitch, 9.3 mm
HALF_W = COLS * CELL / 2     # half cloth width, 0.252
Z0 = 0.075                   # cloth surface height above the table top (z = 0)

# relief and bands (fractions are of CELL)
HILL_H = 0.042               # full hill height (revision 2: large hills; product field, max slope 47 deg)
HILL_RUN = 1.0               # cells over which each side's falloff rises (1.0 = broad: a 2-wide hill is a dome or a ridge)
FIELD_FADE = 0.12            # cells over which a field's stripes fade into meadow at its edge
WEAVE_A = 0.0013             # woven bump amplitude (pick ridge); revision 2: finer, even
WATER_W, BANK_W, WATER_D = 0.31, 0.05, 0.0035   # river half width, bank band, carve depth (revision 2: broad)
PATH_W, PATH_D = 0.12, 0.0008      # revision 2: a broader path                   # path half width, sink
MEANDER_WATER, MEANDER_PATH = 0.13, -0.07        # bulge of straight arms (fraction of CELL); rev 2: calmer river

ROWS_FLAT = 8                # woven rows that lie flat between the fell and the beam crest (rev 2: closer camera)
BEAM_Y = -ROWS_FLAT * CELL   # crest line of the round front (breast) beam: the cloth starts to roll here
ROLL_R = 0.035               # radius the cloth base rolls on (beam radius + 3 mm cloth)
BEAM_AXIS = (BEAM_Y, Z0 - ROLL_R)   # (y, z) of the beam axis
ROW_ARC = math.degrees(CELL / ROLL_R)   # 91.7 deg of beam per rolled row
REED_Y = 0.105               # reed (beater) line beyond the fell
BACK_Y = 0.62                # back beam line where the warp leaves the frame

# Game camera (Blender axes). Lens is given as the engine's: vertical FOV on a 24 mm sensor.
CAM_POS = (0.0, -0.56, 0.25)           # round 3: close and low across the cloth like loom.png; no yaw (rows level)
CAM_TARGET = (0.0, -0.25, 0.075)
SENSOR_H_MM = 24.0           # engine default sensor height (Camera.h:161)
LENS_MM = 32.0
ASPECT = 16 / 9
F_STOP = 4.0                 # round 3: the working area (fell to the traveller and beyond) stays sharp
FOCUS = None                 # set by focus_distance() to the traveller
TRAVELLER = (4, 2)           # (col, row) of the traveller in the target frame
BALL_R0, BALL_R1 = 0.0155, 0.033          # wound-ball radius when empty / full
CUP_Z, CUP_R = 0.019, 0.0145               # the stand's cup rim height and radius
SUN_DIR = (-0.52, 0.62, 0.62)   # toward the sun (Blender axes): warm late sun from the back left, ~39 deg up
TRAV_SCALE = 1.2             # the traveller peg's scale (scene.py traveller())
# wool balls on their turned stands at the right of the cloth: (wool, x, y), table coordinates
BOBBINS = []    # round 3: the close camera leaves the wool balls out of view; the HUD chips show what is left


# the two target frames (tools/scene.py target / target_b, and the game's look states A / B): rows newest first
MAP_A = ["hh.~p..hh", "hhh~p...h", "hh.~p..ww", "..pBp....", ".Hp~~....", ".HH.~..hh", "....~.hhh", "...~~.hhh",
         "...~.....", "...~.....", "...~....."]
# the row being woven: chosen cells (col, wool) in weaving order; shuttle beyond the last
ROW_A = {"cells": [(0, "sage"), (1, "sage"), (2, "brown"), (3, "sage"), (4, "tan")], "dir": 1}
FILL_A = {"sage": 1.0, "indigo": 0.5, "tan": 0.75, "brown": 0.3, "ochre": 0.9, "grey": 0.12, "cream": 0.6}
MAP_B = ["ff....p..", "ff.w..p.h", "..hh..p.h", ".hhh..p..", "...~~~b~~", "~~~~..p..", ".....Hp..", "ww...Hp.w",
         "w.....p.w", "..hh..p..", "..hh..p.."]
ROW_B = {"cells": [(8, "sage"), (7, "tan"), (6, "sage"), (5, "sage")], "dir": -1}
FILL_B = {"sage": 0.45, "indigo": 1.0, "tan": 0.25, "brown": 0.65, "ochre": 0.5, "grey": 0.85, "cream": 0.75}
TRAV_B = (6, 2)


def vfov_deg():
    return math.degrees(2 * math.atan(SENSOR_H_MM / 2 / LENS_MM))


def hfov_deg(aspect=ASPECT):
    """What the engine's camera:set_fov wants (horizontal, CameraBindings.cpp:30)."""
    return math.degrees(2 * math.atan(math.tan(math.radians(vfov_deg()) / 2) * aspect))


def to_engine(p):
    return (p[0], p[2], -p[1])


def col_x(c):
    return (c - (COLS - 1) / 2) * CELL


def row_y(r):
    return -(r + 0.5) * CELL


def row_pose(r):
    """Pose of woven row r: ("flat", y, z, 0) for rows on the table, ("rolled", y, z, angle_deg) for rows
    past the crest. A rolled row uses the bent copy of its variant (bend()), whose origin is the beam axis;
    rotating that node about +x by angle_deg keeps it on the beam, which is also how the scroll animates."""
    if r < ROWS_FLAT:
        return "flat", row_y(r), Z0, 0.0
    return "rolled", BEAM_AXIS[0], BEAM_AXIS[1], (r - ROWS_FLAT) * ROW_ARC


def bend(x, y, z):
    """Cell-local point (y in [-CELL/2, CELL/2], z above the cloth base) -> point on the roll, relative to the
    beam axis, for the row whose north edge sits on the crest. Continuous with the flat row before it."""
    phi = (CELL / 2 - y) / ROLL_R
    r = ROLL_R + z
    return x, -r * math.sin(phi), r * math.cos(phi)


def focus_distance():
    tx, ty = col_x(TRAVELLER[0]), row_y(TRAVELLER[1])
    p = (tx, ty, Z0 + 0.02)
    return math.dist(p, CAM_POS)


# ------------------------------------------------------------- the landscape fields (cell-local)
# A cell's look depends only on its own kind and its 3x3 neighbourhood, so each cooked variant
# is keyed by (kind, mask) and adjacent variants agree along their shared edge by construction:
# every field below is one global function of the grid, evaluated inside one cell.

def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * t * (t * (6 * t - 15) + 10)


def blob_dist(u, v, nb, rho=0.5, soft=0.0):   # fields (and hills before revision 2)
    """Distance (cells) from (u, v) to the land outside a region of cells. nb[(dx, dy)] True where that cell
    is in the region (dy +1 = toward the fell). Convex corners of the region are rounded to radius rho.
    Diagonals only count when both their orthogonals are in the region, so a cell's result depends on its
    47-blob key alone, and it is one global field: neighbours agree on every shared border. Capped at 1."""
    if not nb[(0, 0)]:
        return 0.0
    n, e, s, w = nb[(0, 1)], nb[(1, 0)], nb[(0, -1)], nb[(-1, 0)]
    ds = []
    if not n:
        ds.append(0.5 - v)
    if not s:
        ds.append(v + 0.5)
    if not e:
        ds.append(0.5 - u)
    if not w:
        ds.append(u + 0.5)
    for (sx, sy), a, b in (((1, 1), n, e), ((1, -1), s, e), ((-1, -1), s, w), ((-1, 1), n, w)):
        px, py = 0.5 * sx, 0.5 * sy                       # the corner point
        if a and b and not nb[(sx, sy)]:                  # concave corner: distance to the diagonal cell
            ds.append(math.hypot(px - u, py - v))
        elif not a and not b:                             # convex corner: rounded
            cx, cy = px - rho * sx, py - rho * sy
            if (u - cx) * sx > 0 and (v - cy) * sy > 0:
                ds.append(rho - math.hypot(u - cx, v - cy))
    if not ds:
        return 1.0
    if soft > 0:      # smooth minimum: no creases where two edges are equally near (hills read as round mounds)
        m = min(ds)
        d = m - soft * math.log(sum(math.exp(-(x - m) / soft) for x in ds))
    else:
        d = min(ds)
    return max(0.0, min(d, 1.0))


def hill_height(u, v, nb):
    """0..1 hill height (revision 2): a PRODUCT of smooth falloffs, one per open side of the hill region (distance to
    that cell edge) and one per concave corner (distance to the corner point), each g(d) = smoothstep(d / HILL_RUN).
    A product of smooth factors has no creases (the minimum-distance field made pyramids with ridges on the
    diagonals). Exact continuity: on a shared border every factor that is below 1 there has its twin on the other
    side (an open side shared by both cells, or one cell's open side against the other's concave corner, equal on
    the border), and factors from edges or corners a whole cell away are 1 (HILL_RUN <= 1). Diagonals only count
    when both orthogonals are hill (concave corners), so the 47-blob key still decides the shape."""
    if not nb[(0, 0)]:
        return 0.0

    def g(d):
        t = min(max(d / HILL_RUN, 0.0), 1.0)
        return t * t * (3 - 2 * t)
    n, e, s_, w = nb[(0, 1)], nb[(1, 0)], nb[(0, -1)], nb[(-1, 0)]
    h = 1.0
    if not n:
        h *= g(0.5 - v)
    if not s_:
        h *= g(v + 0.5)
    if not e:
        h *= g(0.5 - u)
    if not w:
        h *= g(u + 0.5)
    for (sx, sy), a_, b_ in (((1, 1), n, e), ((1, -1), s_, e), ((-1, -1), s_, w), ((-1, 1), n, w)):
        if a_ and b_ and not nb[(sx, sy)]:
            h *= g(math.hypot(0.5 * sx - u, 0.5 * sy - v))
    return h


def blob_key(nb):
    """Canonical 47-set key: diagonals only count when both their orthogonals are hill."""
    n, e, s, w = nb[(0, 1)], nb[(1, 0)], nb[(0, -1)], nb[(-1, 0)]
    ne = nb[(1, 1)] and n and e
    se = nb[(1, -1)] and s and e
    sw = nb[(-1, -1)] and s and w
    nw = nb[(-1, 1)] and n and w
    return "".join("1" if b else "0" for b in (n, ne, e, se, s, sw, w, nw))


ARMS = {"n": (0.0, 0.5), "e": (0.5, 0.0), "s": (0.0, -0.5), "w": (-0.5, 0.0)}


def skeleton(arms, bulge):
    """Polyline pieces (lists of (u, v)) of a band joining the given side midpoints.
    Two perpendicular arms: a quarter circle round the shared corner (a smooth bend).
    Two opposite arms: a gentle bulge with zero slope at both ends (C1 with any neighbour).
    Otherwise straight arms to the centre (T, cross, dead end)."""
    a = sorted(arms)
    if len(a) == 2 and set(a) in ({"n", "s"}, {"e", "w"}):
        out = []
        for k in range(25):
            t = k / 24
            off = bulge * (1 - math.cos(2 * math.pi * t)) / 2
            out.append((off, -0.5 + t) if set(a) == {"n", "s"} else (-0.5 + t, off))
        return [out]
    if len(a) == 2:
        (ax, ay), (bx, by) = ARMS[a[0]], ARMS[a[1]]
        cx, cy = ax + bx, ay + by          # the shared corner
        a0 = math.atan2(ay - cy, ax - cx)
        a1 = math.atan2(by - cy, bx - cx)
        if a1 - a0 > math.pi:
            a1 -= 2 * math.pi
        if a0 - a1 > math.pi:
            a1 += 2 * math.pi
        return [[(cx + 0.5 * math.cos(a0 + (a1 - a0) * k / 16), cy + 0.5 * math.sin(a0 + (a1 - a0) * k / 16))
                 for k in range(17)]]
    if not a:
        return [[(0.0, 0.0), (0.0, 0.0)]]
    return [[(0.0, 0.0), ARMS[k]] for k in a]


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = 0.0 if L < 1e-12 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def band_dist(u, v, pieces):
    best = 9.0
    for pl in pieces:
        for i in range(len(pl) - 1):
            best = min(best, seg_dist(u, v, *pl[i], *pl[i + 1]))
    return best


# ------------------------------------------------------------- variant keys (the Lua mirrors these: loom_rules.lua)
# kinds: '.' meadow, 'h' hill, 'w' woods, '~' water, 'p' path, 'f' field, 'r' rock, 'H' house (on a path),
# 'b' bridge over an E-W river (path N-S), 'B' bridge over a N-S river (path E-W). grid[r][c], r = 0 the newest row.
def nb_of(grid, c, r):
    """3x3 neighbourhood of kinds; None outside the cloth. dy = +1 is toward the fell (row r - 1)."""
    rows = len(grid)
    out = {}
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            cc, rr = c + dx, r - dy
            out[(dx, dy)] = grid[rr][cc] if 0 <= cc < COLS and 0 <= rr < rows else None
    return out


SIDES = {"n": (0, 1), "e": (1, 0), "s": (0, -1), "w": (-1, 0)}
OPP = {"n": "s", "s": "n", "e": "w", "w": "e"}


def connects(kind_set, nb, side):
    k = nb[SIDES[side]]
    if k is None:
        return None          # off the cloth: decided below
    if kind_set == "water":
        return k == "~" or (k == "b" and side in "ew") or (k == "B" and side in "ns")
    return k in ("p", "H") or (k == "b" and side in "ns") or (k == "B" and side in "ew")


def arms_of(kind_set, nb):
    on = [s for s in "nesw" if connects(kind_set, nb, s)]
    off = [s for s in "nesw" if connects(kind_set, nb, s) is None]
    if len(on) == 1 and OPP[on[0]] in off:
        on.append(OPP[on[0]])                  # a river or path that reaches the cloth's edge runs off it
    return "".join(s for s in "nesw" if s in on)


def variant_key(grid, c, r, row=None):
    """(kind, mask) of cell (c, r). row: the row's absolute number (the game passes it so a woods / meadow / rock
    cell keeps its look while it scrolls); the target frames use r."""
    nb = nb_of(grid, c, r)
    kind = nb[(0, 0)]
    if kind == "h":
        return ("h", blob_key({d: nb[d] == "h" for d in nb}))
    if kind == "~":
        arms = arms_of("water", nb)
        # round 4: straight river cells meander - the bulge alternates by row (N-S) or by column (E-W), so a river
        # winds in S-curves; both ends keep zero slope at the side midpoints, so every join stays exact
        if arms == "ns" and (r if row is None else row) % 2 == 1:
            arms = "ns2"
        elif arms == "ew" and c % 2 == 1:
            arms = "ew2"
        return ("~", arms)
    if kind in ("p", "H"):
        return ("p", arms_of("path", nb))
    if kind == "b":
        return ("b", "ew")
    if kind == "B":
        return ("B", "ns")
    if kind == "f":
        return ("f", blob_key({d: nb[d] == "f" for d in nb}))
    return (kind, str(alt_of(kind, c, r if row is None else row)))


ALTS = {".": 4, "w": 3, "r": 2}


def alt_of(kind, c, row):
    """Which look of a meadow / woods / rock cell (round 4: 4 meadow looks, mixed so no checkerboard shows)."""
    return (c * 7 + row * 3 + (c * row) % 3) % ALTS[kind]


def water_skeleton(mask):
    """River centre line of a cooked river cell: 'ns2' / 'ew2' bulge the other way from 'ns' / 'ew'."""
    if mask.endswith("2"):
        return skeleton(mask[:-1], -MEANDER_WATER)
    return skeleton(mask, MEANDER_WATER)


def meadow_relief(kind, alt, u, v):
    """Gentle rolling of a meadow / woods / rock floor (m, round 4): one or two soft mounds or hollows of a few mm,
    windowed by (cos pi u cos pi v)^2, which is 0 with zero slope on every border: joins any neighbour exactly."""
    import random as _r
    g = _r.Random("%s%s" % (kind, alt))
    z = 0.0
    for _ in range(1):          # one broad swell or hollow per cell (two made a busy, bubbly field)
        a = g.uniform(-0.0015, 0.004)
        cu, cv, sg = g.uniform(-0.12, 0.12), g.uniform(-0.12, 0.12), g.uniform(0.34, 0.44)
        z += a * math.exp(-((u - cu) ** 2 + (v - cv) ** 2) / (sg * sg))
    w = (math.cos(math.pi * u) * math.cos(math.pi * v)) ** 2
    return z * w


def all_keys():
    """Every cooked base variant: 47 hill + 47 field blob keys, 16 river + 16 path arm masks (+ ns2 / ew2 meanders), 2 bridges,
    meadow 4, woods 3, rock 2 = 139 (round 4: + 2 meandering river cells, + 2 meadow looks)."""
    blobs = set()
    for m in range(256):
        nb = {(0, 0): True}
        for i, d in enumerate(((0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1))):
            nb[d] = bool(m >> i & 1)
        blobs.add(blob_key(nb))
    masks = ["".join(s for i, s in enumerate("nesw") if m >> i & 1) for m in range(16)]
    keys = [("h", b) for b in sorted(blobs)] + [("f", b) for b in sorted(blobs)]
    keys += [("~", m) for m in masks] + [("~", "ns2"), ("~", "ew2")] + [("p", m) for m in masks] + [("b", "ew"), ("B", "ns")]
    keys += [(k, str(a)) for k in (".", "w", "r") for a in range(ALTS[k])]
    return keys


def key_nb(key):
    """A representative 3x3 neighbourhood (kinds) for a key: what the Blender export builds the variant from."""
    kind, mask = key
    nb = {(dx, dy): "." for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    nb[(0, 0)] = kind
    if kind in ("h", "f"):
        for bit, d in zip(mask, ((0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1))):
            if bit == "1":
                nb[d] = kind
    elif kind in ("~", "p"):
        for s in mask.rstrip("2"):
            nb[SIDES[s]] = kind
    return nb


def key_name(key):
    kind, mask = key
    k = {".": "meadow", "h": "hill", "w": "woods", "~": "water", "p": "path", "f": "field", "r": "rock",
         "b": "bridgeEW", "B": "bridgeNS"}[kind]
    return "c_%s_%s" % (k, mask or "x")
