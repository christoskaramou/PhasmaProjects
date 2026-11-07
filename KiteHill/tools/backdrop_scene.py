"""Blender (Cycles) scene for Kite Hill's pre-rendered backdrop. Run by tools/make_backdrop.py:

    blender -b --factory-startup --python tools/backdrop_scene.py -- OUT.png SAMPLES WIDTH HEIGHT

Rolling green hills under a soft daytime sky: the valley the kites race over (empty: the gates, kites, flyer and the
windmill's sails are drawn in 3D by the game), a footpath, a patchwork of fields and hedges, a whitewashed village
with tiled roofs on its hill, the windmill's tower, trees, a few sheep, wild flowers near the camera and cumulus
clouds. Every building stands on the ground (its walls go down into the hill). Aerial haze softens the distance.

Seen from the game's fixed camera (tools/kh_common.py). Blender axes = field axes: X right, Y away, Z up.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kh_common as K  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, SAMPLES, WIDTH, HEIGHT = argv[0], int(argv[1]), int(argv[2]), int(argv[3])
random.seed(21)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
COL = sc.collection
R = math.radians
G = K.ground

HAZE = (0.74, 0.80, 0.86)          # the horizon's colour, mixed in with distance
HAZE_D = 900.0
# Ridges far beyond the play area (only the backdrop has them; they are nowhere near the kites).
FAR = [(-120, 260, 26, 60, 40), (40, 300, 34, 90, 45), (170, 250, 24, 60, 40), (-20, 380, 40, 120, 60)]


def ground_far(x, y):
    g = G(x, y)
    for cx, cy, a, sx, sy in FAR:
        dx, dy = (x - cx) / sx, (y - cy) / sy
        g += a * math.exp(-(dx * dx + dy * dy))
    return g


def cam_pos():
    p = K.CAM_POS
    return Vector((p[0], -p[2], p[1]))


def haze(m, strength=1.0):
    """Mix the surface toward the horizon colour with view distance (aerial perspective)."""
    N, L = m.node_tree.nodes, m.node_tree.links
    out = N["Material Output"]
    sh = out.inputs["Surface"].links[0].from_socket
    cd = N.new("ShaderNodeCameraData")
    k = N.new("ShaderNodeMath"); k.operation = "MULTIPLY"; k.inputs[1].default_value = -strength / HAZE_D
    L.new(cd.outputs["View Distance"], k.inputs[0])
    e = N.new("ShaderNodeMath"); e.operation = "EXPONENT"
    L.new(k.outputs[0], e.inputs[0])
    f = N.new("ShaderNodeMath"); f.operation = "SUBTRACT"; f.inputs[0].default_value = 1.0
    L.new(e.outputs[0], f.inputs[1])
    em = N.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*HAZE, 1)
    em.inputs["Strength"].default_value = 1.0
    mx = N.new("ShaderNodeMixShader")
    L.new(f.outputs[0], mx.inputs["Fac"])
    L.new(sh, mx.inputs[1])
    L.new(em.outputs[0], mx.inputs[2])
    L.new(mx.outputs[0], out.inputs["Surface"])
    return m


def pbr(name, base, rough=0.6, tint2=None, scale=4.0, bump=0.0, fine=0.0, fine_scale=60.0, sss=0.0, tex="noise", coords="Object",
        hz=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    N, L = m.node_tree.nodes, m.node_tree.links
    p = N["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*base, 1)
    p.inputs["Roughness"].default_value = rough
    if sss:
        p.inputs["Subsurface Weight"].default_value = sss
    tc = N.new("ShaderNodeTexCoord")
    normal_in = p.inputs["Normal"]
    if tint2 or bump:
        if tex == "wave":
            t = N.new("ShaderNodeTexWave")
            t.inputs["Scale"].default_value = scale
            t.inputs["Distortion"].default_value = 2.0
        else:
            t = N.new("ShaderNodeTexNoise")
            t.inputs["Scale"].default_value = scale
            t.inputs["Detail"].default_value = 5.0
        L.new(tc.outputs[coords], t.inputs["Vector"])
        if tint2:
            r = N.new("ShaderNodeValToRGB")
            r.color_ramp.elements[0].color = (*base, 1)
            r.color_ramp.elements[1].color = (*tint2, 1)
            L.new(t.outputs["Fac"], r.inputs["Fac"])
            L.new(r.outputs["Color"], p.inputs["Base Color"])
        if bump:
            b = N.new("ShaderNodeBump")
            b.inputs["Strength"].default_value = bump
            L.new(t.outputs["Fac"], b.inputs["Height"])
            L.new(b.outputs["Normal"], normal_in)
            normal_in = b.inputs["Normal"]
    if fine:
        fn = N.new("ShaderNodeTexNoise")
        fn.inputs["Scale"].default_value = fine_scale
        L.new(tc.outputs[coords], fn.inputs["Vector"])
        b2 = N.new("ShaderNodeBump")
        b2.inputs["Strength"].default_value = fine
        L.new(fn.outputs["Fac"], b2.inputs["Height"])
        L.new(b2.outputs["Normal"], normal_in)
    return haze(m, hz) if hz else m


def link(o, m=None):
    if o.name not in COL.objects:
        COL.objects.link(o)
    if m:
        o.data.materials.append(m)
    return o


def mesh_obj(name, verts, faces, m=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    if smooth:
        for f in me.polygons:
            f.use_smooth = True
    return link(bpy.data.objects.new(name, me), m)


def box(loc, size, m=None, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[R(a) for a in rot])
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if m:
        o.data.materials.append(m)
    if bevel:
        md = o.modifiers.new("b", "BEVEL")
        md.width = bevel
        md.segments = 2
    return o


def cyl(loc, r, depth, m=None, verts=24, r2=None, rot=(0, 0, 0)):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=[R(a) for a in rot])
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc, rotation=[R(a) for a in rot])
    o = bpy.context.object
    for f in o.data.polygons:
        f.use_smooth = True
    if m:
        o.data.materials.append(m)
    return o


def blob(loc, size, m, subdiv=3, noise=0.0, nscale=1.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=1, location=loc)
    o = bpy.context.object
    o.scale = size
    for f in o.data.polygons:
        f.use_smooth = True
    if noise:
        tx = bpy.data.textures.new("n", "CLOUDS")
        tx.noise_scale = nscale
        md = o.modifiers.new("d", "DISPLACE")
        md.texture = tx
        md.strength = noise
        md.mid_level = 0.5
    o.data.materials.append(m)
    return o


# ------------------------------------------------------------------ sky
w = bpy.data.worlds.new("W")
sc.world = w
w.use_nodes = True
WN, WL = w.node_tree.nodes, w.node_tree.links
bg = WN["Background"]
tc = WN.new("ShaderNodeTexCoord")
sep = WN.new("ShaderNodeSeparateXYZ")
WL.new(tc.outputs["Generated"], sep.inputs[0])
ramp = WN.new("ShaderNodeValToRGB")
els = ramp.color_ramp.elements
els[0].position, els[0].color = 0.0, (0.80, 0.82, 0.80, 1)
els[1].position, els[1].color = 0.38, (0.22, 0.40, 0.72, 1)
e2 = els.new(0.08)
e2.color = (0.55, 0.66, 0.80, 1)
WL.new(sep.outputs["Z"], ramp.inputs["Fac"])
WL.new(ramp.outputs["Color"], bg.inputs["Color"])
bg.inputs["Strength"].default_value = float(os.environ.get("KH_SKY", "0.8"))

sv = Vector(K.sun())                     # engine axes -> Blender
sun_dir = Vector((sv.x, -sv.z, sv.y)).normalized()
sd = bpy.data.lights.new("sun", "SUN")
sd.energy = float(os.environ.get("KH_SUN", "5.0"))
sd.color = (1.0, 0.90, 0.76)
sd.angle = R(3.0)
so = bpy.data.objects.new("sun", sd)
so.rotation_euler = (-sun_dir).to_track_quat("-Z", "Y").to_euler()
COL.objects.link(so)

# ------------------------------------------------------------------ the land
NY, NX = 300, 420
verts, faces = [], []
for i in range(NY):
    y = -24 + (i / (NY - 1)) ** 1.7 * 460
    half = 70 + max(0.0, y) * 1.1
    for j in range(NX):
        x = (j / (NX - 1) * 2 - 1) * half
        verts.append((x, y, ground_far(x, y)))
for i in range(NY - 1):
    for j in range(NX - 1):
        a = i * NX + j
        faces.append((a, a + 1, a + NX + 1, a + NX))

land = bpy.data.materials.new("land")
land.use_nodes = True
N, L = land.node_tree.nodes, land.node_tree.links
p = N["Principled BSDF"]
p.inputs["Roughness"].default_value = 0.9
tcl = N.new("ShaderNodeTexCoord")
# Meadow: warm greens with a soft mottle.
mot = N.new("ShaderNodeTexNoise"); mot.inputs["Scale"].default_value = 0.09; mot.inputs["Detail"].default_value = 6
L.new(tcl.outputs["Object"], mot.inputs["Vector"])
mr = N.new("ShaderNodeValToRGB")
mr.color_ramp.elements[0].color = (0.17, 0.30, 0.05, 1)
mr.color_ramp.elements[1].color = (0.36, 0.44, 0.09, 1)
mr.color_ramp.elements[0].position, mr.color_ramp.elements[1].position = 0.35, 0.7
L.new(mot.outputs["Fac"], mr.inputs["Fac"])
# Fields: Voronoi cells, each its own crop colour, edged with hedgerows.
vor = N.new("ShaderNodeTexVoronoi"); vor.inputs["Scale"].default_value = 0.055
mapn = N.new("ShaderNodeMapping"); mapn.inputs["Scale"].default_value = (1.0, 1.6, 1.0)
L.new(tcl.outputs["Object"], mapn.inputs["Vector"])
L.new(mapn.outputs["Vector"], vor.inputs["Vector"])
crop = N.new("ShaderNodeValToRGB")
ce = crop.color_ramp.elements
crop.color_ramp.interpolation = "CONSTANT"
ce[0].position, ce[0].color = 0.0, (0.26, 0.38, 0.10, 1)
ce[1].position, ce[1].color = 0.82, (0.60, 0.52, 0.22, 1)
for pos, c in ((0.22, (0.38, 0.46, 0.13)), (0.42, (0.22, 0.32, 0.09)), (0.58, (0.47, 0.50, 0.18)), (0.70, (0.30, 0.42, 0.12))):
    el = ce.new(pos); el.color = (*c, 1)
sepc = N.new("ShaderNodeSeparateColor")
L.new(vor.outputs["Color"], sepc.inputs["Color"])
L.new(sepc.outputs[0], crop.inputs["Fac"])
# Crop rows: a fine stripe inside each field.
rows = N.new("ShaderNodeTexWave"); rows.inputs["Scale"].default_value = 0.9; rows.inputs["Distortion"].default_value = 0.5
L.new(tcl.outputs["Object"], rows.inputs["Vector"])
rmix = N.new("ShaderNodeMix"); rmix.data_type = "RGBA"; rmix.blend_type = "MULTIPLY"
rmix.inputs["Factor"].default_value = 0.12
L.new(crop.outputs["Color"], rmix.inputs[6])
L.new(rows.outputs["Color"], rmix.inputs[7])
# Hedgerows along the cell edges.
ved = N.new("ShaderNodeTexVoronoi"); ved.feature = "DISTANCE_TO_EDGE"; ved.inputs["Scale"].default_value = 0.055
L.new(mapn.outputs["Vector"], ved.inputs["Vector"])
hedge = N.new("ShaderNodeMapRange")
hedge.inputs["From Min"].default_value, hedge.inputs["From Max"].default_value = 0.025, 0.06
hedge.inputs["To Min"].default_value, hedge.inputs["To Max"].default_value = 1.0, 0.0
L.new(ved.outputs["Distance"], hedge.inputs["Value"])
hmix = N.new("ShaderNodeMix"); hmix.data_type = "RGBA"
L.new(hedge.outputs["Result"], hmix.inputs["Factor"])
L.new(rmix.outputs[2], hmix.inputs[6])
hmix.inputs[7].default_value = (0.08, 0.15, 0.04, 1)
# Near the camera it is all meadow; the patchwork starts across the valley.
gen = N.new("ShaderNodeSeparateXYZ")
L.new(tcl.outputs["Object"], gen.inputs[0])
far = N.new("ShaderNodeMapRange")
far.inputs["From Min"].default_value, far.inputs["From Max"].default_value = 17.0, 34.0
L.new(gen.outputs["Y"], far.inputs["Value"])
fmix = N.new("ShaderNodeMix"); fmix.data_type = "RGBA"
L.new(far.outputs["Result"], fmix.inputs["Factor"])
L.new(mr.outputs["Color"], fmix.inputs[6])
L.new(hmix.outputs[2], fmix.inputs[7])
L.new(fmix.outputs[2], p.inputs["Base Color"])
gb = N.new("ShaderNodeTexNoise"); gb.inputs["Scale"].default_value = 3.0
L.new(tcl.outputs["Object"], gb.inputs["Vector"])
bmp = N.new("ShaderNodeBump"); bmp.inputs["Strength"].default_value = 0.25
L.new(gb.outputs["Fac"], bmp.inputs["Height"])
L.new(bmp.outputs["Normal"], p.inputs["Normal"])
haze(land)
mesh_obj("land", verts, faces, land)

# The footpath: a worn strip following the ground.
dirt = pbr("dirt", (0.56, 0.45, 0.31), 0.95, tint2=(0.46, 0.37, 0.25), scale=1.5, fine=0.3, fine_scale=12)
pp = K.path_points()
pv, pf = [], []
for i, (x, y, wd) in enumerate(pp):
    x2, y2 = pp[min(i + 1, len(pp) - 1)][:2]
    x1, y1 = pp[max(i - 1, 0)][:2]
    tx, ty = x2 - x1, y2 - y1
    Lt = math.hypot(tx, ty)
    nx, ny = -ty / Lt, tx / Lt
    for s in (-1, 1):
        wobble = 1 + 0.12 * math.sin(i * 1.7 + s)
        px, py = x + nx * s * wd / 2 * wobble, y + ny * s * wd / 2 * wobble
        pv.append((px, py, G(px, py) + 0.03))
for i in range(len(pp) - 1):
    a = 2 * i
    pf.append((a, a + 1, a + 3, a + 2))
mesh_obj("path", pv, pf, dirt)

# ------------------------------------------------------------------ the village
plaster = pbr("plaster", (0.86, 0.83, 0.76), 0.85, tint2=(0.80, 0.77, 0.70), scale=2.0, bump=0.05, sss=0.0)
tiles = {"terracotta": pbr("tiles", (0.62, 0.27, 0.13), 0.7, tint2=(0.52, 0.22, 0.11), tex="wave", scale=6.0, bump=0.25),
         "rust": pbr("tiles2", (0.55, 0.30, 0.17), 0.7, tint2=(0.46, 0.25, 0.14), tex="wave", scale=6.0, bump=0.25)}
shutter = pbr("shutter", (0.16, 0.27, 0.30), 0.6)
door_m = pbr("door", (0.30, 0.18, 0.10), 0.6)
stone = pbr("stone", (0.52, 0.48, 0.42), 0.9, tint2=(0.42, 0.39, 0.34), scale=3.0, bump=0.2)


def gable_roof(cx, cy, w, d, z0, yaw, m, pitch=0.62, over=0.25):
    """A tiled gable roof (ridge along the house's width)."""
    hw, hd = w / 2 + over, d / 2 + over
    rz = z0 + (d / 2) * pitch
    c, s = math.cos(R(yaw)), math.sin(R(yaw))

    def P(x, y, z):
        return (cx + x * c - y * s, cy + x * s + y * c, z)
    ez = z0 - over * pitch
    v = [P(-hw, -hd, ez), P(hw, -hd, ez), P(hw, 0, rz), P(-hw, 0, rz), P(-hw, hd, ez), P(hw, hd, ez)]
    # Thickness: a copy 0.12 lower closes the eaves.
    v += [(a, b, z - 0.12) for a, b, z in v]
    f = [(0, 1, 2, 3), (3, 2, 5, 4), (6, 9, 8, 7), (9, 10, 11, 8), (0, 6, 7, 1), (4, 5, 11, 10), (0, 3, 9, 6), (3, 4, 10, 9),
         (1, 7, 8, 2), (2, 8, 11, 5)]
    return mesh_obj("roof", v, f, m, smooth=False)


def house(x, y, w, d, h, yaw, roof):
    corners = [(x + sx * w / 2, y + sy * d / 2) for sx in (-1, 1) for sy in (-1, 1)]
    lo = min(G(a, b) for a, b in corners) - 0.8
    hi = max(G(a, b) for a, b in corners)
    top = hi + h
    box((x, y, (lo + top) / 2), (w, d, top - lo), plaster, rot=(0, 0, yaw), bevel=0.06)
    gable_roof(x, y, w, d, top, yaw, tiles[roof])
    c, s = math.cos(R(yaw)), math.sin(R(yaw))
    # Front (toward the camera, -y) windows with shutters and a door.
    fz = hi + 0.1
    for k, lx in enumerate((-w * 0.28, w * 0.22)):
        wx, wy = x + lx * c + (d / 2 + 0.02) * s, y + lx * s - (d / 2 + 0.02) * c
        if k == 0:
            box((wx, wy, fz + 0.75), (0.7, 0.08, 1.5), door_m, rot=(0, 0, yaw))
        else:
            box((wx, wy, fz + h * 0.55), (0.75, 0.08, 0.8), shutter, rot=(0, 0, yaw))
        if h > 3.2:
            box((wx, wy, fz + h * 0.82), (0.7, 0.08, 0.7), shutter, rot=(0, 0, yaw))
    if random.random() < 0.6:
        chx, chy = x + w * 0.3 * c, y + w * 0.3 * s
        box((chx, chy, top + 0.9), (0.45, 0.45, 1.4), plaster, rot=(0, 0, yaw))


for hs in K.village():
    house(*hs)

# The chapel: a whitewashed nave and a bell tower with a tiled cap.
cx, cy = K.CHURCH
gz = G(cx, cy)
box((cx, cy, gz + 1.0), (6.5, 3.6, 5.6), plaster, bevel=0.06)
gable_roof(cx, cy, 6.5, 3.6, gz + 3.8, 0, tiles["terracotta"])
tz = G(cx + 4.0, cy) - 0.8
box((cx + 4.0, cy, tz + 4.4), (2.0, 2.0, 8.8), plaster, bevel=0.05)
box((cx + 4.0, cy - 1.02, tz + 7.6), (0.7, 0.08, 1.2), shutter)
bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=1.65, radius2=0.0, depth=1.8, location=(cx + 4.0, cy, tz + 9.7), rotation=(0, 0, R(45)))
link(bpy.context.object).data.materials.append(tiles["terracotta"])

