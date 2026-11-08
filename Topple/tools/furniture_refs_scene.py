"""Blender: reference pictures of the living room's furniture for Tripo's image-to-3D (Free Build's room concept).
Modelled at the game's scale (a domino is 1 tall, about 5 cm), mid-century pieces in the room's palette, rendered as
clean 3/4 views on a transparent background.

    blender -b --factory-startup --python tools/furniture_refs_scene.py -- <out_dir> [samples]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import house_refs_scene as H  # noqa: E402  (materials, boxes, render setup)

args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
SAMPLES = int(args[1]) if len(args) > 1 else 160
H.SAMPLES = SAMPLES
os.makedirs(OUT, exist_ok=True)


def velvet(name, rgb):
    m, N, L, p = H.nodes_mat(name)
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = 0.85
    p.inputs["Sheen Weight"].default_value = 0.8
    p.inputs["Sheen Tint"].default_value = (*[min(1, c * 1.6) for c in rgb], 1)
    return m


def wood(name, rgb, rough=0.4):
    m, N, L, p = H.nodes_mat(name)
    tc = N.new("ShaderNodeTexCoord")
    wv = N.new("ShaderNodeTexWave"); wv.wave_type = "RINGS"; wv.inputs["Scale"].default_value = 3.0
    wv.inputs["Distortion"].default_value = 6.0; wv.inputs["Detail"].default_value = 3.0
    L.new(tc.outputs["Object"], wv.inputs["Vector"])
    mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs[6].default_value = (*[c * 0.7 for c in rgb], 1)
    mix.inputs[7].default_value = (*rgb, 1)
    L.new(wv.outputs["Fac"], mix.inputs[0])
    L.new(mix.outputs[2], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    p.inputs["Coat Weight"].default_value = 0.4
    return m


def rbox(c, size, mat, r=0.2, segs=4):
    return H.box(c, size, mat, r, segs)


def leg(x, y, z0, z1, r0, r1, mat, tilt=(0.0, 0.0)):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r0, depth=z1 - z0, vertices=20, location=(x, y, (z0 + z1) / 2))
    o = bpy.context.object
    o.rotation_euler = (tilt[1], tilt[0], 0)
    o.data.materials.append(mat)
    for f in o.data.polygons:
        f.use_smooth = True
    return o


def sofa():
    """A three-seat mid-century sofa: teal velvet, rounded arms, buttoned back cushions, mustard throw pillows,
    tapered walnut legs. 36 x 16 x 17 (about 1.8 m long)."""
    teal, mustard = velvet("teal", (0.025, 0.09, 0.09)), velvet("mustard", (0.5, 0.31, 0.06))
    walnut, brass = wood("walnut", (0.1, 0.045, 0.02)), H.paint("brass", (0.85, 0.62, 0.3), 0.25, 0, 1)
    W, D = 36.0, 16.0
    rbox((0, 0, 4.2), (W - 4, D - 1.5, 3.4), teal, 0.8)                      # base
    rbox((0, D / 2 - 1.6, 9.5), (W - 3, 3.2, 13.0), teal, 1.2)               # back frame
    for s in (-1, 1):
        rbox((s * (W / 2 - 1.8), 0, 7.0), (3.6, D, 9.0), teal, 1.4)          # arms
    cw = (W - 7.2) / 3
    for i in range(3):
        x = -W / 2 + 3.6 + cw * (i + 0.5)
        rbox((x, -1.2, 7.4), (cw - 0.2, D - 4.0, 3.2), teal, 1.2)            # seat cushions
        rbox((x, D / 2 - 4.2, 12.5), (cw - 0.4, 3.6, 8.5), teal, 1.6)        # back cushions
        for bz in (11.0, 14.0):
            H.sphere((x, D / 2 - 6.05, bz), 0.28, brass, 2)                   # buttons
    for s, ang in ((-1, 0.35), (1, -0.3)):
        p = rbox((s * 9.0, D / 2 - 6.6, 10.6), (6.0, 1.6, 6.0), mustard, 1.4)
        p.rotation_euler = (math.radians(-12), math.radians(ang * 30), 0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            leg(sx * (W / 2 - 2.2), sy * (D / 2 - 2.0), 0, 2.6, 0.55, 0.3, walnut, (sx * 0.12, sy * 0.12))


def armchair():
    """A lounge armchair: walnut frame with curved arms, cognac leather seat and back cushions."""
    walnut = wood("walnut", (0.11, 0.05, 0.022))
    leather, _ = H.nodes_mat("cognac")[0], None
    lm = bpy.data.materials["cognac"]
    p = lm.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (0.24, 0.08, 0.025, 1)
    p.inputs["Roughness"].default_value = 0.42
    p.inputs["Coat Weight"].default_value = 0.3
    W, D = 16.0, 16.0
    for s in (-1, 1):
        rbox((s * (W / 2 - 0.6), 0, 6.0), (1.2, D, 1.0), walnut, 0.4)         # arm rails
        for sy in (-1, 1):
            leg(s * (W / 2 - 0.6), sy * (D / 2 - 1.0), 0, 6.0, 0.55, 0.4, walnut, (s * 0.08, sy * 0.1))
    rbox((0, 0, 3.4), (W - 1.6, D - 2.0, 0.8), walnut, 0.3)                   # seat frame
    rbox((0, -0.6, 5.0), (W - 2.4, D - 3.0, 2.6), leather, 1.0)               # seat cushion
    back = rbox((0, D / 2 - 2.4, 11.0), (W - 2.6, 2.6, 11.0), leather, 1.2)   # back cushion, reclined
    back.rotation_euler = (math.radians(-14), 0, 0)
    bk = rbox((0, D / 2 - 1.2, 10.5), (W - 1.8, 0.8, 13.0), walnut, 0.3)
    bk.rotation_euler = (math.radians(-14), 0, 0)
    _ = leather


def coffee_table():
    """A walnut coffee table with rounded corners, tapered splayed legs and a lower shelf with two magazines."""
    walnut = wood("walnut", (0.13, 0.06, 0.025), 0.3)
    mag1, mag2 = H.paint("mag1", (0.8, 0.75, 0.62), 0.5), H.paint("mag2", (0.1, 0.16, 0.3), 0.5)
    W, D, Ht = 24.0, 12.0, 8.8
    rbox((0, 0, Ht - 0.4), (W, D, 0.8), walnut, 0.6)
    rbox((0, 0, Ht - 1.4), (W - 2.0, D - 2.0, 1.2), walnut, 0.2)
    rbox((0, 0, 2.6), (W - 3.0, D - 2.4, 0.5), walnut, 0.2)                   # lower shelf
    rbox((-4.0, 0.5, 3.0), (5.0, 7.0, 0.3), mag1, 0.05, 1)
    m = rbox((-3.4, 0.2, 3.35), (5.0, 7.0, 0.3), mag2, 0.05, 1); m.rotation_euler = (0, 0, 0.3)
    for sx in (-1, 1):
        for sy in (-1, 1):
            leg(sx * (W / 2 - 1.6), sy * (D / 2 - 1.4), 0, Ht - 1.6, 0.6, 0.35, walnut, (sx * 0.1, sy * 0.1))


def bookshelf():
    """A walnut bookcase filled with books in the room's colours, a vase and a small plant on top."""
    import random
    random.seed(4)
    walnut = wood("walnut", (0.12, 0.055, 0.025), 0.45)
    cols = [(0.42, 0.07, 0.05), (0.06, 0.1, 0.22), (0.66, 0.44, 0.1), (0.25, 0.36, 0.23), (0.26, 0.08, 0.15), (0.74, 0.68, 0.54)]
    mats = [H.paint("book%d" % i, c, 0.55) for i, c in enumerate(cols)]
    pages = H.paint("pages", (0.82, 0.77, 0.64), 0.8)
    vase, leaf = H.paint("vase", (0.85, 0.82, 0.74), 0.2, 0.3), H.paint("leaf", (0.12, 0.28, 0.1), 0.55)
    W, D, Ht = 24.0, 7.0, 40.0
    for s in (-1, 1):
        rbox((s * (W / 2 - 0.4), 0, Ht / 2), (0.8, D, Ht), walnut, 0.15, 2)
    rbox((0, 0, Ht - 0.4), (W, D, 0.8), walnut, 0.15, 2)
    rbox((0, 0, 0.8), (W, D, 1.6), walnut, 0.15, 2)
    rbox((0, D / 2 - 0.2, Ht / 2), (W, 0.4, Ht), walnut, 0.05, 1)
    levels = [1.6, 11.0, 20.6, 30.2]
    for lv in levels[1:]:
        rbox((0, 0, lv - 0.3), (W - 1.6, D - 0.6, 0.6), walnut, 0.08, 1)
    for i, lv in enumerate(levels):
        x = -W / 2 + 1.2
        while x < W / 2 - 2.0:
            w = random.uniform(0.8, 1.5); hgt = random.uniform(6.0, 8.6)
            if random.random() < 0.07:
                x += random.uniform(1.5, 3.0); continue
            mi = random.randrange(len(mats))
            rbox((x + w / 2, -0.2, lv + hgt / 2), (w, D - 1.4, hgt), mats[mi], 0.06, 1)
            rbox((x + w / 2, 0.15, lv + hgt / 2), (w - 0.2, D - 1.6, hgt - 0.3), pages, 0.02, 1)   # behind the spine
            x += w + 0.05
            if i == 2 and 2.0 < x < 3.4:
                x += 4.0       # a gap on one shelf, with a lying stack
                for k in range(3):
                    rbox((x - 2.2, -0.2, lv + 0.45 + k * 0.9), (3.6, D - 1.6, 0.85), mats[(k + 2) % 6], 0.05, 1)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=2.0, location=(-6.0, 0, Ht + 2.2))
    v = bpy.context.object; v.scale = (0.8, 0.8, 1.2); v.data.materials.append(vase)
    for f in v.data.polygons:
        f.use_smooth = True
    for k in range(6):
        a = k * 1.05
        H.sphere((5.0 + math.cos(a) * 1.2, math.sin(a) * 1.2, Ht + 2.6 + (k % 2) * 0.8), 1.2, leaf, 2)
    rbox((5.0, 0, Ht + 1.0), (3.0, 3.0, 2.0), H.paint("pot2", (0.55, 0.24, 0.13), 0.7), 0.4)


