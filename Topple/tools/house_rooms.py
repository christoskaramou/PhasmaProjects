"""Topple's house: one spec per room, read by tools/gen_house.py (which builds the shells, props, textures, the
rooms' data and the previews). The living room is not here: tools/gen_room.py still makes it.

Table units as everywhere in Topple: x right, y away from the default camera, h up; 1 unit = 5 cm (a Standard
domino's height). Each room is centred on the origin.

A furniture entry (furn()) is a Tripo candidate, furn_<room>_<item>: where it stands, its yaw (0/90/180/270: its local
front is -y, its back +y, the way a Tripo model comes in), its real-world design size (local x, y, h before the yaw)
and, from an archetype, the solids and surfaces the rules read. A prop entry is code-built by gen_house.py.

Heights to build on (units): counter 18, dining table 15, desk 15, chair seat 9, bed 10. Gaps: a Standard domino
(1.0 tall) passes under anything from 1.05 up, a Mini (0.667) under 0.75 - 0.95, which stops a Standard.
"""

# ------------------------------------------------------------------ archetypes (local: front -y, h from the base)


def bx(x0, x1, y0, y1, z0, z1, name):
    return dict(name=name, x0=x0, x1=x1, y0=y0, y1=y1, z0=z0, z1=z1)


def top(x0, x1, y0, y1, h, name, edge=True, board=True):
    return dict(name=name, x0=x0, x1=x1, y0=y0, y1=y1, h=h, edge=edge, board=board)


def refit(arch, surfaces=None, solids=None, z1=None, add=()):
    """An archetype corrected to what its imported model really has (measured from the cooked mesh with
    tools/fit_audit.lua's reader, 2026-11-11): surfaces and/or solids replaced, solid tops lowered (z1: name -> top),
    solids added. Local coordinates, as the archetype's."""
    if surfaces is not None:
        arch["surfaces"] = surfaces
    if solids is not None:
        arch["solids"] = solids
    for b in arch["solids"]:
        if z1 and b["name"] in z1:
            b["z1"] = z1[b["name"]]
    arch["solids"] = arch["solids"] + list(add)
    return arch


def a_block(sx, sy, sz, name, surface=True):
    """A closed piece standing on the floor: a cabinet, a box, a fridge. Its top is buildable if surface."""
    hx, hy = sx / 2, sy / 2
    return dict(solids=[bx(-hx, hx, -hy, hy, 0, sz, name)], surfaces=[top(-hx, hx, -hy, hy, sz, name)] if surface else [])


def a_table(sx, sy, sz, name, leg=1.6, inset=1.0, slab=2.8, shelf=None):
    """Four legs and a top (slab: the top and its apron). shelf: (z0, z1) of a lower shelf between the legs."""
    hx, hy = sx / 2, sy / 2
    S = [bx(-hx, hx, -hy, hy, sz - slab, sz, name)]
    for x in (-hx + inset, hx - inset - leg):
        for y in (-hy + inset, hy - inset - leg):
            S.append(bx(x, x + leg, y, y + leg, 0, sz - slab, name + " leg"))
    if shelf:
        S.append(bx(-hx + inset, hx - inset, -hy + inset, hy - inset, shelf[0], shelf[1], name + " shelf"))
    return dict(solids=S, surfaces=[top(-hx, hx, -hy, hy, sz, name)])


def a_chair(sx, sy, seat, back_h, name, stretch=None, leg=0.9, seat_t=0.9, rockers=False):
    """Legs, a seat, a back along local +y, stretchers between the legs at stretch = (z0, z1) (the gap under them)."""
    hx, hy = sx / 2, sy / 2
    S = []
    for x in (-hx + 0.2, hx - 0.2 - leg):
        for y in (-hy + 0.2, hy - 0.2 - leg):
            S.append(bx(x, x + leg, y, y + leg, 0, seat - seat_t, name + " leg"))
    S.append(bx(-hx, hx, -hy, hy, seat - seat_t, seat, name + " seat"))
    S.append(bx(-hx, hx, hy - 1.0, hy, seat, back_h, name + " back"))
    if stretch:
        z0, z1 = stretch
        for x in (-hx + 0.2, hx - 0.2 - leg):                  # sides
            S.append(bx(x + 0.2, x + leg - 0.2, -hy + 0.2 + leg, hy - 0.2 - leg, z0, z1, name + " stretcher"))
        for y in (-hy + 0.2, hy - 0.2 - leg):                  # front and back
            S.append(bx(-hx + 0.2 + leg, hx - 0.2 - leg, y + 0.2, y + leg - 0.2, z0, z1, name + " stretcher"))
    if rockers:
        for x in (-hx + 0.2, hx - 0.2 - leg):
            S.append(bx(x, x + leg, -hy, hy, 0, 1.2, name + " rocker"))
    return dict(solids=S, surfaces=[top(-hx, hx, -hy, hy - 1.0, seat, name + " seat")],
                gaps=[dict(solid=name + " stretcher", z0=stretch[0])] if stretch else [])


def a_bench(sx, sy, sz, name, shelf, leg=1.4):
    """A shoe bench: four legs, a seat, a slatted shelf for shoes at shelf = (z0, z1); dominoes pass under it."""
    hx, hy = sx / 2, sy / 2
    S = [bx(-hx, hx, -hy, hy, sz - 1.4, sz, name + " seat")]
    for x in (-hx, hx - leg):
        for y in (-hy, hy - leg):
            S.append(bx(x, x + leg, y, y + leg, 0, sz - 1.4, name + " leg"))
    S.append(bx(-hx + leg, hx - leg, -hy + 0.3, hy - 0.3, shelf[0], shelf[1], name + " shelf"))
    return dict(solids=S, surfaces=[top(-hx, hx, -hy, hy, sz, name)], gaps=[dict(solid=name + " shelf", z0=shelf[0])])


def a_sideboard(sx, sy, sz, name, lift, leg=1.4):
    """A cabinet on short legs: the gap under its body is lift tall."""
    hx, hy = sx / 2, sy / 2
    S = [bx(-hx, hx, -hy, hy, lift, sz, name)]
    for x in (-hx + 0.6, hx - 0.6 - leg):
        for y in (-hy + 0.6, hy - 0.6 - leg):
            S.append(bx(x, x + leg, y, y + leg, 0, lift, name + " leg"))
    return dict(solids=S, surfaces=[top(-hx, hx, -hy, hy, sz, name)], gaps=[dict(solid=name, z0=lift)])


def a_counter(sx, sy, sz, name, worktop=1.2, kick=1.6, recess=0.9):
    """A run of base units: plinth set back, carcass, worktop overhanging the front."""
    hx, hy = sx / 2, sy / 2
    S = [bx(-hx, hx, -hy + recess + 0.6, hy, 0, kick, name + " plinth"),
         bx(-hx, hx, -hy + recess, hy, kick, sz - worktop, name),
         bx(-hx, hx, -hy, hy, sz - worktop, sz, name + " worktop")]
    return dict(solids=S, surfaces=[top(-hx, hx, -hy, hy - 0.4, sz, name)])


def a_desk(sx, sy, sz, name, ped=8.0, slab=1.6):
    """A partners' desk: two drawer pedestals, a top over the knee hole, a modesty panel at the back."""
    hx, hy = sx / 2, sy / 2
    S = [bx(-hx, hx, -hy, hy, sz - slab, sz, name),
         bx(-hx, -hx + ped, -hy + 0.4, hy, 0, sz - slab, name + " pedestal"),
         bx(hx - ped, hx, -hy + 0.4, hy, 0, sz - slab, name + " pedestal"),
         bx(-hx + ped, hx - ped, hy - 1.0, hy, 5.0, sz - slab, name + " panel")]
    return dict(solids=S, surfaces=[top(-hx, hx, -hy, hy, sz, name)])