# Hedgerows along a few field edges on the slopes beyond the valley.
hedge_m = pbr("hedge", (0.10, 0.19, 0.06), 0.85, tint2=(0.14, 0.24, 0.07), scale=1.2, bump=0.5)
for x0, y0, x1, y1 in ((-34, 22, -9, 26), (13, 21, 36, 27), (-4, 35, 13, 37), (-60, 30, -36, 33)):
    n = int(math.hypot(x1 - x0, y1 - y0) / 0.7)
    for k in range(n):
        t = k / n
        x, y = x0 + (x1 - x0) * t + random.uniform(-0.2, 0.2), y0 + (y1 - y0) * t
        blob((x, y, G(x, y) + 0.3), (1.1, 0.8, random.uniform(0.7, 0.95)), hedge_m, 3, noise=0.5, nscale=0.35)

# ------------------------------------------------------------------ the windmill's tower (the game turns its sails)
mz = K.MILL_BASE
cyl((K.MILL_X, K.MILL_Y, mz - 0.8 + (K.MILL_H + 0.8) / 2), 2.05, K.MILL_H + 0.8, plaster, 40, r2=1.62)
cap_m = pbr("cap", (0.40, 0.24, 0.14), 0.8, tint2=(0.32, 0.19, 0.11), tex="wave", scale=5, bump=0.2)
cyl((K.MILL_X, K.MILL_Y, mz + K.MILL_H + 0.9), 1.9, 2.0, cap_m, 40, r2=0.25)
fx, fy = math.cos(K.MILL_FACE), math.sin(K.MILL_FACE)
yaw = math.degrees(math.atan2(fy, fx)) + 90
for dz, kind in ((0.0, "door"), (3.6, "win"), (5.6, "win")):
    r0 = 2.05 - (2.05 - 1.62) * (dz + 1.0) / K.MILL_H
    bx, by = K.MILL_X + fx * (r0 - 0.02), K.MILL_Y + fy * (r0 - 0.02)
    if kind == "door":
        box((bx, by, mz + 0.9), (0.9, 0.2, 1.8), door_m, rot=(0, 0, yaw))
    else:
        box((bx, by, mz + dz), (0.55, 0.2, 0.7), shutter, rot=(0, 0, yaw))

