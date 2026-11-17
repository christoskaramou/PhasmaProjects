"""Shadow Puppeteer: the ONE source of stage geometry. Read by the Blender scene (tools/scene.py), the mesh and scene
generator (tools/gen_meshes.py) and, through the generated Assets/Scripts/sp_data.lua (write_lua below), the game.

Units: stage units. Blender axes: X right, Y away from the camera (toward the screen), Z up.
Engine (x, y, z) = (bx, bz, -by)  (Topple's convention, Topple/tools/backdrop_scene.py).
Screen coordinates (rules: puppet, paper pieces, shadows): u = bx, v = bz on the paper plane by = SY (engine z = -SY).
Floor: bz = 0 (engine y = 0).  Prop local coordinates (meshes, silhouettes): x right of the anchor, z up from the floor.
"""
import math

SY = 1.60                       # paper plane (front face of the paper)
SCREEN_U = (-2.5, 2.5)          # paper extent, screen coords
SCREEN_V = (0.0, 2.4)
LZ = 0.12                       # lantern flame height above the floor (the lantern slides on the floor)
LANTERN_X = (-1.45, 1.45)       # lantern flame x range
LANTERN_Y = (-1.20, -0.75)      # lantern flame y range (far .. near the props)
LIGHT_D = 0.009                 # flame diameter: every shadow gets the penumbra it casts, width
                                # LIGHT_D (SY - y_prop) / (y_prop - ly) on the paper (2-6 px at 2560 wide)
FLOOR_X = (-3.2, 3.2)           # stage floor top (z = 0); it ends at the paper plane: nothing live lies behind the paper
FLOOR_Y = (-1.74, SY)

# Props: track depth y and the range of the anchor x (anchor = centre of the footprint on the floor).
PROPS = {
    "cup":    {"y": 0.00, "x": (-1.20, 0.30)},
    "comb":   {"y": 0.35, "x": (-0.60, 1.10)},
    "ladder": {"y": 0.70, "x": (-0.30, 0.80)},
    # map 2's clockwork mouse runs its track BY ITSELF (the level gives its patrol); map 3's toy balloon hangs on a
    # string from the fly bar at the level's x and slides UP and DOWN (anchor z on its track "z")
    "mouse":  {"y": 0.20, "x": (-1.60, 1.60)},
    "balloon": {"y": 0.45, "x": (-1.60, 1.60), "z": (0.0, 0.95)},
}
PROP_KIND = {"cup": "solid", "comb": "solid", "ladder": "ladder", "mouse": "solid", "balloon": "solid"}
PROP_MOVE = {"cup": "x", "comb": "x", "ladder": "x", "mouse": "auto", "balloon": "z"}
# A tin clockwork mouse (nose to +x; reliefs like the cup, 5 % deep): dome body, pointed nose, winding key, tail.
MOUSE = {"rx": 0.2, "rz": 0.2, "zc": 0.03, "relief": 0.035}
# A toy hot-air balloon: wicker basket, two ropes, envelope (an ellipse); its string to the fly bar casts no shadow.
BALLOON = {"rx": 0.15, "rz": 0.18, "zc": 0.33, "relief": 0.045}

# ---------------------------------------------------------------- prop geometry (meshes and silhouettes both)
# Upturned teacup: lathe profile (radius, height); a relief (5 % depth, round shading normals). Handle on the left.
CUP_PROFILE = [(0.17, 0.0), (0.172, 0.01), (0.165, 0.08), (0.14, 0.17), (0.1, 0.225), (0.075, 0.235), (0.075, 0.27),
               (0.06, 0.27), (0.0, 0.268)]
CUP_RELIEF = 0.05
CUP_HANDLE = {"x": -0.17, "z": 0.12, "major": 0.05, "minor": 0.011}
# Comb standing on its teeth, a plain handle on its left end (no teeth under it), spine on top.
COMB = {"length": 0.80, "handle": 0.17, "top": 0.314, "spine": 0.085, "corner": 0.03, "thick": 0.018, "tip": 0.014,
        "teeth": 17, "tooth": 0.022, "tooth_depth": 0.008, "tooth_tip": 0.55}
# Toy ladder: lozenge-section rails and rungs.
LADDER = {"h": 0.95, "w": 0.115, "rungs": 7, "rail": 0.045, "rail_top": 0.85, "rail_d": 0.022, "rung": 0.03, "rung_d": 0.018}


def comb_teeth_x():
    c = COMB
    x0 = -c["length"] / 2 + c["handle"]
    x1 = c["length"] / 2 - 0.025
    n = c["teeth"]
    return [x0 + 0.015 + i * (x1 - x0 - 0.015) / (n - 1) for i in range(n)]


def comb_outline(n=6):
    """The comb's spine and tapered handle: one convex outline (x, z), prop-local, counter-clockwise from the tip.
    The handle's underside rises to a thin tip, so beside the cup its shadow clears the cup's shoulder."""
    c = COMB
    x0, x1 = -c["length"] / 2, c["length"] / 2
    xt = x0 + c["handle"]
    top, zb, r = c["top"], c["top"] - c["spine"], c["corner"]
    pts = [(x0, top - c["tip"]), (xt, zb), (x1 - r, zb)]
    for i in range(1, n + 1):
        a = math.radians(-90 + 90 * i / n)
        pts.append((x1 - r + r * math.cos(a), zb + r + r * math.sin(a)))
    for i in range(1, n + 1):
        a = math.radians(90 * i / n)
        pts.append((x1 - r + r * math.cos(a), top - r + r * math.sin(a)))
    pts.append((x0, top))
    return pts