def a_bed(sx, sy, mattress, head_h, foot_h, name):
    """Bed base and mattress (top buildable), a headboard at local +y, a low footboard at -y."""
    hx, hy = sx / 2, sy / 2
    S = [bx(-hx, hx, -hy + 1.0, hy - 1.2, 0, mattress, name),
         bx(-hx, hx, hy - 1.2, hy, 0, head_h, name + " headboard"),
         bx(-hx, hx, -hy, -hy + 1.0, 0, foot_h, name + " footboard")]
    return dict(solids=S, surfaces=[top(-hx + 0.3, hx - 0.3, -hy + 1.0, hy - 1.2, mattress, name, board=True)])


def a_tub(sx, sy, sz, name, wall=1.2, lift=1.8, floor_h=3.2):
    """A roll-top bath on feet: four walls, a raised inner floor (buildable), rims you can stand a domino on."""
    hx, hy = sx / 2, sy / 2
    S = [bx(-hx, hx, -hy, -hy + wall, lift, sz, name + " side"), bx(-hx, hx, hy - wall, hy, lift, sz, name + " side"),
         bx(-hx, -hx + wall, -hy + wall, hy - wall, lift, sz, name + " end"), bx(hx - wall, hx, -hy + wall, hy - wall, lift, sz, name + " end"),
         bx(-hx + wall, hx - wall, -hy + wall, hy - wall, lift, floor_h, name + " bottom")]
    for x in (-hx + 1.5, hx - 3.0):
        for y in (-hy + 1.0, hy - 2.5):
            S.append(bx(x, x + 1.5, y, y + 1.5, 0, lift, name + " foot"))
    F = [top(-hx + wall, hx - wall, -hy + wall, hy - wall, floor_h, name + " inside", board=True),
         top(-hx, hx, -hy, -hy + wall, sz, name + " rim"),
         top(-hx, -hx + wall, -hy + wall, hy - wall, sz, name + " rim end"),
         top(hx - wall, hx, -hy + wall, hy - wall, sz, name + " rim end")]
    return dict(solids=S, surfaces=F, gaps=[dict(solid=name + " side", z0=lift)])


def a_sink(sx, sy, sz, name):
    """A pedestal basin: a column near the wall (local +y) under a basin."""
    hx, hy = sx / 2, sy / 2
    return dict(solids=[bx(-1.8, 1.8, hy - 4.6, hy, 0, sz - 4.5, name + " pedestal"), bx(-hx, hx, -hy, hy, sz - 4.5, sz, name)], surfaces=[])


def a_post(sx, sy, sz, name, base_h=0.9, pole=1.4, crown=None):
    """A coat stand or standard lamp: a footed base, a pole, a crown (z0) as wide as the base."""
    hx, hy = sx / 2, sy / 2
    S = [bx(-hx, hx, -hy, hy, 0, base_h, name + " base"), bx(-pole / 2, pole / 2, -pole / 2, pole / 2, base_h, sz, name)]
    if crown is not None:
        S.append(bx(-hx, hx, -hy, hy, crown, sz, name + " top"))
    return dict(solids=S, surfaces=[])


def a_globe(sx, sy, sz, name):
    hx, hy = sx / 2, sy / 2
    return dict(solids=[bx(-hx * 0.75, hx * 0.75, -hy * 0.75, hy * 0.75, 0, 1.2, name + " base"), bx(-0.8, 0.8, -0.8, 0.8, 1.2, sz - sx, name + " stand"),
                        bx(-hx, hx, -hy, hy, sz - sx, sz, name)], surfaces=[])


def a_crane(sx, sy, sz, name):
    """A toy crane, as the imported model is (8 x 4.3 x 9.8, measured): a wheeled base whose top (2.87) is buildable
    round a mast, a jib along local x at 7.8 - 9.84 with a hook hanging under its -x tip (3.4 - 5.1)."""
    return dict(solids=[bx(-0.25, 3.3, -2.0, 2.0, 0, 2.87, name + " base"),
                        bx(-0.1, 3.1, -2.3, -2.0, 0, 1.1, name + " wheels"), bx(-0.1, 3.1, 2.0, 2.3, 0, 1.1, name + " wheels"),
                        bx(0.7, 2.35, -0.85, 0.85, 2.87, 8.2, name + " mast"), bx(-3.95, 4.0, -0.5, 0.5, 7.8, 9.84, name + " jib"),
                        bx(-4.0, -3.5, -0.2, 0.2, 3.4, 5.1, name + " hook")],
                surfaces=[top(-0.1, 3.2, -1.75, 1.75, 2.87, name)])


# Each imported model's weight once cooked (tools/mesh_reduce.py: meshoptimizer's attribute-aware simplifier, the
# texture resized): by how big it is on screen at the room's camera, from its largest side. A small prop (under 10)
# 4,000 faces and a 512 texture; a medium piece (up to 25) 8,000 and 1024; large furniture 12,000 and 1024. A piece that
# looks worse at the room camera gets its own furn(..., faces=, tex=).
WEIGHTS = ((10.0, 4000, 512), (25.0, 8000, 1024), (1e9, 12000, 1024))


def weight(f):
    """(face target, texture px) for a furniture entry."""
    side = max(f["size"])
    rule = next(w for w in WEIGHTS if side < w[0])
    return f.get("faces") or rule[1], f.get("tex") or rule[2]


def furn(item, at, size, yaw=0, z=0.0, arch=None, guess=None, goal=False, decor=False, turn=0, shrink=1.0, fit=None, over=0.0,
         faces=None, tex=None, factors=None, lock_tops=False):
    """guess: why the design size is a guess (no standard real-world size), shown in the report. decor: an optional
    piece placed clear of every challenge (a solid, nothing to build on). turn: quarter turns (degrees) that bring the
    imported model's front to the spec's front (-y before the yaw). shrink: a uniform factor (< 1) on the fit inside the
    box, for a model whose top would otherwise stand above the spec's surface. fit="axes": fitted per axis instead (tools/
    gen_house.py axis_fit), for a model whose uniform fit leaves its top off the spec's surface."""
    d = dict(item=item, at=at, size=size, yaw=yaw, z=z, arch=arch, guess=guess, goal=goal, decor=decor, turn=turn, shrink=shrink)
    if faces:
        d["faces"] = faces      # (an override of weight()'s rule)
    if factors:
        d["factors"] = factors  # (a per-axis fit kept as it was cooked, x y h on the uniform import: the spec follows it)
    if lock_tops:
        d["lock_tops"] = True   # (its buildable tops locked when it is simplified)
    if tex:
        d["tex"] = tex
    if fit:
        d["fit"] = fit          # over: how far the model may stand above its box once fitted (a tap, a chair's top rail)
        d["over"] = over
    return d


# ------------------------------------------------------------------ the rooms
SKIRT_T = 0.4
SUN_COLOR = (1.0, 0.86, 0.68)

