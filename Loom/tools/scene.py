"""Loom look target, built from the cell pieces the game will draw (Blender 5.1, Cycles).

    blender -b --factory-startup --python Loom/tools/scene.py -- MODE OUT.png [SAMPLES] [W H]
MODE: target | target_b | backdrop | side | frame (projection report only, no render) |
      export (OUT = a folder: every cooked game piece as OBJ, for tools/gen_assets.py)
side: OUT is the side-by-side; reads .concepts/next/loom.png and the target path from env LOOM_TARGET.

Every cloth cell is a cached variant keyed by (kind, neighbourhood mask), instanced on the grid the way
the engine will show one cooked mesh per cell node. Props that the game moves are separate objects.
"""
import math
import os
import random
import zlib
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import loom_grid as G  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
MODE, OUT = argv[0], os.path.abspath(argv[1])
SAMPLES = int(argv[2]) if len(argv) > 2 else 64
RES = (int(argv[3]), int(argv[4])) if len(argv) > 4 else (1280, 720)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
COL = sc.collection
R = math.radians
V = Vector
C = G.CELL


def srgb(r, g, b):
    f = lambda c: (c / 255) / 12.92 if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b))


# muted natural dyes (linear)
SAGE = srgb(84, 122, 54)           # round 3: measured against loom.png's meadow (116, 134, 80 rendered)
SAGE_HI = srgb(118, 152, 66)
OLIVE = srgb(84, 88, 50)
INDIGO = srgb(46, 88, 164)         # revision 2: the concept's clear blue river
INDIGO_HI = srgb(88, 132, 200)
CREAM = srgb(226, 214, 188)
TAN = srgb(184, 146, 100)
OCHRE = srgb(204, 146, 44)
STRAW = srgb(218, 184, 106)
MADDER = srgb(160, 66, 50)
GREY = srgb(136, 132, 122)
BROWN = srgb(110, 70, 42)
WOOL = {"sage": SAGE, "indigo": INDIGO, "tan": TAN, "brown": BROWN, "ochre": OCHRE, "grey": GREY, "cream": CREAM}
KIND_WOOL = {".": "sage", "h": "sage", "w": "brown", "~": "indigo", "p": "tan", "f": "ochre", "r": "grey", "H": "cream",
             "b": "brown", "B": "brown"}


# ------------------------------------------------------------------ materials


def mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    return m, m.node_tree.nodes, m.node_tree.links, m.node_tree.nodes["Principled BSDF"]


def math_node(N, L, op, a, b=None, val=None):
    n = N.new("ShaderNodeMath")
    n.operation = op
    L.new(a, n.inputs[0]) if not isinstance(a, (int, float)) else n.inputs.__getitem__(0).__setattr__("default_value", a)
    if b is not None:
        if isinstance(b, (int, float)):
            n.inputs[1].default_value = b
        else:
            L.new(b, n.inputs[1])
    return n.outputs[0]


def felt(name, color, rough=0.95, sheen=0.7, bump=0.25, scale=1400.0):
    m, N, L, p = mat(name)
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Sheen Weight"].default_value = sheen
    p.inputs["Sheen Roughness"].default_value = 0.5
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = 6
    tc = N.new("ShaderNodeTexCoord")
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    bp = N.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = bump
    bp.inputs["Distance"].default_value = 0.0004
    L.new(nz.outputs["Fac"], bp.inputs["Height"])
    L.new(bp.outputs["Normal"], p.inputs["Normal"])
    m["lc"] = list(color)      # flat colour for the cooked game mesh (vertex colour)
    return m