def comb_profile(x):
    """(bottom, top) of the comb's outline at local x (the vertical section through the convex outline)."""
    pts = comb_outline(12)
    zs = []
    n = len(pts)
    for i in range(n):
        (ax, az), (bx, bz) = pts[i], pts[(i + 1) % n]
        if (ax - x) * (bx - x) <= 0 and ax != bx:
            zs.append(az + (bz - az) * (x - ax) / (bx - ax))
        elif ax == x:
            zs.append(az)
    return min(zs), max(zs)


def rounded_rect(cx, cz, w, h, r, n=6):
    pts = []
    for (sx, sz, a0) in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        ccx, ccz = cx + sx * (w / 2 - r), cz + sz * (h / 2 - r)
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((ccx + r * math.cos(a), ccz + r * math.sin(a)))
    return pts


def silhouette(name):
    """The prop's one authored silhouette: a list of convex polygons [(x, z), ...] in prop-local coordinates whose
    union is the outline seen along the depth axis. The shadow is this, scaled about the lantern (project)."""
    if name == "cup":
        prof = CUP_PROFILE
        polys = []
        for (r0, z0), (r1, z1) in zip(prof, prof[1:]):          # body: horizontal slabs of the lathe profile
            if abs(z1 - z0) < 1e-9:
                continue
            polys.append([(-r0, z0), (r0, z0), (r1, z1), (-r1, z1)])
        h = CUP_HANDLE
        ro, ri, n = h["major"] + h["minor"], h["major"] - h["minor"], 24
        for i in range(n):                                       # handle ring: annulus as quads
            a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
            polys.append([(h["x"] + ri * math.cos(a0), h["z"] + ri * math.sin(a0)),
                          (h["x"] + ro * math.cos(a0), h["z"] + ro * math.sin(a0)),
                          (h["x"] + ro * math.cos(a1), h["z"] + ro * math.sin(a1)),
                          (h["x"] + ri * math.cos(a1), h["z"] + ri * math.sin(a1))])
        return polys
    if name == "comb":
        c = COMB
        zb = c["top"] - c["spine"]
        polys = [comb_outline()]
        for tx in comb_teeth_x():
            w = c["tooth"]
            polys.append([(tx - w * c["tooth_tip"] / 2, 0.0), (tx + w * c["tooth_tip"] / 2, 0.0), (tx + w / 2, zb + 0.02),
                          (tx - w / 2, zb + 0.02)])
        return polys
    if name == "ladder":
        L = LADDER
        polys = []
        for s in (-1, 1):
            x = s * L["w"]
            wb, wt = L["rail"], L["rail"] * L["rail_top"]
            polys.append([(x - wb / 2, 0.0), (x + wb / 2, 0.0), (x + wt / 2, L["h"]), (x - wt / 2, L["h"])])
        for z in ladder_rung_z():
            polys.append([(-L["w"], z - L["rung"] / 2), (L["w"], z - L["rung"] / 2), (L["w"], z + L["rung"] / 2),
                          (-L["w"], z + L["rung"] / 2)])
        return polys
    if name in ("mouse", "mouse_l"):
        m = MOUSE
        polys = [[(-0.17, 0.0), (0.17, 0.0), (0.17, m["zc"]), (-0.17, m["zc"])]]       # wheels and base
        n = 10
        prev = None
        for i in range(n + 1):                                               # dome: slabs of the ellipse
            a = math.pi / 2 * i / n
            r, z = m["rx"] * math.cos(a), m["zc"] + m["rz"] * math.sin(a)
            if prev:
                polys.append([(-prev[0], prev[1]), (prev[0], prev[1]), (r, z), (-r, z)])
            prev = (r, z)
        polys.append([(0.15, m["zc"]), (0.29, 0.05), (0.13, 0.14)])                    # nose
        polys.append([(-0.21, 0.125), (-0.255, 0.125), (-0.255, 0.145), (-0.21, 0.145)])  # key stem
        for cz in (0.1, 0.17):                                               # key bow: two lobes
            polys.append([(-0.255 + 0.032 * math.cos(2 * math.pi * k / 12) - 0.032, cz + 0.032 * math.sin(2 * math.pi * k / 12))
                          for k in range(12)])
        tail = [(-0.19, 0.04), (-0.25, 0.03), (-0.30, 0.04), (-0.34, 0.07)]
        for (ax, az), (bx, bz) in zip(tail, tail[1:]):
            polys.append([(ax, az - 0.008), (bx, bz - 0.008), (bx, bz + 0.008), (ax, az + 0.008)])
        if name == "mouse_l":                                                # running left: mirrored
            polys = [[(-x, z) for x, z in reversed(poly)] for poly in polys]
        return polys
    if name == "balloon":
        b = BALLOON
        polys = [[(-0.055, 0.0), (0.055, 0.0), (0.06, 0.07), (-0.06, 0.07)]]               # basket
        for sx in (-1, 1):                                                                 # ropes
            polys.append([(sx * 0.04, 0.07), (sx * 0.055, 0.07), (sx * 0.10, 0.19), (sx * 0.085, 0.19)])
        polys.append([(-0.05, 0.15), (0.05, 0.15), (0.1, 0.2), (-0.1, 0.2)])                # neck
        n = 12
        pts = [(b["rx"] * math.cos(2 * math.pi * k / (2 * n)), b["zc"] + b["rz"] * math.sin(2 * math.pi * k / (2 * n)))
               for k in range(2 * n)]
        for k in range(n):                                                                 # envelope: slabs
            a0, a1 = -math.pi / 2 + math.pi * k / n, -math.pi / 2 + math.pi * (k + 1) / n
            z0, z1 = b["zc"] + b["rz"] * math.sin(a0), b["zc"] + b["rz"] * math.sin(a1)
            r0, r1 = b["rx"] * math.cos(a0), b["rx"] * math.cos(a1)
            polys.append([(-r0, z0), (r0, z0), (r1, z1), (-r1, z1)])
        return polys
    raise KeyError(name)