HALL = dict(
    id="hall", name="Hallway", x0=-18.0, x1=18.0, y0=-48.0, y1=48.0, wall_h=52.0,
    floor=dict(kind="herringbone", S=16.0), wall=dict(kind="hall"), ceiling=(0.88, 0.85, 0.79), trim=(0.93, 0.91, 0.86),
    windows=[dict(side="L", a0=16.0, a1=30.0, h0=14.0, h1=42.0, curtains=None)],
    fanlights=[dict(side="B", a0=-8.0, a1=8.0, h0=44.4, h1=49.4)],
    doors=[dict(side="B", a0=-8.0, a1=8.0, h1=42.0, color=(0.1, 0.24, 0.2), glazed=True),
           dict(side="R", a0=-30.0, a1=-14.0, h1=41.0, color=(0.93, 0.91, 0.86)),
           dict(side="L", a0=-40.0, a1=-24.0, h1=41.0, color=(0.93, 0.91, 0.86))],
    sun=dict(dir=(0.8, -0.18, -0.58), intensity=5.0), fill=dict(dir=(-0.35, -0.8, -0.45), intensity=0.45),
    lamp=dict(at=(0.0, 0.0, 42.0), color=(1.0, 0.76, 0.48), intensity=3.0, radius=70.0),
    camera=dict(target=(0.0, -6.0, 1.0), yaw=-58.0, pitch=44.0, dist=118.0),
    furniture=[
        furn("bench", (-13.6, 2.0), (24.0, 8.0, 10.0), factors=(1.0324, 1.0436, 1.0013), yaw=90, arch=refit(a_bench(24.0, 8.0, 10.0, "shoe bench", shelf=(1.15, 1.6)), surfaces=[top(-11.3, 11.3, -3.35, 3.35, 10.0, "shoe bench")]), fit="axes"),
        furn("shoes", (-13.6, 2.0), (6.0, 18.0, 3.0), z=1.6, arch=a_block(6.0, 18.0, 3.0, "shoes", surface=False),
             guess="two pairs of shoes side by side on the bench's shelf"),
        furn("coatstand", (-12.6, 38.0), (7.0, 7.0, 36.0), arch=a_post(7.0, 7.0, 36.0, "coat stand", crown=20.0)),
        furn("umbrellastand", (14.0, 30.0), (5.0, 5.0, 12.0), arch=a_block(5.0, 5.0, 12.0, "umbrella stand", surface=False)),
        furn("clock", (-13.6, 44.6), (8, 5.9, 28.55), yaw=0, z=0.0, arch=a_block(8, 5.9, 28.55, "grandfather clock", surface=False), decor=True),
        furn("plant", (12.6, -42.0), (5.9, 7, 17.35), yaw=0, z=0.0, arch=a_block(5.9, 7, 17.35, "snake plant", surface=False), decor=True),
    ],
    props=[
        dict(kind="rug", name="runner", x0=-6.0, x1=8.0, y0=-40.0, y1=35.0, tex="runner"),
        dict(kind="parcels", boxes=[(8.6, 17.4, -6.0, 3.0, 0.0, 6.4), (10.0, 16.2, -4.6, 1.6, 6.4, 10.6)]),
        dict(kind="doorbell", x0=10.0, x1=14.4, y0=45.4, y1=47.6, h=3.4),
        dict(kind="pendant", style="lantern", at=(0.0, 0.0), h=42.0),
        dict(kind="art", side="R", frames=[(-6.0, 6.0, 22.0, 34.0, 1), (12.0, 22.0, 20.0, 34.0, 0)]),
    ],
    spots=dict(goal=dict(object="doorbell", x=12.2, y=44.6, h=0.0), traps=[
        dict(trap="gap under the shoe bench", kind="gap", x0=-17.6, x1=-9.6, y0=-10.0, y1=14.0, z0=0.0, z1=1.15,
             note="a Standard domino passes under the shoe shelf, a Large does not")]),
)

KITCHEN = dict(
    id="kitchen", name="Kitchen", x0=-36.0, x1=36.0, y0=-30.0, y1=30.0, wall_h=48.0,
    floor=dict(kind="checker", S=8.0), wall=dict(kind="kitchen"), ceiling=(0.93, 0.92, 0.88), trim=(0.92, 0.9, 0.84), skirting=False,
    windows=[dict(side="B", a0=-28.0, a1=-8.0, h0=24.0, h1=42.0, curtains=None)],
    doors=[dict(side="L", a0=-22.0, a1=-6.0, h1=41.0, color=(0.36, 0.5, 0.44))],
    sun=dict(dir=(0.28, -0.72, -0.64), intensity=5.2), fill=dict(dir=(-0.35, -0.8, -0.45), intensity=0.45),
    lamp=dict(at=(-4.0, -10.0, 37.0), color=(1.0, 0.78, 0.5), intensity=3.0, radius=60.0),
    camera=dict(target=(-2.0, -2.0, 4.0), yaw=-64.0, pitch=40.0, dist=100.0),
    furniture=[
        furn("counter", (-12.6, 23.6), (46.0, 12.0, 18.0), arch=a_counter(46.0, 12.0, 18.0, "counter"), fit="axes"),
        furn("oven", (16.6, 23.6), (12.0, 12.0, 18.6), arch=a_block(12.0, 12.0, 18.6, "oven", surface=False)),
        furn("fridge", (29.4, 22.9), (12.0, 13.0, 38.0), arch=a_block(12.0, 13.0, 38.0, "fridge", surface=False)),
        furn("table", (-4.0, -10.0), (30.0, 17.0, 15.0), arch=a_table(30.0, 17.0, 15.0, "kitchen table", leg=1.5, slab=2.6), fit="axes"),
        furn("chair", (-12.0, 3.5), (9.0, 9.0, 19.0), arch=a_chair(9.0, 9.0, 9.0, 19.0, "chair", stretch=(1.2, 1.6)), fit="axes", over=0.45),
        furn("chair", (4.0, 3.5), (9.0, 9.0, 19.0), arch=a_chair(9.0, 9.0, 9.0, 19.0, "chair", stretch=(1.2, 1.6)), fit="axes", over=0.45),
        furn("chair", (-12.0, -23.5), (9.0, 9.0, 19.0), yaw=180, arch=a_chair(9.0, 9.0, 9.0, 19.0, "chair", stretch=(1.2, 1.6)), fit="axes", over=0.45),
        furn("chair", (4.0, -23.5), (9.0, 9.0, 19.0), yaw=180, arch=a_chair(9.0, 9.0, 9.0, 19.0, "chair", stretch=(1.2, 1.6)), fit="axes", over=0.45),
        furn("kettle", (-29.0, 25.0), (5.0, 3.6, 5.4), z=18.0, arch=a_block(5.0, 3.6, 5.4, "kettle", surface=False)),
        furn("herbs", (6.6, 26.9), (7, 2.7, 4.85), faces=8000, yaw=0, z=18.0, arch=a_block(7, 2.7, 4.85, "herb pots", surface=False), decor=True),
    ],
    props=[
        dict(kind="rug", name="mat", x0=-28.0, x1=0.0, y0=9.4, y1=15.0, tex="mat"),
        dict(kind="toaster", x0=-4.1, x1=2.1, y0=23.0, y1=27.0, h0=18.0, h1=21.74),
        dict(kind="shelf", side="B", a0=2.0, a1=14.0, h=31.0, depth=3.2, items="jars"),
        dict(kind="pendant", style="enamel", at=(-4.0, -10.0), h=37.0),
    ],
    spots=dict(goal=dict(object="toaster", x=-1.0, y=21.6, h=18.0), traps=[
        dict(trap="drop off the counter edge", kind="edge", x0=-35.6, x1=10.4, y0=17.6, y1=17.6, h=18.0,
             note="the worktop's front edge: a domino lying past it tumbles 18 down to the floor"),
        dict(trap="gap between chair legs", kind="gap", x0=-16.5, x1=-7.5, y0=-1.0, y1=8.0, z0=0.0, z1=1.2,
             note="under the chair's stretchers: a Standard passes, a Large does not")]),
)