def plant():
    """A fiddle-leaf fig in a terracotta pot: a woody stem, broad wavy leaves spiralling up."""
    pot, soil = H.paint("terracotta", (0.55, 0.24, 0.13), 0.75), H.paint("soil", (0.06, 0.04, 0.03), 1.0)
    stem_m, leaf_m = wood("stem", (0.16, 0.1, 0.05), 0.7), H.paint("figleaf", (0.05, 0.16, 0.04), 0.4)
    bpy.ops.mesh.primitive_cone_add(radius1=2.6, radius2=3.4, depth=6.0, vertices=48, location=(0, 0, 3.0))
    p = bpy.context.object; p.data.materials.append(pot)
    for f in p.data.polygons:
        f.use_smooth = True
    H.box((0, 0, 6.0), (6.2, 6.2, 0.4), pot, 0.15, 2).scale = (1, 1, 1)
    bpy.ops.mesh.primitive_cylinder_add(radius=3.1, depth=0.2, location=(0, 0, 5.8))
    bpy.context.object.data.materials.append(soil)
    H.cyl((0, 0, 13.0), 0.45, 14.0, stem_m, 12)
    for k in range(13):
        a = k * 2.4
        z = 9.0 + k * 1.25
        L = 7.4 - 0.18 * k
        bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
        lf = bpy.context.object
        me = lf.data
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.subdivide(number_cuts=6)
        bpy.ops.object.mode_set(mode="OBJECT")
        for v in me.vertices:
            u, w = v.co.x + 0.5, v.co.y          # u along the leaf 0..1, w across -0.5..0.5
            width = math.sin(math.pi * min(1.0, u * 1.05)) ** 0.7 * 0.75
            v.co.x = u * L
            v.co.y = w * width * L * 0.9
            v.co.z = -0.25 * (u * L) ** 2 / L + 0.35 * math.cos(w * 9.0) * width
        lf.location = (math.cos(a) * 0.3, math.sin(a) * 0.3, z)
        lf.rotation_euler = (0, math.radians(-25 + k * 1.5), a)
        mod = lf.modifiers.new("solid", "SOLIDIFY"); mod.thickness = 0.06
        lf.data.materials.append(leaf_m)
        for f in me.polygons:
            f.use_smooth = True


PIECES = {"furn_sofa": sofa, "furn_armchair": armchair, "furn_coffeetable": coffee_table, "furn_bookshelf": bookshelf, "furn_plant": plant}

only = args[2].split(",") if len(args) > 2 else None
for name, fn in PIECES.items():
    if only and name not in only:
        continue
    H.reset()
    H.setup_render()
    for o in bpy.context.scene.objects:          # furniture is ~20x a house: move the fill light out to match
        if o.type == "LIGHT" and o.data.type == "AREA":
            o.location = o.location * 9.0
            o.data.energy *= 81.0
            o.data.size *= 9.0
    fn()
    H.frame_and_render(name)
print("DONE")