def ladder_rung_z():
    L = LADDER
    # the top rung's top is the rails' top: the ladder's walkable top is drawn
    return [0.1 + i * (L["h"] - L["rung"] / 2 - 0.1) / (L["rungs"] - 1) for i in range(L["rungs"])]


PAPER_PX_PER_UNIT_2560 = 1659 / 5.0           # paper pixels per stage unit in a 2560-wide frame (measured projection)
PENUMBRA_MIN_PX = 2.0                         # floor so the thinnest shadows (ladder rails) still get smoothed edges


def penumbra(name, ly=None):
    """Penumbra width on the paper (stage units) of a prop's shadow for a lantern at depth ly: the flame's diameter
    seen past the prop's edge, LIGHT_D (SY - y) / (y - ly); never under PENUMBRA_MIN_PX at 2560 wide."""
    ly = (LANTERN_Y[0] + LANTERN_Y[1]) / 2 if ly is None else ly
    y = PROPS[name]["y"]
    return max(LIGHT_D * (SY - y) / (y - ly), PENUMBRA_MIN_PX / PAPER_PX_PER_UNIT_2560)


def bbox(name):
    pts = [p for poly in silhouette(name) for p in poly]
    return (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts))


def k_of(ly, prop_y):
    """Shadow scale for a prop plane at depth prop_y and a lantern at depth ly."""
    return (SY - ly) / (prop_y - ly)


def project(lx, ly, prop_y, px, pz, lz=LZ):
    """Screen point (u, v) of a point (px, prop_y, pz) of a prop's silhouette plane, lit from (lx, ly, lz)."""
    k = k_of(ly, prop_y)
    return lx + k * (px - lx), lz + k * (pz - lz)


# ---------------------------------------------------------------- camera and pictures
CAM_POS = (0.0, -10.4, 1.08)
CAM_LOOK = (0.0, SY, 1.10)
CAM_LENS = 56.0                                   # mm on a 36 mm sensor width at 16:9
HFOV_169 = 2 * math.degrees(math.atan(18.0 / CAM_LENS))
VFOV = 2 * math.degrees(math.atan(math.tan(math.radians(HFOV_169 / 2)) * 9 / 16))
WIDE = (3456, 1440)                               # game bakes: 2.4:1 at the same vfov, so wide windows still fit


def to_pixel(p, w, h):
    """Blender-space point -> pixel (x right, y down) in a w x h frame of the game camera (fixed vfov)."""
    f = [CAM_LOOK[i] - CAM_POS[i] for i in range(3)]
    n = math.sqrt(sum(c * c for c in f))
    f = [c / n for c in f]
    r = [f[1] * 1 - f[2] * 0, f[2] * 0 - f[0] * 1, 0.0]            # f x (0, 0, 1)
    n = math.sqrt(sum(c * c for c in r))
    r = [c / n for c in r]
    u = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]]
    d = [p[i] - CAM_POS[i] for i in range(3)]
    x, y, z = (sum(d[i] * r[i] for i in range(3)), sum(d[i] * u[i] for i in range(3)), sum(d[i] * f[i] for i in range(3)))
    tv = math.tan(math.radians(VFOV / 2))
    th = tv * w / h
    return ((x / (z * th) + 1) / 2 * w, (1 - y / (z * tv)) / 2 * h)


# Front-card bakes: the theatre lit by the lantern at these flame positions (the game cross-fades between them).
FRONT_X = [-1.45, -0.725, 0.0, 0.725, 1.45]
FRONT_Y = [-1.20, -0.75]
# Display values (sRGB 0..1) the game must land on, measured in target_2560x1369.png (state A) with
# tools/look_measure.py: the props' shadows on the paper (fill + bounce, no lantern) and the gold paper's floor.
LOOK_DISPLAY = {"shadow": (0.282, 0.180, 0.086), "gold": (0.60, 0.39, 0.05)}
# Engine layer offsets toward the camera from the paper (stage units).
# Each prop's shadow is two cards (2026-11-13): an opaque alpha-cut core at the silhouette's 50 % contour ("shadow"),
# so overlapping shadows make an exact union, and a blended copy just behind it ("penumbra") that shows only the soft
# ramp outside the core. One blended card per shadow broke overlaps: the engine's blend keeps the LAST card's alpha
# (Pipeline.cpp:52-53, alpha ONE/ZERO), so a later card's soft edge erased the earlier shadow (the cup/comb slit).
LAYER = {"penumbra": 0.0015, "shadow": 0.002, "paper": 0.004, "puppet": 0.012}

