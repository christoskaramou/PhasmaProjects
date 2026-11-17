"""Shadow Puppeteer look-plan scene (Blender 5.1, Cycles). Forked from .concepts/next/concepts.py puppet().

    blender -b --factory-startup --python tools/scene.py -- MODE OUT [SAMPLES] [WIDTH HEIGHT]

MODE: iou       shadow-model test: true Cycles prop shadows vs the planar silhouette construction (OUT = report .md)
      target    mid-play frame, lantern left and far           (OUT = png)
      target_b  same level after the player acted               (OUT = png)
      backdrop  only what never moves in any level              (OUT = png)
Geometry shared with the rules lives in tools/sp_common.py.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sp_common as G  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
MODE, OUT = argv[0], os.path.abspath(argv[1])
SAMPLES = int(argv[2]) if len(argv) > 2 and argv[2].isdigit() else 128
RES = (int(argv[3]), int(argv[4])) if len(argv) > 4 else (2560, 1440)
random.seed(11)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
COL = sc.collection
MAPID = os.environ.get("SP_MAP", "stage")        # which stage set (sp_common.MAPS) the bakes dress
TH = G.MAP_BY_ID[MAPID]
R = math.radians
V = Vector


def font(*names):
    for n in names:
        p = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", n)
        if os.path.exists(p):
            return bpy.data.fonts.load(p)
    return None


# ------------------------------------------------------------------ materials
def _nodes(m):
    m.use_nodes = True
    return m.node_tree.nodes, m.node_tree.links


def pbr(name, base, rough=0.5, metal=0.0, coat=0.0, sheen=0.0, trans=0.0, ior=1.45, emit=None, es=0.0,
        tint2=None, tex="noise", scale=4.0, detail=6.0, bump=0.0, fine=0.0, fine_scale=80.0, sss=0.0):
    m = bpy.data.materials.new(name)
    N, L = _nodes(m)
    p = N["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*base, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    p.inputs["IOR"].default_value = ior
    if coat:
        p.inputs["Coat Weight"].default_value = coat
    if sheen:
        p.inputs["Sheen Weight"].default_value = sheen
    if trans:
        p.inputs["Transmission Weight"].default_value = trans
    if sss:
        p.inputs["Subsurface Weight"].default_value = sss
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
            fac = t.outputs["Fac"]
        elif tex == "voronoi":
            t = N.new("ShaderNodeTexVoronoi")
            t.inputs["Scale"].default_value = scale
            fac = t.outputs["Distance"]
        else:
            t = N.new("ShaderNodeTexNoise")
            t.inputs["Scale"].default_value = scale
            t.inputs["Detail"].default_value = detail
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


def glow(name, color, strength):
    return pbr(name, color, rough=0.5, emit=color, es=strength)


def volume(name, color, density, aniso=0.0, noise=None):
    m = bpy.data.materials.new(name)
    N, L = _nodes(m)
    N.remove(N["Principled BSDF"])
    v = N.new("ShaderNodeVolumePrincipled")
    v.inputs["Color"].default_value = (*color, 1)
    v.inputs["Density"].default_value = density
    v.inputs["Anisotropy"].default_value = aniso
    if noise:
        scale, lo, hi = noise
        tc = N.new("ShaderNodeTexCoord")
        t = N.new("ShaderNodeTexNoise")
        t.inputs["Scale"].default_value = scale
        t.inputs["Detail"].default_value = 8
        mr = N.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = 0.42
        mr.inputs["From Max"].default_value = 0.68
        mr.inputs["To Min"].default_value = lo
        mr.inputs["To Max"].default_value = hi
        L.new(tc.outputs["Object"], t.inputs["Vector"])
        L.new(t.outputs["Fac"], mr.inputs["Value"])
        L.new(mr.outputs["Result"], v.inputs["Density"])
    L.new(v.outputs["Volume"], N["Material Output"].inputs["Volume"])
    return m


def world_sky(horizon, zenith, strength=1.0, stars=0.0, top=0.6):
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    N, L = w.node_tree.nodes, w.node_tree.links
    bg, out = N["Background"], N["World Output"]
    tc = N.new("ShaderNodeTexCoord")
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(tc.outputs["Generated"], sep.inputs["Vector"])
    ramp = N.new("ShaderNodeValToRGB")
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.0, (*horizon, 1)
    e[1].position, e[1].color = top, (*zenith, 1)
    L.new(sep.outputs["Z"], ramp.inputs["Fac"])
    L.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    if stars:
        vor = N.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 160
        L.new(tc.outputs["Generated"], vor.inputs["Vector"])
        sr = N.new("ShaderNodeValToRGB")
        se = sr.color_ramp.elements
        se[0].position, se[0].color = 0.0, (1, 0.97, 0.9, 1)
        se[1].position, se[1].color = 0.03, (0, 0, 0, 1)
        L.new(vor.outputs["Distance"], sr.inputs["Fac"])
        bg2 = N.new("ShaderNodeBackground")
        bg2.inputs["Strength"].default_value = stars
        L.new(sr.outputs["Color"], bg2.inputs["Color"])
        add = N.new("ShaderNodeAddShader")
        L.new(bg.outputs["Background"], add.inputs[0])
        L.new(bg2.outputs["Background"], add.inputs[1])
        L.new(add.outputs["Shader"], out.inputs["Surface"])


# ------------------------------------------------------------------ meshes
def put(o, m, smooth=False, bevel=0.0, seg=3):
    if m:
        o.data.materials.append(m)
    if smooth and hasattr(o.data, "polygons"):
        for f in o.data.polygons:
            f.use_smooth = True
    if bevel:
        md = o.modifiers.new("b", "BEVEL")
        md.width = bevel
        md.segments = seg
    return o


def apply_mods(o):
    bpy.context.view_layer.objects.active = o
    for md in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=md.name)


def box(loc, size, m=None, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[R(a) for a in rot])
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return put(o, m, bevel=bevel)


def cyl(loc, r, depth, m=None, rot=(0, 0, 0), verts=32, smooth=True, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=[R(a) for a in rot])
    return put(bpy.context.object, m, smooth, bevel)


def sphere(loc, r, m=None, scale=(1, 1, 1), sub=3, smooth=True):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r, location=loc)
    o = bpy.context.object
    o.scale = scale
    return put(o, m, smooth)


def uvsphere(loc, r, m=None, scale=(1, 1, 1), seg=48, rings=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=loc)
    o = bpy.context.object
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return put(o, m, True)


def cone(loc, r1, r2, depth, m=None, rot=(0, 0, 0), verts=24, smooth=True):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=[R(a) for a in rot])
    return put(bpy.context.object, m, smooth)


def cone_dir(base, direction, r1, depth, m, verts=16, r2=0.0):
    d = V(direction).normalized()
    o = cone(V(base) + d * depth / 2, r1, r2, depth, m, verts=verts)
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return o


def torus(loc, major, minor, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=[R(a) for a in rot],
                                     major_segments=64, minor_segments=12)
    return put(bpy.context.object, m, True)


def lathe(profile, loc, m=None, steps=48, scale=1.0):
    me = bpy.data.meshes.new("lathe")
    vs, fs = [], []
    n = len(profile)
    for s in range(steps):
        a = 2 * math.pi * s / steps
        for r, h in profile:
            vs.append((r * scale * math.cos(a), r * scale * math.sin(a), h * scale))
    for s in range(steps):
        s2 = (s + 1) % steps
        for i in range(n - 1):
            fs.append((s * n + i, s2 * n + i, s2 * n + i + 1, s * n + i + 1))
    me.from_pydata(vs, [], fs)
    o = bpy.data.objects.new("lathe", me)
    COL.objects.link(o)
    o.location = loc
    return put(o, m, True)


def plane(loc, w, h, m=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=[R(a) for a in rot])
    o = bpy.context.object
    o.scale = (w, h, 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return put(o, m)


def mesh_obj(verts, faces, m, name="mesh"):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    o = bpy.data.objects.new(name, me)
    COL.objects.link(o)
    return put(o, m)


def tube(pts, r, m, taper=None, cyclic=False):
    cu = bpy.data.curves.new("tube", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = 4
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (*p, 1)
        if taper:
            sp.points[i].radius = taper[i]
    sp.use_endpoint_u = not cyclic
    sp.use_cyclic_u = cyclic
    sp.order_u = min(4, len(pts))
    o = bpy.data.objects.new("tube", cu)
    COL.objects.link(o)
    cu.materials.append(m)
    return o


def text(body, loc, size, m, fnt=None, extrude=0.02, bevel=0.0, face=None, rot=None, align="CENTER"):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.align_x = align
    cu.align_y = "CENTER"
    if fnt:
        cu.font = fnt
    o = bpy.data.objects.new("txt", cu)
    COL.objects.link(o)
    o.location = loc
    cu.materials.append(m)
    if face is not None:
        o.rotation_euler = (V(face) - V(loc)).to_track_quat("Z", "Y").to_euler()
    elif rot:
        o.rotation_euler = [R(a) for a in rot]
    return o


# Metaballs: each family (unique base name) is one smooth blob with one material.
VIS = 1.45   # element radius per unit of visible radius (threshold 0.6, stiffness 2)


def meta(name, m, res=0.05):
    mb = bpy.data.metaballs.new(name)
    mb.resolution = res
    mb.render_resolution = res
    mb.threshold = 0.6
    o = bpy.data.objects.new(name, mb)
    COL.objects.link(o)
    mb.materials.append(m)
    return mb


def ball(mb, co, r, size=None, quat=None):
    e = mb.elements.new(type="ELLIPSOID" if size else "BALL")
    e.co = V(co)
    e.radius = r * VIS
    if size:
        e.size_x, e.size_y, e.size_z = size
    if quat is not None:
        e.rotation = quat
    return e


def caps(mb, a, b, r):
    a, b = V(a), V(b)
    d = b - a
    e = mb.elements.new(type="CAPSULE")
    e.co = (a + b) / 2
    e.radius = r * VIS
    e.size_x = d.length / 2
    e.rotation = V((1, 0, 0)).rotation_difference(d.normalized())
    return e


# ------------------------------------------------------------------ lights / camera
def light(kind, loc, energy, color, size=0.2, target=None, spot=None, blend=0.4):
    d = bpy.data.lights.new(kind, kind)
    d.energy = energy
    d.color = color
    if kind in ("POINT", "SPOT"):
        d.shadow_soft_size = size
    if kind == "AREA":
        d.size = size
    if kind == "SUN":
        d.angle = R(size)
    if spot:
        d.spot_size = R(spot)
        d.spot_blend = blend
    o = bpy.data.objects.new(kind, d)
    COL.objects.link(o)
    o.location = loc
    if target is not None:
        o.rotation_euler = (V(target) - V(loc)).to_track_quat("-Z", "Y").to_euler()
    return o


def camera(loc, target, lens=35, focus=None, fstop=2.8):
    c = bpy.data.cameras.new("C")
    c.lens = lens
    o = bpy.data.objects.new("C", c)
    COL.objects.link(o)
    o.location = loc
    o.rotation_euler = (V(target) - V(loc)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = o
    if focus is not None:
        c.dof.use_dof = True
        c.dof.focus_distance = (V(focus) - V(loc)).length
        c.dof.aperture_fstop = fstop
    return o


def catmull(pts, n=30):
    P = [pts[0]] + pts + [pts[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-1].copy())
    return out


def resample(line, step):
    out = [line[0].copy()]
    prev = line[0].copy()
    need = step
    for p in line[1:]:
        seg = (p - prev).length
        while seg >= need:
            prev = prev.lerp(p, need / seg)
            out.append(prev.copy())
            seg = (p - prev).length
            need = step
        need -= seg
        prev = p.copy()
    return out




# ================================================================== shared extras
def no_shadow(*objs):
    for o in objs:
        o.visible_shadow = False


def subsurf(o, lvl=2):
    md = o.modifiers.new("s", "SUBSURF")
    md.levels = md.render_levels = lvl
    return o


def solid(o, t):
    md = o.modifiers.new("t", "SOLIDIFY")
    md.thickness = t
    return o


def flat(pts, y, m, t=0.004):
    """A flat cut-paper shape in the XZ plane at depth y (faces -Y)."""
    vs = [(x, y, z) for x, z in pts]
    o = mesh_obj(vs, [list(range(len(vs)))], m, "cut")
    return solid(o, t)


def disc_pts(cx, cz, r, n=32, a0=0.0, a1=2 * math.pi):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cz + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def star_pts(cx, cz, r1, r2, n=5):
    return [(cx + (r1 if i % 2 == 0 else r2) * math.cos(math.pi / 2 + i * math.pi / n),
             cz + (r1 if i % 2 == 0 else r2) * math.sin(math.pi / 2 + i * math.pi / n)) for i in range(2 * n)]


def grid(nx, ny, fn, m, name="grid"):
    """A (nx+1) x (ny+1) grid; fn(u, v) -> (x, y, z) with u, v in 0..1."""
    vs, fs = [], []
    for j in range(ny + 1):
        for i in range(nx + 1):
            vs.append(fn(i / nx, j / ny))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            fs.append((a, a + 1, a + nx + 2, a + nx + 1))
    o = mesh_obj(vs, fs, m, name)
    for f in o.data.polygons:
        f.use_smooth = True
    return o


def transparent_mix(name, color, alpha, emit=None, es=0.0, rough=0.3):
    m = pbr(name, color, rough, emit=emit, es=es)
    m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = alpha
    return m



# ================================================================== render setup
def setup_render(samples, res, denoise=True):
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
    sc.cycles.use_denoising = denoise
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100


# ================================================================== props (one source for picture and IoU)
def relief(o, s):
    """Squash an object's depth (Y, about its origin) to s while keeping its round shading normals."""
    me = o.data
    nrm = [tuple(n.vector) for n in me.corner_normals]
    for v in me.vertices:
        v.co.y *= s
    me.normals_split_custom_set(nrm)
    return o