def wood(name, c1, c2, rough=0.42, coat=0.15, scale=6.0, axis="X", stretch=8.0):
    """Grain along `axis`: bands of wave texture on a stretched coordinate, mixed between two tones."""
    m, N, L, p = mat(name)
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    s = [stretch, stretch, stretch]
    s["XYZ".index(axis)] = 1.0
    mp.inputs["Scale"].default_value = s
    L.new(tc.outputs["Object"], mp.inputs["Vector"])
    wv = N.new("ShaderNodeTexWave")
    wv.wave_type = "RINGS"
    wv.inputs["Scale"].default_value = scale
    wv.inputs["Distortion"].default_value = 6.0
    wv.inputs["Detail"].default_value = 4.0
    wv.inputs["Detail Roughness"].default_value = 0.6
    L.new(mp.outputs["Vector"], wv.inputs["Vector"])
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale * 30
    L.new(mp.outputs["Vector"], nz.inputs["Vector"])
    mx = N.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.inputs[6].default_value = (*c1, 1)
    mx.inputs[7].default_value = (*c2, 1)
    f = math_node(N, L, "MULTIPLY", wv.outputs["Fac"], nz.outputs["Fac"])
    f = math_node(N, L, "POWER", f, 0.7)
    L.new(f, mx.inputs[0])
    L.new(mx.outputs[2], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    p.inputs["Coat Weight"].default_value = coat
    bp = N.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.15
    bp.inputs["Distance"].default_value = 0.0003
    L.new(f, bp.inputs["Height"])
    L.new(bp.outputs["Normal"], p.inputs["Normal"])
    m["lc"] = [(a + b) / 2 for a, b in zip(c1, c2)]      # flat colour for the cooked game mesh (vertex colour)
    return m


def yarn(name, color, twist=0.0028, plies=3, sheen=0.75, fuzz=0.35):
    """For tubes with UV (u = metres along the thread / twist, v = around): ply twist + fuzz."""
    m, N, L, p = mat(name)
    p.inputs["Roughness"].default_value = 0.9
    p.inputs["Sheen Weight"].default_value = sheen
    p.inputs["Sheen Roughness"].default_value = 0.45
    uv = N.new("ShaderNodeUVMap")
    sp = N.new("ShaderNodeSeparateXYZ")
    L.new(uv.outputs["UV"], sp.inputs["Vector"])
    a = math_node(N, L, "MULTIPLY", sp.outputs["X"], 2 * math.pi / twist)
    b = math_node(N, L, "MULTIPLY", sp.outputs["Y"], 2 * math.pi * plies)
    s = math_node(N, L, "SINE", math_node(N, L, "ADD", a, b))
    s = math_node(N, L, "ABSOLUTE", s)
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 2500
    nz.inputs["Detail"].default_value = 8
    h = math_node(N, L, "ADD", s, math_node(N, L, "MULTIPLY", nz.outputs["Fac"], fuzz))
    bp = N.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.6
    bp.inputs["Distance"].default_value = 0.0005
    L.new(h, bp.inputs["Height"])
    L.new(bp.outputs["Normal"], p.inputs["Normal"])
    sh = N.new("ShaderNodeMapRange")
    sh.inputs["To Min"].default_value = 0.72
    sh.inputs["To Max"].default_value = 1.05
    L.new(s, sh.inputs["Value"])
    mx = N.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "MULTIPLY"
    mx.inputs[0].default_value = 1.0
    mx.inputs[6].default_value = (*color, 1)
    L.new(sh.outputs["Result"], mx.inputs[7])
    L.new(mx.outputs[2], p.inputs["Base Color"])
    m["lc"] = list(color)      # flat colour for the cooked game mesh (vertex colour)
    return m


def wound(name, color):
    """Wool wound on a bobbin: turns of plied yarn (2.4 mm) round the spool, slightly helical, with fuzz."""
    m, N, L, p = mat(name)
    p.inputs["Roughness"].default_value = 0.92
    p.inputs["Sheen Weight"].default_value = 0.45
    p.inputs["Sheen Roughness"].default_value = 0.5
    tc = N.new("ShaderNodeTexCoord")
    sp = N.new("ShaderNodeSeparateXYZ")
    L.new(tc.outputs["Object"], sp.inputs["Vector"])
    gx = N.new("ShaderNodeNewGeometry")
    az = N.new("ShaderNodeSeparateXYZ")
    L.new(gx.outputs["Position"], az.inputs["Vector"])
    turns = math_node(N, L, "MULTIPLY", sp.outputs["Z"], 2 * math.pi / 0.0036)
    tilt = math_node(N, L, "MULTIPLY", math_node(N, L, "ARCTAN2", az.outputs["Y"], az.outputs["X"]), 1.0)
    s = math_node(N, L, "ABSOLUTE", math_node(N, L, "SINE", math_node(N, L, "ADD", turns, tilt)))
    s = math_node(N, L, "POWER", s, 0.5)
    ply = math_node(N, L, "ABSOLUTE", math_node(N, L, "SINE", math_node(N, L, "ADD", math_node(N, L, "MULTIPLY", sp.outputs["Z"], 2 * math.pi / 0.0011),
                                                                                      math_node(N, L, "MULTIPLY", tilt, 40.0))))
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 1800
    nz.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    h = math_node(N, L, "ADD", math_node(N, L, "ADD", s, math_node(N, L, "MULTIPLY", ply, 0.25)), math_node(N, L, "MULTIPLY", nz.outputs["Fac"], 0.35))
    bp = N.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.8
    bp.inputs["Distance"].default_value = 0.0008
    L.new(h, bp.inputs["Height"])
    L.new(bp.outputs["Normal"], p.inputs["Normal"])
    sh = N.new("ShaderNodeMapRange")
    sh.inputs["To Min"].default_value = 0.55
    sh.inputs["To Max"].default_value = 1.05
    L.new(s, sh.inputs["Value"])
    mx = N.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "MULTIPLY"
    mx.inputs[0].default_value = 1.0
    mx.inputs[6].default_value = (*color, 1)
    L.new(sh.outputs["Result"], mx.inputs[7])
    L.new(mx.outputs[2], p.inputs["Base Color"])
    m["lc"] = list(color)      # flat colour for the cooked game mesh (vertex colour)
    return m


def cloth_material():
    """Cloth: vertex colour (land, woven shading, pick tones; cooked per variant) x ONE tiling texture.
    The texture coordinates are the cooked UVs, UV = cell-local (u + 0.5, v + 0.5): every cell covers the
    tile exactly once and the cell origins sit on the thread grid, so cell UV == world thread phase mod 1 and
    the pattern runs on across every border. All frequencies below are whole numbers per cell and the fuzz
    noise is sampled on a torus, so the tile is seamless. In the engine this node tree is baked once into a
    1024x1024 albedo tint + normal map pair over UV [0, 1] (repeat sampler)."""
    m, N, L, p = mat("cloth")
    p.inputs["Roughness"].default_value = 0.92
    p.inputs["Sheen Weight"].default_value = 0.6
    p.inputs["Sheen Roughness"].default_value = 0.45
    at = N.new("ShaderNodeAttribute")
    at.attribute_name = "col"
    uv = N.new("ShaderNodeUVMap")
    sp = N.new("ShaderNodeSeparateXYZ")
    L.new(uv.outputs["UV"], sp.inputs["Vector"])
    U, Vv = sp.outputs["X"], sp.outputs["Y"]
    tau = 2 * math.pi
    # torus-sampled fibre noise: periodic in U and V with period 1
    a = 6.0
    cu = math_node(N, L, "MULTIPLY", math_node(N, L, "COSINE", math_node(N, L, "MULTIPLY", U, tau)), a)
    su = math_node(N, L, "MULTIPLY", math_node(N, L, "SINE", math_node(N, L, "MULTIPLY", U, tau)), a)
    cv = math_node(N, L, "MULTIPLY", math_node(N, L, "COSINE", math_node(N, L, "MULTIPLY", Vv, tau)), a)
    sv = math_node(N, L, "MULTIPLY", math_node(N, L, "SINE", math_node(N, L, "MULTIPLY", Vv, tau)), a)
    cx = N.new("ShaderNodeCombineXYZ")
    L.new(cu, cx.inputs[0])
    L.new(su, cx.inputs[1])
    L.new(cv, cx.inputs[2])
    nz = N.new("ShaderNodeTexNoise")
    nz.noise_dimensions = "4D"
    nz.inputs["Scale"].default_value = 5.0
    nz.inputs["Detail"].default_value = 8
    L.new(cx.outputs[0], nz.inputs["Vector"])
    L.new(sv, nz.inputs["W"])
    # ply twist on the weft: 13 twists across a cell, 21 up it (both whole numbers: seamless)
    ph = math_node(N, L, "ADD", math_node(N, L, "MULTIPLY", U, 13.0), math_node(N, L, "MULTIPLY", Vv, 21.0))
    s_ = math_node(N, L, "ABSOLUTE", math_node(N, L, "SINE", math_node(N, L, "MULTIPLY", ph, tau)))
    h = math_node(N, L, "ADD", s_, math_node(N, L, "MULTIPLY", nz.outputs["Fac"], 0.6))
    bp = N.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.55
    bp.inputs["Distance"].default_value = 0.0004
    L.new(h, bp.inputs["Height"])
    L.new(bp.outputs["Normal"], p.inputs["Normal"])
    sh = N.new("ShaderNodeMapRange")
    sh.inputs["To Min"].default_value = 0.82
    sh.inputs["To Max"].default_value = 1.04
    L.new(s_, sh.inputs["Value"])
    # heather: each ply takes one of three yarn tones (chosen along the twist, jittered by the fibre noise)
    sel = math_node(N, L, "FRACT", math_node(N, L, "ADD", math_node(N, L, "MULTIPLY", ph, 0.5),
                                             math_node(N, L, "MULTIPLY", nz.outputs["Fac"], 0.9)))
    ramp = N.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, (1.0, 1.0, 1.0, 1)
    els[1].position, els[1].color = 0.34, (1.12, 1.05, 0.8, 1)
    e3 = els.new(0.67)
    e3.color = (0.84, 0.95, 1.1, 1)
    L.new(sel, ramp.inputs["Fac"])
    tint = N.new("ShaderNodeMix")
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs[0].default_value = 1.0
    L.new(ramp.outputs["Color"], tint.inputs[6])
    L.new(sh.outputs["Result"], tint.inputs[7])
    mx = N.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "MULTIPLY"
    mx.inputs[0].default_value = 1.0
    L.new(at.outputs["Color"], mx.inputs[6])
    L.new(tint.outputs[2], mx.inputs[7])
    L.new(mx.outputs[2], p.inputs["Base Color"])
    return m


M = {}


def build_materials():
    M["cloth"] = cloth_material()
    M["table"] = wood("walnut", srgb(74, 50, 34), srgb(46, 30, 20), rough=0.38, coat=0.25, scale=3.0, axis="X", stretch=10)
    M["oak"] = wood("oak", srgb(150, 116, 76), srgb(112, 82, 50), rough=0.45, coat=0.1, scale=9.0, axis="Y", stretch=12)
    M["oakx"] = wood("oakx", srgb(150, 116, 76), srgb(112, 82, 50), rough=0.45, coat=0.1, scale=9.0, axis="X", stretch=12)
    M["bridge"] = wood("bridgewood", srgb(176, 120, 72), srgb(140, 92, 56), rough=0.5, coat=0.05, scale=40, axis="Y", stretch=6)
    M["bridge_dark"] = wood("bridgewood_dark", srgb(128, 84, 50), srgb(100, 64, 38), rough=0.55, coat=0.0, scale=40, axis="Y", stretch=6)
    M["peg"] = wood("boxwood", srgb(208, 170, 120), srgb(176, 136, 90), rough=0.35, coat=0.3, scale=60, axis="Z", stretch=4)
    M["cloak"] = felt("cloak_paint", MADDER, rough=0.4, sheen=0.0, bump=0.05)
    M["cloak"].node_tree.nodes["Principled BSDF"].inputs["Coat Weight"].default_value = 0.35
    M["hat"] = felt("hat", srgb(70, 62, 56))
    M["pack"] = felt("pack", OCHRE)
    M["warp"] = yarn("warp", srgb(222, 210, 184), twist=0.0016, plies=2, sheen=0.5, fuzz=0.25)
    M["reed"] = felt("reed_metal", srgb(150, 130, 105), rough=0.4, sheen=0.0, bump=0.0)
    M["reed"].node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.6
    M["walls"] = felt("walls", srgb(222, 208, 180), bump=0.6, scale=900, sheen=0.9)
    M["window"] = felt("window", srgb(214, 170, 84), bump=0.5, scale=900)
    # round 3: the concept's red and yellow roofs
    M["roofs"] = [felt("roof_red", srgb(196, 84, 58), bump=0.6, scale=900, sheen=0.9), felt("roof_yellow", srgb(222, 172, 84), bump=0.6, scale=900, sheen=0.9),
                  felt("roof_terracotta", srgb(186, 108, 66), bump=0.6, scale=900, sheen=0.9)]
    M["door"] = felt("door", srgb(76, 52, 38), bump=0.5, scale=900)
    M["stitch"] = yarn("stitch", srgb(236, 226, 204), twist=0.0012, sheen=0.4, fuzz=0.2)
    M["stitch_dark"] = yarn("stitch_dark", srgb(70, 46, 32), twist=0.0012, sheen=0.4, fuzz=0.2)
    M["yard"] = felt("yard", TAN)
    # round 3: rounder, greener wool pompoms like the concept's round trees
    M["tree"] = [felt("tree_a", srgb(74, 118, 46), bump=0.45, scale=1500), felt("tree_b", srgb(92, 132, 52), bump=0.45, scale=1500),
                 felt("tree_c", srgb(66, 106, 44), bump=0.45, scale=1500)]
    M["treecore"] = felt("treecore", srgb(72, 108, 46))
    M["knot"] = [felt("knot_cream", CREAM, bump=0.4), felt("knot_ochre", STRAW, bump=0.4), felt("knot_madder", MADDER, bump=0.4)]
    M["rock"] = felt("rock", GREY, bump=0.6, scale=600)
    M["rock2"] = felt("rock2", srgb(116, 112, 104), bump=0.6, scale=600)
    M["wool"] = {k: yarn("wool_" + k, c, sheen=0.35) for k, c in WOOL.items()}
    M["wound"] = {k: wound("wound_" + k, c) for k, c in WOOL.items()}
    M["wool"] = {k: yarn("wool_" + k, c, twist=0.006, plies=3, sheen=0.55, fuzz=0.5) for k, c in WOOL.items()}
    M["wool_core"] = {k: felt("woolcore_" + k, tuple(x * 0.85 for x in c), bump=0.5, scale=700) for k, c in WOOL.items()}
    M["shuttle"] = wood("shuttlewood", srgb(140, 96, 60), srgb(100, 64, 38), rough=0.3, coat=0.4, scale=14, axis="X", stretch=5)


# ------------------------------------------------------------------ mesh helpers


def obj_from(verts, faces, name, material, uvs=None, colors=None, smooth=True, coll=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    if isinstance(material, list):
        for m_ in material:
            me.materials.append(m_)
    else:
        me.materials.append(material)
    if uvs is not None:
        uvl = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            for li in poly.loop_indices:
                uvl.data[li].uv = uvs[me.loops[li].vertex_index]
    if colors is not None:
        ca = me.color_attributes.new("col", "FLOAT_COLOR", "POINT")
        for i, c in enumerate(colors):
            ca.data[i].color = (*c, 1)
    me.polygons.foreach_set("use_smooth", [smooth] * len(me.polygons))
    me.update()
    o = bpy.data.objects.new(name, me)
    (coll or COL).objects.link(o)
    return o


def tube(pts, r, material, name="tube", ring=8, coll=None, taper=None, closed=False):
    """Swept circle along a polyline, UV u = metres along it, v = around."""
    pts = [V(p) for p in pts]
    n = len(pts)
    verts, faces, uvs = [], [], []
    acc = 0.0
    prev_side = None
    for i, p in enumerate(pts):
        if closed:
            t = (pts[(i + 1) % n] - pts[i - 1])
        else:
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])
        t.normalize()
        ref = prev_side if prev_side is not None else (V((0, 0, 1)) if abs(t.z) < 0.9 else V((1, 0, 0)))
        side = t.cross(ref).normalized() if prev_side is None else (ref - t * ref.dot(t)).normalized()
        if prev_side is None:
            side = t.cross(ref).normalized()
        up = side.cross(t).normalized()
        prev_side = side
        if i:
            acc += (p - pts[i - 1]).length
        rr = r * (taper(i / max(n - 1, 1)) if taper else 1.0)
        for k in range(ring):
            a = 2 * math.pi * k / ring
            verts.append(p + (side * math.cos(a) + up * math.sin(a)) * rr)
            uvs.append((acc, k / ring))
    segs = n if closed else n - 1
    for i in range(segs):
        j = (i + 1) % n
        for k in range(ring):
            k2 = (k + 1) % ring
            faces.append((i * ring + k, i * ring + k2, j * ring + k2, j * ring + k))
    if not closed:
        verts.append(pts[0])
        uvs.append((0, 0))
        verts.append(pts[-1])
        uvs.append((acc, 0))
        a0, a1 = len(verts) - 2, len(verts) - 1
        for k in range(ring):
            k2 = (k + 1) % ring
            faces.append((a0, k2, k))
            faces.append((a1, (n - 1) * ring + k, (n - 1) * ring + k2))
    return obj_from([tuple(v) for v in verts], faces, name, material, uvs=uvs, coll=coll)