# The lantern as baked sprites (the live brass/glass/flame could not match the target: no IBL, no refraction): Cycles
# renders the target's lantern alone, RGBA, from the game camera with the flame at each FRONT_X x FRONT_Y point; the
# game shows the nearest one (2.25 deg of yaw at most between neighbours: ~1 px on the rods) as an unlit card.
LSPRITE_SS = 2                    # supersampling of the sprite bakes (texture texels per 2560x1369 pixel)
LANTERN_R, LANTERN_TOP = 0.105, 0.44   # bounding cylinder of tools/scene.py lantern() round its base point


def from_pixel(px, py, w, h, plane_y):
    """Inverse of to_pixel: the Blender point on the plane y = plane_y that the camera sees at pixel (px, py)."""
    f = [CAM_LOOK[i] - CAM_POS[i] for i in range(3)]
    n = math.sqrt(sum(c * c for c in f))
    f = [c / n for c in f]
    r = [f[1], -f[0], 0.0]
    n = math.sqrt(sum(c * c for c in r))
    r = [c / n for c in r]
    u = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]]
    tv = math.tan(math.radians(VFOV / 2))
    th = tv * w / h
    x, y = (px / w * 2 - 1) * th, (1 - py / h * 2) * tv
    d = [f[i] + r[i] * x + u[i] * y for i in range(3)]
    t = (plane_y - CAM_POS[1]) / d[1]
    return tuple(CAM_POS[i] + t * d[i] for i in range(3))