DINING = dict(
    id="dining", name="Dining Room", x0=-44.0, x1=44.0, y0=-32.0, y1=32.0, wall_h=52.0,
    floor=dict(kind="boards", S=16.0, tone=(0.36, 0.22, 0.13), board=2.4), wall=dict(kind="dining"), ceiling=(0.9, 0.86, 0.78), trim=(0.92, 0.88, 0.8),
    windows=[dict(side="L", a0=-14.0, a1=10.0, h0=14.0, h1=42.0, curtains=(0.22, 0.24, 0.16))],
    doors=[dict(side="R", a0=-26.0, a1=-10.0, h1=42.0, color=(0.92, 0.88, 0.8))],
    sun=dict(dir=(0.8, -0.2, -0.56), intensity=5.2), fill=dict(dir=(-0.35, -0.8, -0.45), intensity=0.45),
    lamp=dict(at=(0.0, -2.0, 36.0), color=(1.0, 0.74, 0.44), intensity=3.2, radius=70.0),
    camera=dict(target=(0.0, -2.0, 6.0), yaw=-62.0, pitch=38.0, dist=116.0),
    furniture=[
        furn("table", (0.0, -2.0), (44.0, 20.0, 15.0), arch=a_table(44.0, 20.0, 15.0, "dining table", leg=1.8, inset=1.6, slab=3.0), fit="axes"),
        furn("sideboard", (0.0, 27.1), (36.0, 9.0, 17.0), arch=a_sideboard(36.0, 9.0, 17.0, "sideboard", lift=0.85), fit="axes"),
        furn("recordplayer", (10.0, 27.1), (9.0, 7.4, 3.6), z=17.0, arch=a_block(9.0, 7.4, 3.6, "record player", surface=False), goal=True,
             guess="a portable player with its lid off: 45 x 37 x 18 cm"),
        furn("candelabra", (6.0, -2.0), (6.4, 6.4, 12.35), yaw=0, z=15.0, arch=a_block(6.4, 6.4, 12.35, "candelabra", surface=False), decor=True),
    ] + [furn("chair", (x, 13.25), (9.0, 9.5, 21.0), yaw=0, arch=a_chair(9.0, 9.5, 9.0, 21.0, "chair", stretch=(0.85, 1.25)), shrink=0.968, fit="axes") for x in (-14.0, 0.0, 14.0)]
      + [furn("chair", (x, -17.25), (9.0, 9.5, 21.0), yaw=180, arch=a_chair(9.0, 9.5, 9.0, 21.0, "chair", stretch=(0.85, 1.25)), shrink=0.968, fit="axes") for x in (-14.0, 0.0, 14.0)],
    props=[
        dict(kind="rug", name="rug", x0=-30.0, x1=30.0, y0=-27.0, y1=21.0, tex="dining"),
        dict(kind="glass_tower", x=-16.0, y=-2.0, h=15.0, tiers=3),
        dict(kind="pendant", style="chandelier", at=(0.0, -2.0), h=36.0),
        dict(kind="art", side="B", frames=[(-14.0, -2.0, 24.0, 38.0, 0), (2.0, 14.0, 24.0, 38.0, 1)]),
    ],
    spots=dict(goal=dict(object="record player", x=10.0, y=22.6, h=17.0), traps=[
        dict(trap="gap only a Mini fits: under the chairs' stretchers", kind="gap", x0=-18.5, x1=18.5, y0=8.5, y1=18.0, z0=0.0, z1=0.85,
             note="stretcher underside 0.85: a Mini (0.667) passes, a Standard does not"),
        dict(trap="gap only a Mini fits: under the sideboard", kind="gap", x0=-18.0, x1=18.0, y0=22.6, y1=31.6, z0=0.0, z1=0.85),
        dict(trap="fragile glass tower", kind="support", x0=-19.0, x1=-13.0, y0=-5.0, y1=1.0, z0=15.0, z1=20.6,
             note="three tiers of glasses under a wooden tray; its top (20.6) is where preset dominoes stand")]),
)

KIDS = dict(
    id="kids", name="Kids' Room", x0=-32.0, x1=32.0, y0=-32.0, y1=32.0, wall_h=46.0,
    floor=dict(kind="carpet", S=16.0), wall=dict(kind="kids"), ceiling=(0.95, 0.94, 0.9), trim=(0.96, 0.95, 0.92),
    windows=[dict(side="B", a0=4.0, a1=24.0, h0=20.0, h1=40.0, curtains=(0.85, 0.62, 0.2))],
    doors=[dict(side="R", a0=-8.0, a1=8.0, h1=40.0, color=(0.96, 0.95, 0.92))],
    sun=dict(dir=(-0.22, -0.78, -0.58), intensity=5.0), fill=dict(dir=(-0.35, -0.8, -0.45), intensity=0.5),
    lamp=dict(at=(0.0, 0.0, 40.0), color=(1.0, 0.8, 0.56), intensity=2.8, radius=60.0),
    camera=dict(target=(0.0, -2.0, 3.0), yaw=-118.0, pitch=42.0, dist=96.0),
    furniture=[
        furn("bed", (-21.8, 12.8), (19.6, 37.6, 10.0), factors=(1.0274, 1.1781, 1.0840), arch=refit(a_bed(19.6, 37.6, 10.0, 20.0, 12.5, "bed"), surfaces=[top(-8.4, 7.4, -16.2, 11.8, 9.95, "bed")], z1={"bed": 9.95},
                                                                        add=[bx(-5.25, 5.25, 11.8, 16.3, 9.95, 10.7, "bed pillow")]), fit="axes", over=1.7),
        furn("toybox", (-4.0, 27.6), (14.0, 8.0, 8.0), arch=a_block(14.0, 8.0, 8.0, "toy box"), fit="axes"),
        furn("rockinghorse", (21.6, 21.0), (7.0, 20.0, 17.0), yaw=90, turn=90, arch=a_block(7.0, 20.0, 17.0, "rocking horse", surface=False),
             guess="a nursery rocking horse, 100 cm long and 85 cm to the ears"),
        furn("crane", (22.0, -20.0), (8.0, 8.0, 18.0), turn=180, arch=a_crane(8.0, 8.0, 18.0, "toy crane"),
             guess="a wooden toy crane 90 cm tall with its jib reaching 40 cm out over the floor"),
        furn("train", (-7.0, -23.5), (9.0, 2.8, 4.0), z=0.35, arch=a_block(9.0, 2.8, 4.0, "toy train", surface=False), goal=True,
             guess="a wooden engine and tender, 45 cm long"),
        furn("teddy", (-9.6, 21.0), (3.7, 4, 5.95), yaw=0, z=0.0, arch=a_block(3.7, 4, 5.95, "teddy bear", surface=False), decor=True),
        furn("drum", (27.0, 12.5), (5.2, 5.2, 4.1), faces=8000, yaw=0, z=0.0, arch=a_block(5.2, 5.2, 4.1, "toy drum", surface=False), decor=True),
    ],
    props=[
        dict(kind="rug", name="playmat", x0=-27.0, x1=11.0, y0=-30.0, y1=-7.0, tex="playmat", h=0.1),
        dict(kind="track", cx=-7.0, cy=-17.0, rx=14.0, ry=6.5, h=0.1),
        dict(kind="block_bridge", x0=3.6, x1=19.0, y0=25.4, y1=29.8, h=8.4),
        dict(kind="pendant", style="star", at=(0.0, 0.0), h=40.0),
        dict(kind="art", side="L", frames=[(-26.0, -12.0, 26.0, 36.0, 1)]),
    ],
    spots=dict(goal=dict(object="toy train", x=-7.0, y=-26.1, h=0.1), traps=[
        dict(trap="fragile block tower holding a bridge", kind="support", x0=3.6, x1=19.0, y0=25.4, y1=29.8, z0=0.0, z1=8.4,
             note="building blocks: two towers under a plank, its top level with the toy box's lid (8.0, a climb of 0.4)"),
        dict(trap="string on a toy crane", kind="string", a=(18.3, -20.0, 7.8), hook=(18.3, -20.0, 3.4),
             note="the crane's jib tip (under its pulley, 4.4 out from the mast, 7.8 up); its hook hangs 3.4 above the floor")]),
)