def box(center, size, material, name="box", rot=(0, 0, 0), bevel=0.0, coll=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=[R(a) for a in rot])
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        md = o.modifiers.new("b", "BEVEL")
        md.width = bevel
        md.segments = 3
        md.limit_method = "NONE"
    o.data.materials.append(material)
    if coll:
        for c in o.users_collection:
            c.objects.unlink(o)
        coll.objects.link(o)
    return o


def lathe(profile, loc, material, name="lathe", steps=40, coll=None):
    verts, faces = [], []
    n = len(profile)
    for s in range(steps):
        a = 2 * math.pi * s / steps
        for r_, z in profile:
            verts.append((loc[0] + r_ * math.cos(a), loc[1] + r_ * math.sin(a), loc[2] + z))
    for s in range(steps):
        s2 = (s + 1) % steps
        for i in range(n - 1):
            faces.append((s * n + i, s2 * n + i, s2 * n + i + 1, s * n + i + 1))
    uvs = [(profile[i][1] * 3, s / steps) for s in range(steps) for i in range(n)]
    return obj_from(verts, faces, name, material, uvs=uvs, coll=coll)


def ico(loc, r, material, name="ico", scale=(1, 1, 1), sub=3, coll=None, jitter=0.0, seed=0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    if jitter:
        rnd = random.Random(seed)
        for v in o.data.vertices:
            v.co *= 1 + rnd.uniform(-jitter, jitter)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    o.data.materials.append(material)
    if coll:
        for c in o.users_collection:
            c.objects.unlink(o)
        coll.objects.link(o)
    return o


# ------------------------------------------------------------------ the cloth cell pieces
WATER_SET = {"~"}
RES_CELL = 48           # quads per cell side (4 per thread at 12 ends)


nb_of, SIDES, OPP, connects, arms_of, variant_key = G.nb_of, G.SIDES, G.OPP, G.connects, G.arms_of, G.variant_key


PICK_TONE = [(1.0, 1.0, 1.0), (1.05, 1.02, 0.9), (0.94, 0.98, 1.05), (1.02, 1.0, 0.95), (0.96, 1.0, 1.03),
             (1.04, 1.01, 0.92)]


def weave(u, v):
    """Woven height (m) and RGB shade at cell-local (u, v) in [-0.5, 0.5]. Period one cell in both directions
    and identical in every variant, with nothing special at a cell border, so the weave never breaks.
    Revision 2: a plain weave of 12 x 12 threads per cell. At each crossing either the weft pick or the warp end lies
    on top (alternating like a chequer), so the cloth reads as an even fine basket texture, not as stripes or diamonds."""
    t = (u + 0.5) * G.ENDS
    q = (v + 0.5) * G.PICKS
    i = min(int(t), G.ENDS - 1)
    j = min(int(q), G.PICKS - 1)
    fu, fv = t - i, q - j
    rw = math.sin(math.pi * min(max(fv, 0.0), 1.0)) ** 0.6        # the weft pick's round profile (runs along x)
    re = math.sin(math.pi * min(max(fu, 0.0), 1.0)) ** 0.6        # the warp end's (runs along y)
    w = 0.5 + 0.5 * math.cos(math.pi * (t - 0.5 - j))             # 1 where the weft passes over
    wv = 0.5 - 0.5 * math.cos(math.pi * (q - 0.5 - i))            # 1 where the warp passes over (the other crossings)
    h = max(rw * (0.45 + 0.55 * w), re * (0.45 + 0.55 * wv))
    lift = 0.975 + 0.05 * j / (G.PICKS - 1)                    # 5% step at each row boundary, nothing else
    k = (0.74 + 0.26 * h) * lift
    tone = PICK_TONE[j % len(PICK_TONE)]
    return G.WEAVE_A * h, (k * tone[0], k * tone[1], k * tone[2])


def mixc(a, b, t):
    t = min(max(t, 0.0), 1.0)
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def land(kind, key, nb, u, v, pieces_w, pieces_p):
    """Height offset (m, without weave) and base colour of the land at (u, v). Woods and rock floors are
    meadow (the trees and stones mark them); fields fade into meadow at their edge (47-blob of the field)."""
    hh = G.hill_height(u, v, {d: nb[d] == "h" for d in nb}) if kind == "h" else 0.0
    z = hh * G.HILL_H
    if kind in (".", "w", "r"):
        z += G.meadow_relief(kind, key[1], u, v)          # round 4: the meadow rolls gently (0 at every border)
    col = mixc(SAGE, SAGE_HI, hh ** 1.5) if kind == "h" else SAGE
    if kind == "f":
        q = int((v + 0.5) * G.PICKS)
        stripe = OCHRE if (q // 2) % 2 == 0 else STRAW
        d = G.blob_dist(u, v, {dd: nb[dd] == "f" for dd in nb}, G.FIELD_FADE)
        col = mixc(SAGE, stripe, G.smooth(d / G.FIELD_FADE))
    if pieces_p is not None:
        dp = G.band_dist(u, v, pieces_p)
        if kind in ("p", "H", "b", "B"):
            e = (dp - G.PATH_W) / 0.012
            col = mixc(TAN, col, e + 0.5)
            z -= G.PATH_D * (1 - G.smooth(min(max(e + 0.5, 0), 1)))
    if pieces_w is not None:
        dw = G.band_dist(u, v, pieces_w)
        ew = (dw - G.WATER_W) / 0.012
        eb = (dw - G.WATER_W - G.BANK_W) / 0.012
        col = mixc(CREAM, col, eb + 0.5)
        q = int((v + 0.5) * G.PICKS)
        wc = INDIGO if (q // 2) % 2 == 0 else mixc(INDIGO, INDIGO_HI, 0.55)   # hatched water, as tapestry does it
        col = mixc(wc, col, ew + 0.5)
        d = max(0.0, 1 - (dw / (G.WATER_W + 0.5 * G.BANK_W)) ** 2)
        z -= G.WATER_D * d
    return z, col


VARIANTS = {}
CELL_COLL = bpy.data.collections.new("cell_variants")


def cell_variant(key, nb):
    if key in VARIANTS:
        return VARIANTS[key]
    kind, mask = key
    coll = bpy.data.collections.new("V_%s_%s" % ("dot" if kind == "." else kind, mask))
    CELL_COLL.children.link(coll)
    rnd = random.Random(zlib.crc32(repr(key).encode()))
    pw = pp = None
    if kind == "~":
        pw = G.water_skeleton(mask)
    elif kind in ("p", "H"):
        pp = G.skeleton(mask, G.MEANDER_PATH)
    elif kind == "b":
        pw, pp = G.skeleton("ew", 0.0), G.skeleton("ns", 0.0)
    elif kind == "B":
        pw, pp = G.skeleton("ns", 0.0), G.skeleton("ew", 0.0)
    n = RES_CELL
    verts, cols, faces, uvs = [], [], [], []
    e = 0.5 / n
    for j in range(n + 1):
        for i in range(n + 1):
            u, v = -0.5 + i / n, -0.5 + j / n
            z, col = land(kind, key, nb, u, v, pw, pp)
            wz, sh = weave(u, v)
            # weave offset along the land normal so slopes keep round picks instead of steps; the normal
            # is blended to vertical over the outer 12% of the cell, where neighbours must match exactly
            gx = (land(kind, key, nb, min(u + e, 0.5), v, pw, pp)[0] - land(kind, key, nb, max(u - e, -0.5), v, pw, pp)[0]) / (
                (min(u + e, 0.5) - max(u - e, -0.5)) * C)
            gy = (land(kind, key, nb, u, min(v + e, 0.5), pw, pp)[0] - land(kind, key, nb, u, max(v - e, -0.5), pw, pp)[0]) / (
                (min(v + e, 0.5) - max(v - e, -0.5)) * C)
            tpr = G.smooth((0.5 - max(abs(u), abs(v))) / 0.12)
            nx_, ny_, nz_ = -gx * tpr, -gy * tpr, 1.0
            ln = math.sqrt(nx_ * nx_ + ny_ * ny_ + 1.0)
            verts.append((u * C + wz * nx_ / ln, v * C + wz * ny_ / ln, z + wz * nz_ / ln))
            cols.append((col[0] * sh[0], col[1] * sh[1], col[2] * sh[2]))
            uvs.append((u + 0.5, v + 0.5))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            faces.append((a, a + 1, a + n + 2, a + n + 1))
    # skirts on all four sides so a cut edge never shows a gap
    def skirt(idx_list):
        # skirt has its OWN copies of the border vertices: sharing them would bend the top surface's smooth
        # normals at every cell edge and draw a line round each cell
        top = len(verts)
        for idx in idx_list:
            verts.append(verts[idx])
            cols.append(tuple(c_ * 0.5 for c_ in cols[idx]))
            uvs.append(uvs[idx])
        base = len(verts)
        for idx in idx_list:
            x, y, _ = verts[idx]
            verts.append((x, y, -0.004))
            cols.append(tuple(c_ * 0.5 for c_ in cols[idx]))
            uvs.append(uvs[idx])
        for k in range(len(idx_list) - 1):
            faces.append((top + k + 1, top + k, base + k, base + k + 1))
    skirt([i for i in range(n + 1)])                                  # south edge (v = -0.5)
    skirt([n * (n + 1) + i for i in range(n, -1, -1)])                # north
    skirt([j * (n + 1) + n for j in range(n + 1)][::-1][::-1])       # east
    skirt([j * (n + 1) for j in range(n, -1, -1)])                    # west
    o = obj_from(verts, faces, "cell_%s_%s" % (kind, mask), M["cloth"], colors=cols, uvs=uvs, coll=coll)

    def ground(u, v):
        z, _ = land(kind, key, nb, u, v, pw, pp)
        return z + weave(u, v)[0]

    # baked cell decorations (part of the cooked variant)
    if kind == "w":
        # round 4: small round single trees scattered like the concept's: 2-3 per cell (one look has 1 big one),
        # varied size, kept apart and inside the cell
        n = (2, 3, 1)[int(mask) % 3]
        placed = []
        tries = 0
        while len(placed) < n and tries < 200:
            tries += 1
            r_ = rnd.uniform(0.0055, 0.0085) if n > 1 else 0.0095
            u, v = rnd.uniform(-0.34, 0.34), rnd.uniform(-0.34, 0.34)
            if all(math.hypot((u - a) * C, (v - b) * C) > r_ + rr + 0.004 for a, b, rr in placed):
                placed.append((u, v, r_))
        for u, v, r_ in placed:
            yarn_tree((u * C, v * C, ground(u, v)), r_, rnd, coll)
    elif kind == "r":
        for k in range(2 + int(mask)):
            u, v = rnd.uniform(-0.25, 0.25), rnd.uniform(-0.25, 0.25)
            r_ = rnd.uniform(0.006, 0.0105)
            ico((u * C, v * C, ground(u, v) + r_ * 0.3), r_, M["rock"] if k % 2 else M["rock2"], "rock",
                scale=(1.0, 0.8, 0.62), sub=3, coll=coll, jitter=0.12, seed=rnd.randint(0, 999))
    if kind in (".", "h"):
        for k in range(1 if rnd.random() < 0.3 else 0):        # round 3: a few French knots, not a speckle
            u, v = rnd.uniform(-0.38, 0.38), rnd.uniform(-0.38, 0.38)
            if pw or pp:
                continue
            ico((u * C, v * C, ground(u, v) + 0.0006), 0.0017, M["knot"][rnd.randint(0, 2)], "knot", sub=2, coll=coll,
                jitter=0.15, seed=k)
    VARIANTS[key] = (coll, ground, None)
    return VARIANTS[key]


def rolled_variant(key, nb):
    """The bent copy of a variant: every vertex of the cell and its baked decorations mapped onto the roll
    by G.bend (origin = beam axis). One extra cooked mesh per variant that reaches the beam."""
    coll, ground, bent = cell_variant(key, nb)
    if bent is not None:
        return bent
    bc = bpy.data.collections.new(coll.name + "_rolled")
    CELL_COLL.children.link(bc)
    for o in coll.objects:
        if not o.name.startswith("cell_"):
            continue            # trees, stones and knots are not drawn on the roll (they would hang off the beam)
        me = o.data.copy()
        mb = o.matrix_basis.copy()
        for vtx in me.vertices:
            w = mb @ vtx.co
            vtx.co = V(G.bend(w.x, w.y, w.z))
        me.update()
        ob = bpy.data.objects.new(o.name + "_r", me)
        bc.objects.link(ob)
    VARIANTS[key] = (coll, ground, bc)
    return bc


def yarn_tree(base, r, rnd, coll):
    """A small round tree (round 4, as loom.png's): a felted wool ball on the cloth with a few fine plied strands
    wound over it (wool, but it reads as one round tree). Sits sunk 15% into the cloth."""
    cx, cy, cz = base
    cz += r * 0.85
    ico((cx, cy, cz), r, M["tree"][rnd.randint(0, 2)], "treecore", scale=(1, 1, 0.96), sub=4, coll=coll, jitter=0.03, seed=rnd.randint(0, 999))
    # (no wound strands: they striped the small balls like melons; the felt itself carries the wool texture)


def instance(coll, loc, rot_x=0.0, rot_z=0.0, name="inst"):
    e = bpy.data.objects.new(name, None)
    e.instance_type = "COLLECTION"
    e.instance_collection = coll
    e.location = loc
    e.rotation_euler = (R(rot_x), 0, R(rot_z))
    COL.objects.link(e)
    return e


# ------------------------------------------------------------------ live props


def felt_block(center, size, material, name, coll, rnd, bevel=0.0035, lump=0.06):
    """A soft felt block: rounded box, its faces slightly bulged and lumpy (hand-made, not machined)."""
    o = box(center, size, material, name, bevel=bevel)
    o.modifiers[0].segments = 4
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=o.modifiers[0].name)
    for c_ in o.users_collection:
        c_.objects.unlink(o)
    coll.objects.link(o)
    me2 = o.data
    sx, sy, sz = size
    ph = [rnd.uniform(0, 6.28) for _ in range(3)]
    for vtx in me2.vertices:
        x, y, z = vtx.co
        b = 1 + lump * (math.sin(x / sx * 5 + ph[0]) * math.sin(y / sy * 4 + ph[1]) + 0.5 * math.sin(z / sz * 6 + ph[2])) * 0.3
        vtx.co = V((x * b, y * b, z * (1 + 0.02 * math.sin(x / sx * 7 + ph[2]))))
    me2.polygons.foreach_set("use_smooth", [True] * len(me2.polygons))
    return o


def running_stitch(p0, p1, n, mat_, coll, r=0.00045, gap=0.45):
    """n stitches from p0 to p1 (each a short thread lying on the surface, gaps between)."""
    p0, p1 = V(p0), V(p1)
    for k in range(n):
        a = p0.lerp(p1, (k + gap / 2) / n)
        b = p0.lerp(p1, (k + 1 - gap / 2) / n)
        mid = (a + b) / 2 + V((0, 0, r * 0.4))
        tube([a, mid, b], r, mat_, "stitch", ring=5, coll=coll)


def house_prop(look, coll):
    """Felt cottage on a felt yard: lumpy felt walls, two puffy felt roof slabs with rows of running stitch,
    a blanket-stitched ridge, a stitched door and a cross-stitched window. Origin at the cell centre."""
    rnd = random.Random(31 + look)
    felt_block((0, 0, 0.0007), (0.04, 0.034, 0.0016), M["yard"], "yard", coll, rnd, bevel=0.0007, lump=0.03)
    w, d, h = 0.031 + 0.002 * look, 0.024, 0.0185 + 0.001 * (look % 2)
    felt_block((0, 0, h / 2 + 0.001), (w, d, h), M["walls"], "walls", coll, rnd)
    roof = M["roofs"][look]
    ang = 37 + 3 * look
    over, th = 0.003, 0.0042
    hd = d / 2 + over
    rise = hd * math.tan(R(ang))
    L_ = hd / math.cos(R(ang))
    base = h + 0.0004
    for s_ in (-1, 1):
        cy = s_ * hd / 2
        cz = base + rise / 2 + th / 2 * math.cos(R(ang))
        sl = felt_block((0, 0, 0), (w + 2 * over, L_ + 0.002, th), roof, "roof", coll, rnd, bevel=0.0018, lump=0.05)
        sl.rotation_euler = (R(-s_ * ang), R(rnd.uniform(-1.5, 1.5)), 0)
        sl.location = (0, cy, cz)
        # rows of running stitch along each slope, like thatch courses
        nrm = V((0, s_ * math.sin(R(ang)), math.cos(R(ang))))
        for t in (0.22, 0.52, 0.8):
            y = s_ * hd * (1 - t)
            z = base + rise * t
            off = nrm * (th + 0.0003)
            a = V((-w / 2 - over + 0.002, y, z)) + off
            b = V((w / 2 + over - 0.002, y, z)) + off
            running_stitch(a, b, 8, M["stitch"], coll)
    # blanket stitch over the ridge seam
    rz = base + rise + th * 0.95
    for k in range(9):
        x = -w / 2 - over + 0.003 + k * (w + 2 * over - 0.006) / 8
        tube([(x, -0.0028, rz - 0.0012), (x, 0, rz + 0.0006), (x, 0.0028, rz - 0.0012)], 0.0005, M["stitch_dark"], "ridge", ring=5, coll=coll)
    fy = -d / 2 - 0.0009
    # door: dark felt patch with a running-stitch outline
    dx, dw, dh = 0.0045, 0.0062, 0.0098
    felt_block((dx, fy + 0.0004, 0.0012 + dh / 2), (dw, 0.0012, dh), M["door"], "door", coll, rnd, bevel=0.0005, lump=0.02)
    fz = fy - 0.0004
    corners = [(dx - dw / 2 - 0.0008, 0.0008), (dx + dw / 2 + 0.0008, 0.0008), (dx + dw / 2 + 0.0008, 0.0012 + dh + 0.0008),
               (dx - dw / 2 - 0.0008, 0.0012 + dh + 0.0008)]
    for k in range(4):
        (x0, z0), (x1, z1) = corners[k], corners[(k + 1) % 4]
        running_stitch((x0, fz, z0), (x1, fz, z1), 3, M["stitch"], coll, r=0.0004)
    # window: ochre felt patch with a cross stitch
    wx, wz = -0.0065, 0.0105
    felt_block((wx, fy + 0.0004, wz), (0.0058, 0.0012, 0.0058), M["window"], "window", coll, rnd, bevel=0.0005, lump=0.02)
    for a, b in (((-1, -1), (1, 1)), ((-1, 1), (1, -1))):
        tube([(wx + a[0] * 0.0024, fz, wz + a[1] * 0.0024), (wx + b[0] * 0.0024, fz, wz + b[1] * 0.0024)],
             0.00045, M["stitch_dark"], "xstitch", ring=5, coll=coll)


def arch_board(coll, x, w, h, span, rise, z0, material, name, n=28):
    """A board swept along the bridge's arch (y across the river, z = z0 + rise * sin(pi t)): stringers and rails."""
    verts, faces = [], []
    for i in range(n + 1):
        t = i / n
        y = -span / 2 + span * t
        z = z0 + rise * math.sin(math.pi * t)
        for dx, dz in ((-w / 2, 0), (w / 2, 0), (w / 2, h), (-w / 2, h)):
            verts.append((x + dx, y, z + dz))
    for i in range(n):
        for k in range(4):
            a_, b_ = i * 4 + k, i * 4 + (k + 1) % 4
            faces.append((a_, b_, b_ + 4, a_ + 4))
    faces.append((3, 2, 1, 0))
    faces.append((n * 4, n * 4 + 1, n * 4 + 2, n * 4 + 3))
    return obj_from(verts, faces, name, material, smooth=False, coll=coll)


def bridge_prop(coll):
    """Arched wooden footbridge (round 4: readable end-on from the play camera). A high humped deck of close planks
    (rise a third of its span), dark arched side boards under its edges, arched hand-rails on tall capped posts.
    Spans y (path N-S over a river E-W). Origin at the cell centre, ends on the banks."""
    span, wdt, rise, base = 0.082, 0.028, 0.026, 0.0012
    n = 17
    for k in range(n):
        t = (k + 0.5) / n
        y = -span / 2 + span * t
        z = base + rise * math.sin(math.pi * t) + 0.0018
        tilt = math.degrees(math.atan(rise * math.pi / span * math.cos(math.pi * t)))
        box((0, y, z), (wdt, span / n * 0.96, 0.0036), M["bridge"], "plank", rot=(tilt, 0, 0), bevel=0.0004, coll=coll)
    for sx in (-1, 1):
        # the arched side board (fascia) under the deck edge: dark, so the hump's outline shows against the water
        arch_board(coll, sx * (wdt / 2 + 0.0008), 0.0026, 0.0085, span * 0.98, rise, base - 0.0062, M["bridge_dark"], "fascia")
        arch_board(coll, sx * (wdt / 2 - 0.0012), 0.0028, 0.003, span * 0.92, rise * 0.98, base + 0.0165, M["bridge"], "rail")
        for t in (0.04, 0.27, 0.5, 0.73, 0.96):
            y = -span * 0.46 + span * 0.92 * t
            z = base + rise * math.sin(math.pi * (y / span + 0.5)) + 0.0035
            box((sx * (wdt / 2 - 0.0012), y, z + 0.0068), (0.0028, 0.0028, 0.0136), M["bridge"], "post", bevel=0.0005, coll=coll)
            box((sx * (wdt / 2 - 0.0012), y, z + 0.0142), (0.0036, 0.0036, 0.0016), M["bridge_dark"], "postcap", bevel=0.0004, coll=coll)


def traveller(coll, scale=1.0):
    """Turned wooden peg with a felt hat, a pack and a staff. Origin on the cloth, faces +y (the fell)."""
    S = scale
    prof = [(0, 0), (0.0082, 0), (0.0086, 0.0012), (0.0078, 0.003), (0.0068, 0.012), (0.0058, 0.02), (0.0052, 0.0245),
            (0.0058, 0.0262), (0.0050, 0.0278), (0.0026, 0.0288), (0, 0.0289)]
    lathe([(r_ * S, z * S) for r_, z in prof], (0, 0, 0), M["cloak"], "peg_body", steps=48, coll=coll)
    hz = 0.0289 * S + 0.0056 * S
    ico((0, 0, hz), 0.0062 * S, M["peg"], "peg_head", sub=4, coll=coll)
    brim = [(0, 0), (0.0108, -0.0012), (0.011, -0.0003), (0.0062, 0.0007), (0, 0.0009)]
    lathe([(r_ * S, z * S) for r_, z in brim], (0, 0, hz + 0.0036 * S), M["hat"], "hat_brim", steps=40, coll=coll)
    crown = [(0.0058, 0), (0.0052, 0.004), (0.0036, 0.0085), (0.0012, 0.0118), (0, 0.0122)]
    o = lathe([(r_ * S, z * S) for r_, z in crown], (0, 0, hz + 0.0040 * S), M["hat"], "hat_crown", steps=40, coll=coll)
    o.rotation_euler = (R(-12), R(6), 0)
    ico((0, 0.0058 * S, 0.0175 * S), 0.0058 * S, M["pack"], "pack", scale=(1.05, 0.7, 1.25), sub=3, coll=coll)
    tube([(0.0095 * S, -0.002 * S, 0.0), (0.0105 * S, -0.0035 * S, 0.047 * S)], 0.0009 * S, M["bridge"], "staff", ring=8, coll=coll)


BALL_R0, BALL_R1, CUP_Z, CUP_R = G.BALL_R0, G.BALL_R1, G.CUP_Z, G.CUP_R


def ball_radius(fill):
    """Radius of a ball holding `fill` (0..1) of a full ball's wool: volume shrinks with the radius cubed."""
    return (BALL_R0 ** 3 + (BALL_R1 ** 3 - BALL_R0 ** 3) * fill) ** (1 / 3)


def stand(loc, coll):
    """Turned wooden cup the ball sits in (static: baked in the backdrop)."""
    x, y = loc
    prof = [(0, 0), (0.021, 0), (0.0215, 0.003), (0.019, 0.0045), (0.009, 0.007), (0.0075, 0.011), (0.011, 0.015),
            (0.0165, CUP_Z - 0.0015), (0.0168, CUP_Z), (CUP_R, CUP_Z + 0.0005), (CUP_R - 0.003, CUP_Z - 0.004), (0, CUP_Z - 0.005)]
    lathe(prof, (x, y, 0), M["oak"], "stand", steps=48, coll=coll)


def bobbin(loc, wool, fill, coll):
    """A ball of chunky wool: a felted core under ~24 turns of plied yarn (real strands, 2.4 mm thick) wound
    round different axes. One cooked mesh per colour and fill level (live)."""
    x, y = loc
    rb = ball_radius(fill)
    cz = CUP_Z + math.sqrt(max(rb * rb - CUP_R * CUP_R, 0.0))
    ry = 0.0024
    rnd = random.Random(zlib.crc32(wool.encode()))
    core = WOOL[wool]
    ico((x, y, cz), rb - ry * 1.4, M["wool_core"][wool], "ball_core", sub=4, coll=coll)
    turns = 30 + int(14 * fill)
    for k in range(turns):
        # axes spread over the sphere (golden spiral), each turn slightly tilted: a cross-wound ball
        zk = 1 - 2 * (k + 0.5) / turns
        th = k * 2.39996 + rnd.uniform(-0.2, 0.2)
        ax = V((math.sqrt(1 - zk * zk) * math.cos(th), math.sqrt(1 - zk * zk) * math.sin(th), zk))
        a = ax.orthogonal().normalized()
        b = ax.cross(a).normalized()
        rr = rb - ry * (0.2 + 0.5 * rnd.random())
        pts = [tuple(V((x, y, cz)) + (a * math.cos(2 * math.pi * s / 44) + b * math.sin(2 * math.pi * s / 44)) * rr) for s in range(44)]
        tube(pts, ry, M["wool"][wool], "ball_turn", ring=6, coll=coll, closed=True)


def shuttle(loc, coll, trail_to=None, wool="tan"):
    """Boat shuttle along x lying on the warp, with its pirn of wool; trails the loose weft."""
    x, y, z = loc
    L_, W_, H_ = 0.12, 0.024, 0.016
    verts, faces = [], []
    nx, nr = 40, 16
    for i in range(nx + 1):
        t = -1 + 2 * i / nx
        w = (1 - abs(t) ** 2.2) ** 0.75
        for k in range(nr):
            a = 2 * math.pi * k / nr
            verts.append((x + t * L_ / 2, y + math.cos(a) * W_ / 2 * w, z + H_ / 2 + math.sin(a) * H_ / 2 * w * (0.75 if math.sin(a) > 0 else 1)))
    for i in range(nx):
        for k in range(nr):
            k2 = (k + 1) % nr
            faces.append((i * nr + k, i * nr + k2, (i + 1) * nr + k2, (i + 1) * nr + k))
    obj_from(verts, faces, "shuttle", M["shuttle"], coll=coll)
    # the pirn of wool sitting in the shuttle's open top
    pts = [(x - 0.026, y, z + H_ * 0.86), (x + 0.026, y, z + H_ * 0.86)]
    tube(pts, 0.0052, M["wool"][wool], "pirn", ring=16, coll=coll)
    if trail_to is not None:
        tx, ty, tz = trail_to
        tube([(x - 0.02 * (1 if tx < x else -1), y, z + H_ * 0.9), ((x + tx) / 2, (y + ty) / 2, max(z, tz) + 0.004), (tx, ty, tz)],
             0.0013, M["wool"][wool], "trail", ring=8, coll=coll)


# ------------------------------------------------------------------ static loom, table, light


WARP_N = 6              # warp threads drawn per cell beyond the fell (revision 2: the woven cloth has 12 ends per cell; drawn
                        # at 12 the warp merged into a grey sheet, so the static warp shows every second end, thicker)


def warp_x(i):
    return -G.HALF_W + (i + 0.5) * G.CELL / WARP_N


def build_static(coll):
    box((0.1, 0.6, -0.02), (4.0, 4.4, 0.04), M["table"], "table", bevel=0.004, coll=coll)
    # side frame: rails along y, carrying the beams
    for s in (-1, 1):
        x = s * (G.HALF_W + 0.05)
        box((x, (G.BEAM_Y + G.BACK_Y) / 2 - 0.02, 0.05), (0.04, G.BACK_Y - G.BEAM_Y + 0.14, 0.06), M["oak"], "rail", bevel=0.004, coll=coll)
        for yy in (G.BEAM_Y + 0.02, G.BACK_Y - 0.02):
            box((x, yy, 0.01), (0.05, 0.05, 0.02), M["oak"], "foot", bevel=0.004, coll=coll)
        # beater swords
        box((s * (G.HALF_W + 0.022), G.REED_Y, G.Z0 + 0.03), (0.012, 0.018, 0.1), M["oak"], "sword", bevel=0.002, coll=coll)
    # front (breast) beam: a rounded bar under the cloth's fold
    by, bz = G.BEAM_AXIS
    rb = G.ROLL_R - 0.003
    bpy.ops.mesh.primitive_cylinder_add(radius=rb, depth=0.70, location=(0, by, bz), rotation=(0, R(90), 0), vertices=96)
    o = bpy.context.active_object
    o.name = "breast_beam"
    o.data.materials.append(M["oakx"])
    bpy.ops.object.shade_smooth()
    for c_ in o.users_collection:
        c_.objects.unlink(o)
    coll.objects.link(o)
    for sx in (-1, 1):       # turned end knobs outside the rails
        prof = [(0, 0), (rb * 0.8, 0), (rb * 1.05, 0.008), (rb * 0.9, 0.018), (rb * 0.55, 0.026), (rb * 0.6, 0.034), (0, 0.04)]
        k = lathe([(r_, z_) for r_, z_ in prof], (0, 0, 0), M["oak"], "beam_knob", steps=48, coll=coll)
        k.rotation_euler = (0, R(90 * sx), 0)
        k.location = (sx * 0.35, by, bz)
    # back beam
    bpy.ops.mesh.primitive_cylinder_add(radius=0.022, depth=2 * G.HALF_W + 0.14, location=(0, G.BACK_Y, 0.095), rotation=(0, R(90), 0))
    o = bpy.context.active_object
    o.data.materials.append(M["oakx"])
    bpy.ops.object.shade_smooth()
    for c in o.users_collection:
        c.objects.unlink(o)
    coll.objects.link(o)
    # reed: top and bottom bars, a dent between every warp end
    box((0, G.REED_Y, G.Z0 + 0.026), (2 * G.HALF_W + 0.03, 0.016, 0.01), M["oakx"], "reed_top", bevel=0.002, coll=coll)
    box((0, G.REED_Y, G.Z0 - 0.016), (2 * G.HALF_W + 0.03, 0.016, 0.01), M["oakx"], "reed_bot", bevel=0.002, coll=coll)
    verts, faces = [], []
    for i in range(G.COLS * WARP_N + 1):
        x = -G.HALF_W + i * G.CELL / WARP_N
        b = len(verts)
        for dz in (G.Z0 - 0.012, G.Z0 + 0.022):
            for dy in (-0.005, 0.005):
                verts.append((x, G.REED_Y + dy, dz))
        faces.append((b, b + 1, b + 3, b + 2))
    obj_from(verts, faces, "dents", M["reed"], smooth=False, coll=coll)
    # heddle frame between reed and back beam
    hy = 0.36
    for dz in (G.Z0 - 0.02, G.Z0 + 0.05):
        box((0, hy, dz), (2 * G.HALF_W + 0.03, 0.01, 0.008), M["oakx"], "shaft", bevel=0.0015, coll=coll)
    for s in (-1, 1):
        box((s * (G.HALF_W + 0.022), hy, G.Z0 + 0.015), (0.012, 0.012, 0.09), M["oak"], "shaft_side", bevel=0.002, coll=coll)
    for i in range(G.COLS * WARP_N):
        x = warp_x(i)
        tube([(x, hy, G.Z0 - 0.02), (x, hy, G.Z0 + 0.05)], 0.0004, M["reed"], "heddle", ring=4, coll=coll)
    # warp: from the fell, under the loose weft, through reed and heddles, to the back beam
    for i in range(G.COLS * WARP_N):
        x = warp_x(i)
        pts = [(x, -0.004, G.Z0 + 0.0008), (x, G.CELL, G.Z0 + 0.0012), (x, G.REED_Y, G.Z0 + 0.003), (x, hy, G.Z0 + 0.012),
               (x, G.BACK_Y - 0.02, 0.112), (x, G.BACK_Y, 0.117)]
        tube(pts, 0.0012, M["warp"], "warp", ring=6, coll=coll)


def build_light(cast_coll):
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*srgb(178, 172, 160), 1)     # round 4: a warm room, dimmer: stronger shading
    bg.inputs["Strength"].default_value = 0.42
    sd = bpy.data.lights.new("sun", "SUN")
    sd.energy = 7.0                                                    # round 4: warm late sun, soft-edged shadows
    sd.color = (1.0, 0.80, 0.56)
    sd.angle = R(3.0)
    so = bpy.data.objects.new("sun", sd)
    COL.objects.link(so)
    sun_dir = SUN_DIR.normalized()
    so.rotation_euler = (-sun_dir).to_track_quat("-Z", "Y").to_euler()
    # window frame between the sun and the table: casts the bar shadows, never seen by the camera
    centre = V((0.05, -0.3, 0.0)) + sun_dir * 1.25
    up = V((0, 0, 1))
    side = sun_dir.cross(up).normalized()
    up = side.cross(sun_dir).normalized()
    rot = Matrix((side, up, sun_dir)).transposed().to_euler()
    pieces = []          # revision 2: no window-bar shadows (the concept is open sunlight)
    for (ox, oy), (w, h) in pieces:
        p = centre + side * ox + up * oy
        o = box(tuple(p), (w, h, 0.03), M["table"], "window_bar", coll=cast_coll)
        o.rotation_euler = rot
        o.visible_camera = False
        o.visible_glossy = False
        o.visible_diffuse = False
    # cool fill from the room, weak
    ad = bpy.data.lights.new("fill", "AREA")
    ad.energy = 8.0
    ad.size = 1.5
    ad.color = (0.92, 0.94, 1.0)
    ao = bpy.data.objects.new("fill", ad)
    ao.location = (0.8, -1.4, 1.2)
    ao.rotation_euler = (V((0, -0.3, 0)) - ao.location).to_track_quat("-Z", "Y").to_euler()
    COL.objects.link(ao)


SUN_DIR = V(G.SUN_DIR)             # toward the sun (loom_grid.py, shared with the engine's sun)
WIN_BAR_V, WIN_BAR_H = -0.16, 0.12


def build_camera():
    cd = bpy.data.cameras.new("cam")
    cd.sensor_fit = "VERTICAL"
    cd.sensor_height = G.SENSOR_H_MM
    cd.lens = G.LENS_MM
    cd.clip_start = 0.01
    cd.dof.use_dof = True
    cd.dof.focus_distance = G.focus_distance()
    cd.dof.aperture_fstop = G.F_STOP
    co = bpy.data.objects.new("cam", cd)
    COL.objects.link(co)
    co.location = G.CAM_POS
    co.rotation_euler = (V(G.CAM_TARGET) - V(G.CAM_POS)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = co
    return co


# ------------------------------------------------------------------ the two stretches of cloth
MAP_A, ROW_A, FILL_A, MAP_B, ROW_B, FILL_B, TRAV_B = G.MAP_A, G.ROW_A, G.FILL_A, G.MAP_B, G.ROW_B, G.FILL_B, G.TRAV_B
BOBBINS = G.BOBBINS

AUDIT = []
TRAV_SCALE = G.TRAV_SCALE


def place_cloth(grid):
    """One instance per cell node: the cooked variant of its (kind, mask)."""
    used = {}
    rolled = set()
    for r in range(len(grid)):
        for c in range(G.COLS):
            key = variant_key(grid, c, r, len(grid) - r)   # absolute row, as the game counts it
            nb = nb_of(grid, c, r)
            coll, ground, _ = cell_variant(key, nb)
            used[key] = used.get(key, 0) + 1
            state, y, z, ang = G.row_pose(r)
            if state == "rolled":
                coll = rolled_variant(key, nb)
                rolled.add(key)
            instance(coll, (G.col_x(c), y, z), rot_x=ang, name="cell_%d_%d" % (c, r))
    print("LOOM variants used", len(used), "rolled copies", len(rolled), "cells", sum(used.values()))
    print("LOOM keys", sorted(used))
    return used


def ground_at(grid, c, r, u=0.0, v=0.0, rad=0.0):
    """Cloth height (m above Z0) under a prop: the highest woven point inside its footprint radius (cells),
    so a prop rests on the ridges and the weave never pokes through it."""
    key = variant_key(grid, c, r, len(grid) - r)
    _, ground, _ = cell_variant(key, nb_of(grid, c, r))
    if not rad:
        return ground(u, v)
    pts = [(u + rad * i / 4, v + rad * j / 4) for i in range(-4, 5) for j in range(-4, 5) if i * i + j * j <= 16]
    return max(ground(max(-0.5, min(0.5, a)), max(-0.5, min(0.5, b))) for a, b in pts)


PROP_COLLS = {}


def prop_coll(name, fn):
    if name not in PROP_COLLS:
        cl = bpy.data.collections.new("P_" + name)
        fn(cl)
        PROP_COLLS[name] = cl
    return PROP_COLLS[name]


def place_props(grid, trav):
    for r in range(len(grid)):
        if G.row_pose(r)[0] == "rolled":       # props are hidden once their row rolls onto the beam
            continue
        for c in range(G.COLS):
            k = grid[r][c]
            x, y = G.col_x(c), G.row_y(r)
            ka = len(grid) - r              # the row's absolute number, as the game counts it (loom_world.lua)
            if k == "H":
                look = (c + 2 * ka + 1) % 3
                cl = prop_coll("house%d" % look, lambda cl, look=look: house_prop(look, cl))
                zg = ground_at(grid, c, r, rad=0.36)
                instance(cl, (x, y, G.Z0 + zg - 0.0005), rot_z=((c * 37 + ka * 11) % 17 - 8), name="house")
                AUDIT.append(("house", c, r, zg))
            elif k in ("b", "B"):
                cl = prop_coll("bridge", bridge_prop)
                zg = min(ground_at(grid, c, r, 0, 0.47), ground_at(grid, c, r, 0, -0.47)) if k == "b" else \
                    min(ground_at(grid, c, r, 0.47, 0), ground_at(grid, c, r, -0.47, 0))
                instance(cl, (x, y, G.Z0 + zg - 0.0008), rot_z=0 if k == "b" else 90, name="bridge")
                AUDIT.append(("bridge ends", c, r, zg))
    tc, tr = trav
    cl = prop_coll("traveller", lambda cl: traveller(cl, TRAV_SCALE))
    zg = ground_at(grid, tc, tr, 0.0, 0.07, rad=0.23)
    instance(cl, (G.col_x(tc), G.row_y(tr) + 0.004, G.Z0 + zg - 0.0006), rot_z=-28, name="traveller")
    AUDIT.append(("traveller", tc, tr, zg))


def place_row(row, coll):
    """The half-woven row: loose picks per chosen cell lying across the bare warp; shuttle beyond."""
    last = None
    for c, wool in row["cells"]:
        x0 = G.col_x(c) - C / 2
        for j in range(G.PICKS - 1):
            y = 0.006 + j * C * 0.93 / (G.PICKS - 1) + 0.0015 * math.sin(c * 3 + j * 1.7)
            pts = []
            for k in range(25):
                t = k / 24
                x = x0 - 0.0015 + (C + 0.003) * t
                i = (x + G.HALF_W) / G.THREAD
                over = math.cos(math.pi * (i - 0.5 - j))
                pts.append((x, y + 0.0012 * math.sin(t * 6.3 + j + c), G.Z0 + 0.0021 + 0.0009 * over))
            tube(pts, 0.0017, M["wool"][wool], "weft", ring=8, coll=coll)
        last = (c, wool)
    c, wool = last
    d = row["dir"]
    sx = G.col_x(c) + d * (C / 2 + 0.07)
    shuttle((sx, 0.03, G.Z0 + 0.0016), coll, trail_to=(G.col_x(c) + d * C / 2, 0.03, G.Z0 + 0.0028), wool=wool)


def place_bobbins(fill, coll, balls=True, stands=True):
    for wool, x, y in BOBBINS:
        if stands:
            stand((x, y), coll)
        if balls:
            bobbin((x, y), wool, fill[wool], coll)


# ------------------------------------------------------------------ render


def report_projection():
    from bpy_extras.object_utils import world_to_camera_view as w2c
    bpy.context.view_layer.update()
    cam = sc.camera

    def px(p):
        q = w2c(sc, cam, V(p))
        return (round(q.x * 1920), round((1 - q.y) * 1080))
    for name, p in [("fell L", (-G.HALF_W, 0, G.Z0)), ("fell R", (G.HALF_W, 0, G.Z0)), ("fell C", (0, 0, G.Z0)),
                    ("beam L", (-G.HALF_W, G.BEAM_Y, G.Z0)), ("beam R", (G.HALF_W, G.BEAM_Y, G.Z0)),
                    ("reed C", (0, G.REED_Y, G.Z0 + 0.03)), ("back C", (0, G.BACK_Y, 0.11))]:
        print("LOOM px1080", name, px(p))
    tx, ty = G.col_x(G.TRAVELLER[0]), G.row_y(G.TRAVELLER[1])
    a, b = px((tx, ty, G.Z0)), px((tx, ty, G.Z0 + 0.0475 * TRAV_SCALE))
    print("LOOM traveller height px", a[1] - b[1])
    for wool, x, y in BOBBINS:
        for fill in (1.0, 0.5, 0.0):
            rb = ball_radius(fill)
            cz = CUP_Z + math.sqrt(max(rb * rb - CUP_R * CUP_R, 0.0))
            top, bot = px((x, y + rb * 0.6, cz + rb)), px((x, y - 0.021, 0.0))
            l, r_ = px((x - rb, y, cz)), px((x + rb, y, cz))
            print("LOOM ball", wool, "fill", fill, "h", bot[1] - top[1], "w", r_[0] - l[0])


def render(path, samples):
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
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.render.resolution_x, sc.render.resolution_y = RES
    for vt in ("ACES 1.3", "ACES 2.0", "ACES"):
        try:
            sc.view_settings.view_transform = vt
            print("LOOM view transform", vt)
            break
        except TypeError:
            continue
    else:
        print("LOOM view transform fallback", sc.view_settings.view_transform)
    sc.view_settings.exposure = EXPOSURE
    sc.render.filepath = path
    if MODE == "backdrop":
        sc.view_layers[0].use_pass_z = True
    bpy.ops.render.render(write_still=True)
    print("wrote", path)
    if MODE == "backdrop":
        # camera-space depth for the engine's depth mesh (so its depth of field blurs the backdrop correctly)
        try:
            sc.render.image_settings.media_type = "MULTI_LAYER_IMAGE"
        except (AttributeError, TypeError):
            pass
        sc.render.image_settings.file_format = "OPEN_EXR_MULTILAYER"
        sc.render.image_settings.color_depth = "32"
        dp = os.path.splitext(path)[0] + "_depth.exr"
        bpy.data.images["Render Result"].save_render(dp, scene=sc)
        print("wrote", dp)


EXPOSURE = 0.55        # revision 2: bright and sunny like the concept


def side_by_side():
    import numpy as np
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    a = bpy.data.images.load(os.path.join(root, ".concepts", "next", "loom.png"))
    b = bpy.data.images.load(os.environ.get("LOOM_TARGET", os.path.join(root, ".concepts", "next", "loom", "target.png")))
    W, H = 1920, 1080
    out = np.zeros((H, 2 * W + 16, 4), dtype=np.float32)
    out[..., 3] = 1
    for k, im in enumerate((a, b)):
        if (im.size[0], im.size[1]) != (W, H):
            im.scale(W, H)
        px_ = np.array(im.pixels[:], dtype=np.float32).reshape(H, W, 4)
        out[:, k * (W + 16):k * (W + 16) + W] = px_
    img = bpy.data.images.new("side", 2 * W + 16, H, alpha=False)
    img.pixels = out.ravel()
    img.filepath_raw = OUT
    img.file_format = "PNG"
    img.save()
    print("wrote", OUT)


# ------------------------------------------------------------------ export: every cooked game piece (tools/gen_assets.py)


def lin_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def write_engine_obj(objs, path, xf=None):
    """One OBJ (one object, triangles, no degenerate ones) from Blender objects, in engine axes (x, z, -y).
    Colour per vertex in sRGB: the cloth's 'col' attribute, else the material's flat colour (m['lc']).
    xf: optional function mapping a world point (Vector) -> Vector before the axis swap (normals follow by
    finite difference)."""
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    out_v, out_t, out_n, faces = [], [], [], []
    for o in objs:
        if o.type != "MESH":
            continue
        oe = o.evaluated_get(deps)
        me = oe.to_mesh()
        me.calc_loop_triangles()
        mw = o.matrix_world.copy()
        nm = mw.to_3x3().inverted_safe().transposed()
        uvl = me.uv_layers.active
        ca = me.color_attributes.get("col")
        mats = [m_["lc"] if (m_ is not None and "lc" in m_) else (0.8, 0.8, 0.8) for m_ in me.materials] or [(0.8, 0.8, 0.8)]
        cn = me.corner_normals
        seen = {}
        # closed props wound inward (tubes, some lathes) show their inside in a back-face-culling engine: if a
        # piece's signed volume is negative, flip its winding and normals (the cloth top keeps its own: 'col')
        flip = False
        if ca is None:
            vol = 0.0
            for tri in me.loop_triangles:
                a_, b_, c_ = (mw @ me.vertices[i].co for i in tri.vertices)
                vol += a_.dot(b_.cross(c_))
            flip = vol < 0
        for tri in me.loop_triangles:
            idx = []
            for li in tri.loops:
                vi = me.loops[li].vertex_index
                p = mw @ me.vertices[vi].co
                n = (nm @ V(cn[li].vector)).normalized()
                if flip:
                    n = -n
                if xf is not None:
                    p2 = xf(p)
                    q = xf(p + n * 1e-4)
                    n = (q - p2).normalized()
                    p = p2
                uv = tuple(uvl.data[li].uv) if uvl else (0.0, 0.0)
                col = tuple(ca.data[vi].color[:3]) if ca is not None else tuple(mats[min(tri.material_index, len(mats) - 1)])
                key = (vi, round(uv[0], 5), round(uv[1], 5), round(n.x, 3), round(n.y, 3), round(n.z, 3), col)
                if key not in seen:
                    seen[key] = len(out_v)
                    out_v.append((p.x, p.z, -p.y, *[lin_to_srgb(c) for c in col]))
                    out_t.append(uv)
                    out_n.append((n.x, n.z, -n.y))
                idx.append(seen[key])
            a, b, c = idx
            if flip:
                b, c = c, b
            pa, pb, pc = (V(out_v[i][:3]) for i in (a, b, c))
            if len({a, b, c}) < 3 or (pb - pa).cross(pc - pa).length < 1e-13:
                continue
            faces.append((a, b, c))
        oe.to_mesh_clear()
    with open(path, "w") as fo:
        fo.write("o mesh\n")
        for v in out_v:
            fo.write("v %.6f %.6f %.6f %.4f %.4f %.4f\n" % v)
        for t in out_t:
            fo.write("vt %.6f %.6f\n" % t)
        for n in out_n:
            fo.write("vn %.5f %.5f %.5f\n" % n)
        for a, b, c in faces:
            fo.write("f %d/%d/%d %d/%d/%d %d/%d/%d\n" % (a + 1, a + 1, a + 1, b + 1, b + 1, b + 1, c + 1, c + 1, c + 1))
    return len(out_v), len(faces)


def export_coll(coll, path, xf=None):
    if coll.name not in COL.children:
        COL.children.link(coll)
    return write_engine_obj(list(coll.all_objects), path, xf)


def bake_weave(outdir):
    """The ONE tiling weave texture pair shared by every cloth variant, baked over UV [0, 1] from the cloth node
    tree on a plane one cell square (so bump distances are at true scale): albedo tint and tangent normal."""
    me = bpy.data.meshes.new("bakeplane")
    h = C / 2
    me.from_pydata([(-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0)], [], [(0, 1, 2, 3)])
    uvl = me.uv_layers.new(name="UVMap")
    for li, uv in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
        uvl.data[li].uv = uv
    ca = me.color_attributes.new("col", "FLOAT_COLOR", "POINT")
    for i in range(4):
        ca.data[i].color = (1, 1, 1, 1)
    m_ = M["cloth"]
    me.materials.append(m_)
    o = bpy.data.objects.new("bakeplane", me)
    COL.objects.link(o)
    for ob in bpy.context.view_layer.objects:
        ob.select_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 16
    sc.render.bake.margin = 0
    nt = m_.node_tree
    res = {}
    # the tint reaches 1.17 (bright plies): bake it scaled by 1 / ALBEDO_SCALE so an 8-bit sRGB PNG keeps it; the
    # engine material's base colour factor puts the scale back
    mr = [n for n in nt.nodes if n.bl_idname == "ShaderNodeMapRange"]
    for n in mr:
        n.inputs["To Min"].default_value /= ALBEDO_SCALE
        n.inputs["To Max"].default_value /= ALBEDO_SCALE
    for name, kind in (("weave_albedo", "DIFFUSE"), ("weave_normal", "NORMAL")):
        img = bpy.data.images.new(name, 1024, 1024, alpha=False, float_buffer=False)
        if kind == "NORMAL":
            img.colorspace_settings.name = "Non-Color"
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        nt.nodes.active = tn
        if kind == "DIFFUSE":
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True, margin=0)
        else:
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_clear=True, margin=0)
        img.filepath_raw = os.path.join(outdir, name + ".png")
        img.file_format = "PNG"
        img.save()
        nt.nodes.remove(tn)
        res[name] = img.filepath_raw
    for n in mr:
        n.inputs["To Min"].default_value *= ALBEDO_SCALE
        n.inputs["To Max"].default_value *= ALBEDO_SCALE
    bpy.data.objects.remove(o)
    return res


