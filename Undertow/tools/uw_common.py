"""Numbers shared by Undertow's tools (Blender scene, bakes, meshes) and, later, the Lua rules (R.* in
undertow_rules.lua must copy these). Plain Python, no numpy, so Blender's interpreter imports it too.

Play-plane coordinates (Blender): x along the harbour (the run goes +x), y away from the camera, z up.
Water rests at z = 0. All play happens in the plane y = 0. Engine axes: (x, y, z)_engine = (x, z, -y).
"""
import math
import random

# ---------------------------------------------------------------- play plane
FLOAT_R = 0.42            # glass float radius
CHAIN_LINK = (0.075, 0.022, 0.13)   # chain link ring radius, wire radius, spacing (22:3x: 0.05 / 0.013 / 0.085 vanished at
                                    # 1280x720; the concept's chain reads as a clear dotted line)
HOOK_Z_BUOY = 4.6         # hook height on a channel buoy's lamp arm (z above still water)
HOOK_Z_PIER = 5.2         # hook height on a pier lamp arm
CHAIN_MIN, CHAIN_MAX = 2.6, 4.1   # chain length = distance float->hook at hook time, clamped (longer reels in)
REACH = 7.5               # a hook is reachable when it is ahead of the float and of the last hook used, within this distance
                          # (LOOKPLAN: 7.5; was 5.2, too tight for a person). CHAIN_MAX stays 4.1, not LOOKPLAN's 4.8: from
                          # the 4.6 hooks a 4.8 chain puts the float's bottom at -0.62, under every swing's water.
BUOY_BACK = 1.6           # buoy bodies stand this far behind the play plane; their arm reaches to y = 0
ARM_FWD = 0.9             # hook sits this far ahead (+x) of the buoy's tower axis
SPACING = (7.0, 10.0)     # seeded buoy spacing along x (grows with distance via DIFFICULTY)

# ---------------------------------------------------------------- game camera (follows the float)
# Camera = float.x + CAM_DX, fixed y and z; it looks along (yaw, pitch). Lens is Blender mm on a 36 mm
# sensor fitted horizontally (engine: fovx = 2 * atan(18 / LENS)).
CAM_DX, CAM_Y, CAM_Z = -0.15, -11.5, 1.7
CAM_YAW = 9.0             # degrees, turned toward +x (three-quarter look ahead along the run)
CAM_PITCH = 5.2           # degrees up: puts the horizon about 37% up the frame
LENS = 24.0
CAM_FOLLOW = 3.0          # 1/s, exponential follow of float.x (z is fixed; the float may leave the top)

# ---------------------------------------------------------------- sea
# The near sea is one frozen swell pattern H(x, y), periodic in x with SEA_P, that travels along x at SEA_C:
#     surface(x, y, t) = H(x - SEA_C * t, y)
# The engine draws it as pooled tile meshes (one cooked mesh per tile, vertex colours = troughs / backs / crest foam)
# slid along x every frame, so swells move smoothly and their foam stays on their crests. Small chop comes from a
# looping normal-map flipbook (RIPPLE_FRAMES textures). Components with nx > 0 roll toward the camera (SEA_C < 0).
SEA_P = 48.0              # tile period along x
SEA_C = -3.0              # pattern speed along x (units/s)
SEA_NEAR_Y = (-16.0, 64.0)   # displaced near sea; beyond it a flat far plane to the horizon
SEA_FADE_Y = (40.0, 64.0)    # swell amplitude fades to 0 over this band so the near tile meets the flat far plane
RIPPLE_P = 16.0           # normal / detail map repeat (units); SEA_P / RIPPLE_P must be an integer. Two ripple layers
RIPPLE_FRAMES, RIPPLE_FPS = 8, 6.0   # (fine wind chop + a coarser cross chop) under a patchy envelope, baked in one loop
# The game's ripple maps are mapped to the near sea in world depth, not repeated (22:1x): u = x / RIPPLE_P repeats along
# x, v runs once over RIPPLE_V with texels spread like screen rows (v ~ 1 / distance from the camera). So each depth has
# its own map rows: ripples too fine to resolve there are left out (no sparkling foil in the mid sea) and their slope
# goes into a roughness map instead (Toksvig-style, which the engine does not do: GBufferPS.hlsl:80-90).
RIPPLE_V = (-6.0, 64.0)