# ------------------------------------------------------------------ trees, sheep, flowers
leaf = [pbr(f"leaf{i}", c, 0.8, tint2=tuple(v * 0.75 for v in c), scale=1.5, bump=0.4, sss=0.0)
        for i, c in enumerate(((0.16, 0.26, 0.07), (0.20, 0.30, 0.08), (0.13, 0.22, 0.07)))]
cypress = pbr("cypress", (0.08, 0.16, 0.06), 0.85, tint2=(0.06, 0.12, 0.05), scale=2.0, bump=0.4)
bark = pbr("bark", (0.22, 0.15, 0.09), 0.9)
for x, y, kind, s in K.trees():
    z = G(x, y)
    if kind == "cypress":
        blob((x, y, z + 2.6 * s), (0.75 * s, 0.75 * s, 2.9 * s), cypress, 3, noise=0.25, nscale=0.5)
    else:
        cyl((x, y, z + 0.6 * s), 0.18 * s, 1.4 * s, bark, 8)
        blob((x, y, z + 2.0 * s), (1.5 * s, 1.5 * s, 1.3 * s), random.choice(leaf), 3, noise=0.45, nscale=0.6)

wool = pbr("wool", (0.86, 0.84, 0.78), 0.95, tint2=(0.78, 0.76, 0.70), scale=10, bump=0.3)
face = pbr("sheepface", (0.08, 0.07, 0.06), 0.7)
for x, y, a in ((-22, 24, 20), (-19, 26, 160), (-24, 27.5, 80), (20, 23, 200), (23, 25, 30), (9, 30, 110), (11, 32, 300)):
    z = G(x, y)
    blob((x, y, z + 0.55), (0.75, 0.48, 0.45), wool, 2, noise=0.08, nscale=0.2)
    hx, hy = x + 0.75 * math.cos(R(a)), y + 0.75 * math.sin(R(a))
    blob((hx, hy, z + 0.6), (0.24, 0.17, 0.2), face, 2)

