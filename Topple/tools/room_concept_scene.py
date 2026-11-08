"""Blender side of tools/make_room_concept.py: build the Free Build room concept and render it.

    blender -b --factory-startup --python tools/room_concept_scene.py -- concept_spec.json

Table coordinates (x right, y away, h up) are Blender's (x, y, z). The game's OBJs are in engine axes and import
with Blender's defaults (forward -Z, up Y). Domino poses are engine positions and Euler degrees (R = Rz * Ry * Rx).
"""
import json
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Vector

spec = json.load(open(sys.argv[sys.argv.index("--") + 1:][0]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
COL = sc.collection


# ------------------------------------------------------------------ materials
def principled(name, color=(1, 1, 1), rough=0.5, metal=0.0, tex=None, emis=None, emis_tex=None, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    N, L = m.node_tree.nodes, m.node_tree.links
    p = N["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    p.inputs["Coat Weight"].default_value = coat
    if tex:
        t = N.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(tex)
        L.new(t.outputs["Color"], p.inputs["Base Color"])
    if emis_tex or emis:
        if emis_tex:
            t = N.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(emis_tex)
            L.new(t.outputs["Color"], p.inputs["Emission Color"])
        else:
            p.inputs["Emission Color"].default_value = (*emis, 1)
        p.inputs["Emission Strength"].default_value = 1.0
    return m


def window_glass(sky_tex):
    """See-through for the sun (Transparent BSDF), with the garden picture glowing faintly on it."""
    m = bpy.data.materials.new("glass")
    m.use_nodes = True
    N, L = m.node_tree.nodes, m.node_tree.links
    N.remove(N["Principled BSDF"])
    out = N["Material Output"]
    tr = N.new("ShaderNodeBsdfTransparent")
    em = N.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = 1.6
    t = N.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(sky_tex)
    L.new(t.outputs["Color"], em.inputs["Color"])
    lp = N.new("ShaderNodeLightPath")
    mix = N.new("ShaderNodeMixShader")
    L.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])     # the camera sees the garden; light rays pass through
    L.new(tr.outputs["BSDF"], mix.inputs[1])
    L.new(em.outputs["Emission"], mix.inputs[2])
    L.new(mix.outputs["Shader"], out.inputs["Surface"])
    return m


def import_obj(path):
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    return new[0] if new else None


# ------------------------------------------------------------------ the room
for pc in spec["pieces"]:
    o = import_obj(pc["obj"])
    if not o:
        continue
    o.data.materials.clear()
    if pc.get("transmission"):
        o.data.materials.append(window_glass(pc["emis_tex"]))
    else:
        o.data.materials.append(principled(pc["name"], tuple(pc.get("color", (1, 1, 1))), pc.get("rough", 0.5), pc.get("metal", 0.0),
                                           pc.get("tex"), tuple(pc["emis"]) if pc.get("emis") and not pc.get("emis_tex") else None,
                                           pc.get("emis_tex")))
    for f in o.data.polygons:
        f.use_smooth = True
    # The camera looks in through the ceiling and the front wall; they still shut the sun out.
    if pc["name"] in ("room_ceiling", "room_wall_F", "room_trim_F"):
        o.visible_camera = False


def box(x0, x1, y0, y1, z0, z1, mat, bevel=0.06):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    o = bpy.context.object
    o.scale = (x1 - x0, y1 - y0, z1 - z0)
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        b = o.modifiers.new("b", "BEVEL"); b.width = bevel; b.segments = 3
    o.data.materials.append(mat)
    return o


# The staircase of books (covers, page edges inset on three sides).
covers = [principled("cover%d" % i, c, 0.5) for i, c in enumerate([(0.06, 0.1, 0.22), (0.66, 0.44, 0.1), (0.42, 0.07, 0.05),
                                                                   (0.25, 0.36, 0.23), (0.26, 0.08, 0.15)])]
pages = principled("pages", (0.8, 0.75, 0.62), 0.8)
for i, bk in enumerate(spec["books"]):
    box(bk["x0"], bk["x1"], bk["y0"], bk["y1"], bk["h0"] + 0.02, bk["h1"], covers[i % 5], 0.05)
    box(bk["x0"] + 0.15, bk["x1"] - 0.15, bk["y0"] + 0.35, bk["y1"] + 0.02, bk["h0"] + 0.1, bk["h1"] - 0.08, pages, 0.02)

# The side table under the lamp, and frames round the paintings.
walnut = principled("walnut", (0.11, 0.05, 0.022), 0.4, coat=0.4)
sd = spec["side"]
bpy.ops.mesh.primitive_cylinder_add(radius=sd["r"], depth=0.5, location=(sd["x"], sd["y"], sd["h"] - 0.25), vertices=64)
bpy.context.object.data.materials.append(walnut)
bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=sd["h"] - 0.5, location=(sd["x"], sd["y"], (sd["h"] - 0.5) / 2), vertices=24)
bpy.context.object.data.materials.append(walnut)
bpy.ops.mesh.primitive_cylinder_add(radius=2.4, depth=0.4, location=(sd["x"], sd["y"], 0.2), vertices=48)
bpy.context.object.data.materials.append(walnut)
for a0, a1, h0, h1 in spec["art"]:
    f = 0.9
    y = 34.0
    for (x0, x1, z0, z1) in ((a0 - f, a1 + f, h1, h1 + f), (a0 - f, a1 + f, h0 - f, h0), (a0 - f, a0, h0, h1), (a1, a1 + f, h0, h1)):
        box(x0, x1, y - 0.5, y, z0, z1, walnut, 0.1)

# The ramp: a wooden ruler propped from the coffee table's front edge down onto the rug, a glass marble at its top.
tb = spec["table"]
ruler = principled("ruler", (0.55, 0.38, 0.18), 0.45)
top, bot = Vector((-12.0, tb["y0"] - 0.2, tb["h"] + 0.3)), Vector((-12.0, -16.6, 0.3))
mid = (top + bot) / 2
length = (top - bot).length
bpy.ops.mesh.primitive_cube_add(size=1, location=mid)
rm = bpy.context.object
rm.scale = (2.6, length, 0.25)
rm.rotation_euler = (math.atan2(top.z - bot.z, top.y - bot.y), 0, 0)     # local Y along the slope
rm.data.materials.append(ruler)
for s in (-1, 1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=mid + Vector((s * 1.25, 0, 0.3)))
    rl = bpy.context.object
    rl.scale = (0.12, length, 0.45)
    rl.rotation_euler = rm.rotation_euler
    rl.data.materials.append(ruler)
mg = bpy.data.materials.new("marble")
mg.use_nodes = True
pm = mg.node_tree.nodes["Principled BSDF"]
pm.inputs["Base Color"].default_value = (0.95, 0.72, 0.42, 1)
pm.inputs["Transmission Weight"].default_value = 1.0
pm.inputs["Roughness"].default_value = 0.02
pm.inputs["IOR"].default_value = 1.5
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.75, location=top + Vector((0, -2.2, 0.55 + 0.1)), segments=48, ring_count=24)
mo = bpy.context.object
mo.data.materials.append(mg)
for f in mo.data.polygons:
    f.use_smooth = True