BATH = dict(
    id="bath", name="Bathroom", x0=-26.0, x1=26.0, y0=-24.0, y1=24.0, wall_h=46.0,
    floor=dict(kind="mosaic", S=8.0), wall=dict(kind="bath"), ceiling=(0.95, 0.95, 0.93), trim=(0.96, 0.96, 0.94), skirting=False,
    windows=[dict(side="L", a0=-2.0, a1=12.0, h0=24.0, h1=40.0, curtains=None, frosted=True)],
    doors=[dict(side="R", a0=-21.0, a1=-7.0, h1=40.0, color=(0.96, 0.96, 0.94))],
    sun=dict(dir=(0.78, -0.12, -0.6), intensity=4.6), fill=dict(dir=(-0.35, -0.8, -0.45), intensity=0.55),
    lamp=dict(at=(0.0, 0.0, 41.0), color=(1.0, 0.86, 0.66), intensity=2.6, radius=50.0),
    camera=dict(target=(-1.0, 0.0, 4.0), yaw=-60.0, pitch=42.0, dist=84.0),
    furniture=[
        furn("bathtub", (-8.6, 16.1), (34.0, 15.0, 12.0), factors=(1.1778, 1.1415, 1.1339), arch=refit(a_tub(34.0, 15.0, 12.0, "bathtub"),  # (the roll-top as modelled: its rim is flat only in these stretches)
                     surfaces=[top(-11, 11.6, -2.1, 2.1, 3.05, "bathtub inside"),
                               top(-9.4, 10.1, -7.36, -6.8, 11.95, "bathtub rim"),
                               top(10.023, 10.207, -7.251, -6.859, 11.95, "bathtub rim corner"),
                               top(10.422, 10.624, -7.198, -6.803, 11.95, "bathtub rim corner"),
                               top(10.821, 11.037, -7.123, -6.726, 11.95, "bathtub rim corner"),
                               top(11.214, 11.446, -7.025, -6.627, 11.95, "bathtub rim corner"),
                               top(11.601, 11.852, -6.909, -6.511, 11.95, "bathtub rim corner"),
                               top(11.983, 12.246, -6.768, -6.371, 11.95, "bathtub rim corner"),
                               top(12.355, 12.637, -6.609, -6.214, 11.95, "bathtub rim corner"),
                               top(12.715, 13.012, -6.419, -6.028, 11.95, "bathtub rim corner"),
                               top(13.067, 13.376, -6.21, -5.824, 11.95, "bathtub rim corner"),
                               top(13.407, 13.729, -5.983, -5.602, 11.95, "bathtub rim corner"),
                               top(13.732, 14.066, -5.733, -5.359, 11.95, "bathtub rim corner"),
                               top(14.044, 14.389, -5.465, -5.098, 11.95, "bathtub rim corner"),
                               top(14.341, 14.698, -5.179, -4.822, 11.95, "bathtub rim corner"),
                               top(14.618, 14.984, -4.871, -4.526, 11.95, "bathtub rim corner"),
                               top(14.879, 15.252, -4.549, -4.213, 11.95, "bathtub rim corner"),
                               top(15.12, 15.501, -4.21, -3.888, 11.95, "bathtub rim corner"),
                               top(15.344, 15.731, -3.858, -3.55, 11.95, "bathtub rim corner"),
                               top(15.547, 15.938, -3.493, -3.198, 11.95, "bathtub rim corner"),
                               top(15.732, 16.126, -3.119, -2.836, 11.95, "bathtub rim corner"),
                               top(15.893, 16.29, -2.731, -2.464, 11.95, "bathtub rim corner"),
                               top(16.038, 16.436, -2.335, -2.087, 11.95, "bathtub rim corner"),
                               top(16.156, 16.554, -1.931, -1.7, 11.95, "bathtub rim corner"),
                               top(16.245, 16.641, -1.517, -1.307, 11.95, "bathtub rim corner"),
                               top(16.313, 16.706, -1.102, -0.908, 11.95, "bathtub rim corner"),
                               top(16.516, 16.784, -0.788, -0.392, 11.95, "bathtub rim corner"),
                               top(-16.48, -15.98, -0.4, 0.44, 11.95, "bathtub rim end"),
                               top(16.32, 16.82, -0.6, 0.4, 11.95, "bathtub rim end")],
                     solids=[bx(-11.55, 11.85, -7.6, -7.1, 1.8, 11.95, "bathtub side"),
                             bx(-12.7, 13, -7.1, -6.6, 1.8, 11.95, "bathtub side"),
                             bx(-13.5, 13.85, -6.6, -6.1, 1.8, 11.95, "bathtub side"),
                             bx(-14.15, -11.05, -6.1, -5.6, 1.8, 11.95, "bathtub side"),
                             bx(11.35, 14.45, -6.1, -5.6, 1.8, 11.95, "bathtub side"),
                             bx(-14.65, -12.3, -5.6, -5.1, 1.8, 11.95, "bathtub side"),
                             bx(12.65, 15, -5.6, -5.1, 1.8, 11.95, "bathtub side"),
                             bx(-15.1, -13.1, -5.1, -4.6, 1.8, 11.95, "bathtub side"),
                             bx(13.45, 15.75, -5.1, -4.1, 1.8, 11.95, "bathtub side"),
                             bx(-15.75, -13.7, -4.6, -3.6, 1.8, 11.95, "bathtub side"),
                             bx(14.5, 16.3, -4.1, -3.1, 1.8, 11.95, "bathtub side"),
                             bx(-16.025, -13.95, -3.6, -3.1, 1.8, 11.95, "bathtub side"),
                             bx(-16.225, -14.25, -3.1, -2.6, 1.8, 11.95, "bathtub side"),
                             bx(-16.425, -14.525, -2.6, -2, 1.8, 11.95, "bathtub side"),
                             bx(-16.55, -14.7, -2, -1.4, 1.8, 11.95, "bathtub side"),
                             bx(-16.625, -14.825, -1.4, -0.8, 1.8, 11.95, "bathtub side"),
                             bx(-14.675, -14.575, -1.4, -0.8, 3.05, 4.7, "bathtub slope"),
                             bx(-14.575, -14.5, -1.4, -0.8, 3.05, 4.58, "bathtub slope"),
                             bx(-14.5, -14.425, -1.4, -0.8, 3.05, 4.47, "bathtub slope"),
                             bx(-14.425, -14.35, -1.4, -0.8, 3.05, 4.36, "bathtub slope"),
                             bx(-14.35, -14.275, -1.4, -0.8, 3.05, 4.25, "bathtub slope"),
                             bx(-14.275, -14.2, -1.4, -0.8, 3.05, 4.15, "bathtub slope"),
                             bx(-14.2, -14.125, -1.4, -0.8, 3.05, 4.04, "bathtub slope"),
                             bx(-14.125, -14.05, -1.4, -0.8, 3.05, 3.94, "bathtub slope"),
                             bx(-14.05, -13.975, -1.4, -0.8, 3.05, 3.83, "bathtub slope"),
                             bx(-13.975, -13.9, -1.4, -0.8, 3.05, 3.73, "bathtub slope"),
                             bx(-13.9, -13.85, -1.4, -0.8, 3.05, 3.65, "bathtub slope"),
                             bx(-13.85, -13.75, -1.4, -0.8, 3.05, 3.57, "bathtub slope"),
                             bx(-13.75, -12.775, -1.4, -0.8, 3.05, 3.43, "bathtub slope"),
                             bx(-12.775, -11, -1.4, -0.8, 3.05, 3.17, "bathtub slope"),
                             bx(-16.675, -14.875, -0.8, 0.8, 1.8, 11.95, "bathtub side"),
                             bx(-14.8, -14.675, -0.8, 0.8, 3.05, 4.75, "bathtub slope"),
                             bx(-14.675, -14.55, -0.8, 0.8, 3.05, 4.56, "bathtub slope"),
                             bx(-14.55, -14.425, -0.8, 0.8, 3.05, 4.38, "bathtub slope"),
                             bx(-14.425, -14.3, -0.8, 0.8, 3.05, 4.19, "bathtub slope"),
                             bx(-14.3, -14.175, -0.8, 0.8, 3.05, 4.01, "bathtub slope"),
                             bx(-14.175, -14.05, -0.8, 0.8, 3.05, 3.83, "bathtub slope"),
                             bx(-14.05, -13.925, -0.8, 0.8, 3.05, 3.66, "bathtub slope"),
                             bx(-13.925, -13.125, -0.8, 0.8, 3.05, 3.47, "bathtub slope"),
                             bx(-13.125, -11, -0.8, 0.8, 3.05, 3.19, "bathtub slope"),
                             bx(-16.65, -14.825, 0.8, 1.4, 1.8, 11.95, "bathtub side"),
                             bx(-14.675, -14.575, 0.8, 1.4, 3.05, 4.69, "bathtub slope"),
                             bx(-14.575, -14.5, 0.8, 1.4, 3.05, 4.57, "bathtub slope"),
                             bx(-14.5, -14.425, 0.8, 1.4, 3.05, 4.47, "bathtub slope"),
                             bx(-14.425, -14.35, 0.8, 1.4, 3.05, 4.36, "bathtub slope"),
                             bx(-14.35, -14.275, 0.8, 1.4, 3.05, 4.25, "bathtub slope"),
                             bx(-14.275, -14.2, 0.8, 1.4, 3.05, 4.14, "bathtub slope"),
                             bx(-14.2, -14.125, 0.8, 1.4, 3.05, 4.03, "bathtub slope"),
                             bx(-14.125, -14.05, 0.8, 1.4, 3.05, 3.93, "bathtub slope"),
                             bx(-14.05, -13.975, 0.8, 1.4, 3.05, 3.83, "bathtub slope"),
                             bx(-13.975, -13.9, 0.8, 1.4, 3.05, 3.73, "bathtub slope"),
                             bx(-13.9, -13.825, 0.8, 1.4, 3.05, 3.63, "bathtub slope"),
                             bx(-13.825, -13.475, 0.8, 1.4, 3.05, 3.53, "bathtub slope"),
                             bx(-13.475, -11.05, 0.8, 1.4, 3.05, 3.25, "bathtub slope"),
                             bx(-16.55, -14.7, 1.4, 2, 1.8, 11.95, "bathtub side"),
                             bx(-14.5, -14.475, 1.4, 2, 3.05, 4.71, "bathtub slope"),
                             bx(-14.475, -14.45, 1.4, 2, 3.05, 4.67, "bathtub slope"),
                             bx(-14.45, -14.425, 1.4, 2, 3.05, 4.64, "bathtub slope"),
                             bx(-14.425, -14.4, 1.4, 2, 3.05, 4.6, "bathtub slope"),
                             bx(-14.4, -14.375, 1.4, 2, 3.05, 4.57, "bathtub slope"),
                             bx(-14.375, -14.35, 1.4, 2, 3.05, 4.53, "bathtub slope"),
                             bx(-16.425, -14.525, 2, 2.6, 1.8, 11.95, "bathtub side"),
                             bx(-16.225, -14.25, 2.6, 3.1, 1.8, 11.95, "bathtub side"),
                             bx(-16.025, -13.95, 3.1, 3.6, 1.8, 11.95, "bathtub side"),
                             bx(-15.775, -13.525, 3.6, 4, 1.8, 11.95, "bathtub side"),
                             bx(-15.55, -13.1, 4, 4.4, 1.8, 11.95, "bathtub side"),
                             bx(14.575, 16.55, -3.1, -2.6, 1.8, 11.95, "bathtub side"),
                             bx(14.85, 16.75, -2.6, -2, 1.8, 11.95, "bathtub side"),
                             bx(15.025, 16.875, -2, -1.4, 1.8, 11.95, "bathtub side"),
                             bx(14.8, 14.825, -2, -1.4, 3.05, 4.71, "bathtub slope"),
                             bx(14.775, 14.8, -2, -1.4, 3.05, 4.68, "bathtub slope"),
                             bx(14.75, 14.775, -2, -1.4, 3.05, 4.64, "bathtub slope"),
                             bx(14.725, 14.75, -2, -1.4, 3.05, 4.61, "bathtub slope"),
                             bx(14.7, 14.725, -2, -1.4, 3.05, 4.58, "bathtub slope"),
                             bx(14.675, 14.7, -2, -1.4, 3.05, 4.54, "bathtub slope"),
                             bx(14.65, 14.675, -2, -1.4, 3.05, 4.51, "bathtub slope"),
                             bx(14.625, 14.65, -2, -1.4, 3.05, 4.48, "bathtub slope"),
                             bx(14.6, 14.625, -2, -1.4, 3.05, 4.44, "bathtub slope"),
                             bx(14.575, 14.6, -2, -1.4, 3.05, 4.41, "bathtub slope"),
                             bx(14.55, 14.575, -2, -1.4, 3.05, 4.37, "bathtub slope"),
                             bx(15.15, 16.975, -1.4, -0.8, 1.8, 11.95, "bathtub side"),
                             bx(14.925, 15, -1.4, -0.8, 3.05, 4.72, "bathtub slope"),
                             bx(14.85, 14.925, -1.4, -0.8, 3.05, 4.61, "bathtub slope"),
                             bx(14.775, 14.85, -1.4, -0.8, 3.05, 4.5, "bathtub slope"),
                             bx(14.7, 14.775, -1.4, -0.8, 3.05, 4.4, "bathtub slope"),
                             bx(14.625, 14.7, -1.4, -0.8, 3.05, 4.29, "bathtub slope"),
                             bx(14.55, 14.625, -1.4, -0.8, 3.05, 4.19, "bathtub slope"),
                             bx(14.475, 14.55, -1.4, -0.8, 3.05, 4.08, "bathtub slope"),
                             bx(14.4, 14.475, -1.4, -0.8, 3.05, 3.97, "bathtub slope"),
                             bx(14.35, 14.4, -1.4, -0.8, 3.05, 3.88, "bathtub slope"),
                             bx(14.3, 14.35, -1.4, -0.8, 3.05, 3.81, "bathtub slope"),
                             bx(14.25, 14.3, -1.4, -0.8, 3.05, 3.74, "bathtub slope"),
                             bx(14.2, 14.25, -1.4, -0.8, 3.05, 3.68, "bathtub slope"),
                             bx(14.15, 14.2, -1.4, -0.8, 3.05, 3.61, "bathtub slope"),
                             bx(13.9, 14.15, -1.4, -0.8, 3.05, 3.54, "bathtub slope"),
                             bx(11.8, 13.9, -1.4, -0.8, 3.05, 3.26, "bathtub slope"),
                             bx(15.2, 17, -0.8, 0.8, 1.8, 11.95, "bathtub side"),
                             bx(15, 15.125, -0.8, 0.8, 3.05, 4.75, "bathtub slope"),
                             bx(14.875, 15, -0.8, 0.8, 3.05, 4.56, "bathtub slope"),
                             bx(14.75, 14.875, -0.8, 0.8, 3.05, 4.38, "bathtub slope"),
                             bx(14.625, 14.75, -0.8, 0.8, 3.05, 4.19, "bathtub slope"),
                             bx(14.5, 14.625, -0.8, 0.8, 3.05, 4.01, "bathtub slope"),
                             bx(14.375, 14.5, -0.8, 0.8, 3.05, 3.83, "bathtub slope"),
                             bx(14.25, 14.375, -0.8, 0.8, 3.05, 3.65, "bathtub slope"),
                             bx(13.475, 14.25, -0.8, 0.8, 3.05, 3.47, "bathtub slope"),
                             bx(11.6, 13.475, -0.8, 0.8, 3.05, 3.19, "bathtub slope"),
                             bx(15.15, 16.975, 0.8, 1.4, 1.8, 11.95, "bathtub side"),
                             bx(14.975, 15.025, 0.8, 1.4, 3.05, 4.8, "bathtub slope"),
                             bx(14.875, 14.975, 0.8, 1.4, 3.05, 4.65, "bathtub slope"),
                             bx(14.775, 14.875, 0.8, 1.4, 3.05, 4.51, "bathtub slope"),
                             bx(14.7, 14.775, 0.8, 1.4, 3.05, 4.39, "bathtub slope"),
                             bx(14.625, 14.7, 0.8, 1.4, 3.05, 4.28, "bathtub slope"),
                             bx(14.55, 14.625, 0.8, 1.4, 3.05, 4.18, "bathtub slope"),
                             bx(14.475, 14.55, 0.8, 1.4, 3.05, 4.07, "bathtub slope"),
                             bx(14.4, 14.475, 0.8, 1.4, 3.05, 3.97, "bathtub slope"),
                             bx(14.325, 14.4, 0.8, 1.4, 3.05, 3.87, "bathtub slope"),
                             bx(14.25, 14.325, 0.8, 1.4, 3.05, 3.77, "bathtub slope"),
                             bx(14.175, 14.25, 0.8, 1.4, 3.05, 3.67, "bathtub slope"),
                             bx(14.1, 14.175, 0.8, 1.4, 3.05, 3.57, "bathtub slope"),
                             bx(13.4, 14.1, 0.8, 1.4, 3.05, 3.47, "bathtub slope"),
                             bx(11.6, 13.4, 0.8, 1.4, 3.05, 3.2, "bathtub slope"),
                             bx(15.025, 16.875, 1.4, 2, 1.8, 11.95, "bathtub side"),
                             bx(14.8, 14.825, 1.4, 2, 3.05, 4.7, "bathtub slope"),
                             bx(14.775, 14.8, 1.4, 2, 3.05, 4.67, "bathtub slope"),
                             bx(14.75, 14.775, 1.4, 2, 3.05, 4.63, "bathtub slope"),
                             bx(14.725, 14.75, 1.4, 2, 3.05, 4.6, "bathtub slope"),
                             bx(14.7, 14.725, 1.4, 2, 3.05, 4.57, "bathtub slope"),
                             bx(14.675, 14.7, 1.4, 2, 3.05, 4.53, "bathtub slope"),
                             bx(14.65, 14.675, 1.4, 2, 3.05, 4.5, "bathtub slope"),
                             bx(14.625, 14.65, 1.4, 2, 3.05, 4.47, "bathtub slope"),
                             bx(14.6, 14.625, 1.4, 2, 3.05, 4.43, "bathtub slope"),
                             bx(14.85, 16.75, 2, 2.6, 1.8, 11.95, "bathtub side"),
                             bx(14.6, 16.55, 2.6, 3.1, 1.8, 11.95, "bathtub side"),
                             bx(14.275, 16.35, 3.1, 3.6, 1.8, 11.95, "bathtub side"),
                             bx(13.85, 16.1, 3.6, 4, 1.8, 11.95, "bathtub side"),
                             bx(13.425, 15.875, 4, 4.4, 1.8, 11.95, "bathtub side"),
                             bx(-16.95, -15.15, -1.9, -0.42, 11.95, 13.4, "bathtub tap"),
                             bx(-16.95, -15.15, 0.46, 2, 11.95, 13.4, "bathtub tap"),
                             bx(-15.25, -13.35, 4.4, 4.9, 1.8, 11.95, "bathtub side"),
                             bx(13.7, 15.55, 4.4, 4.9, 1.8, 11.95, "bathtub side"),
                             bx(-14.85, -12.65, 4.9, 5.4, 1.8, 11.95, "bathtub side"),
                             bx(13, 15.2, 4.9, 5.4, 1.8, 11.95, "bathtub side"),
                             bx(-14.4, -11.65, 5.4, 5.9, 1.8, 11.95, "bathtub side"),
                             bx(12, 14.7, 5.4, 5.9, 1.8, 11.95, "bathtub side"),
                             bx(-13.8, -9.3, 5.9, 6.4, 1.8, 11.95, "bathtub side"),
                             bx(9.55, 14.15, 5.9, 6.4, 1.8, 11.95, "bathtub side"),
                             bx(-13.05, 13.4, 6.4, 6.9, 1.8, 11.95, "bathtub side"),
                             bx(-12.05, 12.4, 6.9, 7.4, 1.8, 11.95, "bathtub side"),
                             bx(-10.25, 10.6, 7.4, 7.9, 1.8, 11.95, "bathtub side"),
                             bx(-15.8, 15.8, -6.3, 6.3, 1.8, 3.05, "bathtub bottom"),
                             bx(-12.85, -10.2, -5.85, -3.1, 0, 1.8, "bathtub foot"),
                             bx(10.55, 13.2, -5.85, -3.1, 0, 1.8, "bathtub foot"),
                             bx(-12.85, -10.2, 3.15, 5.9, 0, 1.8, "bathtub foot"),
                             bx(10.55, 13.2, 3.15, 5.9, 0, 1.8, "bathtub foot")]), fit="axes", over=1.7),
        furn("sink", (-21.6, -12.0), (10.0, 8.0, 17.0), yaw=90, arch=a_sink(10.0, 8.0, 17.0, "basin")),
        furn("stool", (3.0, -6.0), (11.0, 6.0, 9.0), arch=a_table(11.0, 6.0, 9.0, "bench", leg=1.2, inset=0.4, slab=1.4), fit="axes"),
        furn("musicbox", (6.0, -6.0), (4.4, 3.2, 2.8), z=9.0, arch=a_block(4.4, 3.2, 2.8, "music box", surface=False), goal=True,
             guess="a wind-up music box, 22 x 16 x 14 cm"),
        furn("basket", (16.0, 19.4), (8.0, 8.0, 11.0), arch=a_block(8.0, 8.0, 11.0, "laundry basket", surface=False)),
        furn("towelrail", (22.9, 11.5), (11.8, 5.4, 15.35), yaw=270, z=0.0, arch=a_block(11.8, 5.4, 15.35, "towel rail", surface=False), decor=True),
        furn("fern", (21.0, -0.5), (6, 4.9, 3), faces=12000, yaw=0, z=0.0, arch=a_block(6, 4.9, 3, "fern", surface=False), decor=True),
    ],
    props=[
        dict(kind="rug", name="mat", x0=-18.0, x1=-2.0, y0=2.2, y1=7.4, tex="bathmat"),
        dict(kind="mirror", side="L", a0=-16.0, a1=-8.0, h0=24.0, h1=36.0),
        dict(kind="bracket", side="R", a=4.0, h=30.0, reach=6.5),
        dict(kind="towel_rail", side="B", a0=12.0, a1=22.0, h=26.0),
        dict(kind="weight", x=19.5, y=4.0, h=14.0, r=1.1),
        dict(kind="pendant", style="globe", at=(0.0, 0.0), h=41.0),
    ],
    spots=dict(goal=dict(object="music box", x=6.0, y=-8.1, h=9.0), traps=[
        dict(trap="string holding a weight over a switch", kind="weight", x=19.5, y=4.0, h=14.0, r=1.1, a=(19.5, 4.0, 30.0),
             note="hangs from the brass bracket on the right wall over open floor"),
        dict(trap="edge drop: bath rim", kind="edge", x0=-25.6, x1=8.4, y0=8.6, y1=9.8, h=12.0,
             note="the rim drops 8.8 into the bath or 12 to the floor"),
        dict(trap="edge drop: bench", kind="edge", x0=-2.5, x1=8.5, y0=-9.0, y1=-3.0, h=9.0)]),
)