def lantern_sprite(i, j, w=2560, h=1369):
    """Sprite (i, j): its pixel rectangle (X0, Y0, X1, Y1) in a (w, h) * LSPRITE_SS render (sizes multiples of 64) and
    the card's corners (bottom-left, bottom-right, top-right, top-left) in Blender space relative to the lantern's base
    point, on the vertical plane through the front of the lantern (so the floor in front never cuts into it)."""
    fx, fy = FRONT_X[i], FRONT_Y[j]
    S = LSPRITE_SS
    pts = [to_pixel((fx + LANTERN_R * math.cos(a * math.pi / 12), fy + LANTERN_R * math.sin(a * math.pi / 12), z), w, h)
           for a in range(24) for z in (0.0, LANTERN_TOP)]
    x0, x1 = min(p[0] for p in pts) - 4, max(p[0] for p in pts) + 4
    y0, y1 = min(p[1] for p in pts) - 4, max(p[1] for p in pts) + 4
    X0, X1, Y0, Y1 = math.floor(x0 * S), math.ceil(x1 * S), math.floor(y0 * S), math.ceil(y1 * S)
    pw, ph = -(-(X1 - X0) // 64) * 64, -(-(Y1 - Y0) // 64) * 64
    X0 -= (pw - (X1 - X0)) // 2
    Y0 -= (ph - (Y1 - Y0)) // 2
    X1, Y1 = X0 + pw, Y0 + ph
    py_ = fy - LANTERN_R - 0.01             # 1 cm before the base: the rays to its lowest edge are still above the floor
    corners = []
    for cx, cy in ((X0, Y1), (X1, Y1), (X1, Y0), (X0, Y0)):
        p = from_pixel(cx / S, cy / S, w, h, py_)
        corners.append((p[0] - fx, p[1] - fy, p[2]))
    return (X0, Y0, X1, Y1), corners
# The lantern's light bounced off the lit paper onto the floor (Cycles has it; the engine has no GI): a shadowless
# point light behind the paper (so it cannot light the paper itself), x following the lantern, strength ~ 1/(SY-ly)^2.
BOUNCE = {"behind": 0.6, "z": 0.9, "x_follow": 0.6}
CANDLE = (1.86, -1.50)                            # candle holder on the floor (Blender x, y)
LANTERN_W = 120.0                                 # Cycles watts of the lantern flame (targets and bakes)

# ---------------------------------------------------------------- the level of the look slice
LEVEL = {
    "left_cliff": [(-2.6, 0.0), (-2.6, 0.47), (-0.80, 0.47), (-0.735, 0.465), (-0.78, 0.44), (-0.98, 0.425),
                   (-1.18, 0.39), (-1.30, 0.33), (-1.33, 0.18), (-1.37, 0.0)],
    "right_cliff": [(0.74, 0.0), (0.70, 0.18), (0.76, 0.36), (0.73, 0.44), (0.80, 0.47), (2.6, 0.47), (2.6, 0.0)],
    "ledge": [(1.52, 1.30), (2.36, 1.30), (2.38, 1.26), (2.34, 1.22), (1.62, 1.21), (1.56, 1.24)],
    "pit": (-1.36, 0.74),           # thorns along the pit floor
    "door": (2.12, 0.47),           # foot of the star door on the right cliff
    "bonus": (2.30, 1.42),          # bonus star on the high ledge
    "moon": (-1.70, 1.95),
}



def thorn_polygon():
    """The bramble of paper thorns along the pit floor (deterministic): one polygon, deadly to touch."""
    import random
    rnd = random.Random(3)
    x0, x1 = LEVEL["pit"]
    n = int((x1 - x0) / 0.07)
    pts = [(x0 - 0.02, 0.0)]
    for k in range(n):
        xa = x0 + k * (x1 - x0) / n
        xb = x0 + (k + 1) * (x1 - x0) / n
        hgt = rnd.uniform(0.09, 0.15)
        lean = rnd.uniform(-0.025, 0.025)
        pts += [(xa, 0.05), (xa + 0.018, 0.06), ((xa + xb) / 2 + lean, hgt), (xb - 0.022, 0.06)]
    pts += [(x1, 0.05), (x1 + 0.02, 0.0)]
    return pts


# The cut-paper puppet's joints (prop-local units x PUPPET["scale"]; feet at the origin): the art in scene.puppet and the
# jointed parts the game swings (hip and shoulder pins).
PUPPET = {"scale": 1.33, "hip": 0.078, "shoulder": 0.132, "thigh": 0.04, "shin": 0.038, "arm": 0.06,
          "shin_w": 0.0085}    # half width of the shin (scene.py puppet_parts limb): the shoe's heel is this far back

# ---------------------------------------------------------------- the rules (puppet_rules.lua reads these)
# From the art: the puppet is 0.30 tall (hat included) and about 0.07 wide; a step is a third of its height.
RULES = {
    "dt": 1.0 / 120.0,          # fixed step
    "puppet_h": 0.30, "puppet_w": 0.07, "step": 0.10,
    # ground holds the puppet only under its drawn shoe with the legs together: heel to heel, 2 x the shin's half width
    # (0.035 reached past the heel: it stood on ground its shoe never touched, live run 2026-11-13)
    "feet_w": round(2 * PUPPET["shin_w"] * PUPPET["scale"], 5),
    "walk": 0.22,               # stage units / s
    "climb": 0.25,
    "gravity": 5.0, "fall_max": 3.0,
    "push_max": 0.12,           # the farthest ground moving into the puppet's side can shove it in one step
    "lift_max": 0.45,           # the farthest ground rising under it can lift it in one step
    "fell_v": -0.25,            # below this the puppet has fallen off the bottom of the paper
    "door_w": 0.06, "door_dv": 0.04,
    "star_r": 0.07,
    "candle_s": 45.0,           # the candle's burn: the level's time
    # ground steeper than this cannot be stood on going down: the puppet slides down it, its back to the face, attached
    # at its centre column (it stood on its heel's corner beside 74 deg cliffs, live run 2026-11-13); it stands again
    # below slide_exit (hysteresis: no slide/walk flicker) and falls only where the surface drops away
    "max_slope": 55.0, "slide_exit": 45.0, "slide": 0.5,   # degrees, degrees, speed along the slope (units / s)
    # after standing up from a slide it walks at least this long before it can slide again (bumpy shadows such as the
    # mouse's key slid and stood every 50-75 ms: the pose and its sound flickered, 2026-11-13)
    "slide_rearm": 0.3,
}
# The reference level: starts unsolved (doing nothing walks the puppet off the cliff into the thorns); the player
# drags the lantern and props into a bridge while it walks. Door and bonus star from LEVEL.
LEVEL_START = {"lantern": (0.9, -1.0), "cup": 0.30, "comb": 1.10, "ladder": 0.80, "puppet": (-2.2, 0.47), "dir": 1}

# Two frames of play: lantern flame (x, y), each prop's anchor x on its track, puppet (u, v, stride phase).
STATE_A = {"lantern": (-1.45, -1.20), "cup": -1.064, "comb": -0.4552, "ladder": 0.59, "puppet": (-0.56, 0.47, 0.3),
           "candle": 0.55}
STATE_B = {"lantern": (1.45, -0.75), "cup": 0.20, "comb": 1.00, "ladder": -0.25, "puppet": (0.62, 0.511, 0.75),
           "candle": 0.30}

# The reference solution the scripted win drags to: state A's bridge with the ladder 6 cm further left, so its shadow's
# middle (where the puppet climbs) clears the ledge's left end (state A's ladder is the look frame; climbed in the
# middle its top is under the ledge).
SOLUTION = dict(STATE_A, ladder=0.53)


# ---------------------------------------------------------------- the levels (challenge tiers on each stage set)
def thorns(x0, x1, seed=3, lo=0.09, hi=0.15, base=0.0):
    """A bramble of paper thorns along a pit floor from x0 to x1 (deterministic): one polygon, deadly to touch."""
    import random
    rnd = random.Random(seed)
    n = max(2, int((x1 - x0) / 0.07))
    pts = [(x0 - 0.02, base)]
    for k in range(n):
        xa = x0 + k * (x1 - x0) / n
        xb = x0 + (k + 1) * (x1 - x0) / n
        hgt = rnd.uniform(lo, hi)
        lean = rnd.uniform(-0.025, 0.025)
        pts += [(xa, base + 0.05), (xa + 0.018, base + 0.06), ((xa + xb) / 2 + lean, base + hgt), (xb - 0.022, base + 0.06)]
    pts += [(x1, base + 0.05), (x1 + 0.02, base)]
    return pts


def cliff_l(x1, top, x0=-2.6):
    """A start cliff from the paper's left edge to x1, top at `top`, with a ragged cut-paper end."""
    return [(x0, 0.0), (x0, top), (x1 - 0.06, top), (x1, top - 0.006), (x1 - 0.04, top - 0.04), (x1 - 0.02, top * 0.55),
            (x1 - 0.05, 0.0)]


def cliff_r(x0, top, x1=2.6):
    return [(x0 + 0.04, 0.0), (x0, top * 0.4), (x0 + 0.05, top * 0.78), (x0 + 0.02, top - 0.03), (x0 + 0.07, top), (x1, top),
            (x1, 0.0)]


# Every level: cut-paper solids, thorn pits (x0, x1), door foot and bonus star (u, v), the puppet's start, the props
# present with their start (x; mouse: its patrol x0, x1, speed (units/s) and phase; balloon: its string's x and start
# z), the lantern's start, the candle (s) and the "quick" mark (arrive before it for the third star).
LEVELS = [
    {"id": "1-1", "hint": "The cup's shadow is the bridge: slide the cup and move the lantern until it spans the pit.", "map": "stage", "name": "First Bridge",
     "solids": [cliff_l(-0.55, 0.47), cliff_r(0.55, 0.47)], "pits": [(-0.58, 0.58)],
     "door": (2.0, 0.47), "bonus": (0.0, 0.80), "puppet": (-2.2, 0.47),
     "props": {"cup": {"x": 0.3}}, "lantern": (1.4, -0.9), "candle": 40.0, "quick": 24.0},
    {"id": "1-2", "hint": "Two gaps: the cup's shadow for the first, the comb's long spine for the second.", "map": "stage", "name": "Two Spans",
     "solids": [cliff_l(-0.85, 0.47), cliff_r(1.12, 0.47)], "pits": [(-0.88, 1.15)],
     "door": (2.15, 0.47), "bonus": (0.55, 0.78), "puppet": (-2.2, 0.47),
     "props": {"cup": {"x": 0.3}, "comb": {"x": -0.6}}, "lantern": (1.2, -1.0), "candle": 40.0, "quick": 25.0},
    {"id": "1-3", "hint": "Bridge with the cup and comb, then stand the ladder's shadow under the ledge to climb to the star.", "map": "stage", "name": "The High Star",
     "solids": "REF", "pits": "REF", "door": (2.12, 0.47), "bonus": (2.30, 1.42), "puppet": (-2.2, 0.47),
     "props": {"cup": {"x": 0.30}, "comb": {"x": 1.10}, "ladder": {"x": 0.80}}, "lantern": (0.9, -1.0),
     "candle": 45.0, "quick": 28.0},
    {"id": "2-1", "hint": "Use the lantern so the mouse's back reaches the cliff edge just as the puppet gets there.", "map": "nursery", "name": "Wind-up",
     "solids": [cliff_l(-0.5, 0.40), cliff_r(0.75, 0.40)], "pits": [(-0.53, 0.78)],
     "door": (2.0, 0.40), "bonus": (0.15, 0.66), "puppet": (-2.2, 0.40),
     "props": {"mouse": {"x0": -1.2, "x1": 0.9, "speed": 0.07, "phase": 0.0}}, "lantern": (1.4, -1.15),
     "candle": 40.0, "quick": 26.0},
    {"id": "2-2", "hint": "The cup's shadow over the first pit, then ride the mouse's back over the second.", "map": "nursery", "name": "Mouse and Cup",
     "solids": [cliff_l(-1.1, 0.40), [(-0.2, 0.0), (-0.24, 0.3), (-0.2, 0.40), (0.15, 0.40), (0.19, 0.3), (0.15, 0.0)],
                cliff_r(1.15, 0.40)], "pits": [(-1.13, -0.22), (0.17, 1.18)],
     "door": (2.1, 0.40), "bonus": (-0.65, 0.68), "puppet": (-2.25, 0.40),
     "props": {"cup": {"x": 0.3}, "mouse": {"x0": 0.1, "x1": 0.55, "speed": 0.06, "phase": 0.5}}, "lantern": (-1.3, -0.9),
     "candle": 42.0, "quick": 27.0},
    {"id": "2-3", "hint": "Ride the mouse across, then stand the ladder's shadow under the high ledge.", "map": "nursery", "name": "Night Climb",
     "solids": [cliff_l(-0.75, 0.40), cliff_r(0.95, 0.40),
                [(1.35, 1.30), (2.5, 1.30), (2.5, 1.21), (1.45, 1.21), (1.39, 1.24)]], "pits": [(-0.78, 0.98)],
     "door": (2.2, 1.30), "bonus": (0.1, 0.55), "puppet": (-2.2, 0.40),
     "props": {"mouse": {"x0": -0.25, "x1": 0.35, "speed": 0.06, "phase": 0.67}, "ladder": {"x": 0.8}},
     "lantern": (1.3, -1.1), "candle": 42.0, "quick": 32.0},
    {"id": "3-1", "hint": "Bring the balloon into the gap with the lantern; raise it while the puppet walks toward the high cliff.", "map": "fair", "name": "Going Up",
     # the lift: bring the balloon's shadow into the gap (it starts hidden behind the high cliff), let the puppet walk
     # onto it (it paces between the start cliff and the high cliff's face), raise it level with the high cliff
     "solids": [cliff_l(-0.30, 0.80), cliff_r(0.12, 1.60)], "pits": [(-0.33, 0.14)],
     "door": (2.0, 1.60), "bonus": (-0.05, 2.02), "puppet": (-2.2, 0.80),
     "props": {"balloon": {"x": 0.0, "z": 0.0}}, "lantern": (-1.4, -0.9), "candle": 40.0, "quick": 24.0},
    # lift onto a high block, drop off its far side, bridge the last pit with the comb (the balloon's top is never
    # below 0.78, so a lift always starts from a high cliff)
    {"id": "3-2", "hint": "Lift onto the block, drop to the ledge, and let the comb's shadow bridge the last pit.", "map": "fair", "name": "Balloon and Comb",
     "solids": [cliff_l(-1.25, 0.80), [(-0.72, 0.0), (-0.76, 0.9), (-0.72, 1.45), (0.33, 1.45), (0.36, 1.2), (0.33, 0.0)],
                [(0.33, 0.0), (0.33, 0.47), (0.72, 0.47), (0.76, 0.3), (0.72, 0.0)], cliff_r(1.55, 0.47)],
     "pits": [(-1.28, -0.74), (0.74, 1.58)],
     "door": (2.15, 0.47), "bonus": (-1.0, 2.02), "puppet": (-2.25, 0.80),
     "props": {"comb": {"x": 1.1}, "balloon": {"x": -0.55, "z": 0.0}}, "lantern": (1.4, -0.9),
     "candle": 45.0, "quick": 30.0},
    # the lift, a drop to a low ledge, then the clockwork mouse ferries the puppet over the last pit
    {"id": "3-3", "hint": "Lift, drop, then ride the mouse over the last pit: watch where it is before you raise the balloon.", "map": "fair", "name": "Grand Finale",
     "solids": [cliff_l(-1.35, 0.80), [(-0.82, 0.0), (-0.86, 0.9), (-0.82, 1.45), (-0.08, 1.45), (-0.05, 1.2), (-0.08, 0.0)],
                [(-0.08, 0.0), (-0.08, 0.40), (0.35, 0.40), (0.39, 0.25), (0.35, 0.0)], cliff_r(1.45, 0.40)],
     "pits": [(-1.38, -0.84), (0.37, 1.48)],
     "door": (2.15, 0.40), "bonus": (0.9, 0.72), "puppet": (-2.25, 0.80),
     "props": {"mouse": {"x0": 0.15, "x1": 0.6, "speed": 0.06, "phase": 0.0}, "balloon": {"x": -0.6, "z": 0.0}},
     "lantern": (1.4, -0.9), "candle": 45.0, "quick": 32.0},
]


# The start cliff's paper decoration (tree / house / tent, scene.map_decor): its centre x and half-width. Clear of the
# puppet's start in every level (it stood inside them, live 2026-11-13); the reference level keeps target.png's tree.
DECOR_HALF = 0.16              # its right edge from that x (house .04 + .10, tent .02 + .14, tree -.03 + .18)


def decor_x(lv):
    if lv["id"] == "1-3":
        return -2.09
    return min(-2.42, lv["puppet"][0] - RULES["puppet_w"] / 2 - DECOR_HALF - 0.005)


def level_data(lv):
    """One level as plain data for the game and the rules (thorn polygons generated from its pits)."""
    ref = lv["solids"] == "REF"
    solids = [LEVEL[k] for k in ("left_cliff", "right_cliff", "ledge")] if ref else lv["solids"]
    pits = [LEVEL["pit"]] if lv["pits"] == "REF" else lv["pits"]
    th = [thorn_polygon()] if ref else [thorns(a, b, seed=3 + i) for i, (a, b) in enumerate(pits)]
    props = {n: dict(p) for n, p in lv["props"].items()}
    return {"id": lv["id"], "map": lv["map"], "name": lv["name"], "solids": [[list(q) for q in poly] for poly in solids],
            "thorns": [[list(q) for q in poly] for poly in th], "pits": [list(p) for p in pits],
            "door": list(lv["door"]), "bonus": list(lv["bonus"]), "props": props,
            "start": {"puppet": list(lv["puppet"]), "dir": 1, "lantern": list(lv["lantern"])},
            "candle": lv["candle"], "quick": lv["quick"], "hint": lv.get("hint", ""), "decor_x": decor_x(lv)}


# ---------------------------------------------------------------- maps (stage sets): theme of each set's bakes
# velvet/paper/wood: base colours; trim: "brass" or "silver" (pewter); spot/fill: house light colours; header: the
# board's word. The game reads name, trim and unlock (stars needed); scene.py (SP_MAP) reads the rest.
MAPS = [
    {"id": "stage", "name": "The Red Theatre", "header": "THEATRE", "unlock": 0, "trim": "brass",
     "velvet": (0.3, 0.015, 0.025), "paper": (0.86, 0.75, 0.56), "paper2": (0.8, 0.68, 0.48), "wood": (0.2, 0.085, 0.035),
     "spot": (1.0, 0.7, 0.5), "fill": (1.0, 0.8, 0.6), "dressing": None},
    {"id": "nursery", "intro": "A clockwork mouse runs back and forth by itself. You cannot drag it, but its shadow is a moving platform: the lantern still moves and sizes it.", "name": "The Moonlit Nursery", "header": "NURSERY", "unlock": 4, "trim": "silver",
     "velvet": (0.012, 0.03, 0.12), "paper": (0.62, 0.68, 0.8), "paper2": (0.55, 0.6, 0.72), "wood": (0.07, 0.06, 0.075),
     "spot": (0.55, 0.68, 1.0), "fill": (0.7, 0.8, 1.0), "dressing": "nursery"},
    {"id": "fair", "intro": "A toy balloon hangs on a string. Drag it up and down (or W / S): its shadow is a lift. Raise it with the puppet standing on top.", "name": "The Harvest Fair", "header": "FAIR", "unlock": 9, "trim": "brass",
     "velvet": (0.02, 0.11, 0.035), "paper": (0.9, 0.72, 0.42), "paper2": (0.82, 0.6, 0.32), "wood": (0.22, 0.11, 0.04),
     "spot": (1.0, 0.72, 0.38), "fill": (1.0, 0.75, 0.45), "dressing": "fair"},
]
MAP_BY_ID = {m["id"]: m for m in MAPS}


# ---------------------------------------------------------------- export for the game
def _lua(v, ind=""):
    if isinstance(v, dict):
        items = []
        for k in sorted(v):
            key = k if isinstance(k, str) and k.isidentifier() else "[%r]" % k
            items.append("%s  %s = %s" % (ind, key, _lua(v[k], ind + "  ")))
        return "{\n" + ",\n".join(items) + "\n" + ind + "}"
    if isinstance(v, (list, tuple)):
        if all(isinstance(x, (int, float)) for x in v):
            return "{ " + ", ".join(_lua(x) for x in v) + " }"
        return "{\n" + ",\n".join(ind + "  " + _lua(x, ind + "  ") for x in v) + "\n" + ind + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(round(v, 6))
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return '"%s"' % v
    raise TypeError(v)


def lua_data(extra=None):
    cam_e = (CAM_POS[0], CAM_POS[2], -CAM_POS[1])
    look_e = (CAM_LOOK[0], CAM_LOOK[2], -CAM_LOOK[1])
    props = {}
    for n, p in PROPS.items():
        props[n] = {"y": p["y"], "x": list(p["x"]), "silhouette": [[list(q) for q in poly] for poly in silhouette(n)],
                    "bbox": list(bbox(n))}
        if "z" in p:
            props[n]["z"] = list(p["z"])
        if n == "mouse":
            props[n]["silhouette_l"] = [[list(q) for q in poly] for poly in silhouette("mouse_l")]
    d = {"SY": SY, "SCREEN_U": list(SCREEN_U), "SCREEN_V": list(SCREEN_V), "LZ": LZ, "LANTERN_X": list(LANTERN_X),
         "LANTERN_Y": list(LANTERN_Y), "PROPS": props, "CAM": {"pos": list(cam_e), "look": list(look_e), "vfov": VFOV},
         "WIDE": list(WIDE), "LOOK_DISPLAY": {k: list(v) for k, v in LOOK_DISPLAY.items()}, "FRONT_X": FRONT_X, "FRONT_Y": FRONT_Y, "LAYER": LAYER, "LIGHT_D": LIGHT_D, "CANDLE": list(CANDLE), "BOUNCE": BOUNCE,
         "LEVEL": {"pit": list(LEVEL["pit"]), "door": list(LEVEL["door"]), "bonus": list(LEVEL["bonus"]),
                   "solids": {k: [list(p) for p in LEVEL[k]] for k in ("left_cliff", "right_cliff", "ledge")},
                   "thorns": [list(p) for p in thorn_polygon()],
                   "start": {k: (list(v) if isinstance(v, tuple) else v) for k, v in LEVEL_START.items()}},
         "RULES": RULES, "PUPPET": PUPPET, "DECOR_HALF": DECOR_HALF, "PROP_KIND": PROP_KIND, "PROP_MOVE": PROP_MOVE,
         "LEVELS": [level_data(lv) for lv in LEVELS],
         "MAPS": [{"id": m["id"], "name": m["name"], "unlock": m["unlock"], "trim": m["trim"], "intro": m.get("intro", "")} for m in MAPS],
         "STATE_A": {k: list(v) if isinstance(v, tuple) else v for k, v in STATE_A.items()},
         "STATE_B": {k: list(v) if isinstance(v, tuple) else v for k, v in STATE_B.items()},
         "SOLUTION": {k: list(v) if isinstance(v, tuple) else v for k, v in SOLUTION.items()}}
    if extra:
        d.update(extra)
    return d


def write_lua(path, extra=None):
    with open(path, "w", encoding="utf-8") as f:
        f.write("-- GENERATED by tools/gen_meshes.py from tools/sp_common.py. Do not edit: change sp_common.py and rerun.\n")
        f.write("return " + _lua(lua_data(extra)) + "\n")