def build_cup(x, y, m=None, rim=None, oval=None):
    """Upturned teacup (sp_common.CUP_*), footprint centre (x, y). A relief: shallow in depth with round shading
    normals, so its shadow stays the planar silhouette under an oblique lantern. Handle ring in the paper's plane."""
    oval = G.CUP_RELIEF if oval is None else oval
    parts = [relief(lathe(G.CUP_PROFILE, (x, y, 0), m, steps=64), oval)]
    if rim:
        parts.append(relief(torus((x, y, 0.012), 0.168, 0.004, rim), oval))
    h = G.CUP_HANDLE
    hd = torus((x + h["x"], y, h["z"]), h["major"], h["minor"], m, rot=(90, 0, 0))
    apply_mods(hd)
    bpy.context.view_layer.objects.active = hd
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    for p_ in hd.data.polygons:
        p_.use_smooth = True
    parts.append(relief(hd, min(1.0, oval * 1.5)))
    return parts


def prism(pts_a, pts_b, m, name="prism"):
    """Closed prism between two equal-length rings of points (caps are n-gons)."""
    n = len(pts_a)
    vs = list(pts_a) + list(pts_b)
    fs = [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
    fs += [list(range(n))[::-1], list(range(n, 2 * n))]
    o = mesh_obj(vs, fs, m, name)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return o


def diamond_v(x, y, z0, z1, w0, w1, d):
    """Vertical bar with a diamond (lozenge) section whose side corners lie in the plane y: knife edges left/right.
    d is the depth at the w1 end; the section keeps its shape (depth tapers with width) so the edge angle holds."""
    ring = lambda z, w: [V((x - w / 2, y, z)), V((x, y - d * w / w1 / 2, z)), V((x + w / 2, y, z)), V((x, y + d * w / w1 / 2, z))]
    return ring(z0, w0), ring(z1, w1)


def build_comb(x, y, m=None):
    """Comb standing on its teeth (sp_common.COMB): spine with a tapered handle, lofted from lozenge sections whose
    corners lie in the centre plane (top/bottom edges and both ends are knife edges), and lozenge teeth. So its shadow
    is its planar silhouette (sp_common.comb_outline + teeth)."""
    c = G.COMB
    x0, x1 = -c["length"] / 2, c["length"] / 2
    xs = sorted(set([x0 + 1e-4, x0 + c["handle"], x1 - 1e-4] + [x0 + (x1 - x0) * i / 80 for i in range(1, 80)]
                    + [x1 - c["corner"] * (1 - math.cos(math.radians(a))) for a in range(0, 91, 10)]))
    rings = []
    for px in xs:
        zb, zt = G.comb_profile(px)
        d = min(c["thick"], (zt - zb) / 2.6, 0.75 * (px - x0) + 0.0005, 0.75 * (x1 - px) + 0.0005)
        zm = (zb + zt) / 2
        rings.append([V((x + px, y, zt)), V((x + px, y - d / 2, zm)), V((x + px, y, zb)), V((x + px, y + d / 2, zm))])
    vs = [v for r in rings for v in r]
    fs = []
    for i in range(len(rings) - 1):
        a0, a1 = 4 * i, 4 * (i + 1)
        for k in range(4):
            fs.append([a0 + k, a1 + k, a1 + (k + 1) % 4, a0 + (k + 1) % 4])
    fs.append([3, 2, 1, 0])
    n = 4 * (len(rings) - 1)
    fs.append([n, n + 1, n + 2, n + 3])
    sp = mesh_obj(vs, fs, m, "spine")
    bpy.context.view_layer.objects.active = sp
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = [sp]
    zb = c["top"] - c["spine"]
    for tx in G.comb_teeth_x():
        r0, r1 = diamond_v(x + tx, y, 0.0, zb + 0.02, c["tooth"] * c["tooth_tip"], c["tooth"], c["tooth_depth"])
        parts.append(prism(r0, r1, m, "tooth"))
    return parts


def build_ladder(x, y, m=None):
    """Toy ladder (sp_common.LADDER): lozenge-section rails (knife edges in the centre plane) and lozenge rungs."""
    L = G.LADDER
    parts = []
    for s in (-1, 1):
        r0, r1 = diamond_v(x + s * L["w"], y, L["h"], 0.0, L["rail"] * L["rail_top"], L["rail"], L["rail_d"])
        parts.append(prism(r0, r1, m, "rail"))
    w, rung, rd = L["w"], L["rung"], L["rung_d"]
    for z in G.ladder_rung_z():
        ring = lambda xx: [V((xx, y, z - rung / 2)), V((xx, y - rd / 2, z)), V((xx, y, z + rung / 2)), V((xx, y + rd / 2, z))]
        parts.append(prism(ring(x - w), ring(x + w), m, "rung"))
    return parts


def to_mesh(o):
    """A curve object (tube) as a mesh, so it can be joined and reliefed."""
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")
    return bpy.context.object


def rod(a, b, r, m, verts=12):
    """A straight round rod from point a to point b."""
    a, b = V(a), V(b)
    return cone_dir(a, b - a, r, (b - a).length, m, verts=verts, r2=r)


def build_mouse(x, y, M=None, rel=None):
    """Tin clockwork mouse (sp_common.MOUSE), nose to +x, built from the numbers of sp_common.silhouette("mouse"): an
    elliptical dome on a low chassis with wheels, a nose cone, a brass winding key and a wire tail. A relief like the
    cup (depth squashed to MOUSE["relief"], round shading normals kept), so its shadow is its planar outline."""
    mm = G.MOUSE
    rel = mm["relief"] if rel is None else rel
    g = (lambda k: M[k]) if M else (lambda k: None)
    rx, rz, zc = mm["rx"], mm["rz"], mm["zc"]
    n = 24
    prof = [(0.0, zc)] + [(rx * math.cos(math.pi / 2 * i / n), zc + rz * math.sin(math.pi / 2 * i / n)) for i in range(n + 1)]
    parts = [lathe(prof, (0, 0, 0), g("tin"), steps=64)]
    parts.append(box((0, 0, zc / 2), (0.34, 0.3, zc), g("tindark"), bevel=0.004))          # chassis
    for wx in (-0.11, 0.11):                                                               # wheels
        parts.append(cyl((wx, 0, 0.018), 0.018, 0.34, g("tindark"), rot=(90, 0, 0), verts=24))
    parts.append(cone_dir((0.14, 0, 0.085), (0.15, 0, -0.035), 0.056, 0.154, g("tinnose"), verts=32))   # nose
    parts.append(sphere((0.1, -0.05, 0.15), 0.014, g("eye"), sub=2))                     # eye (inside the outline)
    parts.append(cyl((-0.2325, 0, 0.135), 0.01, 0.045, g("brass"), rot=(0, 90, 0), verts=16))  # key stem
    for cz in (0.1, 0.17):                                                                 # key bow: two lobes
        parts.append(cyl((-0.287, 0, cz), 0.032, 0.012, g("brass"), rot=(90, 0, 0), verts=32))
    tail = tube([(-0.19, 0, 0.04), (-0.25, 0, 0.03), (-0.30, 0, 0.04), (-0.34, 0, 0.07)], 0.008, g("tindark"))
    tail.data.splines[0].type = "POLY"
    parts.append(to_mesh(tail))
    o = join(parts, "mouse")
    relief(o, rel)
    o.location = (x, y, 0)
    return [o]


def build_balloon(x, y, M=None, rel=None, string=True):
    """Toy hot-air balloon (sp_common.BALLOON) from the numbers of sp_common.silhouette("balloon"): wicker basket, two
    ropes, a flared neck, a striped silk envelope (12 gores) and, for the game, the string it hangs on from the fly bar
    (not in the silhouette: a 3 mm thread's shadow is not drawn). A relief like the cup."""
    b = G.BALLOON
    rel = b["relief"] if rel is None else rel
    g = (lambda k: M[k]) if M else (lambda k: None)
    d = 0.1
    ring = lambda z, w: [V((-w, -d / 2, z)), V((w, -d / 2, z)), V((w, d / 2, z)), V((-w, d / 2, z))]
    parts = [prism(ring(0.0, 0.055), ring(0.07, 0.06), g("wicker"), "basket")]
    parts.append(box((0, 0, 0.072), (0.124, d + 0.008, 0.008), g("wicker")))               # basket rim
    for sx in (-1, 1):
        parts.append(rod((sx * 0.0475, 0, 0.07), (sx * 0.0925, 0, 0.19), 0.0075, g("rope")))
    parts.append(cone((0, 0, 0.175), 0.05, 0.1, 0.05, g("silk_b"), verts=32))              # neck
    n = 24
    prof = [(1e-4 + b["rx"] * math.cos(a), b["zc"] + b["rz"] * math.sin(a))
            for a in [-math.pi / 2 + math.pi * i / n for i in range(n + 1)]]
    env = lathe(prof, (0, 0, 0), g("silk_a"), steps=48)
    if M:                                                                                  # 12 gores, red and cream
        env.data.materials.append(g("silk_b"))
        for f in env.data.polygons:
            c = f.center
            a = math.atan2(c.y, c.x) % (2 * math.pi)
            f.material_index = int(a / (2 * math.pi) * 12) % 2
    parts.append(env)
    if string:
        top = b["zc"] + b["rz"]
        parts.append(cyl((0, 0, top + 1.6), 0.003, 3.2, g("rope"), verts=8))
    o = join(parts, "balloon")
    relief(o, rel)
    o.location = (x, y, 0)
    return [o]


def silhouette_obj(name, x, y, m=None):
    """The shared silhouette (sp_common.silhouette) as a flat mesh in the plane y, anchor at x: the shadow caster."""
    vs, fs = [], []
    for poly in G.silhouette(name):
        b = len(vs)
        vs += [(x + px, y, pz) for px, pz in poly]
        fs.append(list(range(b, b + len(poly))))
    return mesh_obj(vs, fs, m, name + "_silhouette")


PROP_BUILD = {"ladder": build_ladder, "cup": build_cup, "comb": build_comb, "mouse": build_mouse, "balloon": build_balloon}


def join(parts, name):
    for o in parts:
        apply_mods(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.object
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.name = name
    return o


def flattened_copy(o, plane_y, name):
    """The prop's one authored silhouette: its orthographic outline along +Y, in the plane y = plane_y."""
    c = o.copy()
    c.data = o.data.copy()
    COL.objects.link(c)
    for v in c.data.vertices:
        v.co.y = plane_y + (v.co.y + o.location.y - plane_y) * 1e-4 - c.location.y
    c.name = name
    return c


# ================================================================== mode: iou
def img_array(path):
    import numpy as np
    im = bpy.data.images.load(path)
    w, h = im.size
    a = np.empty(w * h * 4, dtype=np.float32)
    im.pixels.foreach_get(a)
    bpy.data.images.remove(im)
    return a.reshape(h, w, 4)[:, :, 0]


def run_iou(report):
    import numpy as np
    setup_render(8, (100, 100), denoise=False)
    sc.cycles.max_bounces = 0
    sc.cycles.use_adaptive_sampling = False
    sc.render.image_settings.file_format = "OPEN_EXR"
    sc.view_settings.view_transform = "Standard"
    white = pbr("white", (0.8, 0.8, 0.8), 1.0)
    plane((0, G.SY + 0.001, 3.0), 40.0, 6.0, white, rot=(90, 0, 0))
    lamp = light("POINT", (0, -1, G.LZ), 60.0, (1, 1, 1), size=0.0005)
    ppu = 250          # pixels per stage unit; the window is fitted round each predicted shadow
    cam = bpy.data.cameras.new("O")
    cam.type = "ORTHO"
    co = bpy.data.objects.new("O", cam)
    COL.objects.link(co)
    co.rotation_euler = (R(90), 0, 0)
    sc.camera = co

    def window(lx, ly, py, obj):
        """Fit the ortho camera round the planar shadow of obj (+ margin); returns (u0, v0)."""
        k = G.k_of(ly, py)
        ws = [obj.matrix_world @ v.co for v in obj.data.vertices]
        u0 = lx + k * (min(w.x for w in ws) - lx) - 0.25
        u1 = lx + k * (max(w.x for w in ws) - lx) + 0.25
        v1_ = G.LZ + k * (max(w.z for w in ws) - G.LZ) + 0.25
        nx, ny = int((u1 - u0) * ppu), int(v1_ * ppu)
        sc.render.resolution_x, sc.render.resolution_y = nx, ny
        cam.ortho_scale = max(nx, ny) / ppu
        co.location = (u0 + nx / ppu / 2, G.SY - 6, ny / ppu / 2)
        return u0
    tmp = os.path.join(os.path.dirname(os.path.abspath(report)), "iou_tmp")
    os.makedirs(tmp, exist_ok=True)

    variants = [
        ("cup round (concept shape)", lambda x, y: build_cup(x, y, oval=1.0)),
        ("cup relief 5% (final)", lambda x, y: build_cup(x, y, oval=0.05)),
        ("comb lozenge (final)", lambda x, y: build_comb(x, y)),
        ("ladder round dowels (concept shape)", lambda x, y: [cyl((x + s_ * 0.115, y, 0.475), 0.014, 0.95, None, verts=12)
            for s_ in (-1, 1)] + [cyl((x, y, 0.1 + i * 0.13), 0.009, 0.23, None, rot=(0, 90, 0), verts=10) for i in range(7)]),
        ("ladder lozenge (final)", lambda x, y: build_ladder(x, y)),
        ("mouse relief (final)", lambda x, y: build_mouse(x, y)),
        ("balloon relief (final)", lambda x, y: build_balloon(x, y, string=False)),
    ]
    vars_ = os.environ.get("SP_IOU_VARIANTS")
    if vars_:
        variants = [v for v in variants if v[0] in vars_.split(";")]
    lx0, lx1 = G.LANTERN_X
    lyf, lyn = G.LANTERN_Y
    lpos = [(lx0, lyf), (lx1, lyf), (0.0, (lyf + lyn) / 2), (lx0, lyn), (lx1, lyn)]

    count = [0]

    def shot(name):
        count[0] += 1
        p = os.path.join(tmp, "%s_%04d.exr" % (name, count[0]))
        sc.render.filepath = p
        for attempt in range(4):
            try:
                bpy.ops.render.render(write_still=True)
                break
            except RuntimeError as e:  # transient Windows file locks on the EXR
                print("retry render", attempt, e, flush=True)
        a = img_array(p)
        try:
            os.remove(p)
        except OSError:
            pass
        return a

    rows = []
    for vname, fn in variants:
        key = vname.split()[0]
        py = G.PROPS[key]["y"]
        tx0, tx1 = G.PROPS[key]["x"]
        res = [[] for _ in lpos]
        tops = []
        for px in (tx0, (tx0 + tx1) / 2, tx1):
            real = join(fn(px, py), "real")
            flat_ = silhouette_obj(key, px, py)   # the shared silhouette (sp_common), what the game draws
            zmax = max((real.matrix_world @ v.co).z for v in real.data.vertices)
            for o in (real, flat_):
                o.visible_camera = False
            for i, (lx, ly) in enumerate(lpos):
                lamp.location = (lx, ly, G.LZ)
                window(lx, ly, py, flat_)
                real.hide_render, flat_.hide_render = True, True
                ref = shot("ref")
                valid = ref > 1e-4 * ref.max()
                ref = np.maximum(ref, 1e-6)
                real.hide_render, flat_.hide_render = False, True
                a = (shot("a") / ref < 0.5) & valid
                real.hide_render, flat_.hide_render = True, False
                b = (shot("b") / ref < 0.5) & valid
                inter, uni = np.logical_and(a, b).sum(), np.logical_or(a, b).sum()
                if uni < 50:  # shadow entirely off the paper: nothing to compare
                    print("IOU", vname, px, lx, ly, "off-screen", flush=True)
                    continue
                iou = inter / uni
                # planar formula check: top of the flattened shadow vs lz + k (zmax - lz)
                rowsb = np.where(b.any(axis=1))[0]
                rowsa = np.where(a.any(axis=1))[0]
                k = G.k_of(ly, py)
                top_formula = G.LZ + k * (zmax - G.LZ)
                top_b = (rowsb.max() + 1) / ppu if len(rowsb) else -1
                top_a = (rowsa.max() + 1) / ppu if len(rowsa) else -1
                res[i].append((iou, px, k, top_formula, top_b, top_a))
                print("IOU", vname, px, lx, ly, round(iou, 4), "k", round(k, 3), "top formula/planar/true",
                      round(top_formula, 3), round(top_b, 3), round(top_a, 3), flush=True)
            bpy.data.objects.remove(real)
            bpy.data.objects.remove(flat_)
        rows.append((vname, res))
    with open(report, "w") as f:
        f.write("# Shadow model IoU (true Cycles prop shadow vs planar silhouette)\n\n")
        f.write("Lantern z %.2f; positions (x, y): %s\n\n" % (G.LZ, ", ".join("(%.2f, %.2f)" % p for p in lpos)))
        f.write("Each cell: worst IoU over the prop at its track min / centre / max x, measured on the screen plane "
                "(window fitted round each whole shadow, on or off the paper) at %d px per unit; k in brackets.\n\n" % ppu)
        f.write("| prop | " + " | ".join("L%d" % (i + 1) for i in range(len(lpos))) + " | worst | worst top-edge error |\n")
        f.write("|---" * (len(lpos) + 3) + "|\n")
        for vname, res in rows:
            cells = []
            worst, terr = 1.0, 0.0
            for r in res:
                if not r:
                    cells.append("off")
                    continue
                m = min(t[0] for t in r)
                worst = min(worst, m)
                terr = max(terr, max(abs(t[5] - t[4]) for t in r))
                cells.append("%.3f (k %.2f)" % (m, r[0][2]))
            f.write("| %s | %s | %.3f | %.3f |\n" % (vname, " | ".join(cells), worst, terr))
        f.write("\nPlanar-construction check (top of flattened-silhouette shadow vs formula lz + k (h - lz)):\n\n")
        for vname, res in rows:
            d = max([abs(t[3] - t[4]) for r in res for t in r if t[4] > 0] or [0])
            f.write("- %s: max |formula - render| = %.4f units (pixel = %.4f)\n" % (vname, d, 1 / ppu))
    print("wrote", report)


# ================================================================== the theatre (static: baked into the backdrop)
PROS_TOP = 2.78          # bottom of the header board = top of valance and curtains
CANDLE = (G.CANDLE[0], G.CANDLE[1], 0.0)
LANTERN_W = G.LANTERN_W
FILL_W = 14.0          # stage bounce on the paper: low, so the lantern's pool and falloff show (review note 1)
GOLD_EMIT = 0.12


def materials():
    M = {}
    wd = TH["wood"]
    M["wood"] = pbr("wood", wd, 0.4, coat=0.35, tint2=tuple(c * 0.55 for c in wd), tex="wave", scale=5, bump=0.03)
    M["boards"] = pbr("boards", (0.32, 0.17, 0.08), 0.55, tint2=(0.2, 0.1, 0.045), tex="wave", scale=2.5, bump=0.08)
    if TH["trim"] == "silver":                  # pewter trim on the moonlit set
        M["brass"] = pbr("brass", (0.72, 0.74, 0.78), 0.3, metal=1.0, fine=0.1)
    else:
        M["brass"] = pbr("brass", (0.82, 0.56, 0.26), 0.28, metal=1.0, fine=0.1)
    M["velvet"] = pbr("velvet", TH["velvet"], 0.75, sheen=1.0, fine=0.25, fine_scale=120)
    M["paper"] = pbr("paper", TH["paper"], 0.9, tint2=TH["paper2"], scale=3, fine=0.12, fine_scale=90)
    M["cutp"] = pbr("cutpaper", (0.035, 0.025, 0.02), 0.85, fine=0.15, fine_scale=90)
    M["redp"] = pbr("redpaper", (0.32, 0.05, 0.03), 0.8, fine=0.15, fine_scale=90)
    # painted gold paper: its own emissive floor so stars stay bright wherever the lantern is (review note 3)
    M["goldp"] = pbr("goldpaper", (0.9, 0.62, 0.22), 0.35, metal=0.55, emit=(1.0, 0.55, 0.12), es=GOLD_EMIT)
    M["glass"] = pbr("glass", (1.0, 0.97, 0.92), 0.02, trans=1.0)
    M["flame"] = glow("flame", (1.0, 0.52, 0.16), 40.0)
    M["wax"] = pbr("wax", (0.88, 0.8, 0.66), 0.45, sss=0.12)
    M["china"] = pbr("china", (0.92, 0.9, 0.85), 0.12, coat=0.6)
    M["toy"] = pbr("toywood", (0.55, 0.32, 0.14), 0.5, tint2=(0.4, 0.2, 0.08), tex="wave", scale=40)
    M["horn"] = pbr("horn", (0.05, 0.018, 0.008), 0.25, coat=0.8, tint2=(0.32, 0.14, 0.03), tex="voronoi", scale=18)
    M["plaque"] = pbr("plaque", (0.11, 0.045, 0.022), 0.35, coat=0.5, tint2=(0.1, 0.04, 0.02), tex="wave", scale=6)
    M["groove"] = pbr("groove", (0.012, 0.008, 0.006), 0.9)
    M["railbrass"] = pbr("railbrass", (0.55, 0.38, 0.18), 0.5, metal=0.6)
    M["backwall"] = pbr("backwall", (0.02, 0.012, 0.01), 0.9, fine=0.2, fine_scale=60)
    # the nursery's clockwork mouse: lacquered tin, a pink nose, a jet eye (brass key: M["brass"])
    M["tin"] = pbr("tin", (0.5, 0.53, 0.58), 0.32, metal=0.45, coat=0.5, tint2=(0.4, 0.43, 0.48), scale=30, fine=0.08)
    M["tindark"] = pbr("tindark", (0.16, 0.16, 0.18), 0.4, metal=0.5)
    M["tinnose"] = pbr("tinnose", (0.78, 0.42, 0.42), 0.35, coat=0.5)
    M["eye"] = pbr("eye", (0.01, 0.01, 0.01), 0.1, coat=1.0)
    # the fair's balloon: red and cream silk gores, a wicker basket, hemp ropes and string
    M["silk_a"] = pbr("silk_a", (0.62, 0.07, 0.05), 0.45, sheen=0.5, fine=0.08, fine_scale=140)
    M["silk_b"] = pbr("silk_b", (0.86, 0.76, 0.55), 0.45, sheen=0.5, fine=0.08, fine_scale=140)
    M["wicker"] = pbr("wicker", (0.45, 0.28, 0.12), 0.7, tint2=(0.25, 0.14, 0.05), tex="wave", scale=90, bump=0.05)
    M["rope"] = pbr("rope", (0.62, 0.52, 0.36), 0.8)
    return M


def theatre(M):
    """Everything that never moves in any level. Returns (paper screen + floor boards, all objects made)."""
    before = set(bpy.data.objects)
    SY = G.SY
    y0, y1 = G.FLOOR_Y
    floor = []
    for i in range(16):
        x = -3.2 + 0.4 * i + 0.2
        floor.append(box((x, (y0 + y1) / 2, -0.06), (0.395, y1 - y0, 0.12), M["boards"], bevel=0.006))
    box((0, -1.84, -0.32), (6.6, 0.2, 0.64), M["wood"], bevel=0.02)
    box((0, -1.95, -0.04), (6.6, 0.03, 0.05), M["brass"], bevel=0.008)
    # paper screen (front face on y = SY), its frame and the dark back wall
    W, H = G.SCREEN_U[1] - G.SCREEN_U[0], G.SCREEN_V[1]
    # the paper reaches 10 cm below the floor top: the boards' bevelled back edge must not open a slit onto the back wall
    screen = box((0, SY + 0.01, (H - 0.1) / 2), (W, 0.02, H + 0.1), M["paper"])
    for x in (-W / 2 - 0.06, W / 2 + 0.06):
        box((x, SY + 0.0, H / 2 + 0.06), (0.12, 0.06, H + 0.12), M["wood"], bevel=0.01)
    box((0, SY + 0.0, H + 0.06), (W + 0.24, 0.06, 0.12), M["wood"], bevel=0.01)
    box((0, SY + 0.45, 2.0), (30.0, 0.05, 14.0), M["backwall"])   # wide: no world shows in any bake
    # proscenium
    for s_ in (-1, 1):
        x = s_ * 2.84
        box((x, -1.55, (PROS_TOP + 0.5) / 2), (0.42, 0.34, PROS_TOP + 0.5), M["wood"], bevel=0.03)
        box((x, -1.55, 0.08), (0.52, 0.42, 0.16), M["wood"], bevel=0.02)
        for z in (0.55, 1.45, 2.35):
            cyl((x, -1.73, z), 0.06, 0.03, M["brass"], rot=(90, 0, 0), bevel=0.008)
            sphere((x, -1.75, z), 0.03, M["brass"])
    box((0, -1.55, PROS_TOP + 0.25), (6.2, 0.36, 0.5), M["wood"], bevel=0.03)
    box((0, -1.74, PROS_TOP + 0.25), (5.4, 0.03, 0.26), M["brass"], bevel=0.01)
    for x in (-2.3, -1.15, 0, 1.15, 2.3):
        sphere((x, -1.77, PROS_TOP + 0.25), 0.05, M["brass"])
    text(TH["header"], (0, -1.765, PROS_TOP + 0.25), 0.16, M["wood"], fnt=font("georgiab.ttf", "timesbd.ttf"), extrude=0.004,
         rot=(90, 0, 0))

    def curtain(s_):
        def f(u, v):
            z = PROS_TOP * v
            outer = s_ * 2.66
            tie = 1.0
            k = math.exp(-((z - tie) / 0.5) ** 2)
            inner = s_ * (2.02 + 0.42 * k + 0.1 * (1 - v))
            x = outer + (inner - outer) * u
            y = -1.38 + 0.06 * math.sin(u * 13 * math.pi) * (0.6 + 0.6 * k) - 0.05 * k
            return (x, y, z)
        o = grid(80, 60, f, M["velvet"], "curtain")
        solid(o, 0.012)
        tube([V((s_ * 2.62, -1.5, 1.0)), V((s_ * 2.5, -1.47, 0.96)), V((s_ * 2.36, -1.42, 1.0))], 0.022, M["brass"])
        sphere((s_ * 2.5, -1.49, 0.9), 0.035, M["brass"], scale=(1, 1, 1.4))
    curtain(-1)
    curtain(1)

    def valance(u, v):
        x = -2.66 + 5.32 * u
        sc_ = 0.1 * abs(math.sin(u * 7 * math.pi))
        z = PROS_TOP - (0.36 - sc_) * (1 - v)
        y = -1.43 + 0.04 * math.sin(u * 70 * math.pi)
        return (x, y, z)
    solid(grid(400, 8, valance, M["velvet"], "valance"), 0.012)
    for i in range(210):
        u = i / 209
        x = -2.66 + 5.32 * u
        z = PROS_TOP - (0.36 - 0.1 * abs(math.sin(u * 7 * math.pi)))
        cyl((x, -1.45, z - 0.035), 0.006, 0.07, M["brass"], verts=6)
    # brass-edged plaque on the apron, where the HUD will sit (review note 5), and a low house light on it
    box((0, -1.952, -0.215), (3.4, 0.012, 0.3), M["brass"], bevel=0.006)
    box((0, -1.96, -0.215), (3.34, 0.012, 0.24), M["plaque"], bevel=0.004)
    for x in (-1.6, 1.6):
        sphere((x, -1.965, -0.215), 0.022, M["brass"])
    light("SPOT", (0.0, -4.8, 0.9), 90.0, (1.0, 0.78, 0.55), size=0.4, target=(0.0, -1.95, -0.2), spot=40, blend=0.8)
    for s_ in (-1, 1):
        light("SPOT", (s_ * 1.6, -5.2, 3.6), 45.0 if TH["id"] == "stage" else 60.0, TH["spot"], size=0.3,
              target=(s_ * 2.55, -1.45, 1.4), spot=15, blend=0.6)
    dressing(M, TH["dressing"])
    # stage bounce on the paper only (lifts shadows to warm grey; static, so it is part of the baked screen and of
    # the flat colour of the engine's shadow cards)
    fill = bpy.data.lights.new("fill", "AREA")
    fill.energy, fill.size, fill.color = FILL_W, 5.0, TH["fill"]
    fo = bpy.data.objects.new("fill", fill)
    COL.objects.link(fo)
    fo.location = (0.0, -4.0, 1.4)
    fo.rotation_euler = (R(90), 0, 0)
    fo.light_linking.receiver_collection = link_collection("lk_paper", [screen])
    return [screen] + floor, [o for o in bpy.data.objects if o not in before]


def dressing(M, kind):
    """Each stage set's own dressing, inside the play frame's border only: the floor corners in front of the curtains
    and the curtains' fronts (the proscenium columns are out of frame since the reframe for play)."""
    if kind is None:
        return
    # a soft light on the valance so the dressing up there reads (the house spots only reach the curtains)
    light("SPOT", (0.0, -5.5, 3.2), 70.0, TH["spot"], size=0.6, target=(0.0, -1.45, PROS_TOP - 0.25), spot=35, blend=0.7)
    if kind == "nursery":
        # painted toy blocks stacked on both floor corners; a silver crescent and stars on threads before each curtain
        cols = [(0.55, 0.08, 0.06), (0.08, 0.22, 0.5), (0.85, 0.62, 0.12), (0.12, 0.4, 0.2)]
        k = 0
        for s_ in (-1, 1):
            x = s_ * 2.42
            for dx, dy, z, sz, rz in ((0.0, 0.0, 0.0, 0.15, 8), (s_ * -0.17, 0.05, 0.0, 0.13, -14), (s_ * -0.05, 0.02, 0.15, 0.12, 22)):
                m = pbr("block%d" % k, cols[k % 4], 0.45, coat=0.4)
                box((x + dx, -1.6 + dy, z + sz / 2), (sz, sz, sz), m, rot=(0, 0, rz), bevel=0.012)
                k += 1
            th = M["brass"]
            hx = s_ * 2.33
            cyl((hx, -1.52, 2.5), 0.0015, 0.36, th, verts=6)
            moon = crescent_pts(0, 0, 0.1, 0.04, 0.028, 0.09)
            flat([(hx + px, pz + 2.22) for px, pz in moon], -1.52, th, 0.012)
            for dz, dx in ((1.86, -s_ * 0.09), (1.62, s_ * 0.06)):
                cyl((hx + dx, -1.52, dz + 0.32), 0.0012, 0.6, th, verts=6)
                flat(star_pts(hx + dx, dz, 0.045, 0.02), -1.52, th, 0.01)
    elif kind == "fair":
        # striped bunting along the valance's lower edge; a sheaf of wheat and pumpkins on both floor corners
        cols = [(0.62, 0.08, 0.05), (0.85, 0.62, 0.12), (0.9, 0.85, 0.7), (0.1, 0.3, 0.14)]
        mats = [pbr("flag%d" % i, c, 0.7, sheen=0.4) for i, c in enumerate(cols)]
        n = 28
        sag = lambda u: 0.07 * math.sin(math.pi * ((u * 4) % 1.0))
        for i in range(n):
            u0, u1 = i / n, (i + 0.85) / n
            x0, x1 = -2.4 + 4.8 * u0, -2.4 + 4.8 * u1
            zt0, zt1 = PROS_TOP - 0.3 - sag(u0), PROS_TOP - 0.3 - sag(u1)
            flat([(x0, zt0), (x1, zt1), ((x0 + x1) / 2, (zt0 + zt1) / 2 - 0.12)], -1.47, mats[i % 4], 0.004)
        rope = pbr("rope", (0.45, 0.34, 0.2), 0.8)
        tube([V((-2.4 + 4.8 * u / 200, -1.465, PROS_TOP - 0.3 - sag(u / 200))) for u in range(201)], 0.004, rope)
        straw = pbr("straw", (0.75, 0.55, 0.2), 0.7, tint2=(0.55, 0.38, 0.12), tex="wave", scale=30)
        pump = pbr("pumpkin", (0.75, 0.28, 0.04), 0.5, coat=0.3)
        stem = pbr("stem", (0.18, 0.2, 0.06), 0.7)
        for s_ in (-1, 1):
            x = s_ * 2.45
            for i in range(26):
                a = (i - 13) * 0.045
                cyl((x + math.sin(a) * 0.15, -1.62, 0.2 + math.cos(a) * 0.08), 0.005, 0.36, straw, rot=(0, math.degrees(a), 0), verts=6)
                sphere((x + math.sin(a) * 0.33, -1.62, 0.2 + math.cos(a) * 0.26), 0.016, straw, scale=(0.7, 0.7, 1.8))
            torus((x, -1.62, 0.2), 0.045, 0.011, rope, rot=(90, 0, 0))
            for dx, r in ((s_ * -0.2, 0.07), (s_ * -0.31, 0.05)):
                sphere((x + dx, -1.58, r * 0.8), r, pump, scale=(1.15, 1.15, 0.8))
                cyl((x + dx, -1.58, r * 1.55), 0.008, 0.04, stem, verts=8)


# ================================================================== live pieces
def lantern(M, L):
    F = V((L[0], L[1], G.LZ))
    b = (F.x, F.y, 0)
    parts = [lathe([(0, 0), (0.1, 0), (0.1, 0.018), (0.08, 0.04), (0.046, 0.055), (0, 0.06)], b, M["brass"]),
             lathe([(0.04, 0.055), (0.072, 0.1), (0.078, 0.17), (0.06, 0.25), (0.042, 0.28)], b, M["glass"]),
             lathe([(0.03, 0.27), (0.062, 0.282), (0.052, 0.315), (0.022, 0.335), (0, 0.345)], b, M["brass"]),
             torus((F.x, F.y, 0.385), 0.045, 0.006, M["brass"], rot=(90, 0, 0)),
             sphere(F, 0.016, M["flame"], scale=(1, 1, 2.3)),
             cyl((F.x, F.y, 0.072), 0.012, 0.04, M["brass"])]
    for k in range(3):
        a = k * 2.094 + 0.5
        parts.append(cyl((F.x + 0.086 * math.cos(a), F.y + 0.086 * math.sin(a), 0.168), 0.005, 0.226, M["brass"], verts=8))
    no_shadow(*parts)
    return F, parts


def halo(F, radius, strength, color=(1.0, 0.62, 0.3)):
    """The glow of the air round the flame: a camera-facing additive card (the engine draws one big soft particle)."""
    m = bpy.data.materials.new("halo")
    N, Ln = _nodes(m)
    N.remove(N["Principled BSDF"])
    tc = N.new("ShaderNodeTexCoord")
    gr = N.new("ShaderNodeTexGradient")
    gr.gradient_type = "SPHERICAL"
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.0 / radius, 1.0 / radius, 1.0 / radius)
    Ln.new(tc.outputs["Object"], mp.inputs["Vector"])
    Ln.new(mp.outputs["Vector"], gr.inputs["Vector"])
    pw = N.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 2.2
    Ln.new(gr.outputs["Fac"], pw.inputs[0])
    em = N.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    mul = N.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = strength
    Ln.new(pw.outputs["Value"], mul.inputs[0])
    Ln.new(mul.outputs["Value"], em.inputs["Strength"])
    tr = N.new("ShaderNodeBsdfTransparent")
    add = N.new("ShaderNodeAddShader")
    Ln.new(tr.outputs["BSDF"], add.inputs[0])
    Ln.new(em.outputs["Emission"], add.inputs[1])
    Ln.new(add.outputs["Shader"], N["Material Output"].inputs["Surface"])
    cam = V(G.CAM_POS)
    o = plane(tuple(F), 2 * radius, 2 * radius, m)
    o.rotation_euler = (cam - F).to_track_quat("Z", "Y").to_euler()
    for a in ("visible_diffuse", "visible_glossy", "visible_transmission", "visible_shadow", "visible_volume_scatter"):
        setattr(o, a, False)
    return o


def dust(F, n=90, seed=5):
    rnd = random.Random(seed)
    mote = glow("mote", (1.0, 0.85, 0.6), 1.6)
    out = []
    for _ in range(n):
        t = rnd.uniform(0.12, 0.9)
        tgt = V((rnd.uniform(-2.4, 2.4), G.SY, rnd.uniform(0.05, 2.2)))
        p = F.lerp(tgt, t) + V((rnd.gauss(0, 0.07), rnd.gauss(0, 0.07), rnd.gauss(0, 0.07)))
        if p.z < 0.02:
            continue
        out.append(sphere(p, rnd.uniform(0.002, 0.0045), mote, sub=1))
    no_shadow(*out)
    return out


def props(M, st):
    """The three real props (cast no shadow themselves) and their planar silhouettes (invisible, cast the shadow)."""
    real, casters = [], []
    for name, fn in (("cup", lambda x, y: build_cup(x, y, M["china"], rim=M["goldp"])),
                     ("comb", lambda x, y: build_comb(x, y, M["horn"])),
                     ("ladder", lambda x, y: build_ladder(x, y, M["toy"]))):
        y = G.PROPS[name]["y"]
        o = join(fn(st[name], y), name)
        c = silhouette_obj(name, st[name], y)
        o.visible_shadow = False
        for a in ("visible_camera", "visible_diffuse", "visible_glossy", "visible_transmission"):
            setattr(c, a, False)
        real.append(o)
        casters.append(c)
    return real, casters


def crescent_pts(cx, cz, r, ix, iz, ir, n=160):
    """Outline of the disc (cx, cz, r) minus the disc (ix, iz, ir), as one polygon."""
    def arc(ax, az, ar, keep):
        pts = [(ax + ar * math.cos(2 * math.pi * i / n), az + ar * math.sin(2 * math.pi * i / n)) for i in range(n)]
        flags = [keep(p) for p in pts]
        start = next(i for i in range(n) if flags[i] and not flags[i - 1])
        out = []
        for j in range(n):
            i = (start + j) % n
            if not flags[i]:
                break
            out.append(pts[i])
        return out
    outer = arc(cx, cz, r, lambda p: math.hypot(p[0] - ix, p[1] - iz) > ir)
    inner = arc(ix, iz, ir, lambda p: math.hypot(p[0] - cx, p[1] - cz) < r)
    return outer + inner[::-1]


TRACKED = ("cup", "comb", "ladder", "mouse")            # props on a floor track (the balloon hangs on a string)


def tracks(M, names=("cup", "comb", "ladder"), per=False):
    """Each prop's floor track: a dark groove with dull brass edges, flush with the boards (live: set per level).
    per=True: {name: [objects]}."""
    half = {n: (-G.bbox(n)[0] + 0.02, G.bbox(n)[2] + 0.02) for n in G.PROPS}
    out, by = [], {}
    for name in names:
        tr = G.PROPS[name]
        n0 = len(out)
        x0, x1 = tr["x"][0] - half[name][0], tr["x"][1] + half[name][1]
        y = tr["y"]
        out.append(box(((x0 + x1) / 2, y, 0.0003), (x1 - x0, 0.03, 0.0006), M["groove"]))
        for s_ in (-1, 1):
            out.append(box(((x0 + x1) / 2, y + s_ * 0.0195, 0.0005), (x1 - x0 + 0.008, 0.009, 0.001), M["railbrass"]))
        by[name] = out[n0:]
    return by if per else out


def rails_game(M, names=("cup", "comb", "ladder"), per=False):
    """The game's brass rails: the lines of tracks() with a 3.5 mm face toward the lantern (~3 px like the target; 2 px lines shimmered under TAA) and camera (the target's 1 mm
    rails read as lit 2-3 px lines through Cycles' glossy light; the engine has no IBL, so a face the lantern lights
    directly draws that line, and it fades with the lantern's distance like the target's)."""
    half = {n: (-G.bbox(n)[0] + 0.02, G.bbox(n)[2] + 0.02) for n in G.PROPS}
    out, by = [], {}
    for name in names:
        tr = G.PROPS[name]
        n0 = len(out)
        x0, x1 = tr["x"][0] - half[name][0], tr["x"][1] + half[name][1]
        # the front rail is nearer the camera: thinner, so both draw as the target's ~2 px lines (2026-11-13 crop)
        for s_, dy, dz in ((-1, 0.0055, 0.003), (1, 0.009, 0.0045)):
            out.append(box(((x0 + x1) / 2, tr["y"] + s_ * 0.0195, 0.0035 - dz / 2), (x1 - x0 + 0.008, dy, dz), M["railbrass"]))
        by[name] = out[n0:]
    return by if per else out


def door_and_bonus(M, y, door, bonus):
    """The red arched door with its gold star, and the bonus star (same shapes in every level)."""
    dx, dz = door
    arch = [(dx - 0.11, dz)] + disc_pts(dx, dz + 0.27, 0.11, 16, math.pi, 0)[::-1] + [(dx + 0.11, dz)]
    out = [flat(arch, y - 0.002, M["redp"], 0.003), flat(star_pts(dx, dz + 0.26, 0.055, 0.024), y - 0.004, M["goldp"], 0.002)]
    bx, bz = bonus
    out.append(flat(star_pts(bx, bz, 0.07, 0.03), y - 0.003, M["goldp"], 0.002))
    return out


def map_decor(M, y, mapid, top, dx=-2.42):
    """Each stage set's paper decorations (never ground: gold pieces float high, black ones stand on the start cliff,
    whose top is at `top`, at its far left)."""
    out = []
    if mapid == "nursery":
        # a moon nearer the middle, a sky of small stars, a paper house with a lit window on the start cliff
        out.append(flat(crescent_pts(1.55, 2.02, 0.17, 1.62, 2.06, 0.155), y - 0.001, M["goldp"], 0.002))
        for cx, cz, r in ((-1.9, 2.15, 0.03), (-1.3, 1.95, 0.022), (-0.75, 2.22, 0.034), (-0.2, 2.0, 0.02), (0.3, 2.25, 0.028),
                          (0.8, 1.92, 0.024), (1.05, 2.25, 0.02), (2.2, 2.12, 0.03), (-2.3, 1.7, 0.02), (0.05, 1.72, 0.018)):
            out.append(flat(star_pts(cx, cz, r, r * 0.45), y - 0.001, M["goldp"], 0.002))
        hx = dx + 0.04                        # clear of the puppet's start (x -2.2: it stood inside the house)
        out.append(flat([(hx - 0.1, top - 0.01), (hx + 0.1, top - 0.01), (hx + 0.1, top + 0.14), (hx, top + 0.23),
                         (hx - 0.1, top + 0.14)], y - 0.001, M["cutp"], 0.003))
        out.append(flat([(hx + 0.045, top + 0.17), (hx + 0.07, top + 0.17), (hx + 0.07, top + 0.24), (hx + 0.045, top + 0.24)],
                        y - 0.001, M["cutp"], 0.003))                                  # chimney
        out.append(flat([(hx - 0.04, top + 0.06), (hx + 0.03, top + 0.06), (hx + 0.03, top + 0.12), (hx - 0.04, top + 0.12)],
                        y - 0.003, M["goldp"], 0.002))                                 # lit window
    elif mapid == "fair":
        # a harvest moon, bunting across the top, a paper tent with a pennant on the start cliff
        out.append(flat(disc_pts(-1.55, 2.02, 0.16, 48), y - 0.001, M["goldp"], 0.002))
        for i in range(17):
            cx = -2.3 + i * 0.29
            cz = 2.33 - 0.06 * math.sin(math.pi * i / 16)
            out.append(flat([(cx - 0.06, cz), (cx + 0.06, cz), (cx, cz - 0.11)], y - 0.001, M["goldp" if i % 2 else "redp"], 0.002))
        tx = dx + 0.02                        # clear of the puppet's start
        out.append(flat([(tx - 0.14, top - 0.01), (tx + 0.14, top - 0.01), (tx, top + 0.24)], y - 0.001, M["cutp"], 0.003))
        out.append(flat([(tx - 0.005, top + 0.23), (tx + 0.005, top + 0.23), (tx + 0.005, top + 0.31), (tx - 0.005, top + 0.31)],
                        y - 0.001, M["cutp"], 0.003))
        out.append(flat([(tx + 0.005, top + 0.31), (tx + 0.07, top + 0.29), (tx + 0.005, top + 0.27)], y - 0.003, M["redp"], 0.002))
    else:
        # the reference set: moon, stars and a small tree (target.png)
        mx, mz = G.LEVEL["moon"]
        out.append(flat(crescent_pts(mx, mz, 0.2, mx + 0.075, mz + 0.05, 0.19), y - 0.001, M["goldp"], 0.002))
        for cx, cz, r in ((-0.7, 2.15, 0.04), (-0.1, 1.9, 0.028), (0.5, 2.22, 0.035), (1.1, 1.98, 0.03), (1.75, 2.2, 0.04),
                          (-2.25, 1.6, 0.026), (2.25, 1.85, 0.026)):
            out.append(flat(star_pts(cx, cz, r, r * 0.45), y - 0.001, M["goldp"], 0.002))
        tx = dx - 0.03                        # target.png's tree at -2.12 (dx -2.09); elsewhere clear of the start
        out.append(flat([(tx - 0.025, top - 0.01), (tx - 0.02, top + 0.15), (tx + 0.02, top + 0.15), (tx + 0.025, top - 0.01)],
                        y - 0.001, M["cutp"], 0.003))
        for cx, cz, r in ((tx, top + 0.25, 0.11), (tx + 0.1, top + 0.19, 0.08), (tx - 0.1, top + 0.2, 0.08)):
            out.append(flat(disc_pts(cx, cz, r), y - 0.001, M["cutp"], 0.003))
    return out


def paper_level_of(M, lv, y):
    """One level's cut paper (sp_common.level_data: the rules' own polygons) and its stage set's decorations."""
    d = G.level_data(lv)
    out = [flat(pts, y, M["cutp"], 0.003) for pts in d["solids"]]
    out += [flat(pts, y - 0.001, M["cutp"], 0.003) for pts in d["thorns"]]
    out += door_and_bonus(M, y, d["door"], d["bonus"])
    # the reference level keeps target.png's tree; every other level's decoration stands clear of the puppet's start
    out += map_decor(M, y, lv["map"], d["start"]["puppet"][1], dx=d["decor_x"])
    return out


def paper_level(M, y=None):
    """The level's cut-paper pieces (list of objects; the exporter groups them by material)."""
    y = G.SY - 0.002 if y is None else y
    L = G.LEVEL
    out = [flat(L["left_cliff"], y, M["cutp"], 0.003), flat(L["right_cliff"], y, M["cutp"], 0.003),
           flat(L["ledge"], y, M["cutp"], 0.003)]
    # bramble of paper thorns along the pit floor (sp_common.thorn_polygon: the rules use the same outline)
    pts = G.thorn_polygon()
    out.append(flat(pts, y - 0.001, M["cutp"], 0.003))
    # star door on the right cliff
    dx, dz = L["door"]
    arch = [(dx - 0.11, dz)] + disc_pts(dx, dz + 0.27, 0.11, 16, math.pi, 0)[::-1] + [(dx + 0.11, dz)]
    out.append(flat(arch, y - 0.002, M["redp"], 0.003))
    out.append(flat(star_pts(dx, dz + 0.26, 0.055, 0.024), y - 0.004, M["goldp"], 0.002))
    # bonus star on the ledge, moon and stars
    bx, bz = L["bonus"]
    out.append(flat(star_pts(bx, bz, 0.07, 0.03), y - 0.003, M["goldp"], 0.002))
    mx, mz = L["moon"]
    out.append(flat(crescent_pts(mx, mz, 0.2, mx + 0.075, mz + 0.05, 0.19), y - 0.001, M["goldp"], 0.002))
    for cx, cz, r in ((-0.7, 2.15, 0.04), (-0.1, 1.9, 0.028), (0.5, 2.22, 0.035), (1.1, 1.98, 0.03), (1.75, 2.2, 0.04),
                      (-2.25, 1.6, 0.026), (2.25, 1.85, 0.026)):
        out.append(flat(star_pts(cx, cz, r, r * 0.45), y - 0.001, M["goldp"], 0.002))
    # a small paper tree on the start cliff
    tx = -2.12
    out.append(flat([(tx - 0.025, 0.46), (tx - 0.02, 0.62), (tx + 0.02, 0.62), (tx + 0.025, 0.46)], y - 0.001, M["cutp"], 0.003))
    for cx, cz, r in ((tx, 0.72, 0.11), (tx + 0.1, 0.66, 0.08), (tx - 0.1, 0.67, 0.08)):
        out.append(flat(disc_pts(cx, cz, r), y - 0.001, M["cutp"], 0.003))
    return out


def puppet(M, u, v, phase, y=None):
    """Jointed cut-paper man in a top hat, 0.30 tall, feet at (u, v), facing right; phase 0..1 of the stride."""
    S = 1.33
    y = G.SY - 0.008 if y is None else y
    out = []

    def P(dx, dz):
        return (u + dx * S, v + dz * S)

    def limb(a, b, w):
        dx, dz = b[0] - a[0], b[1] - a[1]
        L_ = math.hypot(dx, dz)
        nx, nz = -dz / L_ * w * S, dx / L_ * w * S
        pts = [(a[0] + nx, a[1] + nz), (b[0] + nx, b[1] + nz), (b[0] - nx, b[1] - nz), (a[0] - nx, a[1] - nz)]
        out.append(flat(pts, y, M["cutp"], 0.003))
    sw = math.sin(phase * 2 * math.pi)
    hip = P(0, 0.078)
    for sgn in (1, -1):
        a = sgn * 0.42 * sw
        knee = (hip[0] + math.sin(a) * 0.04 * S, hip[1] - math.cos(a) * 0.04 * S)
        a2 = a - 0.25 * max(0.0, -sgn * sw)
        foot = (knee[0] + math.sin(a2) * 0.038 * S, max(v, knee[1] - math.cos(a2) * 0.038 * S))
        limb(hip, knee, 0.0095)
        limb(knee, foot, 0.0085)
        limb(foot, (foot[0] + 0.016 * S, foot[1]), 0.005)
    out.append(flat([P(-0.024, 0.072), P(0.022, 0.072), P(0.017, 0.142), P(-0.017, 0.142)], y, M["cutp"], 0.003))
    out.append(flat([P(-0.024, 0.075), P(-0.034, 0.05), P(-0.016, 0.07)], y, M["cutp"], 0.003))  # coat tail
    for sgn in (1, -1):
        sh = P(0.0, 0.132)
        a = -sgn * 0.5 * sw
        hand = (sh[0] + math.sin(a) * 0.06 * S, sh[1] - math.cos(a) * 0.06 * S)
        limb(sh, hand, 0.0065)
    out.append(flat(disc_pts(*P(0.004, 0.163), 0.021 * S), y, M["cutp"], 0.003))
    out.append(flat([P(0.022, 0.165), P(0.034, 0.158), P(0.021, 0.155)], y, M["cutp"], 0.003))  # nose
    out.append(flat([P(-0.03, 0.179), P(0.04, 0.179), P(0.04, 0.187), P(-0.03, 0.187)], y, M["cutp"], 0.003))
    out.append(flat([P(-0.015, 0.186), P(0.023, 0.186), P(0.021, 0.228), P(-0.013, 0.228)], y, M["cutp"], 0.003))
    for px, pz in ((0.0, 0.078), (0.0, 0.132)):
        q = P(px, pz)
        out.append(cyl((q[0], y - 0.006, q[1]), 0.005, 0.004, M["brass"], rot=(90, 0, 0), verts=12))
    return out


def puppet_parts(M):
    """The puppet in jointed pieces for the game: body (torso, coat tail, head, nose, hat; feet at the origin),
    one leg (hip pin at the origin, straight down, foot forward), one arm (shoulder pin at the origin, straight down),
    and the two brass pins. Same outlines and widths as puppet()."""
    P_ = G.PUPPET
    S = P_["scale"]
    y = 0.0

    def P(dx, dz):
        return (dx * S, dz * S)

    def limb(a, b, w, out):
        dx, dz = b[0] - a[0], b[1] - a[1]
        L_ = math.hypot(dx, dz)
        nx, nz = -dz / L_ * w * S, dx / L_ * w * S
        out.append(flat([(a[0] + nx, a[1] + nz), (b[0] + nx, b[1] + nz), (b[0] - nx, b[1] - nz), (a[0] - nx, a[1] - nz)], y,
                        M["cutp"], 0.003))
    body = [flat([P(-0.024, 0.072), P(0.022, 0.072), P(0.017, 0.142), P(-0.017, 0.142)], y, M["cutp"], 0.003),
            flat([P(-0.024, 0.075), P(-0.034, 0.05), P(-0.016, 0.07)], y, M["cutp"], 0.003),
            flat(disc_pts(*P(0.004, 0.163), 0.021 * S), y, M["cutp"], 0.003),
            flat([P(0.022, 0.165), P(0.034, 0.158), P(0.021, 0.155)], y, M["cutp"], 0.003),
            flat([P(-0.03, 0.179), P(0.04, 0.179), P(0.04, 0.187), P(-0.03, 0.187)], y, M["cutp"], 0.003),
            flat([P(-0.015, 0.186), P(0.023, 0.186), P(0.021, 0.228), P(-0.013, 0.228)], y, M["cutp"], 0.003)]
    leg = []
    knee, foot = P(0, -P_["thigh"]), P(0, -P_["thigh"] - P_["shin"])
    limb((0.0, 0.0), knee, 0.0095, leg)
    limb(knee, foot, P_["shin_w"], leg)                    # sp_common: the rules stand the puppet on this width
    limb(foot, (foot[0] + 0.016 * S, foot[1]), 0.005, leg)
    arm = []
    limb((0.0, 0.0), P(0, -P_["arm"]), 0.0065, arm)
    pins = [cyl((q[0], y - 0.006, q[1]), 0.005, 0.004, M["brass"], rot=(90, 0, 0), verts=12)
            for q in (P(0.0, P_["hip"]), P(0.0, P_["shoulder"]))]
    return body, leg, arm, pins


def candle(M, left):
    """Wax left (0..1 of a fresh 0.30 candle) in the static holder, flame and its small light."""
    C = V(CANDLE)
    holder = [lathe([(0, 0), (0.12, 0), (0.125, 0.012), (0.11, 0.02), (0.04, 0.02), (0.035, 0.035), (0, 0.035)], C, M["brass"]),
              torus((C.x + 0.13, C.y, 0.015), 0.03, 0.006, M["brass"], rot=(90, 0, 0))]
    h = 0.035 + 0.30 * left
    out = [lathe([(0, 0.035), (0.045, 0.035), (0.046, h - 0.012), (0.04, h - 0.002), (0.02, h + 0.002), (0, h)], C, M["wax"])]
    for k in range(5):
        a = k * 1.3
        out.append(sphere((C.x + 0.043 * math.cos(a), C.y + 0.043 * math.sin(a), h - 0.025 - k * 0.012), 0.006, M["wax"],
                          scale=(1, 1, 3.2)))
    out.append(cyl((C.x, C.y, h + 0.007), 0.0015, 0.018, M["cutp"], verts=6))
    fl = sphere((C.x, C.y, h + 0.028), 0.011, M["flame"], scale=(1, 1, 2.2))
    no_shadow(fl)
    lt = light("POINT", (C.x, C.y, h + 0.03), 3.0, (1.0, 0.6, 0.3), size=0.02)
    lt.data.use_shadow = False
    return out + [fl] + holder, lt


def link_collection(name, objs):
    c = bpy.data.collections.new(name)
    for o in objs:
        c.objects.link(o)
    return c


def set_camera(res):
    """The game camera at a fixed vertical fov (sensor fit vertical), so 16:9 and 2.4:1 frames share one projection."""
    cam = camera(G.CAM_POS, G.CAM_LOOK, lens=G.CAM_LENS, focus=(0.0, G.SY, 0.5), fstop=2.0)
    cam.data.sensor_fit = "VERTICAL"
    cam.data.sensor_height = 2 * G.CAM_LENS * math.tan(math.radians(G.VFOV / 2))
    sc.render.resolution_x, sc.render.resolution_y = res
    return cam


def lantern_lights(F, planes, static, casters):
    """Lantern light, split so Cycles draws exactly what the engine will:
    A lights only the paper and the floor; only the shared planar silhouettes block it (the game's shadow cards).
    B lights the live pieces with no shadows (engine point lights cast none).
    C lights the static theatre with ordinary shadows (the game shows it through the baked front cards)."""
    la = light("POINT", F, LANTERN_W, (1.0, 0.62, 0.3), size=G.LIGHT_D / 2)   # radius: the shadows' penumbra
    la.light_linking.receiver_collection = link_collection("lk_planes", planes)
    la.light_linking.blocker_collection = link_collection("lk_casters", casters)
    lb = light("POINT", F, LANTERN_W, (1.0, 0.62, 0.3), size=0.004)
    lb.data.use_shadow = False
    live = [o for o in bpy.data.objects if o.type == "MESH" and o not in static and o not in casters]
    lb.light_linking.receiver_collection = link_collection("lk_live", live)
    lc = light("POINT", F, LANTERN_W, (1.0, 0.62, 0.3), size=0.004)
    lc.light_linking.receiver_collection = link_collection("lk_static", [o for o in static if o not in planes])


def build_frame(mode):
    M = materials()
    world_sky((0.012, 0.009, 0.008), (0.004, 0.003, 0.003), 1.0)
    planes, static = theatre(M)
    wide = mode.endswith("_wide") or mode.startswith("front")
    set_camera(G.WIDE if wide else RES)
    sc.view_settings.exposure = 0.4
    if mode in ("backdrop", "backdrop_wide"):
        return
    if mode == "albedo_wide":
        # the paper's and floor's base colour as seen by the camera (the engine's base_color for the live planes)
        for o in bpy.data.objects:
            if o.type == "MESH" and o not in planes:
                o.hide_render = True
        # the 5 mm gaps between boards would bake black (nothing under them): a board-coloured underlay fills them
        u = box((0, (G.FLOOR_Y[0] + G.FLOOR_Y[1]) / 2, -0.03), (G.FLOOR_X[1] - G.FLOOR_X[0], G.FLOOR_Y[1] - G.FLOOR_Y[0], 0.01), M["boards"])
        planes.append(u)
        for o in planes:
            albedo_override(o)
        sc.world = None
        sc.view_settings.exposure = 0.0
        return
    if mode.startswith("front"):
        # the static theatre lit by the lantern at one bake position; paper and floor cut out (alpha 0)
        i, j = (int(t) for t in mode.split("_")[1:3])
        F = V((G.FRONT_X[i], G.FRONT_Y[j], G.LZ))
        for o in planes:
            o.is_holdout = True
        lc = light("POINT", F, LANTERN_W, (1.0, 0.62, 0.3), size=0.004)
        lc.light_linking.receiver_collection = link_collection("lk_static", [o for o in static if o not in planes])
        # the candle's own glow on the right curtain and proscenium (state A's height; it burns lower slowly)
        cl = light("POINT", (CANDLE[0], CANDLE[1], 0.035 + 0.30 * G.STATE_A["candle"] + 0.03), 3.0, (1.0, 0.6, 0.3), size=0.02)
        cl.data.use_shadow = False
        cl.light_linking.receiver_collection = link_collection("lk_static_c", [o for o in static if o not in planes])
        sc.render.film_transparent = True
        return
    if mode.startswith("lsprite"):
        # the target's lantern alone (state A's scene lights it), flame at FRONT_X[i], FRONT_Y[j]: tools/sp_common.py
        i, j = (int(t) for t in mode.split("_")[1:3])
        st = dict(G.STATE_A, lantern=(G.FRONT_X[i], G.FRONT_Y[j]))
    else:
        st = G.STATE_A if mode == "target" else G.STATE_B
    F, lan = lantern(M, st["lantern"])
    real, casters = props(M, st)
    tracks(M)
    paper_level(M)
    puppet(M, *st["puppet"])
    candle(M, st["candle"])
    dust(F)
    halo(F, 0.18, 0.5)                       # small and faint like the game's (polish note 2); the floor pool lights
    lantern_lights(F, planes, static, casters)
    if mode.startswith("lsprite"):
        keep = set(lan)
        for o in bpy.data.objects:
            if o.type == "MESH" and o not in keep:
                o.visible_camera = False                  # still lights, reflects and refracts; only the lantern is drawn
        sc.render.film_transparent = True
        sc.cycles.film_transparent_glass = False          # opaque glass refracting the baked scene, like the target (transparent glass left dark partial-alpha fringes)
        (X0, Y0, X1, Y1), _ = G.lantern_sprite(i, j)
        W2, H2 = RES
        sc.render.use_border, sc.render.use_crop_to_border = True, False
        sc.render.border_min_x, sc.render.border_max_x = (X0 - 2) / W2, (X1 + 2) / W2
        sc.render.border_min_y, sc.render.border_max_y = 1 - (Y1 + 2) / H2, 1 - (Y0 - 2) / H2


def albedo_override(o):
    """Replace o's materials with an emission of their base colour (same texture graph)."""
    for slot in o.material_slots:
        m = slot.material.copy()
        N, Ln = m.node_tree.nodes, m.node_tree.links
        p = N["Principled BSDF"]
        em = N.new("ShaderNodeEmission")
        bc = p.inputs["Base Color"]
        if bc.is_linked:
            Ln.new(bc.links[0].from_socket, em.inputs["Color"])
        else:
            em.inputs["Color"].default_value = bc.default_value
        Ln.new(em.outputs["Emission"], N["Material Output"].inputs["Surface"])
        slot.material = m


# ================================================================== mode: export (live meshes for the engine)
def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def export_obj(objs, path):
    """OBJ in engine axes (x, z, -y), triangulated, with UVs and (custom) normals."""
    select_only(objs)
    bpy.ops.wm.obj_export(filepath=path, export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                          export_uv=True, export_normals=True, export_materials=False, export_triangulated_mesh=True,
                          apply_modifiers=True)


def bake_albedo(o, path, size=1024):
    """UV-unwrap o and bake its base colour (procedural textures) to path."""
    select_only([o])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    albedo_override(o)
    img = bpy.data.images.new(os.path.basename(path), size, size)
    for slot in o.material_slots:
        tn = slot.material.node_tree.nodes.new("ShaderNodeTexImage")
        tn.image = img
        slot.material.node_tree.nodes.active = tn
    sc.cycles.samples = 16
    bpy.ops.object.bake(type="EMIT", margin=8)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()


def bake_teeth_mask(o, path, z_below, size=1024):
    """In o's (already unwrapped) UVs: R = 1 where the surface is below z_below (the comb's teeth), 0 above; G = the
    texel's x across the comb, 0..1 (the UVs are a packed atlas, so a left-to-right ramp needs it: gen_meshes)."""
    import mathutils
    xs = [(o.matrix_world @ mathutils.Vector(c)).x for c in o.bound_box]
    for slot in o.material_slots:
        m = bpy.data.materials.new("teeth_mask")
        m.use_nodes = True
        N, Ln = m.node_tree.nodes, m.node_tree.links
        N.remove(N["Principled BSDF"])
        geo = N.new("ShaderNodeNewGeometry")
        sep = N.new("ShaderNodeSeparateXYZ")
        lt = N.new("ShaderNodeMath")
        lt.operation = "LESS_THAN"
        lt.inputs[1].default_value = z_below
        em = N.new("ShaderNodeEmission")
        Ln.new(geo.outputs["Position"], sep.inputs["Vector"])
        Ln.new(sep.outputs["Z"], lt.inputs[0])
        mr = N.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value, mr.inputs["From Max"].default_value = min(xs), max(xs)
        cc = N.new("ShaderNodeCombineXYZ")
        Ln.new(sep.outputs["X"], mr.inputs["Value"])
        Ln.new(lt.outputs["Value"], cc.inputs["X"])
        Ln.new(mr.outputs["Result"], cc.inputs["Y"])
        Ln.new(cc.outputs["Vector"], em.inputs["Color"])
        Ln.new(em.outputs["Emission"], N["Material Output"].inputs["Surface"])
        slot.material = m
    img = bpy.data.images.new(os.path.basename(path), size, size)
    img.colorspace_settings.name = "Non-Color"
    for slot in o.material_slots:
        tn = slot.material.node_tree.nodes.new("ShaderNodeTexImage")
        tn.image = img
        slot.material.node_tree.nodes.active = tn
    bpy.ops.object.bake(type="EMIT", margin=8)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()


def grid_projected(name, corners_fn, nu, nv, cam):
    """A (nu x nv) grid whose UVs are the camera projection into the WIDE frame (bakes map pixel-exactly)."""
    from bpy_extras.object_utils import world_to_camera_view
    vs, fs, uvs = [], [], []
    for j in range(nv + 1):
        for i in range(nu + 1):
            vs.append(corners_fn(i / nu, j / nv))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i
            fs.append((a, a + 1, a + nu + 2, a + nu + 1))
    o = mesh_obj(vs, fs, None, name)
    uvl = o.data.uv_layers.new(name="UV")
    bpy.context.view_layer.update()
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            c = world_to_camera_view(sc, cam, V(vs[o.data.loops[li].vertex_index]))
            uvl.data[li].uv = (c.x, c.y)
    return o


def drop_degenerates(o):
    """Triangulate and delete zero-area triangles: the cooker (Assimp FindDegenerates + SortByPType) turns them into
    lines and puts those in sub-mesh 0, which is the one the scene shows. Custom normals of the rest are kept."""
    import bmesh
    me = o.data
    keep = None
    if me.has_custom_normals:                      # the cup's relief keeps its round normals (by vertex position)
        acc = {}
        for loop, cn in zip(me.loops, me.corner_normals):
            key = tuple(round(c, 5) for c in me.vertices[loop.vertex_index].co)
            acc.setdefault(key, V((0, 0, 0)))
            acc[key] += V(cn.vector)
        keep = {k: v.normalized() for k, v in acc.items()}
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bad = [f for f in bm.faces if f.calc_area() < 1e-10]
    bmesh.ops.delete(bm, geom=bad, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    if keep:
        me = o.data
        me.normals_split_custom_set_from_vertices(
            [keep.get(tuple(round(c, 5) for c in v.co), V((0, 0, 1))) for v in me.vertices])


def boards_projected(boards, cam, cuts=24):
    """The live floor: the real bevelled boards (so the lantern lights their bevels like the target's), cut across
    their length so the camera-projected UVs stay exact under perspective, top and bevel faces only."""
    import bmesh
    from bpy_extras.object_utils import world_to_camera_view
    objs = []
    for b in boards:
        c = b.copy()
        c.data = b.data.copy()
        COL.objects.link(c)
        c.hide_set(False)
        objs.append(c)
    o = join(objs, "floor")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    y0, y1 = G.FLOOR_Y
    for i in range(1, cuts):
        y = y0 + (y1 - y0) * i / cuts
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, y, 0), plane_no=(0, 1, 0))
    bm.normal_update()
    drop = [f for f in bm.faces if f.normal.z < 0.05]          # bottoms, sides and ends never show
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    uvl = o.data.uv_layers.new(name="UV") if not o.data.uv_layers else o.data.uv_layers[0]
    bpy.context.view_layer.update()
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            c = world_to_camera_view(sc, cam, o.data.vertices[o.data.loops[li].vertex_index].co)
            uvl.data[li].uv = (c.x, c.y)
    for poly in o.data.polygons:
        poly.use_smooth = False
    # real (flat) normals: the bevel facing the lantern catches its low light as the target's lit seam line, the one
    # facing away stays dark like the target's (2026-11-13; normals all up had drawn each seam as a faint dark line)
    return o