STUDY = dict(
    id="study", name="Study", x0=-36.0, x1=36.0, y0=-28.0, y1=28.0, wall_h=50.0,
    floor=dict(kind="boards", S=16.0, tone=(0.6, 0.4, 0.22), board=1.8), wall=dict(kind="study"), ceiling=(0.86, 0.83, 0.76), trim=(0.3, 0.17, 0.09),
    windows=[dict(side="L", a0=-12.0, a1=8.0, h0=14.0, h1=42.0, curtains=(0.12, 0.24, 0.17))],
    doors=[dict(side="R", a0=-22.0, a1=-6.0, h1=42.0, color=(0.3, 0.17, 0.09))],
    sun=dict(dir=(0.8, -0.28, -0.52), intensity=5.0), fill=dict(dir=(-0.35, -0.8, -0.45), intensity=0.45),
    lamp=dict(at=(-31.4, 21.4, 29.0), color=(1.0, 0.72, 0.4), intensity=3.0, radius=60.0),
    camera=dict(target=(-2.0, 2.0, 5.0), yaw=-62.0, pitch=38.0, dist=98.0),
    furniture=[
        furn("desk", (-14.0, 20.9), (28.0, 13.0, 15.0), arch=a_desk(28.0, 13.0, 15.0, "desk"), fit="axes"),
        furn("chair", (-14.0, 9.9), (10.0, 10.0, 22.0), factors=(1.1391, 1.0000, 1.1046), yaw=180, arch=refit(a_chair(10.0, 10.0, 9.0, 22.0, "desk chair", leg=1.0), surfaces=[top(-4.1, 4.2, -3.8, 2.0, 9.0, "desk chair seat")]), fit="axes"),
        furn("cabinet", (17.0, 23.6), (18.0, 8.0, 15.0), arch=a_block(18.0, 8.0, 15.0, "cabinet"), fit="axes"),
        furn("globe", (27.0, 7.0), (9.0, 9.0, 19.0), arch=a_globe(9.0, 9.0, 19.0, "globe")),
        furn("lamp", (-23.6, 16.7), (7.8, 4.2, 8.7), yaw=0, z=15.0, arch=a_block(7.8, 4.2, 8.7, "desk lamp", surface=False), decor=True),
    ],
    props=[
        dict(kind="rug", name="rug", x0=-26.0, x1=12.0, y0=-22.0, y1=6.0, tex="study"),
        # The challenges' goal is a Titan-size preset (3.375 tall, 0.51 thick, 1.69 wide) at (22.8, 23.6) facing +x: the
        # book is drawn round it, front face flush with the preset's, and is not a solid (the preset stands there).
        dict(kind="dictionary", x0=22.55, x1=23.55, y0=22.3, y1=24.9, h0=15.0, h1=19.0, solid=False),
        dict(kind="plank", x=-0.6, y=22.0, h=15.0, len=11.0, width=3.0),
        dict(kind="shelf", side="B", a0=8.0, a1=26.0, h=27.0, depth=4.0, items="books"),
        dict(kind="shelf", side="B", a0=8.0, a1=26.0, h=37.0, depth=4.0, items="books"),
        dict(kind="floor_lamp", x=-31.4, y=21.4, h=32.0),
        dict(kind="art", side="R", frames=[(4.0, 16.0, 24.0, 36.0, 0)]),
    ],
    spots=dict(goal=dict(object="big dictionary", x=22.8, y=23.6, h=15.0, a=0.0, size=5,
                         note="a goal preset of Titan size facing +x, inside the book: only a Giant or a Titan tips it"), traps=[
        dict(trap="string-held plank between desk and shelf", kind="plank", x=-0.6, y=22.0, h=15.0, a=0.0, len=11.0, width=3.0,
             string=dict(a=(-0.6, 22.0, 26.0), b=(-0.6, 27.6, 26.0)),
             note="upright at the desk's right end; released, it falls +x across the 8-unit gap onto the cabinet top (15)")]),
)