ALBEDO_SCALE = 1.2


def backdrop_depth_mesh(path, nx=192, ny=108):
    """The backdrop's surface: a grid of camera rays cast into the static scene, each vertex at its hit (pushed
    3 mm farther), UV = its screen position. Drawn with backdrop.png as an unlit texture, it matches the bake
    at the bake's camera and gives the engine's depth of field the real depth."""
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    cam = sc.camera
    cp = cam.matrix_world.translation.copy()
    rot = cam.matrix_world.to_3x3()
    th = math.tan(math.radians(G.vfov_deg()) / 2)
    tw = th * G.ASPECT
    verts, uvs, faces = [], [], []
    for j in range(ny + 1):
        for i in range(nx + 1):
            sx, sy = -1 + 2 * i / nx, 1 - 2 * j / ny
            d = (rot @ V((sx * tw, sy * th, -1.0))).normalized()
            hit, loc, nrm, _, ob, _ = sc.ray_cast(deps, cp, d, distance=20.0)
            t = (loc - cp).length + 0.003 if hit else 6.0
            p = cp + d * t
            verts.append((p.x, p.z, -p.y))
            uvs.append((i / nx, 1 - j / ny))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces += [(a, a + nx + 1, a + nx + 2), (a, a + nx + 2, a + 1)]
    fwd = rot @ V((0, 0, -1))
    with open(path, "w") as fo:
        fo.write("o backdrop\n")
        for v in verts:
            fo.write("v %.6f %.6f %.6f\n" % v)
        for t in uvs:
            fo.write("vt %.6f %.6f\n" % t)
        fo.write("vn %.5f %.5f %.5f\n" % (-fwd.x, -fwd.z, fwd.y))
        for a, b, c in faces:
            fo.write("f %d/%d/1 %d/%d/1 %d/%d/1\n" % (a + 1, a + 1, b + 1, b + 1, c + 1, c + 1))
    return len(verts), len(faces)


