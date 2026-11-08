"""Blender side of tools/make_icons.py: import the toy OBJs, paint them, frame each icon from the game camera's side
and render it on a transparent background.

    blender -b --factory-startup --python tools/icon_scene.py -- spec.json
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

spec = json.load(open(sys.argv[sys.argv.index("--") + 1:][0]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
COL = sc.collection

PAINT = {
    "brick": ((0.58, 0.15, 0.08), 0.32, 0.0), "mustard": ((0.80, 0.55, 0.14), 0.32, 0.0), "sage": ((0.33, 0.45, 0.31), 0.32, 0.0),
    "navy": ((0.11, 0.17, 0.32), 0.32, 0.0), "cream": ((0.86, 0.79, 0.64), 0.32, 0.0), "pip": ((0.03, 0.03, 0.03), 0.3, 0.0),
    "brass": ((0.86, 0.62, 0.30), 0.2, 1.0), "steel": ((0.78, 0.78, 0.80), 0.22, 1.0), "wood": ((0.58, 0.38, 0.19), 0.45, 0.0),
    "glassdark": ((0.04, 0.05, 0.06), 0.05, 0.0),
}
MATS = {}


def mat(name):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    if name == "glass":
        p.inputs["Base Color"].default_value = (0.95, 0.72, 0.42, 1)
        p.inputs["Roughness"].default_value = 0.02
        p.inputs["Transmission Weight"].default_value = 1.0
        p.inputs["IOR"].default_value = 1.5
    else:
        c, r, metal = PAINT[name]
        p.inputs["Base Color"].default_value = (*c, 1)
        p.inputs["Roughness"].default_value = r
        p.inputs["Metallic"].default_value = metal
        p.inputs["Coat Weight"].default_value = 0.5 if metal == 0 and name not in ("wood", "pip") else 0.0
    MATS[name] = m
    return m


C4 = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))   # engine -> Blender axes


def place(o, M_e):
    o.matrix_world = C4 @ Matrix(M_e) @ C4.inverted()


w = bpy.data.worlds.new("W")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.16, 0.12, 0.09, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7

cam = bpy.data.cameras.new("cam")
cam.type = "ORTHO"
co = bpy.data.objects.new("cam", cam)
COL.objects.link(co)
sc.camera = co
VIEW = Vector((0.42, -0.75, 0.44)).normalized()            # the game camera's side of the table


def add_light(kind, energy, color, size, d):
    L = bpy.data.lights.new(kind, kind)
    L.energy, L.color = energy, color
    L.size = size
    o = bpy.data.objects.new(kind, L)
    COL.objects.link(o)
    return o, Vector(d).normalized()


key = add_light("AREA", 900, (1.0, 0.8, 0.58), 4.0, (-8, -6, 11))
fill = add_light("AREA", 260, (0.75, 0.82, 1.0), 6.0, (10, 12, 6))
front = add_light("AREA", 160, (1.0, 0.9, 0.8), 6.0, (0.42, -0.75, 0.3))

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
sc.cycles.samples = spec["samples"]
sc.cycles.use_denoising = True
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = 256
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Medium High Contrast"
sc.view_settings.exposure = 0.3
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"

for icon, parts in spec["icons"].items():
    objs = []
    for mesh, m, M in parts:
        if mesh == "@marble":
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, segments=48, ring_count=24)
            o = bpy.context.object
            for f in o.data.polygons:
                f.use_smooth = True
            o.data.materials.append(mat("glass"))
            place(o, M)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, segments=24, ring_count=12)
            core = bpy.context.object
            core.data.materials.append(mat("brick"))
            place(core, M)
            objs += [o, core]
            continue
        bpy.ops.object.select_all(action="DESELECT")
        bpy.ops.wm.obj_import(filepath=os.path.join(spec["tmp"], mesh + ".obj"))
        for o in bpy.context.selected_objects:
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            o.data.materials.clear()
            o.data.materials.append(mat(m))
            place(o, M)
            objs.append(o)
    # Frame: the parts' bounds seen from the camera direction.
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    centre = sum(pts, Vector()) / len(pts)
    co.location = centre + VIEW * 30
    co.rotation_euler = (-VIEW).to_track_quat("-Z", "Y").to_euler()
    right = (co.matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()
    upv = (co.matrix_world.to_3x3() @ Vector((0, 1, 0))).normalized()
    xs = [(p - centre).dot(right) for p in pts]
    ys = [(p - centre).dot(upv) for p in pts]
    cam.ortho_scale = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.12
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    co.location = centre + right * cx + upv * cy + VIEW * 30
    for o, d in (key, fill, front):
        o.location = centre + d * 12
        o.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(spec["out"], f"icon_{icon}.png")
    bpy.ops.render.render(write_still=True)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
print("DONE")