def _cam_d(y):
    return math.hypot(y - CAM_Y, CAM_Z)


def ripple_v(y):
    """Texture v (0..1) of world depth y on the near sea."""
    y = min(max(y, RIPPLE_V[0]), RIPPLE_V[1])
    a, b = 1.0 / _cam_d(RIPPLE_V[0]), 1.0 / _cam_d(RIPPLE_V[1])
    return (a - 1.0 / _cam_d(y)) / (a - b)


def ripple_y(v):
    """Inverse of ripple_v."""
    a, b = 1.0 / _cam_d(RIPPLE_V[0]), 1.0 / _cam_d(RIPPLE_V[1])
    d = 1.0 / (a - v * (a - b))
    return CAM_Y + math.sqrt(max(d * d - CAM_Z * CAM_Z, 0.0))


# Swell components: (amplitude, nx cycles per SEA_P, wavelength along y, phase)
# The second line (21:4x): a train almost parallel to the main swell, so the two beat along the crest (crest heights
# vary over each 48-unit tile) and the near crest no longer reads as one straight edge (state B's "seam").
SWELLS = [
    (0.34, 2, 15.0, 0.3),
    (0.14, 1, 13.0, 2.6),
    (0.24, 3, 9.5, 1.9),
    (0.14, -4, 5.5, 4.0),
    (0.06, 7, 3.1, 2.2),
    (0.03, -11, 1.9, 5.1),
]
CHOP = 1.0                # Gerstner steepness; sum(CHOP * a * k) must stay < 1
AMP = sum(c[0] for c in SWELLS)


def _fade(y):
    if y <= SEA_FADE_Y[0]:
        return 1.0
    return max(0.0, 1.0 - (y - SEA_FADE_Y[0]) / (SEA_FADE_Y[1] - SEA_FADE_Y[0]))


def sea_point(x, y):
    """Pattern vertex (Gerstner) for pattern coords (x, y): returns (x', y', z, jacobian)."""
    f = _fade(y)
    dx = dy = h = 0.0
    jxx = jyy = 1.0
    for a, nx, ly, ph in SWELLS:
        kx, ky = 2 * math.pi * nx / SEA_P, 2 * math.pi / ly
        k = math.hypot(kx, ky)
        s = kx * x + ky * y + ph
        h += a * math.sin(s)
        q = CHOP * a * math.cos(s)          # pulls vertices toward each crest: sharp crests, broad troughs
        dx += q * kx / k
        dy += q * ky / k
        jxx -= CHOP * a * math.sin(s) * kx * kx / k * f
        jyy -= CHOP * a * math.sin(s) * ky * ky / k * f
    return x + dx * f, y + dy * f, h * f, jxx * jyy


def pattern_height(x, y):
    """Height of the displaced pattern above pattern point (x, y): inverts the Gerstner shift (8 fixed-point steps, < 4 mm)."""
    x0, y0 = x, y
    for _ in range(8):
        px, py, _h, _j = sea_point(x0, y0)
        x0, y0 = x0 + (x - px), y0 + (y - py)
    return sea_point(x0, y0)[2]


# Swell "breathing": the frozen pattern's height swells and eases irregularly over time (the game scales the tiles'
# height by it), so the sea is not one rigid sliding shape. Zero at both target states (t = 5.0 and 8.88) so A and B
# match the targets: amp(t) = 1 + a * sin(pi (t - t0) / h) * cos(2 pi t / T).
SEA_BREATH = (0.15, 5.0, 3.88, 17.0)     # a, t0, h, T


def sea_amp(t):
    a, t0, h, T = SEA_BREATH
    return 1.0 + a * math.sin(math.pi * (t - t0) / h) * math.cos(2 * math.pi * t / T)