def weft_cell(wool, coll):
    """The loose picks of one cell of the row being woven (cell-local: x about the cell centre, y from the fell)."""
    x0 = -C / 2
    for j in range(G.PICKS - 1):
        y = 0.006 + j * C * 0.93 / (G.PICKS - 1) + 0.0015 * math.sin(12 + j * 1.7)
        pts = []
        for k in range(25):
            t = k / 24
            x = x0 - 0.0015 + (C + 0.003) * t
            i = (x + C / 2) / G.THREAD
            over = math.cos(math.pi * (i - 0.5 - j))
            pts.append((x, y + 0.0012 * math.sin(t * 6.3 + j + 4), G.Z0 + 0.0021 + 0.0009 * over))
        tube(pts, 0.0017, M["wool"][wool], "weft", ring=8, coll=coll)


def cursor_piece(coll):
    """The cell the shuttle is at: a loop of cream yarn laid round it on the warp (cell-local, like weft_cell)."""
    h, y0, y1, z = C / 2 - 0.002, 0.002, C - 0.002, G.Z0 + 0.0052
    pts = [(-h, y0, z), (h, y0, z), (h, y1, z), (-h, y1, z)]
    dense = []
    for k in range(4):
        a, b = V(pts[k]), V(pts[(k + 1) % 4])
        for s_ in range(10):
            dense.append(tuple(a.lerp(b, s_ / 10)))
    tube(dense, 0.0011, M["stitch"], "cursor", ring=6, coll=coll, closed=True)