# The swinging ball: a brass frame between the sofa and the bookshelf, a steel ball on a cord, pulled back toward the
# wall and about to swing down onto the end of its line.
brass = principled("brass", (0.85, 0.62, 0.3), 0.25, 1.0)
steel = principled("steel", (0.8, 0.8, 0.82), 0.15, 1.0)
cord = principled("cord", (0.75, 0.7, 0.6), 0.8)
px, py = 9.0, 21.5
for dx in (-2.8, 2.8):
    box(px + dx - 0.3, px + dx + 0.3, py - 0.3, py + 0.3, 0, 15, brass, 0.1)
    box(px + dx - 1.2, px + dx + 1.2, py - 1.2, py + 1.2, 0, 0.4, brass, 0.1)
box(px - 3.1, px + 3.1, py - 0.3, py + 0.3, 14.6, 15.2, brass, 0.1)
pivot = Vector((px, py, 14.9))
ang = math.radians(32)
ball = pivot + Vector((0, math.sin(ang) * 12.5, -math.cos(ang) * 12.5))
bpy.ops.mesh.primitive_uv_sphere_add(radius=1.1, location=ball, segments=48, ring_count=24)
bo = bpy.context.object
bo.data.materials.append(steel)
for f in bo.data.polygons:
    f.use_smooth = True
d = ball - pivot
bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=d.length, location=(pivot + ball) / 2, vertices=8)
cd = bpy.context.object
cd.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
cd.data.materials.append(cord)

