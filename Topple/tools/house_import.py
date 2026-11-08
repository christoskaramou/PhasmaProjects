"""Blender side of tools/make_houses.py (import step): bring a Tripo GLB to the game's conventions and export it.

    blender -b --factory-startup --python tools/house_import.py -- <in.glb> <out.obj> <out_texture.png> <height> <yaw_deg> [sheet.png|-] [icon.png]

- joins the model into one mesh with transforms applied;
- turns it so its footprint is square to the axes (the yaw that gives the smallest bounding rectangle), then by
  yaw_deg more (a multiple of 90 that puts the door on -Y, the game's front);
- scales it to `height` (its base on z = 0, centred on the origin);
- saves the model's base colour image as a PNG (at most 1024 px) and exports an OBJ with UVs and normals
  (Blender's OBJ export maps -Y to the game's +Z, Z to +Y);
- optionally renders the four sides into one sheet, to check which side is the front.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

a = sys.argv[sys.argv.index("--") + 1:]
GLB, OBJ, TEX, HEIGHT, YAW = a[0], a[1], a[2], float(a[3]), float(a[4])
SHEET = a[5] if len(a) > 5 and a[5] != "-" else None
ICON = a[6] if len(a) > 6 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
if len(meshes) > 1:
    bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for e in [x for x in bpy.context.scene.objects if x.type == "EMPTY"]:
    bpy.data.objects.remove(e, do_unlink=True)

# Square the footprint to the axes.
pts = [v.co.copy() for v in o.data.vertices]
best = None
for k in range(90):
    t = math.radians(k)
    c, s = math.cos(t), math.sin(t)
    xs = [p.x * c - p.y * s for p in pts]
    ys = [p.x * s + p.y * c for p in pts]
    area = (max(xs) - min(xs)) * (max(ys) - min(ys))
    if best is None or area < best[0]:
        best = (area, t)
rot = Matrix.Rotation(best[1] + math.radians(YAW), 4, "Z")
o.data.transform(rot)
# Scale to height, base on the ground, centred.
pts = [v.co for v in o.data.vertices]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
k = HEIGHT / (hi.z - lo.z)
o.data.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
o.data.transform(Matrix.Scale(k, 4))
pts = [v.co for v in o.data.vertices]
size = (max(p.x for p in pts) - min(p.x for p in pts), max(p.y for p in pts) - min(p.y for p in pts), max(p.z for p in pts))
print("SIZE %.3f %.3f %.3f faces %d footprint_yaw %.1f" % (size[0], size[1], size[2], len(o.data.polygons), math.degrees(best[1])))

# The base colour image.
img = None
for m in o.data.materials:
    if m and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                outs = [l.to_node for s_ in n.outputs for l in s_.links]
                if any(t.type == "BSDF_PRINCIPLED" for t in outs) or img is None:
                    img = n.image
if img:
    im = img.copy()
    if max(im.size) > 1024:
        im.scale(1024, 1024)
    im.filepath_raw = TEX
    im.file_format = "PNG"
    im.save()
    print("TEXTURE", TEX, tuple(im.size))
else:
    print("NO TEXTURE")

bpy.ops.object.select_all(action="DESELECT")
o.select_set(True)
bpy.ops.wm.obj_export(filepath=OBJ, export_selected_objects=True, export_materials=False, export_uv=True, export_normals=True,
                      apply_modifiers=True, forward_axis="NEGATIVE_Z", up_axis="Y")
print("OBJ", OBJ)

if SHEET:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 384
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.78, 0.8, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.2
    cam = bpy.data.cameras.new("c"); cam.type = "ORTHO"; cam.ortho_scale = max(size) * 1.3
    co = bpy.data.objects.new("c", cam); bpy.context.collection.objects.link(co); sc.camera = co
SHEET_FILES = []
if SHEET:
    for name, d in (("front", (0, -1, 0.35)), ("right", (1, 0, 0.35)), ("back", (0, 1, 0.35)), ("left", (-1, 0, 0.35))):
        dv = Vector(d).normalized()
        co.location = Vector((0, 0, size[2] / 2)) + dv * 10
        co.rotation_euler = (-dv).to_track_quat("-Z", "Y").to_euler()
        f = SHEET.replace(".png", "_%s.png" % name)
        sc.render.filepath = f
        bpy.ops.render.render(write_still=True)
        SHEET_FILES.append(f)
if ICON:
    # The shop icon, framed and lit like tools/icon_scene.py (the game camera's side, warm key, cool fill), transparent.
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 256
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.render.image_settings.color_mode = "RGBA"
    if not sc.world:
        sc.world = bpy.data.worlds.new("W")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.16, 0.12, 0.09, 1)
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    for kind, energy, d, col in (("AREA", 900, (-8, -6, 11), (1.0, 0.8, 0.58)), ("AREA", 260, (10, 12, 6), (0.75, 0.82, 1.0)), ("AREA", 160, (0.42, -0.75, 0.3), (1.0, 0.9, 0.8))):
        L = bpy.data.lights.new("L", kind); L.energy, L.color, L.size = energy, col, 5.0
        lo_ = bpy.data.objects.new("L", L); bpy.context.collection.objects.link(lo_)
        dv = Vector(d).normalized(); lo_.location = Vector((0, 0, size[2] / 2)) + dv * 12
        lo_.rotation_euler = (-dv).to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.cameras.new("ic"); cam.type = "ORTHO"
    ic = bpy.data.objects.new("ic", cam); bpy.context.collection.objects.link(ic); sc.camera = ic
    view = Vector((0.42, -0.75, 0.44)).normalized()
    ic.location = Vector((0, 0, size[2] / 2)) + view * 30
    ic.rotation_euler = (-view).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()
    right = (ic.matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()
    upv = (ic.matrix_world.to_3x3() @ Vector((0, 1, 0))).normalized()
    ctr = Vector((0, 0, size[2] / 2))
    xs = [(v.co - ctr).dot(right) for v in o.data.vertices]
    ys = [(v.co - ctr).dot(upv) for v in o.data.vertices]
    cam.ortho_scale = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.12
    ic.location = ctr + right * (max(xs) + min(xs)) / 2 + upv * (max(ys) + min(ys)) / 2 + view * 30
    sc.render.filepath = ICON
    bpy.ops.render.render(write_still=True)
    print("ICON", ICON)
print("DONE")