ATTIC = dict(
    id="attic", name="Attic", x0=-48.0, x1=48.0, y0=-36.0, y1=36.0, wall_h=58.0, knee=14.0,
    floor=dict(kind="pine", S=16.0), wall=dict(kind="attic"), ceiling=None, trim=(0.5, 0.36, 0.22),
    windows=[dict(side="L", a0=-7.0, a1=7.0, h0=28.0, h1=44.0, curtains=None)],
    skylights=[dict(x0=-9.0, x1=9.0, h0=30.0, h1=44.0)],
    doors=[],
    hatch=dict(x0=26.0, x1=40.0, y0=-30.0, y1=-20.0),
    sun=dict(dir=(0.12, -0.5, -0.86), intensity=5.6), fill=dict(dir=(-0.35, -0.8, -0.45), intensity=0.4),
    lamp=dict(at=(0.0, 0.0, 47.0), color=(1.0, 0.7, 0.38), intensity=3.0, radius=70.0),
    camera=dict(target=(0.0, -2.0, 6.0), yaw=-60.0, pitch=36.0, dist=132.0),
    furniture=[
        furn("trunk", (-30.0, 24.0), (18.0, 10.0, 11.0), arch=a_block(18.0, 10.0, 11.0, "trunk"), fit="axes", over=0.15),
        furn("lamp", (36.0, 12.0), (7.0, 7.0, 30.0), arch=a_post(7.0, 7.0, 30.0, "standard lamp", crown=22.0)),
        furn("rockingchair", (20.0, 15.0), (12.0, 18.0, 22.0), factors=(1.0853, 1.0642, 0.9992), arch=refit(a_chair(12.0, 18.0, 9.0, 22.0, "rocking chair", rockers=True), surfaces=[top(-4.0, 4.0, -3.6, 3.2, 8.95, "rocking chair seat")],
                         z1={"rocking chair seat": 8.95}), shrink=0.965, fit="axes",
             guess="a bentwood rocker, 60 x 90 cm on its rockers, 110 cm tall"),
        furn("dressform", (-14.0, -3.0), (7.8, 7.2, 28.95), yaw=0, z=0.0, arch=a_block(7.8, 7.2, 28.95, "dress form", surface=False), decor=True),
        furn("suitcases", (-38.0, -4.0), (15.7, 12.2, 11.4), yaw=0, z=0.0, arch=a_block(15.7, 12.2, 11.4, "suitcases", surface=False), decor=True),
    ],
    props=[
        dict(kind="rafters", every=12.0),
        dict(kind="rug", name="rug", x0=-30.0, x1=-6.0, y0=-14.0, y1=6.0, tex="attic"),
        dict(kind="boxes", boxes=[(-46.0, -34.0, -26.0, -16.0, 0.0, 8.0), (-45.0, -36.0, -24.6, -17.4, 8.0, 14.0),
                                  (-32.0, -24.0, -27.0, -19.0, 0.0, 6.0), (32.0, 46.0, 26.0, 33.0, 0.0, 7.0)]),
        dict(kind="crate_tower", x0=-2.0, x1=4.0, y0=-16.0, y1=-10.0, h=9.0),
        dict(kind="master_switch", x0=45.0, x1=47.6, y0=-11.0, y1=-5.0, h0=0.0, h1=8.0),
        dict(kind="bulb", at=(0.0, 0.0), h=47.0),
        dict(kind="weight", x=6.0, y=2.0, h=10.0, r=1.2, style="iron"),
    ],
    spots=dict(goal=dict(object="master light switch", x=41.6, y=-8.0, h=0.0, note="its lever reaches -x to 42.0, its grip at h 2.2 to 3"), traps=[
        dict(trap="fragile crate tower", kind="support", x0=-2.0, x1=4.0, y0=-16.0, y1=-10.0, z0=0.0, z1=9.0),
        dict(trap="string holding a weight", kind="weight", x=6.0, y=2.0, h=10.0, r=1.2, a=(6.0, 2.0, 44.0),
             note="an old flat iron hung from the collar tie above"),
        dict(trap="string-held plank", kind="plank", x=-21.4, y=24.0, h=11.0, a=0.0, len=10.0, width=3.0,
             note="room for a plank upright on the trunk's right end, falling +x")]),
)

ROOMS = [HALL, KITCHEN, DINING, KIDS, BATH, STUDY, ATTIC]
BY_ID = {r["id"]: r for r in ROOMS}