def sea_height(x, y, t=0.0):
    """Water surface height under world point (x, y) at time t."""
    return sea_amp(t) * pattern_height((x - SEA_C * t) % SEA_P, y)


# ---------------------------------------------------------------- course (seeded, endless)
# The two target frames sample the same course. Kinds: buoy_red, buoy_white (hooks), pier (hooks on lamp arms),
# boat (scenery behind the plane, or in-plane hazard), bw (breakwater segment, 12 long), bw_gap (8 long).
BW_Y = 19.0               # breakwater line, behind the play plane
GAP_X = 19.0              # where the target stretch's harbour mouth starts
BW_SEG, BW_GAP = 12.0, 8.0
PIER_Y = 2.6              # pier deck centre line (behind the plane; lamp arms reach to y = 0)
PIER_SEG = 8.0


def target_course():
    """The fixed stretch the two target frames show (x from about -30 to 80)."""
    c = [
        ("buoy_red", 0.0, {"lit": True, "no": 4}),
        ("buoy_white", 8.0, {"lit": False, "no": 7}),
        ("boat", 7.6, {"y": 12.0, "yaw": 172.0, "roll": 3.0}),     # clear of the float in state A
        ("pier", 28.0, {"segs": 2}),          # hooks at 28 + 4 and 28 + 12
        ("buoy_red", 46.5, {"lit": False, "no": 6}),
        ("boat", 38.5, {"y": 8.5, "yaw": 8.0, "roll": -3.0}),
        ("buoy_white", -8.0, {"lit": True, "no": 5}),
        # far channel markers (scenery, lit)
        ("buoy_red", 31.0, {"lit": True, "y": 13.0, "scale": 0.9, "no": 2}),
        ("buoy_white", -12.0, {"lit": True, "y": 13.0, "scale": 0.9, "no": 3}),
        ("buoy_red", 58.0, {"lit": True, "y": 16.0, "scale": 0.9, "no": 8}),
    ]
    x = GAP_X - 7 * BW_SEG
    while x < 110.0:
        if GAP_X <= x < GAP_X + BW_GAP:
            c.append(("bw_gap", x, {}))
            x += BW_GAP
        else:
            c.append(("bw", x, {}))
            x += BW_SEG
    return c


# Buoy number plates: red (port) buoys carry even numbers, white ones odd; the course numbers buoys in order and wraps
# after PLATE_N per colour, so two buoys in view never share a number (tests/view_smoke.lua checks a long scroll).
# The bake leaves the plate blank; the game draws the number as a decal in the buoy's own frame.
PLATE_N = 16              # numbers per colour: red 2, 4 .. 32; white 1, 3 .. 31
PLATE_SIZE = (0.46, 0.36)  # decal width, height (the plate is 0.52 x 0.42)


def plate_local(kind):
    """Buoy-local centre of the number plate's front face (as scene.py build_buoy draws it)."""
    deck = 1.0 if kind == "buoy_red" else 1.16
    z0, z1, pz = deck + 0.08, 3.35, 2.15
    py = -(0.58 + (0.27 - 0.58) * (pz - z0) / (z1 - z0)) - 0.05
    return (0.0, py - 0.0125, pz)


BUOY_TILT = (0.0, -3.0)   # default (roll, pitch) degrees of a buoy in the target frames; Lua bobs/tilts them live


def tilt_point(local, roll, pitch):
    """Rotate a buoy-local point by roll (about x) then pitch (about y), as Blender's XYZ Euler does."""
    x, y, z = local
    cr, sr = math.cos(math.radians(roll)), math.sin(math.radians(roll))
    y, z = y * cr - z * sr, y * sr + z * cr
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    x, z = x * cp + z * sp, -x * sp + z * cp
    return x, y, z


BOB_K = {"buoy": 0.6, "boat": 0.45}     # how much of the water's rise a floating piece follows
SINK = 0.05               # floating pieces sit this much lower than the bobbed water line


