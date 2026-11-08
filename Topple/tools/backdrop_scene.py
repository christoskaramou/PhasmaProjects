"""Blender (Cycles) scene for Topple's pre-rendered backdrop. Run by tools/make_backdrop.py:

    blender -b --factory-startup --python tools/backdrop_scene.py -- OUT.png SAMPLES WIDTH HEIGHT

The empty games table of the concept render: green felt in a walnut rim, the papered wall and book shelf behind,
the desk lamp's pool of warm light, and the blank chalk score board on its easel (the game writes on it). Every
toy is drawn by the engine on top. Seen from the game's fixed camera with the concept's grade (AgX, medium high
contrast, +0.4 exposure), so the table looks the way the approved concept does.

Blender axes: X right, Y away from the camera, Z up. Engine (x, y, z) = Blender (x, -z, y).
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, SAMPLES, WIDTH, HEIGHT = argv[0], int(argv[1]), int(argv[2]), int(argv[3])
random.seed(11)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
COL = sc.collection
R = math.radians

# Shared with tools/gen_meshes.py and topple_world.lua (engine axes).
CAM_POS, CAM_LOOK, VFOV = (12.53, 13.65, 19.93), (-0.6, 0.0, -3.6), 29.84
BOARD_BASE = (3.5, 14.0)                 # the easel, in table coordinates (Blender x, y)


def B(x, y, z):
    """Engine point -> Blender location."""
    return (x, -z, y)


def pbr(name, base, rough=0.5, metal=0.0, coat=0.0, sheen=0.0, tint2=None, tex="noise", scale=4.0, bump=0.0, fine=0.0, fine_scale=80.0,
        emit=None, es=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    N, L = m.node_tree.nodes, m.node_tree.links
    p = N["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*base, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if coat:
        p.inputs["Coat Weight"].default_value = coat
    if sheen:
        p.inputs["Sheen Weight"].default_value = sheen
    if emit:
        p.inputs["Emission Color"].default_value = (*emit, 1)
        p.inputs["Emission Strength"].default_value = es
    tc, height = None, None
    if tint2 or bump:
        tc = N.new("ShaderNodeTexCoord")
        if tex == "wave":
            t = N.new("ShaderNodeTexWave")
            t.inputs["Scale"].default_value = scale
            t.inputs["Distortion"].default_value = 6.0
            t.inputs["Detail"].default_value = 3.0
        else:
            t = N.new("ShaderNodeTexNoise")
            t.inputs["Scale"].default_value = scale
            t.inputs["Detail"].default_value = 6.0
        fac = t.outputs["Fac"]
        L.new(tc.outputs["Object"], t.inputs["Vector"])
        if tint2:
            r = N.new("ShaderNodeValToRGB")
            r.color_ramp.elements[0].color = (*base, 1)
            r.color_ramp.elements[1].color = (*tint2, 1)
            L.new(fac, r.inputs["Fac"])
            L.new(r.outputs["Color"], p.inputs["Base Color"])
        if bump:
            height = fac
    normal_in = p.inputs["Normal"]
    if fine:
        tc = tc or N.new("ShaderNodeTexCoord")
        fn = N.new("ShaderNodeTexNoise")
        fn.inputs["Scale"].default_value = fine_scale
        fn.inputs["Detail"].default_value = 4
        L.new(tc.outputs["Object"], fn.inputs["Vector"])
        b2 = N.new("ShaderNodeBump")
        b2.inputs["Strength"].default_value = fine
        L.new(fn.outputs["Fac"], b2.inputs["Height"])
        L.new(b2.outputs["Normal"], normal_in)
        normal_in = b2.inputs["Normal"]
    if height is not None:
        b = N.new("ShaderNodeBump")
        b.inputs["Strength"].default_value = bump
        L.new(height, b.inputs["Height"])
        L.new(b.outputs["Normal"], normal_in)
    return m


def put(o, m, bevel=0.0):
    if m:
        o.data.materials.append(m)
    if bevel:
        md = o.modifiers.new("b", "BEVEL")
        md.width = bevel
        md.segments = 3
    return o


def box(loc, size, m=None, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[R(a) for a in rot])
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return put(o, m, bevel)


def plane(loc, w, h, m=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=[R(a) for a in rot])
    o = bpy.context.object
    o.scale = (w, h, 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return put(o, m)


def cyl(loc, r, depth, m=None, verts=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc)
    o = bpy.context.object
    for f in o.data.polygons:
        f.use_smooth = True
    return put(o, m)


def light(kind, loc, energy, color, size=0.2, target=None):
    d = bpy.data.lights.new(kind, kind)
    d.energy = energy
    d.color = color
    if kind == "AREA":
        d.size = size
    else:
        d.shadow_soft_size = size
    o = bpy.data.objects.new(kind, d)
    COL.objects.link(o)
    o.location = loc
    if target is not None:
        o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return o


# ------------------------------------------------------------------ the room
w = bpy.data.worlds.new("W")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.04, 0.03, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.4

felt = pbr("felt", (0.10, 0.25, 0.15), rough=0.95, sheen=0.8, tint2=(0.12, 0.29, 0.18), scale=1.5, fine=0.25, fine_scale=500)
walnut = pbr("walnut", (0.20, 0.10, 0.05), rough=0.3, coat=0.4, tint2=(0.12, 0.06, 0.03), tex="wave", scale=2.5, bump=0.03)
wood = pbr("wood", (0.58, 0.38, 0.19), 0.45, coat=0.2, tint2=(0.42, 0.26, 0.12), tex="wave", scale=4, bump=0.02)
slate = pbr("slate", (0.05, 0.07, 0.06), 0.9, tint2=(0.08, 0.10, 0.09), scale=3)
chalk_dust = pbr("chalkdust", (0.07, 0.09, 0.08), 0.95, tint2=(0.10, 0.12, 0.11), scale=9)

plane((0, 3, 0), 32, 24, felt)
for x, y, sx, sy in ((0, -9.6, 34.4, 1.2), (0, 15.6, 34.4, 1.2), (-16.6, 3, 1.2, 26.4), (16.6, 3, 1.2, 26.4)):
    box((x, y, 0.3), (sx, sy, 0.6), walnut, bevel=0.15)
box((0, 3, -0.83), (34.4, 26.4, 1.6), walnut)          # top just below the felt (no z-fighting)
wall = pbr("wallpaper", (0.26, 0.13, 0.08), 0.8, tint2=(0.20, 0.10, 0.06), tex="wave", scale=1.0)
plane((0, 24, 6), 80, 40, wall, rot=(90, 0, 0))
plane((0, 3, -1.6), 80, 60, pbr("floor", (0.10, 0.06, 0.04), 0.6))
box((0, 23.5, 7.5), (20, 1.2, 0.25), walnut)
for i in range(34):
    h = random.uniform(1.0, 1.8)
    c = random.choice(((0.35, 0.10, 0.06), (0.12, 0.18, 0.28), (0.40, 0.32, 0.14), (0.18, 0.26, 0.17), (0.5, 0.42, 0.3)))
    box((-9.6 + i * 0.57, 23.4, 7.62 + h / 2), (0.5, 0.9, h), pbr(f"book{i}", c, 0.7))

# The chalk score board on its easel, turned toward the camera; blank but for old chalk smudges.
cam_t = Vector((CAM_POS[0], -CAM_POS[2]))
eb = Vector((BOARD_BASE[0], BOARD_BASE[1], 0))
fd = Vector((cam_t.x - eb.x, cam_t.y - eb.y))
fd.normalize()
yaw = math.atan2(fd.x, -fd.y)


def onboard(lx, lz, ly=0.0):
    return eb + Vector((lx * math.cos(yaw) - ly * math.sin(yaw), lx * math.sin(yaw) + ly * math.cos(yaw), lz))


for lx, ly in ((-1.6, 0.2), (1.6, 0.2), (0, 1.4)):
    cyl(onboard(lx, 2.2, ly), 0.07, 4.4, wood, verts=8)
box(onboard(0, 3.3, -0.1), (4.8, 0.14, 3.0), slate, rot=(0, 0, math.degrees(yaw)), bevel=0.03)
box(onboard(0, 3.3, -0.176), (4.4, 0.01, 2.6), chalk_dust, rot=(0, 0, math.degrees(yaw)))
for lz in (1.75, 4.85):
    box(onboard(0, lz, -0.12), (5.0, 0.2, 0.18), wood, rot=(0, 0, math.degrees(yaw)))
box(onboard(1.9, 1.88, -0.25), (0.5, 0.08, 0.08), pbr("chalkstick", (0.92, 0.9, 0.84), 0.9), rot=(0, 0, math.degrees(yaw) + 8))

# The desk lamp: a dark green shade at the top left; warm light pooled on the felt, a cool window fill.
lamp_pos, lamp_tgt = Vector((-9.0, -3.0, 11.5)), Vector((-1.0, 2.5, 0))
bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=1.5, radius2=0.5, depth=1.6, location=lamp_pos)
shade = bpy.context.object
shade.rotation_euler = (lamp_pos - lamp_tgt).to_track_quat("Z", "Y").to_euler()
put(shade, pbr("shade", (0.10, 0.20, 0.14), 0.4, metal=0.3))
shade.visible_shadow = False            # its rim cut hard-edged patches out of the lamp's pool
lamp = light("SPOT", lamp_pos - (lamp_pos - lamp_tgt).normalized() * 0.6, float(os.environ.get("TOPPLE_LAMP", "2000")),
             (1.0, 0.76, 0.52), size=0.8, target=lamp_tgt)
lamp.data.spot_size = R(120)
lamp.data.spot_blend = 1.0
light("AREA", (0, 3, 15), float(os.environ.get("TOPPLE_FILL", "950")), (1.0, 0.86, 0.70), size=16, target=(0, 3, 0))
light("AREA", (14, 16, 12), float(os.environ.get("TOPPLE_WIN", "600")), (0.72, 0.80, 1.0), size=8, target=(0, 3, 0))
light("AREA", (2, -18, 14), 400, (1.0, 0.85, 0.7), size=14, target=(0, 3, 0))

# ------------------------------------------------------------------ camera (the game's) and render
cam = bpy.data.cameras.new("cam")
cam.sensor_fit = "VERTICAL"
cam.angle = R(VFOV)
cam.clip_end = 300
cam.dof.use_dof = True
focus = Vector(B(0.0, 0.5, -3.0))
co = bpy.data.objects.new("cam", cam)
co.location = B(*CAM_POS)
co.rotation_euler = (Vector(B(*CAM_LOOK)) - co.location).to_track_quat("-Z", "Y").to_euler()
cam.dof.focus_distance = (focus - co.location).length
cam.dof.aperture_fstop = 1.4
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
sc.cycles.max_bounces = 8
sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = WIDTH, HEIGHT, 100
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Medium High Contrast"
sc.view_settings.exposure = 0.4
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGB"
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("DONE", OUT)