def export_all(outdir):
    """Write every cooked piece of the game as OBJ into outdir, plus pieces.json, the weave textures and the
    backdrop's depth mesh. Names match the scene's template nodes (T_<name>)."""
    import json
    os.makedirs(outdir, exist_ok=True)
    info = {"cells": [], "rolled": [], "props": [], "stats": {}}
    only = os.environ.get("LOOM_ONLY", "")

    def want(name):
        return not only or any(name.startswith(p) for p in only.split(","))

    for key in G.all_keys():
        name = G.key_name(key)
        if not want(name):
            continue
        coll, ground, _ = cell_variant(key, G.key_nb(key))
        info["stats"][name] = export_coll(coll, os.path.join(outdir, name + ".obj"))
        info["cells"].append(name)
        cloth = [o for o in coll.all_objects if o.name.startswith("cell_")]     # the roll carries no trees or stones
        info["stats"][name + "_r"] = write_engine_obj(cloth, os.path.join(outdir, name + "_r.obj"), xf=lambda p: V(G.bend(p.x, p.y, p.z)))
        info["rolled"].append(name + "_r")
    props = {"house0": lambda cl: house_prop(0, cl), "house1": lambda cl: house_prop(1, cl), "house2": lambda cl: house_prop(2, cl),
             "bridge": bridge_prop, "traveller": lambda cl: traveller(cl, TRAV_SCALE), "cursor": cursor_piece}
    for w in WOOL:
        props["weft_" + w] = lambda cl, w=w: weft_cell(w, cl)
        if G.BOBBINS:          # round 3: no wool balls in view (the HUD shows the counts), so none are cooked
            for lv in range(5):
                props["ball_%s_%d" % (w, lv)] = lambda cl, w=w, lv=lv: bobbin((0.0, 0.0), w, lv / 4, cl)
    for name, fn in props.items():
        if not want(name):
            continue
        cl = bpy.data.collections.new("X_" + name)
        fn(cl)
        info["stats"][name] = export_coll(cl, os.path.join(outdir, name + ".obj"))
        info["props"].append(name)
    if want("shuttle") or want("pirn_"):
        cl = bpy.data.collections.new("X_shuttle")
        shuttle((0.0, 0.03, G.Z0 + 0.0016), cl)
        COL.children.link(cl)
        body = [o for o in cl.objects if o.name.startswith("shuttle")]
        info["stats"]["shuttle"] = write_engine_obj(body, os.path.join(outdir, "shuttle.obj"))
        info["props"].append("shuttle")
        for w in WOOL:
            pc = bpy.data.collections.new("X_pirn_" + w)
            zp = G.Z0 + 0.0016 + 0.016 * 0.86
            tube([(-0.026, 0.03, zp), (0.026, 0.03, zp)], 0.0052, M["wool"][w], "pirn", ring=16, coll=pc)
            info["stats"]["pirn_" + w] = export_coll(pc, os.path.join(outdir, "pirn_" + w + ".obj"))
            info["props"].append("pirn_" + w)
    if want("backdrop"):
        info["stats"]["backdrop"] = backdrop_depth_mesh(os.path.join(outdir, "backdrop.obj"))
    if want("weave"):
        info["textures"] = bake_weave(outdir)
    with open(os.path.join(outdir, "pieces.json" if not only else "pieces_partial.json"), "w") as fo:
        json.dump(info, fo, indent=1)
    print("LOOM exported", len(info["stats"]), "pieces to", outdir)