def export_all(out_dir, tex_dir):
    """Every live mesh as an OBJ (prop-local origins where the game moves the piece), plus baked prop textures."""
    os.makedirs(out_dir, exist_ok=True)
    M = materials()
    planes, static = theatre(M)
    cam = set_camera(G.WIDE)
    bpy.context.view_layer.update()
    for o in static:
        o.hide_set(True)
    made = {}

    def put_(name, objs):
        """One OBJ = one joined mesh (the cooker makes a sub-mesh per object and the scene shows sub-mesh 0)."""
        objs = [o for o in objs if o is not None]
        for o in objs:
            o.hide_set(False)
        o = join(objs, name) if len(objs) > 1 else objs[0]
        if len(objs) == 1:
            apply_mods(o)
        drop_degenerates(o)
        export_obj([o], os.path.join(out_dir, name + ".obj"))
        made[name] = len(o.data.polygons)
        o.hide_set(True)

    # props at the origin (the game sets x on the track and z = -track y)
    def groups(objs, spec):
        """Split objects by material before any join removes them: {name: [objs]}."""
        return {name: [o for o in objs if o.type == "MESH" and o.data.materials and o.data.materials[0] in mats]
                for name, mats in spec.items()}

    cup = build_cup(0, 0, M["china"], rim=M["goldp"])
    for k, v in groups(cup, {"cup": (M["china"],), "cup_rim": (M["goldp"],)}).items():
        put_(k, v)
    comb = join(build_comb(0, 0, M["horn"]), "comb")
    bake_albedo(comb, os.path.join(tex_dir, "comb.png"))
    # the teeth (below the spine) in the same UVs: gen_meshes lightens them toward the target's lit cream (no IBL here)
    bake_teeth_mask(comb, os.path.join(tex_dir, "comb_teeth_mask.png"), G.COMB["top"] - G.COMB["spine"] + 0.002)
    put_("comb", [comb])
    ladder = join(build_ladder(0, 0, M["toy"]), "ladder")
    bake_albedo(ladder, os.path.join(tex_dir, "ladder.png"))
    put_("ladder", [ladder])
    for name, fn in (("mouse", build_mouse), ("balloon", build_balloon)):
        o = fn(0, 0, M)[0]
        bake_albedo(o, os.path.join(tex_dir, name + ".png"))
        put_(name, [o])
    # lantern at the origin, flame at (0, LZ)
    F, lan = lantern(M, (0.0, 0.0))
    for k, v in groups(lan, {"lantern_glass": (M["glass"],), "lantern_flame": (M["flame"],),
                             "lantern_brass": (M["brass"],)}).items():
        put_(k, v)
    # candle at the origin: holder, and the wax at each height the look slice shows (plus fresh)
    global CANDLE
    keep = CANDLE
    CANDLE = (0.0, 0.0, 0.0)
    for left in (1.0, 0.55, 0.3):
        parts, lt = candle(M, left)
        bpy.data.objects.remove(lt)
        tag = "%03d" % round(left * 100)
        g = groups(parts, {"wax": (M["wax"], M["cutp"]), "flame": (M["flame"],), "holder": (M["brass"],)})
        put_("candle_wax_" + tag, g["wax"])
        put_("candle_flame_" + tag, g["flame"])
        holder = g["holder"]
        if left == 1.0:
            put_("candle_holder", holder)
        else:
            for o in holder:
                bpy.data.objects.remove(o)
    CANDLE = keep
    # paper pieces and puppet in the plane y = 0, back faces moved onto y = 0 (the game puts them just off the paper)
    def back_to_zero(objs):
        for o in objs:
            apply_mods(o)
        ymax = max((o.matrix_world @ v.co).y for o in objs for v in o.data.vertices)
        for o in objs:
            o.location.y -= ymax
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    # every level's cut paper (the reference frames use level 1-3's: the target's own pieces)
    for lv in G.LEVELS:
        tag = lv["id"].replace("-", "_")
        pieces = paper_level_of(M, lv, 0.0)
        back_to_zero(pieces)
        for k, v in groups(pieces, {"paper_black": (M["cutp"],), "paper_red": (M["redp"],), "paper_gold": (M["goldp"],)}).items():
            put_(k + "_" + tag, v)
    for key, st in (("puppet_a", G.STATE_A), ("puppet_b", G.STATE_B)):
        pp = puppet(M, 0.0, 0.0, st["puppet"][2], y=0.0)
        back_to_zero(pp)
        for k, v in groups(pp, {key: (M["cutp"],), key + "_pins": (M["brass"],)}).items():
            put_(k, v)
    # the jointed puppet the game walks: each piece's back face on y = 0 like the paper pieces
    for key in ("pp_leg_l", "pp_leg_r", "pp_arm_l", "pp_arm_r", "pp_body", "pp_pins"):
        body, leg, arm, pins = puppet_parts(M)
        part = {"pp_body": body, "pp_pins": pins, "pp_leg_l": leg, "pp_leg_r": leg, "pp_arm_l": arm, "pp_arm_r": arm}[key]
        for o in body + leg + arm + pins:
            if o not in part:
                bpy.data.objects.remove(o)
        if key != "pp_pins":
            back_to_zero(part)
        put_(key, part)
    # each tracked prop's own track (a level shows only the tracks of its props)
    slots, rails = tracks(M, TRACKED, per=True), rails_game(M, TRACKED, per=True)
    for name in TRACKED:
        keep = [o for o in slots[name] if o.active_material is not M["railbrass"]]
        for o in slots[name]:
            if o not in keep:
                bpy.data.objects.remove(o)
        tr = keep + rails[name]
        for k, v in groups(tr, {"track_slot": (M["groove"],), "track_brass": (M["railbrass"],)}).items():
            put_(k + "_" + name, v)
    # the live paper and floor: grids with UVs = camera projection into the WIDE bakes
    u0, u1 = G.SCREEN_U
    v1 = G.SCREEN_V[1]
    # the paper reaches 3 cm below the floor top (hidden by the floor) so no pixel gap opens along the junction
    put_("paper", [grid_projected("paper", lambda a, b: (u0 + (u1 - u0) * a, G.SY, -0.03 + (v1 + 0.03) * b), 24, 12, cam)])
    # the 5 mm gaps between boards showed black (nothing under them): the same underlay as the albedo bake fills them
    # its top 7 mm down, just under the 6 mm bevels: the lantern lights it like a board (deeper it drew a black seam)
    under = box((0, (G.FLOOR_Y[0] + G.FLOOR_Y[1]) / 2, -0.012), (G.FLOOR_X[1] - G.FLOOR_X[0], G.FLOOR_Y[1] - G.FLOOR_Y[0], 0.01),
                M["boards"])
    put_("floor", [boards_projected(planes[1:] + [under], cam)])
    with open(os.path.join(out_dir, "faces.txt"), "w") as f:
        for k in sorted(made):
            f.write("%s %d\n" % (k, made[k]))
    print("exported", len(made), "meshes")