# ------------------------------------------------------------------ Tripo furniture
for name, f in spec["furniture"].items():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f["glb"])
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for e in [x for x in new if x.type == "EMPTY"]:
        bpy.data.objects.remove(e, do_unlink=True)
    # Square to the axes (smallest footprint), turn by its yaw, scale, stand it at its spot.
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
    o.data.transform(Matrix.Rotation(best[1], 4, "Z"))
    pts = [v.co for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    k = f["size_x"] / (hi.x - lo.x) if f.get("size_x") else f["size_z"] / (hi.z - lo.z)
    o.data.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
    o.data.transform(Matrix.Scale(k, 4))
    o.data.transform(Matrix.Rotation(math.radians(f.get("yaw", 0.0)), 4, "Z"))
    o.location = (f["at"][0], f["at"][1], 0.0)
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    print("FURN %s size %.1f x %.1f x %.1f" % (name, max(p.x for p in pts) - min(p.x for p in pts), max(p.y for p in pts) - min(p.y for p in pts),
                                               max(p.z for p in pts)))

# ------------------------------------------------------------------ dominoes
lay = json.load(open(spec["layout"]))
PAINT = {"brick": (0.5, 0.13, 0.07), "mustard": (0.78, 0.52, 0.13), "sage": (0.32, 0.44, 0.3), "navy": (0.1, 0.16, 0.32), "cream": (0.84, 0.77, 0.62)}
pmat = {k: principled("dom_" + k, c, 0.3, coat=0.5) for k, c in PAINT.items()}
pip_dark, pip_light = principled("pip_dark", (0.03, 0.03, 0.03), 0.35), principled("pip_light", (0.88, 0.82, 0.68), 0.35)
body = import_obj(os.path.join(spec["objdir"], "domino.obj"))
pipobj = [import_obj(os.path.join(spec["objdir"], f"pips_{k}.obj")) for k in range(10)]
shared = {}


def domino_mesh(paint, k):
    key = (paint, k)
    if key in shared:
        return shared[key]
    a = body.copy(); a.data = body.data.copy(); a.data.materials.clear(); a.data.materials.append(pmat[paint])
    b = pipobj[k].copy(); b.data = pipobj[k].data.copy(); b.data.materials.clear()
    b.data.materials.append(pip_light if paint == "navy" else pip_dark)
    COL.objects.link(a); COL.objects.link(b)
    bpy.ops.object.select_all(action="DESELECT")
    a.select_set(True); b.select_set(True)
    bpy.context.view_layer.objects.active = a
    bpy.ops.object.join()
    for f in a.data.polygons:
        f.use_smooth = True
    me = a.data
    bpy.data.objects.remove(a, do_unlink=True)
    shared[key] = me
    return me


C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))     # engine axes -> Blender axes
for i, dd in enumerate(lay["dominoes"]):
    me = domino_mesh(dd["paint"], dd["pips"])
    o = bpy.data.objects.new("dom%d" % i, me)
    COL.objects.link(o)
    rx, ry, rz = (math.radians(v) for v in dd["r"])
    Re = Matrix.Rotation(rz, 3, "Z") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rx, 3, "X")
    Rb = C @ Re @ C.transposed()
    px_, py_, pz_ = dd["p"]
    o.matrix_world = Matrix.Translation((px_, -pz_, py_)) @ Rb.to_4x4()
for o in [body] + pipobj:
    bpy.data.objects.remove(o, do_unlink=True)
print("DOMINOES %d (%d fallen)" % (lay["count"], lay["fallen"]))

# ------------------------------------------------------------------ light, camera, render
sun = bpy.data.lights.new("sun", "SUN")
sun.energy = 7.0
sun.angle = math.radians(1.2)
sun.color = (1.0, 0.86, 0.68)
so = bpy.data.objects.new("sun", sun)
COL.objects.link(so)
so.rotation_euler = Vector(spec["sun"]).normalized().to_track_quat("-Z", "Y").to_euler()
lamp = bpy.data.lights.new("lamp", "POINT")
lamp.energy = 2500.0
lamp.color = (1.0, 0.72, 0.42)
lamp.shadow_soft_size = 1.2
lo_ = bpy.data.objects.new("lamp", lamp)
COL.objects.link(lo_)
lo_.location = spec["lamp"]
fill = bpy.data.lights.new("fill", "AREA")
fill.energy = 12000.0
fill.size = 60.0
fill.color = (0.85, 0.9, 1.0)
fo = bpy.data.objects.new("fill", fill)
COL.objects.link(fo)
fo.location = (0, -10, 46.0)
fo.rotation_euler = (0, 0, 0)
fo.visible_camera = False
w = bpy.data.worlds.new("W")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.009, 0.007, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0

cam = bpy.data.cameras.new("cam")
cam.lens = 30
cam.dof.use_dof = True
cam.dof.aperture_fstop = 4.0
co = bpy.data.objects.new("cam", cam)
COL.objects.link(co)
sc.camera = co
target = Vector((-1.0, -6.0, 2.0))
yaw, pitch, dist = math.radians(-58), math.radians(33), 86.0
co.location = target + Vector((math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch))) * dist
co.rotation_euler = (target - co.location).to_track_quat("-Z", "Y").to_euler()
cam.dof.focus_distance = (Vector((14.0, -8.0, 1.0)) - co.location).length

sc.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
for dev in ("OPTIX", "CUDA"):
    try:
        prefs.compute_device_type = dev
        prefs.get_devices()
        if any(dv.type == dev for dv in prefs.devices):
            for dv in prefs.devices:
                dv.use = dv.type == dev
            sc.cycles.device = "GPU"
            break
    except TypeError:
        continue
sc.cycles.samples = spec["samples"]
sc.cycles.use_denoising = True
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Medium High Contrast"
sc.view_settings.exposure = 0.0
sc.render.image_settings.file_format = "PNG"
sc.render.filepath = spec["out"]
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=spec["out"].replace(".png", ".blend"))
print("DONE")