def piece_origin(kind, x, p, t=0.0):
    """World origin (x, y, z) of a placed piece at time t. Buoys and boats bob on the sea; piers and the breakwater
    stand still. For buoys x is the hook's x (the tower stands ARM_FWD behind it)."""
    sc = p.get("scale", 1.0)
    if kind.startswith("buoy"):
        y = p.get("y", BUOY_BACK)
        ox = x - ARM_FWD * sc
        return ox, y, BOB_K["buoy"] * sea_height(ox, y, t) - SINK
    if kind == "boat":
        y = p["y"]
        return x, y, BOB_K["boat"] * sea_height(x, y, t) - SINK
    if kind == "pier":
        return x, PIER_Y, 0.0
    return x, BW_Y, 0.0


def hook_world(kind, x, p, t=0.0):
    """World hook point of a hook-bearing piece (bob and buoy tilt included), Blender axes."""
    if kind == "pier":
        return (x + PIER_SEG / 2, 0.0, HOOK_Z_PIER)
    roll, pitch = p.get("roll", BUOY_TILT[0]), p.get("pitch", BUOY_TILT[1])
    hx, hy, hz = tilt_point((ARM_FWD, -BUOY_BACK, HOOK_Z_BUOY), roll, pitch)
    ox, oy, oz = piece_origin(kind, x, p, t)
    return (ox + hx, oy + hy, oz + hz)


# ---------------------------------------------------------------- reference states (the two target frames)
# hook = (kind, course x); theta = chain angle from straight down (+ = swung ahead), degrees; L = chain length;
# t = sea time. State A's t is chosen (find_skim_t) so the float's underside just skims the swell it is over.
STATES = {
    "A": {"hook": ("buoy_red", 0.0), "theta": 13.0, "L": 4.05, "t": 0.0, "spray": True, "lit_pier": False},
    "B": {"hook": ("pier", 36.0), "theta": 30.0, "L": 4.4, "t": 5.0, "spray": False, "lit_pier": True},
}


def float_pos(state, t=None):
    st = STATES[state]
    kind, x = st["hook"]
    tt = st["t"] if t is None else t
    hx, hy, hz = hook_world(kind, x, {}, tt)
    th = math.radians(st["theta"])
    return (hx + st["L"] * math.sin(th), hy, hz - st["L"] * math.cos(th)), (hx, hy, hz)


def find_skim_t(state="A", depth=0.06):
    """Sea time at which the water under the float rises to `depth` above the float's underside, on a rising back."""
    best = None
    for i in range(0, int(SEA_P / abs(SEA_C) / 0.02)):
        t = i * 0.02
        (fx, fy, fz), _ = float_pos(state, t)
        under = sea_height(fx, 0.0, t)
        rising = sea_height(fx, 0.0, t + 0.05) > under
        err = abs(under - (fz - FLOAT_R + depth))
        if rising and (best is None or err < best[0]):
            best = (err, t)
    return best[1]


STATES["A"]["t"] = round(find_skim_t("A"), 2)


def hooks(course):
    """Hook points (x, z) in the play plane for a course list."""
    out = []
    for kind, x, p in course:
        if kind.startswith("buoy") and p.get("y", BUOY_BACK) == BUOY_BACK and "scale" not in p:
            out.append((x, HOOK_Z_BUOY))
        elif kind == "pier":
            for s in range(p.get("segs", 1)):
                out.append((x + PIER_SEG * s + PIER_SEG / 2, HOOK_Z_PIER))
    return sorted(out)


