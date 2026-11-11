"""Blender side of tools/make_furniture.py: bring a Tripo GLB into the room, baked in table coordinates.

    blender -b --factory-startup --python tools/furniture_import.py -- <in.glb> <out.obj> <out_texture.png> <spec.json>

spec: at [x, y], yaw (degrees), and size_x (length along x before the yaw) or size_z (height), or size [x, y, h]
(tools/gen_house.py: the room spec's box; the model gets one uniform scale that fits it inside the box, centred on the
footprint, seated on the base), turn (quarter turns in degrees that bring the model's front to -y, default 0) and z
(the base's height, default 0).
Blender's axes are the table's (x, y, h), and the OBJ export maps them to the engine's (x, h, -y), so a room piece needs
no node transform. Prints BOX (the world bounds) and SLICE lines (the footprint of the model in height bands), which
is what the collision boxes in tools/gen_room.py are read from.
"""
import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

a = sys.argv[sys.argv.index("--") + 1:]
GLB, OBJ, TEX = a[0], a[1], a[2]
F = json.load(open(a[3]))
MAX_TEX = 2048          # the camera gets close to furniture, unlike Table Run's houses

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

# The same steps as the room concept (tools/room_concept_scene.py): square to the axes, scale, turn, stand at its spot.
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
if F.get("size") and best[1] > math.radians(45):
    best = (best[0], best[1] - math.pi / 2)      # the same box, without swapping the model's width and depth
o.data.transform(Matrix.Rotation(best[1], 4, "Z"))
if F.get("size"):
    # turn: quarter turns (degrees, multiple of 90) that bring the model's front to local -y, the spec's front.
    o.data.transform(Matrix.Rotation(math.radians(F.get("turn", 0.0)), 4, "Z"))
pts = [v.co for v in o.data.vertices]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
o.data.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
if F.get("size"):
    # tools/gen_house.py: one uniform scale that fits the model inside the spec's box (x, y, h), centred on its
    # footprint and seated on its base, so the box (the collision the rules use) never has to move for the model.
    ext = [hi[i] - lo[i] for i in range(3)]
    k = min(F["size"][i] / max(1e-9, ext[i]) for i in range(3)) * min(1.0, F.get("shrink", 1.0))
    got = [e * k for e in ext]
    print("FIT uniform %.4f  model %.2f x %.2f x %.2f in box %.2f x %.2f x %.2f  (short by %.2f %.2f %.2f)" % (
        k, *got, *F["size"], *[F["size"][i] - got[i] for i in range(3)]))
    o.data.transform(Matrix.Scale(k, 4))
else:
    k = F["size_x"] / (hi.x - lo.x) if F.get("size_x") else F["size_z"] / (hi.z - lo.z)
    o.data.transform(Matrix.Scale(k, 4))
o.data.transform(Matrix.Rotation(math.radians(F.get("yaw", 0.0)), 4, "Z"))
o.data.transform(Matrix.Translation((F["at"][0], F["at"][1], F.get("z", 0.0))))
o.data.update()

P = [v.co.copy() for v in o.data.vertices]
top = max(p.z for p in P)
print("BOX x %.2f %.2f y %.2f %.2f h 0 %.2f faces %d" % (min(p.x for p in P), max(p.x for p in P), min(p.y for p in P), max(p.y for p in P), top,
                                                         len(o.data.polygons)))
BANDS = 12
for b in range(BANDS):
    h0, h1 = top * b / BANDS, top * (b + 1) / BANDS
    S = [p for p in P if h0 <= p.z <= h1]
    if S:
        print("SLICE h %.2f-%.2f x %.2f %.2f y %.2f %.2f n %d" % (h0, h1, min(p.x for p in S), max(p.x for p in S), min(p.y for p in S), max(p.y for p in S), len(S)))

img = None
for m in o.data.materials:
    if m and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                if any(l.to_node.type == "BSDF_PRINCIPLED" for s_ in n.outputs for l in s_.links) or img is None:
                    img = n.image
if img:
    im = img.copy()
    if max(im.size) > MAX_TEX:
        im.scale(MAX_TEX, MAX_TEX)
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
print("DONE")