flower_m = [pbr("poppy", (0.72, 0.12, 0.06), 0.6, hz=0.6), pbr("daisy", (0.92, 0.90, 0.84), 0.6, hz=0.6),
            pbr("buttercup", (0.88, 0.66, 0.12), 0.6, hz=0.6), pbr("clover", (0.66, 0.46, 0.66), 0.6, hz=0.6)]
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1, location=(0, 0, -50))
proto = bpy.context.object
flower_me = []
for m in flower_m:
    me = proto.data.copy()
    me.materials.append(m)
    flower_me.append(me)
bpy.data.objects.remove(proto)
PATCHES = [(random.uniform(-24, 24), random.uniform(0, 11), random.uniform(1.5, 3.5), random.randrange(4)) for _ in range(22)]
for k in range(900):
    px, py, pr, pc = random.choice(PATCHES)
    x, y = px + random.gauss(0, pr), py + random.gauss(0, pr * 0.6)
    o = bpy.data.objects.new("flower", flower_me[pc if random.random() < 0.8 else k % 4])
    s = random.uniform(0.035, 0.065)
    o.scale = (s, s, s * 0.6)
    o.location = (x, y, G(x, y) + s * 0.4)
    COL.objects.link(o)

# ------------------------------------------------------------------ clouds (soft volumes)
cloud_m = bpy.data.materials.new("cloud")
cloud_m.use_nodes = True
N, L = cloud_m.node_tree.nodes, cloud_m.node_tree.links
N.remove(N["Principled BSDF"])
vol = N.new("ShaderNodeVolumePrincipled")
vol.inputs["Color"].default_value = (1.0, 0.98, 0.95, 1)
vol.inputs["Anisotropy"].default_value = 0.3
tcc = N.new("ShaderNodeTexCoord")
# Density: a ball falling off to the edge, broken up by noise, cut flat underneath.
vm = N.new("ShaderNodeVectorMath"); vm.operation = "LENGTH"
sub = N.new("ShaderNodeVectorMath"); sub.operation = "SUBTRACT"; sub.inputs[1].default_value = (0.5, 0.5, 0.5)
L.new(tcc.outputs["Generated"], sub.inputs[0])
L.new(sub.outputs["Vector"], vm.inputs[0])
nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 2.2; nz.inputs["Detail"].default_value = 8; nz.inputs["Roughness"].default_value = 0.6
L.new(tcc.outputs["Object"], nz.inputs["Vector"])
mix = N.new("ShaderNodeMath"); mix.operation = "MULTIPLY_ADD"
L.new(nz.outputs["Fac"], mix.inputs[0]); mix.inputs[1].default_value = 0.45; L.new(vm.outputs["Value"], mix.inputs[2])
den = N.new("ShaderNodeMapRange")
den.inputs["From Min"].default_value, den.inputs["From Max"].default_value = 0.78, 0.62
den.inputs["To Min"].default_value, den.inputs["To Max"].default_value = 0.0, 1.0
L.new(mix.outputs[0], den.inputs["Value"])
sepz = N.new("ShaderNodeSeparateXYZ")
L.new(tcc.outputs["Generated"], sepz.inputs[0])
cut = N.new("ShaderNodeMapRange")
cut.inputs["From Min"].default_value, cut.inputs["From Max"].default_value = 0.30, 0.42
L.new(sepz.outputs["Z"], cut.inputs["Value"])
dm = N.new("ShaderNodeMath"); dm.operation = "MULTIPLY"
L.new(den.outputs["Result"], dm.inputs[0]); L.new(cut.outputs["Result"], dm.inputs[1])
ds = N.new("ShaderNodeMath"); ds.operation = "MULTIPLY"; ds.inputs[1].default_value = float(os.environ.get("KH_CLOUD", "0.1"))
L.new(dm.outputs[0], ds.inputs[0])
L.new(ds.outputs[0], vol.inputs["Density"])
L.new(vol.outputs[0], N["Material Output"].inputs["Volume"])