def main():
    if MODE == "side":
        side_by_side()
        return
    build_materials()
    static = bpy.data.collections.new("static")
    COL.children.link(static)
    build_static(static)
    build_light(static)
    build_camera()
    report_projection()
    if MODE == "frame":
        return
    if MODE == "export":
        # the stands are static (baked); the backdrop's depth mesh needs them in the scene
        place_bobbins(FILL_A, static, balls=False)
        export_all(OUT)
        return
    if MODE == "backdrop":
        # the stands never move or change: baked. The balls are live (they shrink), shadowed by live cards.
        place_bobbins(FILL_A, static, balls=False)
        sc.camera.data.dof.use_dof = False      # baked sharp: the engine's depth of field blurs it by depth
        render(OUT, SAMPLES)
        return
    grid, row, fill, trav = (MAP_A, ROW_A, FILL_A, G.TRAVELLER) if MODE == "target" else (MAP_B, ROW_B, FILL_B, TRAV_B)
    live = bpy.data.collections.new("live")
    COL.children.link(live)
    place_cloth(grid)
    place_props(grid, trav)
    place_row(row, live)
    place_bobbins(fill, static, balls=False)
    place_bobbins(fill, live, stands=False)
    for a in AUDIT:
        print("LOOM audit", a)
    if os.environ.get("LOOM_BLEND"):
        bpy.ops.wm.save_as_mainfile(filepath=os.environ["LOOM_BLEND"])
    render(OUT, SAMPLES)


main()