def report_metrics():
    """Print framing numbers: screen width share, prop and puppet sizes in px at 1080p."""
    from bpy_extras.object_utils import world_to_camera_view
    bpy.context.view_layer.update()
    cam = sc.camera

    def px(p):
        c = world_to_camera_view(sc, cam, V(p))
        return c.x * 1920, (1 - c.y) * 1080
    l_, r_ = px((G.SCREEN_U[0], G.SY, 0)), px((G.SCREEN_U[1], G.SY, 0))
    t_ = px((0, G.SY, G.SCREEN_V[1]))
    print("METRIC screen width share %.3f  screen px x %.0f..%.0f  bottom %.0f top %.0f (1080p)"
          % ((r_[0] - l_[0]) / 1920, l_[0], r_[0], l_[1], t_[1]))
    for key in ("STATE_A", "STATE_B"):
        u, v, _ = getattr(G, key)["puppet"]
        a, b = px((u, G.SY, v)), px((u, G.SY, v + 0.30))
        print("METRIC puppet %s height px %.0f (1080p)" % (key, a[1] - b[1]))
    faces = {}
    for o in bpy.data.objects:
        if o.type == "MESH":
            nm = o.name.split(".")[0]
            faces[nm] = faces.get(nm, 0) + len(o.data.polygons)
    print("METRIC faces", sorted(faces.items(), key=lambda t: -t[1])[:40])
    for o in bpy.data.objects:
        if o.type != "MESH" or o.name not in ("cup", "comb", "ladder"):
            continue
        cs = [px(o.matrix_world @ v.co) for v in o.data.vertices]
        xs, ys = [c[0] for c in cs], [c[1] for c in cs]
        print("METRIC %s px w %.0f h %.0f  x %.0f..%.0f  y %.0f..%.0f" % (o.name, max(xs) - min(xs), max(ys) - min(ys),
              min(xs), max(xs), min(ys), max(ys)))


if MODE == "iou":
    run_iou(OUT)
elif MODE == "export":
    # OUT = OBJ folder; textures go to Assets/Textures next to it (argv[2] when given)
    setup_render(16, G.WIDE, denoise=False)
    tex = os.path.abspath(argv[2]) if len(argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets", "Textures")
    export_all(OUT, tex)
else:
    build_frame(MODE)
    setup_render(SAMPLES, (sc.render.resolution_x, sc.render.resolution_y), denoise=MODE != "albedo_wide")
    sc.cycles.max_bounces = 10
    sc.cycles.transmission_bounces = 10
    if MODE == "albedo_wide":
        sc.view_settings.view_transform = "Standard"
        sc.view_settings.look = "None"
    else:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    if MODE in ("target", "target_b"):
        report_metrics()
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA" if MODE.startswith(("front", "lsprite")) else "RGB"
    sc.render.filepath = OUT
    bpy.ops.render.render(write_still=True)
    print("wrote", OUT)