# ---------------------------------------------------------------- rules (Assets/Scripts/uw_rules.lua reads these)
# Fixed step 120 Hz. The float hangs on a rigid chain while taut (RK4 pendulum), flies ballistically when released or
# when the chain goes slack. Hooking from further than CHAIN_MAX reels the chain in at REEL (this is the energy pump).
G = 9.81
DT = 1.0 / 120.0
REEL = 5.0                # chain reel-in speed (units/s) while longer than CHAIN_MAX
# Pump: skims and the chain snapping taut take energy out of a swing and nothing put it back, so a run could hang on a
# hook for ever with the next one out of reach (the 2,000-unit bot runs stalled on 16 of 20 seeds). While a taut swing's
# amplitude is below PUMP_THETA, the swell drags the float along its motion at PUMP_ACC (units/s^2); above it the
# pendulum is free (energy conserved).
PUMP_THETA = 75.0
PUMP_ACC = 1.5
START = {"theta": -78.0, "L": 3.0}    # the run starts hanging from the first hook, swung back (degrees, units). 3.0, not
# 4.05: the player waits on this swing before the first press; at 4.05 it met a crest in 60 of 60 one-minute waits
# (scratch/start_safe.lua), at 3.0 none (closest 0.55 above the water).
# Water: the float touches the water when its bottom goes below the surface. Relative to the moving surface, a hit at
# most SKIP_ANGLE degrees steep with at least SKIP_SPEED skips (SKIP_KEEP of the along-surface speed kept, SKIP_BOUNCE
# of the into-surface speed returned); anything else sinks. On a taut chain the float skims instead (SKIM_DRAG per
# second off its speed) unless it is slow, steep or its centre goes under.
SKIP_ANGLE = 22.0
SKIP_SPEED = 5.0
SKIP_KEEP = 0.85
SKIP_BOUNCE = 0.45
SKIM_DRAG = 0.4           # was 0.9: a 4.1 chain on a buoy skims at every bottom pass, and at 0.9 a one-minute hold sank in 11
                          # of 20 sea times (scratch/diag/hang.lua); at 0.4 none. Holding while the next hook comes into reach
                          # must not be a slow death.
RIDE_DEPTH = 0.2          # a chain only pulls: a hooked float (taut, or slack and coming in shallow) at speed rides over a crest
                          # with its bottom at most this far under the surface; the water lifts it and the chain goes slack. (It
                          # was held rigid, so a crest under a 4.1 chain - 0.07 above still water at the bottom - pushed the
                          # float's centre under and sank it: scratch/diag/boatfail.lua.)
# Pieces that reach into the play plane (their hit shapes are cut from the same meshes the game draws): channel buoys
# (lamp arm and the front of the fender), the pier front, moored boats lying alongside the plane, the breakwater head.
BOAT_IN_Y = 1.75          # moored boats: hull side (rubbing strake, fenders) in the plane
GAP_IN_Y = 2.45           # breakwater head (bw_gap) beside the plane: its toe rocks reach the plane
HOOK_CLEAR = 0.3          # margin added to the distance along x where a swing arc passes below a hazard's top
BOAT_RUNUP = 10.0         # a boat section starts with a buoy this far after the last hook. Hook to hook over a hull is 12.7-14.3
                          # (hull 5.9 long in the plane + the arc clearance either side), which no dead hang can fly (0 of 36,
                          # scratch/diag/dh_*.log); hooking that buoy from 10 away reels the chain in and pumps the swing enough
                          # from any hang on the hook before (scratch/diag/runup.log: 7/7 at chains 2.6/3.0/4.1).
HIT_CELL = 0.05           # hit grid cell (units)
# Score: distance (units) + LAMP_PTS per lamp lit (each hook) + CLEAN_PTS per clean release (next hook, no water).
LAMP_PTS, CLEAN_PTS = 10, 25
# Difficulty: one step every LEVEL_LEN units, LEVELS steps. Per step: hook spacing, chance of a hazard section,
# share of pier hooks (5.2 high; buoys hang 4.6 and dip with the swell), sea clock rate (faster, so taller-feeling swells).
LEVEL_LEN, LEVELS = 300.0, 6
LEVEL = {
    "spacing": [(6.5, 8.0), (7.0, 8.5), (7.5, 9.0), (8.0, 9.5), (8.5, 10.0), (9.0, 10.5)],
    "hazard": [0.15, 0.25, 0.35, 0.45, 0.55, 0.65],
    "pier": [0.30, 0.25, 0.20, 0.15, 0.10, 0.05],
    "sea_rate": [1.0, 1.1, 1.2, 1.3, 1.45, 1.6],
}
