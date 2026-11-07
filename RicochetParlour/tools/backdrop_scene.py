"""Blender (Cycles) scene for Ricochet Parlour's pre-rendered backdrop. Run by tools/make_backdrop.py:

    blender -b --factory-startup --python tools/backdrop_scene.py -- GEOMETRY.json OUT_DIR SAMPLES WIDTH HEIGHT

The static board (walnut frame, dentil arch, aprons, felt, brass pins, rubber bumpers, brass cups with ivory
plates, the drop slot, the papered wall) lit by the concept render's warm lamp and cool fill, seen from the
game's fixed camera. Geometry comes from the rules (pins, walls, cups) so the picture matches the physics.

Blender axes: X right, Y away from the camera, Z up. Engine (x, y, z) = Blender (x, -y, z) -> (x, z, -y).
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
GEOM, OUT, SAMPLES, WIDTH, HEIGHT = argv[0], argv[1], int(argv[2]), int(argv[3]), int(argv[4])
G = json.load(open(GEOM))
TEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets", "Textures")
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def B(x, y, z=0.0):
    """Engine point (x right, y up, z toward camera) -> Blender location."""
    return (x, -z, y)


def principled(name):
    m = bpy.data.materials.new(name); m.use_nodes = True
    return m, m.node_tree, m.node_tree.nodes["Principled BSDF"]


def mat(name, base, metal=0.0, rough=0.5, coat=0.0):
    m, nt, p = principled(name)
    p.inputs["Base Color"].default_value = (*base, 1)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    p.inputs["Coat Weight"].default_value = coat
    return m


def textured(name, c1, c2, scale, rough, detail=8, bump=0.1, stretch=(1, 1, 1), coat=0.0):
    m, nt, p = principled(name)
    tc = nt.nodes.new("ShaderNodeTexCoord"); mp = nt.nodes.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = stretch
    nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = scale; nz.inputs["Detail"].default_value = detail
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*c1, 1); ramp.color_ramp.elements[1].color = (*c2, 1)
    bp = nt.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = bump
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"]); nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"]); nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
    nt.links.new(nz.outputs["Fac"], bp.inputs["Height"]); nt.links.new(bp.outputs["Normal"], p.inputs["Normal"])
    p.inputs["Roughness"].default_value = rough; p.inputs["Coat Weight"].default_value = coat
    return m


def image_mat(name, path, rough=0.35, coat=0.5):
    m, nt, p = principled(name)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = bpy.data.images.load(os.path.abspath(path))
    nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough; p.inputs["Coat Weight"].default_value = coat
    return m


def put(o, m, smooth=False):
    o.data.materials.append(m)
    if smooth:
        for pg in o.data.polygons: pg.use_smooth = True
    return o


def box(size, loc, m, rot=(0, 0, 0), bevel=0.0, segs=4):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object; o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        b = o.modifiers.new("b", "BEVEL"); b.width = bevel; b.segments = segs; b.limit_method = "NONE"
    return put(o, m)


def cyl(r, d, loc, m, rot=(math.pi / 2, 0, 0), v=40, bevel=True):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d, location=loc, rotation=rot, vertices=v)
    o = bpy.context.object
    if bevel:
        b = o.modifiers.new("b", "BEVEL"); b.width = min(r, d) * 0.25; b.segments = 3; b.limit_method = "ANGLE"
    return put(o, m, True)


def torus(R0, r, loc, m):
    bpy.ops.mesh.primitive_torus_add(location=loc, rotation=(math.pi / 2, 0, 0), major_radius=R0, minor_radius=r,
                                     major_segments=96, minor_segments=16)
    return put(bpy.context.object, m, True)


# ------------------------------------------------------------------ materials (the concept render's)
WALNUT = textured("walnut", (0.09, 0.045, 0.02), (0.22, 0.11, 0.05), 7, 0.28, bump=0.04, stretch=(1, 1, 0.12), coat=0.7)
WALNUT_H = textured("walnut_h", (0.09, 0.045, 0.02), (0.22, 0.11, 0.05), 7, 0.28, bump=0.04, stretch=(0.12, 1, 1), coat=0.7)
FELT = textured("felt", (0.04, 0.16, 0.09), (0.06, 0.22, 0.12), 60, 0.95, detail=4, bump=0.15)
BRASS = mat("brass", (0.85, 0.62, 0.3), 1.0, 0.18)
BRASS_POL = mat("brass_pol", (0.92, 0.72, 0.42), 1.0, 0.08)
RUBBER = mat("rubber", (0.35, 0.05, 0.04), 0.0, 0.6)
SLOT = mat("slot", (0.01, 0.01, 0.012), 0, 0.9)
WALL = textured("wallpaper", (0.1, 0.07, 0.05), (0.16, 0.11, 0.07), 3, 0.8, bump=0.05)
W, H, SLOTW = G["W"], G["H"], G["SLOT"]

# Felt and frame (rails are 0.4 wide, 0.5 deep; their inner faces are the rules' side walls at x = +-3).
box((W + 0.1, 0.1, H + 0.1), (0, 0.05, H / 2), FELT)
for sx in (-1, 1):
    box((0.4, 0.5, H + 0.4), (sx * (W / 2 + 0.2), -0.15, H / 2), WALNUT, bevel=0.06)
box((W + 0.8, 0.5, 0.4), (0, -0.15, H + 0.2), WALNUT_H, bevel=0.06)
half = (W + 0.8) / 2 - SLOTW
for sx in (-1, 1):
    box((half, 0.6, 0.3), (sx * (SLOTW + half / 2), -0.2, -0.3), WALNUT_H, bevel=0.05)
# The drop slot: a dark pocket under the gap, with a walnut floor set back.
box((SLOTW * 2, 0.04, 0.5), B(0, -0.16, -0.12), SLOT)
for sx in (-1, 1):
    box((0.02, 0.5, 0.5), B(sx * (SLOTW + 0.01), -0.16, 0.12), SLOT)
box((SLOTW * 2 + 0.02, 0.4, 0.06), B(0, -0.42, 0.05), WALNUT_H, bevel=0.02)

walls = G["walls"]
# Dentil arch: a walnut block per arch segment, inner face on the collision line.
for s in walls[2:-2]:
    mx, my = (s[0] + s[2]) / 2, (s[1] + s[3]) / 2
    dx, dy = s[2] - s[0], s[3] - s[1]
    L = math.hypot(dx, dy)
    nx, ny = dy / L, -dx / L
    if mx * nx + (my - G["ARCH_CY"]) * ny < 0:
        nx, ny = -nx, -ny
    th = math.atan2(dy, dx)
    box((L * 0.9, 0.3, 0.2), B(mx + nx * 0.1, my + ny * 0.1, 0.15), WALNUT_H, rot=(0, -th, 0), bevel=0.03, segs=3)
# Aprons: thick boards whose top face is the collision line, running from inside the rail to the slot.
for s in walls[-2:]:
    dx, dy = s[2] - s[0], s[3] - s[1]
    L = math.hypot(dx, dy)
    dx, dy = dx / L, dy / L
    nx, ny = -dy, dx
    if ny < 0:
        nx, ny = -nx, -ny
    ox, oy = s[0] - dx * 0.15 - nx * 0.11, s[1] - dy * 0.15 - ny * 0.11
    Lb = 2.65
    th = math.atan2(dy, dx)
    box((Lb, 0.3, 0.22), B(ox + dx * Lb / 2, oy + dy * Lb / 2, 0.15), WALNUT_H, rot=(0, -th, 0), bevel=0.05)
# Pins: brass posts with a domed cap and a collar on the felt; rubber rings on the bumpers.
for p in G["pins"]:
    cyl(0.062, 0.31, B(p["x"], p["y"], 0.105), BRASS_POL)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.062, location=B(p["x"], p["y"], 0.26), segments=24, ring_count=12)
    o = bpy.context.object; o.scale = (1, 0.45, 1); put(o, BRASS_POL, True)
    cyl(0.1, 0.034, B(p["x"], p["y"], 0.017), BRASS)
    if p["rubber"]:
        torus(0.12, 0.042, B(p["x"], p["y"], G["BALL_R"] + 0.01), RUBBER)
# Bonus cups: brass rings inlaid in the felt, ivory number plates below.
for c in G["cups"]:
    torus(c["r"], 0.04, B(c["x"], c["y"], 0.005), BRASS_POL)
    bpy.ops.mesh.primitive_plane_add(size=1, location=B(c["x"], c["y"] - c["r"] - 0.2, 0.012), rotation=(math.pi / 2, 0, 0))
    o = bpy.context.object; o.scale = (0.62, 0.23, 1)
    put(o, image_mat(f"plate{c['points']}", os.path.join(TEX, f"plate{c['points']}.png")))
    box((0.66, 0.012, 0.27), B(c["x"], c["y"] - c["r"] - 0.2, 0.004), BRASS, bevel=0.004, segs=2)

# Room: papered wall behind.
box((40, 0.2, 26), (0, 0.5, 5), WALL)

# ------------------------------------------------------------------ light and camera (the concept render's)
lamp = bpy.data.lights.new("lamp", "SPOT"); lamp.energy = 2600; lamp.color = (1, 0.85, 0.62)
lamp.spot_size = math.radians(75); lamp.spot_blend = 0.6; lamp.shadow_soft_size = 0.6
lo = bpy.data.objects.new("lamp", lamp); lo.location = (0.4, -4.5, 10.5)
lo.rotation_euler = (Vector((0, 0, 4)) - lo.location).to_track_quat("-Z", "Y").to_euler(); scene.collection.objects.link(lo)
fill = bpy.data.lights.new("fill", "AREA"); fill.energy = 220; fill.size = 6; fill.color = (0.75, 0.82, 1.0)
fo = bpy.data.objects.new("fill", fill); fo.location = (-6, -8, 4)
fo.rotation_euler = (Vector((0, 0, 4)) - fo.location).to_track_quat("-Z", "Y").to_euler(); scene.collection.objects.link(fo)
w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.01, 0.009, 0.008, 1)

cam = bpy.data.cameras.new("cam"); cam.sensor_fit = "VERTICAL"; cam.angle = math.radians(46)
cam.dof.use_dof = True; cam.dof.focus_distance = 12.6; cam.dof.aperture_fstop = 8
co = bpy.data.objects.new("cam", cam); co.location = B(1.3, 4.4, 12.6)
co.rotation_euler = (Vector(B(0.15, 4.05, 0.0)) - co.location).to_track_quat("-Z", "Y").to_euler()
scene.collection.objects.link(co); scene.camera = co

r = scene.render
r.engine = "CYCLES"; r.resolution_x, r.resolution_y, r.resolution_percentage = WIDTH, HEIGHT, 100
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "OPTIX"; prefs.get_devices()
for d in prefs.devices: d.use = d.type == "OPTIX"
scene.cycles.device = "GPU"; scene.cycles.samples = SAMPLES; scene.cycles.use_denoising = True
scene.cycles.max_bounces = 10
scene.view_settings.view_transform = "Standard"
r.image_settings.file_format = "OPEN_EXR"; r.image_settings.color_depth = "32"
r.filepath = os.path.join(OUT, "backdrop.exr")
bpy.ops.render.render(write_still=True)
img = bpy.data.images.load(os.path.join(OUT, "backdrop.exr"))
wd, ht = img.size
buf = np.empty(wd * ht * 4, np.float32); img.pixels.foreach_get(buf)
np.save(os.path.join(OUT, "backdrop.npy"), buf.reshape(ht, wd, 4)[::-1, :, :3].copy())
print("DONE", wd, ht)
