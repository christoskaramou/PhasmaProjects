"""Blender side of tools/make_houses.py (refs step): three miniature houses for Table Run, modelled at the game's scale
(a domino is 1 tall) like model-railway buildings in the concept's palette, rendered as clean 3/4 reference
pictures on a transparent background for Tripo's image-to-3D.

    blender -b --factory-startup --python tools/house_refs_scene.py -- <out_dir> [samples]

Blender axes: Z up, the front (door) faces -Y (the game's +Z, toward its camera).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
SAMPLES = int(args[1]) if len(args) > 1 else 160
os.makedirs(OUT, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ------------------------------------------------------------------ materials
def nodes_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m, m.node_tree.nodes, m.node_tree.links, m.node_tree.nodes["Principled BSDF"]


def paint(name, rgb, rough=0.55, coat=0.0, metal=0.0):
    m, N, L, p = nodes_mat(name)
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    p.inputs["Coat Weight"].default_value = coat
    return m


def plaster(name, rgb):
    """Rendered wall: the colour mottled a little, a fine bumpy surface."""
    m, N, L, p = nodes_mat(name)
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 18; nz.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs[6].default_value = (*[c * 0.88 for c in rgb], 1)
    mix.inputs[7].default_value = (*rgb, 1)
    L.new(nz.outputs["Fac"], mix.inputs[0])
    L.new(mix.outputs[2], p.inputs["Base Color"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25; bump.inputs["Distance"].default_value = 0.004
    L.new(nz.outputs["Fac"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], p.inputs["Normal"])
    p.inputs["Roughness"].default_value = 0.85
    return m


def courses(name, c1, c2, mortar, rows_per_unit, bricks_per_unit, bump_k=0.6, rough=0.75, row_offset=0.5):
    """A brick-texture pattern: brick walls, roof tiles in rows, slates."""
    m, N, L, p = nodes_mat(name)
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    L.new(tc.outputs["Object"], mp.inputs["Vector"])
    br = N.new("ShaderNodeTexBrick")
    br.offset = row_offset
    br.inputs["Color1"].default_value = (*c1, 1)
    br.inputs["Color2"].default_value = (*c2, 1)
    br.inputs["Mortar"].default_value = (*mortar, 1)
    br.inputs["Scale"].default_value = 1.0
    br.inputs["Mortar Size"].default_value = 0.012
    br.inputs["Brick Width"].default_value = 1.0 / bricks_per_unit
    br.inputs["Row Height"].default_value = 1.0 / rows_per_unit
    L.new(mp.outputs["Vector"], br.inputs["Vector"])
    L.new(br.outputs["Color"], p.inputs["Base Color"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = bump_k; bump.inputs["Distance"].default_value = 0.01
    L.new(br.outputs["Fac"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], p.inputs["Normal"])
    p.inputs["Roughness"].default_value = rough
    return m, mp


def boards(name, rgb):
    """Horizontal weatherboards: a wave pattern up the wall, painted."""
    m, N, L, p = nodes_mat(name)
    tc = N.new("ShaderNodeTexCoord")
    wv = N.new("ShaderNodeTexWave"); wv.wave_type = "BANDS"; wv.bands_direction = "Z"; wv.wave_profile = "SAW"
    wv.inputs["Scale"].default_value = 9.0; wv.inputs["Distortion"].default_value = 0.0
    L.new(tc.outputs["Object"], wv.inputs["Vector"])
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 40
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs[6].default_value = (*[c * 0.9 for c in rgb], 1)
    mix.inputs[7].default_value = (*rgb, 1)
    L.new(nz.outputs["Fac"], mix.inputs[0])
    L.new(mix.outputs[2], p.inputs["Base Color"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.6; bump.inputs["Distance"].default_value = 0.01
    L.new(wv.outputs["Fac"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], p.inputs["Normal"])
    p.inputs["Roughness"].default_value = 0.6
    return m


def glass():
    m, N, L, p = nodes_mat("glass")
    p.inputs["Base Color"].default_value = (0.05, 0.07, 0.09, 1)
    p.inputs["Roughness"].default_value = 0.06
    p.inputs["Specular IOR Level"].default_value = 0.8
    return m


# ------------------------------------------------------------------ geometry
def box(c, size, mat, bevel=0.012, segs=2, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=c)
    o = bpy.context.object
    o.scale = size
    if rot:
        o.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        b = o.modifiers.new("bevel", "BEVEL"); b.width = bevel; b.segments = segs; b.limit_method = "ANGLE"
    o.data.materials.append(mat)
    return o


def cyl(c, r, h, mat, verts=24, rot=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, vertices=verts, location=c)
    o = bpy.context.object
    if rot:
        o.rotation_euler = rot
    o.data.materials.append(mat)
    for f in o.data.polygons:
        f.use_smooth = True
    return o


def sphere(c, r, mat, sub=2):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=sub, location=c)
    o = bpy.context.object
    o.data.materials.append(mat)
    for f in o.data.polygons:
        f.use_smooth = True
    return o


def gable_walls(w, d, h, ridge, mat):
    """Four walls with triangular gables on the +-X ends, as one closed mesh (ridge along X)."""
    hw, hd = w / 2, d / 2
    V = [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0),
         (-hw, -hd, h), (hw, -hd, h), (hw, hd, h), (-hw, hd, h),
         (-hw, 0, ridge), (hw, 0, ridge)]
    F = [(0, 3, 2, 1), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 9, 5), (3, 0, 4, 8, 7), (4, 5, 9, 8), (7, 8, 9, 6)]
    me = bpy.data.meshes.new("walls")
    me.from_pydata(V, [], F)
    me.update()
    o = bpy.data.objects.new("walls", me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(mat)
    return o


def roof(w, d, h, ridge, over, thick, mat, ridge_mat):
    """Two pitched slabs meeting at the ridge, overhanging the walls, and a rounded ridge cap."""
    hd = d / 2 + over
    run = hd
    rise = (ridge - h) * hd / (d / 2)
    slope = math.atan2(ridge - h, d / 2)
    L = math.hypot(run, rise)
    zc = ridge - rise / 2 + thick * 0.5
    for s in (-1, 1):
        box((0, s * run / 2, zc), (w + 2 * over, L, thick), mat, 0.006, 1, rot=(-s * slope, 0, 0))
    cyl((0, 0, ridge + thick * 0.9), thick * 0.9, w + 2 * over + 0.02, ridge_mat, 20, rot=(0, math.pi / 2, 0))


def window(x, y, z, ww, wh, face, frame_m, glass_m, shutter_m=None, sill=True, bars=(1, 1)):
    """A sash window on a wall face: face is 'front' (-Y), 'back', 'left' (-X) or 'right'."""
    t = 0.035
    if face in ("front", "back"):
        s = -1 if face == "front" else 1
        def at(dx, dz, dy=0.0):
            return (x + dx, y + s * dy, z + dz)
        def sz(a, b, c):
            return (a, c, b)
    else:
        s = -1 if face == "left" else 1
        def at(dx, dz, dy=0.0):
            return (x + s * dy, y + dx, z + dz)
        def sz(a, b, c):
            return (c, a, b)
    box(at(0, 0, 0.004), sz(ww * 0.92, wh * 0.92, 0.012), glass_m, 0)
    for dz in (-wh / 2, wh / 2):
        box(at(0, dz, 0.018), sz(ww + t, t, 0.035), frame_m, 0.004, 1)
    for dx in (-ww / 2, ww / 2):
        box(at(dx, 0, 0.018), sz(t, wh + t, 0.035), frame_m, 0.004, 1)
    nx, nz = bars
    for i in range(1, nx + 1):
        box(at(-ww / 2 + ww * i / (nx + 1), 0, 0.016), sz(0.014, wh, 0.02), frame_m, 0)
    for i in range(1, nz + 1):
        box(at(0, -wh / 2 + wh * i / (nz + 1), 0.016), sz(ww, 0.014, 0.02), frame_m, 0)
    if sill:
        box(at(0, -wh / 2 - t, 0.04), sz(ww + 0.08, 0.025, 0.07), frame_m, 0.005, 1)
    if shutter_m:
        for dx in (-1, 1):
            box(at(dx * (ww / 2 + 0.07), 0, 0.02), sz(0.12, wh + 0.02, 0.018), shutter_m, 0.004, 1)


def door(x, y, z, dw, dh, face_y, door_m, frame_m, brass_m, step_m):
    s = -1 if face_y < 0 else 1
    box((x, y + s * 0.012, z + dh / 2), (dw, 0.03, dh), door_m, 0.005, 1)
    for dz in (dh * 0.28, dh * 0.7):
        box((x, y + s * 0.03, z + dz), (dw * 0.62, 0.012, dh * 0.3), door_m, 0.004, 1)
    for dx in (-dw / 2 - 0.02, dw / 2 + 0.02):
        box((x + dx, y + s * 0.02, z + dh / 2 + 0.01), (0.04, 0.045, dh + 0.04), frame_m, 0.004, 1)
    box((x, y + s * 0.02, z + dh + 0.03), (dw + 0.09, 0.05, 0.045), frame_m, 0.004, 1)
    sphere((x + dw * 0.32, y + s * 0.045, z + dh * 0.48), 0.018, brass_m, 2)
    box((x, y + s * 0.07, z + 0.02), (dw + 0.14, 0.14, 0.04), step_m, 0.006, 1)


def window_box(x, y, z, w, face_y, box_m, leaf_m, flower_m):
    s = -1 if face_y < 0 else 1
    box((x, y + s * 0.05, z), (w, 0.07, 0.05), box_m, 0.005, 1)
    for i in range(7):
        px = x - w / 2 + 0.03 + (w - 0.06) * i / 6
        sphere((px, y + s * 0.055, z + 0.04), 0.03, leaf_m, 1)
        if i % 2 == 0:
            sphere((px + 0.01, y + s * 0.075, z + 0.06), 0.014, flower_m, 1)


def chimney(x, y, base, top, w, mat, cap_m):
    box((x, y, (base + top) / 2), (w, w * 0.8, top - base), mat, 0.004, 1)
    box((x, y, top + 0.015), (w + 0.04, w * 0.8 + 0.04, 0.03), cap_m, 0.004, 1)
    cyl((x - w * 0.18, y, top + 0.07), 0.025, 0.08, cap_m, 12)


# ------------------------------------------------------------------ the houses
def cottage():
    """Cream rendered cottage, terracotta tiles, green shutters and door, brick chimney, window boxes."""
    w, d, h, ridge = 1.4, 1.1, 0.92, 1.62
    walls = plaster("plaster_cream", (0.88, 0.78, 0.58))
    tiles, mp = courses("tiles", (0.62, 0.22, 0.12), (0.52, 0.17, 0.09), (0.32, 0.11, 0.06), 22, 9, 0.9, 0.7)
    white, green = paint("white", (0.9, 0.88, 0.84), 0.4), paint("green", (0.12, 0.28, 0.17), 0.45, 0.3)
    brick, _ = courses("brick", (0.46, 0.15, 0.08), (0.36, 0.11, 0.06), (0.3, 0.27, 0.24), 22, 7, 0.5)
    stone, _ = courses("plinth", (0.55, 0.53, 0.5), (0.47, 0.46, 0.44), (0.35, 0.34, 0.32), 9, 5, 0.6, 0.9, 0.3)
    brass, glass_m = paint("brass", (0.85, 0.62, 0.3), 0.25, 0, 1), glass()
    leaf, flower = paint("leaf", (0.14, 0.32, 0.1), 0.6), paint("flower", (0.85, 0.2, 0.25), 0.5)
    box((0, 0, 0.04), (w + 0.06, d + 0.06, 0.08), stone, 0.01, 1)
    gable_walls(w, d, h, ridge - 0.03, walls).location.z = 0.08
    roof(w, d, h + 0.08, ridge + 0.05, 0.09, 0.05, tiles, tiles)
    door(-0.28, -d / 2, 0.08, 0.26, 0.5, -1, green, white, brass, stone)
    for x in (0.25,):
        window(x, -d / 2, 0.5, 0.3, 0.32, "front", white, glass_m, green)
        window_box(x, -d / 2, 0.3, 0.34, -1, green, leaf, flower)
    window(0.0, d / 2, 0.5, 0.3, 0.32, "back", white, glass_m, green)
    for f, x in (("left", -w / 2), ("right", w / 2)):
        window(x, 0.0, 0.5, 0.26, 0.3, f, white, glass_m)
        window(x, 0.0, 1.12, 0.18, 0.2, f, white, glass_m, bars=(1, 0))
    chimney(0.45, 0.18, 1.2, 1.9, 0.16, brick, stone)


def townhouse():
    """Narrow two-storey mustard townhouse, slate roof, white cornice, red door, stone chimney."""
    w, d, h, ridge = 1.1, 1.05, 1.36, 1.86
    walls = plaster("plaster_mustard", (0.8, 0.58, 0.22))
    slate, _ = courses("slate", (0.17, 0.2, 0.27), (0.13, 0.15, 0.21), (0.08, 0.09, 0.12), 26, 11, 0.7, 0.55)
    white, red = paint("white", (0.9, 0.88, 0.84), 0.4), paint("red", (0.5, 0.1, 0.07), 0.4, 0.4)
    stone, _ = courses("stone", (0.6, 0.58, 0.54), (0.52, 0.5, 0.47), (0.38, 0.37, 0.35), 10, 5, 0.6, 0.9, 0.3)
    brick2, _ = courses("brick2", (0.46, 0.15, 0.08), (0.36, 0.11, 0.06), (0.3, 0.27, 0.24), 22, 7, 0.5)
    brass, glass_m = paint("brass", (0.85, 0.62, 0.3), 0.25, 0, 1), glass()
    box((0, 0, 0.05), (w + 0.06, d + 0.06, 0.1), stone, 0.01, 1)
    gable_walls(w, d, h, ridge - 0.03, walls).location.z = 0.1
    box((0, 0, h + 0.1), (w + 0.05, d + 0.05, 0.05), white, 0.01, 1)                      # cornice
    box((0, 0, 0.74), (w + 0.03, d + 0.03, 0.035), white, 0.006, 1)                      # band between storeys
    roof(w, d, h + 0.12, ridge + 0.06, 0.07, 0.045, slate, slate)
    door(-0.22, -d / 2, 0.1, 0.24, 0.52, -1, red, white, brass, stone)
    window(0.22, -d / 2, 0.42, 0.24, 0.36, "front", white, glass_m, None, True, (1, 2))
    for x in (-0.22, 0.22):
        window(x, -d / 2, 1.06, 0.24, 0.38, "front", white, glass_m, None, True, (1, 2))
        window(x, d / 2, 1.06, 0.24, 0.38, "back", white, glass_m, None, True, (1, 2))
        window(x, d / 2, 0.42, 0.24, 0.36, "back", white, glass_m, None, True, (1, 2))
    for f, x in (("left", -w / 2), ("right", w / 2)):
        window(x, 0.0, 1.06, 0.22, 0.34, f, white, glass_m, None, True, (1, 1))
    chimney(-0.32, 0.2, 1.5, 2.12, 0.18, brick2, white)


def farmhouse():
    """Sage weatherboarded farmhouse, terracotta roof, porch canopy on posts, cream trim, stone chimney."""
    w, d, h, ridge = 1.5, 1.15, 0.86, 1.58
    walls = boards("boards_sage", (0.34, 0.46, 0.32))
    tiles, _ = courses("tiles2", (0.58, 0.2, 0.11), (0.48, 0.16, 0.09), (0.3, 0.1, 0.05), 22, 9, 0.9, 0.7)
    cream, navy = paint("cream", (0.88, 0.83, 0.7), 0.4), paint("navy", (0.1, 0.15, 0.3), 0.4, 0.4)
    stone, _ = courses("stone2", (0.55, 0.52, 0.47), (0.46, 0.44, 0.4), (0.33, 0.32, 0.3), 9, 4, 0.7, 0.9, 0.3)
    brass, glass_m = paint("brass", (0.85, 0.62, 0.3), 0.25, 0, 1), glass()
    wood = paint("wood", (0.36, 0.22, 0.12), 0.6)
    chim, _ = courses("chim", (0.5, 0.48, 0.44), (0.4, 0.39, 0.36), (0.22, 0.21, 0.2), 14, 6, 0.8, 0.9, 0.3)
    box((0, 0, 0.04), (w + 0.06, d + 0.06, 0.08), stone, 0.01, 1)
    gable_walls(w, d, h, ridge - 0.03, walls).location.z = 0.08
    roof(w, d, h + 0.08, ridge + 0.05, 0.1, 0.05, tiles, tiles)
    for x in (-w / 2 + 0.02, w / 2 - 0.02):                                                # corner boards
        for y in (-d / 2 + 0.02, d / 2 - 0.02):
            box((x, y, 0.08 + h / 2), (0.05, 0.05, h), cream, 0.004, 1)
    door(0.0, -d / 2, 0.08, 0.26, 0.5, -1, navy, cream, brass, stone)
    # Porch: a small tiled canopy on two posts.
    box((0.0, -d / 2 - 0.2, 0.68), (0.62, 0.42, 0.035), tiles, 0.006, 1, rot=(0.25, 0, 0))
    for x in (-0.27, 0.27):
        box((x, -d / 2 - 0.36, 0.38), (0.035, 0.035, 0.6), wood, 0.004, 1)
    for x in (-0.48, 0.48):
        window(x, -d / 2, 0.46, 0.28, 0.3, "front", cream, glass_m, navy)
        window(x, d / 2, 0.46, 0.28, 0.3, "back", cream, glass_m, navy)
    for f, x in (("left", -w / 2), ("right", w / 2)):
        window(x, 0.0, 1.06, 0.2, 0.22, f, cream, glass_m, None, True, (1, 0))
    chimney(-0.5, -0.12, 1.1, 1.82, 0.17, chim, stone)


HOUSES = {"house_cottage": cottage, "house_townhouse": townhouse, "house_farmhouse": farmhouse}


# ------------------------------------------------------------------ render
def setup_render():
    sc = bpy.context.scene
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
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 1024
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.9, 0.92, 0.95, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.42
    for kind, energy, d, col, size in (("SUN", 3.2, (-0.6, -1.0, 1.3), (1.0, 0.95, 0.88), 3.0), ("AREA", 120, (1.4, -0.8, 0.9), (0.9, 0.95, 1.0), 3.0)):
        L = bpy.data.lights.new(kind, kind)
        L.energy, L.color = energy, col
        if kind == "SUN":
            L.angle = math.radians(size)
        else:
            L.size = size
        o = bpy.data.objects.new(kind, L)
        bpy.context.collection.objects.link(o)
        dv = Vector(d).normalized()
        o.location = dv * 6
        o.rotation_euler = (-dv).to_track_quat("-Z", "Y").to_euler()


def frame_and_render(name):
    sc = bpy.context.scene
    cam = bpy.data.cameras.new("cam")
    cam.lens = 85
    co = bpy.data.objects.new("cam", cam)
    bpy.context.collection.objects.link(co)
    sc.camera = co
    objs = [o for o in sc.objects if o.type == "MESH"]
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre = (lo + hi) / 2
    view = Vector((0.75, -1.25, 0.72)).normalized()          # front-right, a little above: the door side shows
    radius = (hi - lo).length / 2
    dist = radius / math.tan(math.atan(18 / 85)) * 1.12
    co.location = centre + view * dist
    co.rotation_euler = (-view).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    for name, fn in HOUSES.items():
        reset()
        setup_render()
        fn()
        frame_and_render(name)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, name + ".blend"))
    print("DONE")