CLOUDS = [(-150, 330, 95, 1.0), (-40, 380, 120, 1.3), (110, 360, 105, 1.15), (230, 420, 150, 1.2), (-260, 420, 140, 1.1),
          (30, 260, 64, 0.65), (-95, 240, 58, 0.55), (150, 250, 70, 0.6)]
for cx_, cy_, cz_, s in CLOUDS:
    for k in range(7):
        ox, oy, oz = random.uniform(-38, 38) * s, random.uniform(-14, 14) * s, random.uniform(-4, 9) * s
        r = random.uniform(18, 30) * s * (1.2 - abs(ox) / (60 * s))
        bpy.ops.mesh.primitive_cube_add(size=2, location=(cx_ + ox, cy_ + oy, cz_ + oz))
        o = bpy.context.object
        o.scale = (r * 1.25, r, r * 0.8)
        o.data.materials.append(cloud_m)
        o.visible_shadow = True

# ------------------------------------------------------------------ camera (the game's) and render
cam = bpy.data.cameras.new("cam")
cam.sensor_fit = "VERTICAL"
cam.angle = R(K.VFOV)
cam.clip_start, cam.clip_end = 0.2, 3000
co = bpy.data.objects.new("cam", cam)
co.location = cam_pos()
look = Vector((K.CAM_LOOK[0], -K.CAM_LOOK[2], K.CAM_LOOK[1]))
co.rotation_euler = (look - co.location).to_track_quat("-Z", "Y").to_euler()
COL.objects.link(co)
sc.camera = co

sc.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
for dev in ("OPTIX", "CUDA"):
    try:
        prefs.compute_device_type = dev
        prefs.get_devices()
        if any(d.type == dev for d in prefs.devices):
            for d in prefs.devices:
                d.use = d.type == dev
            sc.cycles.device = "GPU"
            break
    except TypeError:
        continue
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 6
sc.cycles.volume_bounces = 8
sc.cycles.volume_step_rate = 2.0
sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = WIDTH, HEIGHT, 100
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Medium High Contrast"
sc.view_settings.exposure = float(os.environ.get("KH_EXPOSURE", "0.0"))
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGB"
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("DONE", OUT)
