"""Undertow look plan: textures, sky panorama, far layer, baked set pieces and the two target frames.

    blender -b --factory-startup --python scene.py -- MODE [--half] [--samples N]

MODE: tex | sky | far | bake | target | target_b | side | all
Outputs go to PhasmaProjects/.concepts/next/undertow/ (layers/ holds the reusable parts).

Rule: target and target_b are assembled ONLY from parts the engine can draw the way LOOKPLAN.md says:
  * sky        = layers/sky_pano.png as an equirect environment (engine skybox), shown as-is;
  * far layer  = layers/far_layer.png on one alpha card at FAR_Y (unlit);
  * set pieces = layers/pieces/*.obj with their Cycles-baked texture, drawn as pure emission (unlit);
  * live parts = sea tile mesh + far sea plane (dark glossy PBR, tiling normal map, foam baked in base colour),
    float (alpha glass + emissive core), chain links, rain/spray/trail/glow/beam alpha cards, point lights.
No ocean modifier, no volumes, no transmission, no light paths the engine lacks.
"""
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import uw_common as U  # noqa: E402
import uw_sea  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, ".concepts", "next", "undertow")
LAY = os.path.join(OUT, "layers")
PCS = os.path.join(LAY, "pieces")
TEX = os.path.join(LAY, "tex")
CONCEPT = os.path.join(ROOT, ".concepts", "next", "undertow.png")
for d in (OUT, LAY, PCS, TEX):
    os.makedirs(d, exist_ok=True)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["target"]
MODE = argv[0]
HALF = "--half" in argv
SAMPLES = int(argv[argv.index("--samples") + 1]) if "--samples" in argv else (48 if HALF else 256)
R = math.radians
V = Vector

FAR_Y = 120.0                 # far layer card depth
FAR_W, FAR_H, FAR_Z0 = 256.0, 40.0, -3.0     # card size (tiles every FAR_W along x), bottom edge z
FAR_PX = (4608, 720)
FAR_SEA_DEG = 1.4                           # where the near sea tiles end below the horizon (atan(1.7 / 75.5) + margin)
FAR_SEA_SRGB = (0.050, 0.072, 0.066)        # display colour of the far sea at that depression
HORIZON_COL = (0.50, 0.33, 0.22)            # display-ish haze colour near the horizon (linear)


# ================================================================== basics
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for dev in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = dev
            prefs.get_devices()
            for d in prefs.devices:
                d.use = d.type == dev
            sc.cycles.device = "GPU"
            break
        except TypeError:
            continue
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 8
    sc.cycles.caustics_reflective = sc.cycles.caustics_refractive = False
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    return sc


def sc():
    return bpy.context.scene


def link(o):
    sc().collection.objects.link(o)
    return o


def nodes(m):
    m.use_nodes = True
    return m.node_tree.nodes, m.node_tree.links


def pbr(name, base, rough=0.5, metal=0.0, coat=0.0, emit=None, es=0.0, tint2=None, scale=4.0, bump=0.0, tex="noise",
        alpha=1.0):
    m = bpy.data.materials.new(name)
    N, L = nodes(m)
    p = N["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*base, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    p.inputs["Alpha"].default_value = alpha
    if coat:
        p.inputs["Coat Weight"].default_value = coat
    if emit:
        p.inputs["Emission Color"].default_value = (*emit, 1)
        p.inputs["Emission Strength"].default_value = es
    if tint2 or bump:
        tc = N.new("ShaderNodeTexCoord")
        if tex == "wave":
            t = N.new("ShaderNodeTexWave")
            t.inputs["Scale"].default_value = scale
            t.inputs["Distortion"].default_value = 4.0
            fac = t.outputs["Fac"]
        else:
            t = N.new("ShaderNodeTexNoise")
            t.inputs["Scale"].default_value = scale
            t.inputs["Detail"].default_value = 8.0
            fac = t.outputs["Fac"]
        L.new(tc.outputs["Object"], t.inputs["Vector"])
        if tint2:
            r = N.new("ShaderNodeValToRGB")
            r.color_ramp.elements[0].color = (*base, 1)
            r.color_ramp.elements[1].color = (*tint2, 1)
            L.new(fac, r.inputs["Fac"])
            L.new(r.outputs["Color"], p.inputs["Base Color"])
        if bump:
            b = N.new("ShaderNodeBump")
            b.inputs["Strength"].default_value = bump
            L.new(fac, b.inputs["Height"])
            L.new(b.outputs["Normal"], p.inputs["Normal"])
    return m


def img_tex(path, colorspace="sRGB"):
    im = bpy.data.images.load(path, check_existing=True)
    im.colorspace_settings.name = colorspace
    return im


def card_mat(name, path, strength=1.0, tint=(1, 1, 1), alpha_mul=1.0, uv_scale=(1, 1), additive=False):
    """Unlit alpha card: emission(texture rgb * tint * strength) over transparent by texture alpha.
    Engine: unlit/emissive material, alpha blend (or additive), no depth write."""
    m = bpy.data.materials.new(name)
    N, L = nodes(m)
    N.remove(N["Principled BSDF"])
    out = N["Material Output"]
    t = N.new("ShaderNodeTexImage")
    t.image = img_tex(path)
    t.extension = "EXTEND" if uv_scale == (1, 1) else "REPEAT"
    if uv_scale != (1, 1):
        tc = N.new("ShaderNodeTexCoord")
        mp = N.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (uv_scale[0], uv_scale[1], 1)
        L.new(tc.outputs["UV"], mp.inputs["Vector"])
        L.new(mp.outputs["Vector"], t.inputs["Vector"])
    em = N.new("ShaderNodeEmission")
    mul = N.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    L.new(t.outputs["Color"], mul.inputs[6])
    mul.inputs[7].default_value = (*tint, 1)
    L.new(mul.outputs[2], em.inputs["Color"])
    em.inputs["Strength"].default_value = strength
    tr = N.new("ShaderNodeBsdfTransparent")
    am = N.new("ShaderNodeMath")
    am.operation = "MULTIPLY"
    am.inputs[1].default_value = alpha_mul
    L.new(t.outputs["Alpha"], am.inputs[0])
    if additive:
        add = N.new("ShaderNodeAddShader")
        sc_ = N.new("ShaderNodeMath")
        sc_.operation = "MULTIPLY"
        L.new(am.outputs[0], sc_.inputs[0])
        sc_.inputs[1].default_value = strength
        em2 = N.new("ShaderNodeEmission")
        L.new(mul.outputs[2], em2.inputs["Color"])
        L.new(sc_.outputs[0], em2.inputs["Strength"])
        L.new(tr.outputs[0], add.inputs[0])
        L.new(em2.outputs[0], add.inputs[1])
        L.new(add.outputs[0], out.inputs["Surface"])
    else:
        mx = N.new("ShaderNodeMixShader")
        L.new(am.outputs[0], mx.inputs[0])
        L.new(tr.outputs[0], mx.inputs[1])
        L.new(em.outputs[0], mx.inputs[2])
        L.new(mx.outputs[0], out.inputs["Surface"])
    return m


def unlit_mat(name, path):
    """Baked set piece: pure emission of its baked texture (engine: unlit / emissive-only)."""
    m = bpy.data.materials.new(name)
    N, L = nodes(m)
    N.remove(N["Principled BSDF"])
    t = N.new("ShaderNodeTexImage")
    t.image = img_tex(path)
    em = N.new("ShaderNodeEmission")
    L.new(t.outputs["Color"], em.inputs["Color"])
    L.new(em.outputs[0], N["Material Output"].inputs["Surface"])
    return m


def put(o, m=None, smooth=True):
    if m is not None:
        o.data.materials.append(m)
    if smooth and hasattr(o.data, "polygons"):
        for f in o.data.polygons:
            f.use_smooth = True
    return o


def mesh(name, verts, faces, m=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    return put(link(bpy.data.objects.new(name, me)), m, smooth)


def box(loc, size, m=None, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[R(a) for a in rot])
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        md = o.modifiers.new("b", "BEVEL")
        md.width = bevel
        md.segments = 2
    return put(o, m, smooth=False)


def cyl(loc, r, depth, m=None, rot=(0, 0, 0), verts=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=[R(a) for a in rot])
    return put(bpy.context.object, m)


def sphere(loc, r, m=None, scale=(1, 1, 1), sub=3):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r, location=loc)
    o = bpy.context.object
    o.scale = scale
    return put(o, m)


def uvsphere(loc, r, m=None, seg=32, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=loc)
    return put(bpy.context.object, m)


def torus(loc, major, minor, m=None, rot=(0, 0, 0), seg=(32, 8)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=[R(a) for a in rot],
                                     major_segments=seg[0], minor_segments=seg[1])
    return put(bpy.context.object, m)


def lathe(profile, loc, m=None, steps=32, mats=None):
    vs, fs = [], []
    n = len(profile)
    for s in range(steps):
        a = 2 * math.pi * s / steps
        for r, h in profile:
            vs.append((loc[0] + r * math.cos(a), loc[1] + r * math.sin(a), loc[2] + h))
    for s in range(steps):
        s2 = (s + 1) % steps
        for i in range(n - 1):
            fs.append((s * n + i, s2 * n + i, s2 * n + i + 1, s * n + i + 1))
    o = mesh("lathe", vs, fs, m)
    if mats:   # mats: list of (material, zmax) assigned by face centre height (relative to loc)
        for mm, _ in mats[1:]:
            o.data.materials.append(mm)
        for f in o.data.polygons:
            z = f.center.z - loc[2]
            for i, (_, zmax) in enumerate(mats):
                if z <= zmax:
                    f.material_index = i
                    break
    return o


def tube(pts, r, m, res=4):
    cu = bpy.data.curves.new("tube", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = res
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (*p, 1)
    cu.materials.append(m)
    return link(bpy.data.objects.new("tube", cu))


def smooth_tube(pts, r, m, res=4):
    cu = bpy.data.curves.new("tube", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = res
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (*p, 1)
    sp.use_endpoint_u = True
    sp.order_u = min(4, len(pts))
    sp.resolution_u = 16
    cu.materials.append(m)
    return link(bpy.data.objects.new("tube", cu))


def rod(a, b, r, m, verts=8):
    a, b = V(a), V(b)
    d = b - a
    o = cyl((a + b) / 2, r, d.length, m, verts=verts)
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return o


def text(body, loc, size, m, rot=(90, 0, 0), extrude=0.01):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    p = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", "arialbd.ttf")
    if os.path.exists(p):
        cu.font = bpy.data.fonts.load(p, check_existing=True)
    cu.materials.append(m)
    o = link(bpy.data.objects.new("txt", cu))
    o.location = loc
    o.rotation_euler = [R(a) for a in rot]
    return o


def light(kind, loc, energy, color, size=0.1, target=None, spot=None, blend=0.3):
    d = bpy.data.lights.new(kind, kind)
    d.energy = energy
    d.color = color
    if kind in ("POINT", "SPOT"):
        d.shadow_soft_size = size
    if kind == "SUN":
        d.angle = R(size)
    if spot:
        d.spot_size = R(spot)
        d.spot_blend = blend
    if kind != "SUN" and NO_POINT_SHADOWS:
        d.use_shadow = False      # engine: only the directional light casts shadows
    o = link(bpy.data.objects.new(kind, d))
    o.location = loc
    if target is not None:
        o.rotation_euler = (V(target) - V(loc)).to_track_quat("-Z", "Y").to_euler()
    return o


def billboard(loc, w, h, m, cam_loc, name="card", roll=0.0):
    """Camera-facing quad (engine: a pooled quad node rotated to face the camera each frame)."""
    o = mesh(name, [(-w / 2, 0, -h / 2), (w / 2, 0, -h / 2), (w / 2, 0, h / 2), (-w / 2, 0, h / 2)], [(0, 1, 2, 3)], m,
             smooth=False)
    uv = o.data.uv_layers.new()
    for i, l in enumerate(o.data.loops):
        uv.data[i].uv = [(0, 0), (1, 0), (1, 1), (0, 1)][l.vertex_index]
    o.location = loc
    d = V(cam_loc) - V(loc)
    o.rotation_euler = (d.to_track_quat("-Y", "Z").to_matrix().to_4x4() @ Euler((0, R(roll), 0)).to_matrix().to_4x4()).to_euler()
    o.visible_shadow = False
    return o


def quad_uv(o, uvs):
    uv = o.data.uv_layers.new()
    for i, l in enumerate(o.data.loops):
        uv.data[i].uv = uvs[l.vertex_index]


def save_rgba(arr, path, noncolor=False):
    """arr: (h, w, 4) float 0..1, row 0 = top. Saved as 8-bit PNG."""
    h, w = arr.shape[:2]
    im = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    if noncolor:
        im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).astype(np.float32).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    print("wrote", path)


def load_rgba(path):
    im = bpy.data.images.load(path)
    w, h = im.size
    a = np.empty(w * h * 4, np.float32)
    im.pixels.foreach_get(a)
    bpy.data.images.remove(im)
    return a.reshape(h, w, 4)[::-1].copy()


# ================================================================== the storm sky (same shader as the concept)
def sky_tree(N, L, vec):
    """The concept's storm-sky nodes driven by a direction vector socket; returns the colour socket."""
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(vec, sep.inputs["Vector"])
    ramp = N.new("ShaderNodeValToRGB")
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.0, (0.58, 0.31, 0.15, 1)
    e[1].position, e[1].color = 0.35, (0.07, 0.085, 0.1, 1)
    mid = ramp.color_ramp.elements.new(0.08)
    mid.color = (0.32, 0.22, 0.17, 1)
    L.new(sep.outputs["Z"], ramp.inputs["Fac"])
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.0, 1.0, 5.0)
    L.new(vec, mp.inputs["Vector"])
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 2.2
    nz.inputs["Detail"].default_value = 10
    nz.inputs["Roughness"].default_value = 0.6
    L.new(mp.outputs["Vector"], nz.inputs["Vector"])
    cr = N.new("ShaderNodeValToRGB")
    ce = cr.color_ramp.elements
    ce[0].position, ce[0].color = 0.35, (0.35, 0.35, 0.38, 1)
    ce[1].position, ce[1].color = 0.7, (1.0, 1.0, 1.0, 1)
    L.new(nz.outputs["Fac"], cr.inputs["Fac"])
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    L.new(ramp.outputs["Color"], mix.inputs[6])
    L.new(cr.outputs["Color"], mix.inputs[7])
    return mix.outputs[2]


def storm_sky(strength=1.0):
    w = bpy.data.worlds.new("W")
    sc().world = w
    N, L = nodes(w)
    tc = N.new("ShaderNodeTexCoord")
    L.new(sky_tree(N, L, tc.outputs["Generated"]), N["Background"].inputs["Color"])
    N["Background"].inputs["Strength"].default_value = strength
    return w


def _math(N, L, op, a, b=None):
    m = N.new("ShaderNodeMath")
    m.operation = op
    for k, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            m.inputs[k].default_value = v
        else:
            L.new(v, m.inputs[k])
    return m.outputs[0]


def pano_world(strength=1.0):
    """Engine skybox stand-in: sky_pano.png looked up with the ENGINE's equirect convention (centre column looks
    along engine +Z = Blender -y, u = 0.75 along +x; Skybox.cpp), shown as-is (it is already display-graded)."""
    w = bpy.data.worlds.new("Pano")
    sc().world = w
    N, L = nodes(w)
    tc = N.new("ShaderNodeTexCoord")
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(tc.outputs["Generated"], sep.inputs["Vector"])
    bx, by, bz = sep.outputs["X"], sep.outputs["Y"], sep.outputs["Z"]
    u = _math(N, L, "ADD", _math(N, L, "DIVIDE", _math(N, L, "ARCTAN2", bx, _math(N, L, "MULTIPLY", by, -1.0)), 2 * math.pi), 0.5)
    v = _math(N, L, "ADD", _math(N, L, "DIVIDE", _math(N, L, "ARCSINE", bz), math.pi), 0.5)
    cv = N.new("ShaderNodeCombineXYZ")
    L.new(u, cv.inputs["X"])
    L.new(v, cv.inputs["Y"])
    t = N.new("ShaderNodeTexImage")
    t.image = img_tex(os.path.join(LAY, "sky_pano.png"))
    t.extension = "REPEAT"
    L.new(cv.outputs[0], t.inputs["Vector"])
    L.new(t.outputs["Color"], N["Background"].inputs["Color"])
    N["Background"].inputs["Strength"].default_value = strength
    return w


def agx(scene):
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "None"          # the concept's grading: plain AgX, +0.3 exposure
    scene.view_settings.exposure = 0.3


# ================================================================== MODE tex: procedural textures (numpy)
def periodic_noise(h, w, comps, rng, kmin, kmax, aniso=1.0):
    """Sum of random integer-frequency waves: tiles seamlessly on both axes."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = x / w, y / h
    out = np.zeros((h, w), np.float32)
    for _ in range(comps):
        kx = rng.integers(-kmax, kmax + 1)
        ky = int(rng.integers(kmin, kmax + 1) * aniso)
        amp = 1.0 / max(1.0, math.hypot(kx, ky)) ** 1.1
        out += amp * np.sin(2 * np.pi * (kx * u + ky * v) + rng.uniform(0, 2 * np.pi))
    out -= out.min()
    return out / max(out.max(), 1e-6)


def ripple_frame(n, comps, k, frames, strength):
    """Ripple normal map frame k of a seamless loop: each wave's phase advances by an integer number of turns."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
    gx = np.zeros((n, n), np.float32)
    gy = np.zeros_like(gx)
    for kx, ky, a, ph, turns in comps:
        s = 2 * np.pi * (kx * x + ky * y) + ph + 2 * np.pi * turns * k / frames
        gx += a * 2 * np.pi * kx * np.cos(s)
        gy += a * 2 * np.pi * ky * np.cos(s)
    nx, ny = -gx * strength, gy * strength
    ln = np.sqrt(nx * nx + ny * ny + 1)
    return np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, 1 / ln * 0.5 + 0.5, np.ones_like(nx)], -1)


def make_sea_textures(rng):
    """Ripple normal-map loop and colour detail map (tools/uw_ripple.py, shared with the game)."""
    import uw_ripple
    uw_ripple.make(TEX)


def make_rain(rng, name, n_streaks, length, alpha, width):
    """Rain streak texture (tiles both ways). Far layers: shorter, fainter, thinner streaks."""
    rh, rw = 1024, 1024
    rain = np.zeros((rh, rw), np.float32)
    for _ in range(n_streaks):
        cx, cy = rng.uniform(0, rw), rng.uniform(0, rh)
        L = rng.uniform(*length)
        a = rng.uniform(*alpha)
        t = np.arange(int(L))
        yy = (cy + t).astype(int) % rh
        xx = cx + t * 0.12
        fall = np.sin(np.pi * t / L) ** 0.7
        for dx in (-1, 0, 1):
            xi = (xx + dx).astype(int) % rw
            wgt = (1.0 if dx == 0 else 0.45) * (width if dx else 1.0)
            rain[yy, xi] = np.maximum(rain[yy, xi], a * fall * wgt)
    save_rgba(np.dstack([np.ones_like(rain) * 0.85, np.ones_like(rain) * 0.88, np.ones_like(rain) * 0.9, rain]),
              os.path.join(TEX, name))


def make_textures():
    rng = np.random.default_rng(7)
    make_sea_textures(rng)
    make_rain(rng, "rain_near.png", 120, (110, 200), (0.55, 0.95), 1.0)
    make_rain(rng, "rain_mid.png", 220, (55, 110), (0.35, 0.7), 0.6)
    make_rain(rng, "rain_far.png", 380, (18, 45), (0.15, 0.4), 0.2)
    # radial glow (lamp halos), soft
    g = 256
    yy, xx = np.mgrid[0:g, 0:g].astype(np.float32)
    r = np.hypot(xx - g / 2 + 0.5, yy - g / 2 + 0.5) / (g / 2)
    glow = np.clip(np.exp(-r * r * 9) * 0.8 + np.exp(-r * 3.2) * 0.35 * (1 - r), 0, 1) * (r < 1)
    save_rgba(np.dstack([np.ones_like(glow)] * 3 + [glow]), os.path.join(TEX, "glow.png"))

    # spray sprite: droplets + mist, 512^2
    s = 512
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    cxy = (xx - s / 2) / (s / 2), (yy - s / 2) / (s / 2)
    rr = np.hypot(*cxy)
    mist = np.clip(1 - rr, 0, 1) ** 2 * 0.35 * (0.6 + 0.4 * periodic_noise(s, s, 30, rng, 2, 9))
    drops = np.zeros((s, s), np.float32)
    for _ in range(220):
        ang = rng.uniform(0, 2 * np.pi)
        d = abs(rng.normal(0, 0.42))
        px, py = s / 2 + math.cos(ang) * d * s / 2, s / 2 + math.sin(ang) * d * s / 2
        rad = rng.uniform(1.2, 4.5) * (1.2 - d)
        if rad <= 0.5:
            continue
        m = np.exp(-((xx - px) ** 2 + (yy - py) ** 2) / (rad * rad))
        drops = np.maximum(drops, m * rng.uniform(0.5, 1.0))
    sa = np.clip(mist + drops, 0, 1) * (rr < 1)
    save_rgba(np.dstack([np.ones_like(sa) * 0.9, np.ones_like(sa) * 0.95, np.ones_like(sa) * 0.95, sa]),
              os.path.join(TEX, "spray.png"))

    # trail streak: u along the arc (0 = tail, 1 = head), v across; soft edges, fades to the tail
    tw, th = 512, 64
    u = np.linspace(0, 1, tw)[None, :]
    v = np.linspace(-1, 1, th)[:, None]
    ta = np.exp(-(v / (0.2 + 0.4 * u)) ** 2 * 1.5) * u ** 2.4 * np.clip((1 - u) / 0.06, 0, 1)
    save_rgba(np.dstack([np.ones((th, tw)) * 0.75, np.ones((th, tw)), np.ones((th, tw)) * 0.75, ta]),
              os.path.join(TEX, "trail.png"))

    # lighthouse beam: u along the beam (0 at the lantern), v across
    bw, bh = 512, 128
    u = np.linspace(0, 1, bw)[None, :]
    v = np.linspace(-1, 1, bh)[:, None]
    wid = 0.25 + 0.75 * u
    ba = np.exp(-(v / wid) ** 2 * 2.5) * (1 - u) ** 1.3 * np.clip(u / 0.02, 0, 1) * 0.55
    save_rgba(np.dstack([np.ones((bh, bw)), np.ones((bh, bw)) * 0.9, np.ones((bh, bw)) * 0.75, ba]),
              os.path.join(TEX, "beam.png"))


# ================================================================== MODE sky: equirect panorama of the storm sky
def make_sky():
    """Equirect panorama in the engine's convention (Skybox.cpp; centre column = engine +Z = Blender -y,
    u = 0.75 = +x): an ortho camera looks at a plane whose emission is the sky shader evaluated in the direction its
    UV stands for. Same nodes as the concept's world."""
    s = reset()
    agx(s)
    m = bpy.data.materials.new("skyplane")
    N, L = nodes(m)
    N.remove(N["Principled BSDF"])
    tc = N.new("ShaderNodeTexCoord")
    sp = N.new("ShaderNodeSeparateXYZ")
    L.new(tc.outputs["UV"], sp.inputs["Vector"])
    az = _math(N, L, "MULTIPLY", _math(N, L, "SUBTRACT", sp.outputs["X"], 0.5), 2 * math.pi)
    el = _math(N, L, "MULTIPLY", _math(N, L, "SUBTRACT", sp.outputs["Y"], 0.5), math.pi)
    ce = _math(N, L, "COSINE", el)
    dx = _math(N, L, "MULTIPLY", ce, _math(N, L, "SINE", az))
    dy = _math(N, L, "MULTIPLY", _math(N, L, "MULTIPLY", ce, _math(N, L, "COSINE", az)), -1.0)
    dz = _math(N, L, "SINE", el)
    cv = N.new("ShaderNodeCombineXYZ")
    for k, sock in enumerate((dx, dy, dz)):
        L.new(sock, cv.inputs[k])
    em = N.new("ShaderNodeEmission")
    L.new(sky_tree(N, L, cv.outputs[0]), em.inputs["Color"])
    L.new(em.outputs[0], N["Material Output"].inputs["Surface"])
    # the plane overhangs the frame by 2%, so the edge columns (the wrap seam, straight ahead in the engine) are full
    e0, e1 = -0.02, 1.02
    o = mesh("skyplane", [(2 * e0, e0, 0), (2 * e1, e0, 0), (2 * e1, e1, 0), (2 * e0, e1, 0)], [(0, 1, 2, 3)], m, smooth=False)
    quad_uv(o, [(e0, e0), (e1, e0), (e1, e1), (e0, e1)])
    cd = bpy.data.cameras.new("ortho")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.0
    co = link(bpy.data.objects.new("ortho", cd))
    co.location = (1, 0.5, 5)
    s.camera = co
    s.render.resolution_x, s.render.resolution_y = (4096, 2048) if HALF else (8192, 4096)
    s.cycles.samples = 4
    s.cycles.use_denoising = False
    s.render.filepath = os.path.join(LAY, "sky_pano.png")
    bpy.ops.render.render(write_still=True)
    # The concept saw this sky through a warm fog volume (no engine equivalent): bake that warmth into the panorama.
    # Gains measured against the concept image (sky top / mid / horizon averages), by elevation.
    a = load_rgba(s.render.filepath)
    h = a.shape[0]
    elev = 90.0 - 180.0 * (np.arange(h) + 0.5) / h
    f = np.clip(elev / 15.0, 0, 1)[:, None, None]
    lo, hi = np.array([1.03, 0.97, 0.93]), np.array([1.0, 0.9, 0.83])
    a[..., :3] = np.clip(a[..., :3] * (lo * (1 - f) + hi * f), 0, 1)
    # The far sea, painted below the horizon (the camera only slides along x, so the far field never changes): dark
    # water where the near sea tiles end (1.3 deg down) rising into each column's own horizon colour, so the water
    # melts into the warm haze with no line. Replaces the flat far plane in both the target and the game.
    hrow = int(round((90.0 - 0.25) / 180.0 * h))
    hcol = a[hrow][None, :, :3]
    dep = np.clip(-elev, 0, None)[:, None, None]
    k = np.clip((dep - 0.1) / (FAR_SEA_DEG - 0.1), 0, 1) ** 0.7
    sea = hcol * 0.92 * (1 - k) + np.array(FAR_SEA_SRGB)[None, None, :] * k
    a[..., :3] = np.where(elev[:, None, None] < 0, sea, a[..., :3])
    save_rgba(a, s.render.filepath)


# ================================================================== set pieces (local frames)
def mats():
    M = {}
    M["red"] = pbr("red", (0.42, 0.035, 0.025), 0.42, coat=0.3, tint2=(0.22, 0.05, 0.03), scale=3, bump=0.06)
    M["white"] = pbr("white", (0.72, 0.70, 0.65), 0.45, coat=0.3, tint2=(0.48, 0.45, 0.39), scale=3, bump=0.06)
    M["antifoul"] = pbr("antifoul", (0.06, 0.05, 0.04), 0.7, tint2=(0.1, 0.12, 0.06), scale=8, bump=0.2)
    M["iron"] = pbr("iron", (0.05, 0.045, 0.04), 0.5, metal=0.6, tint2=(0.22, 0.09, 0.03), scale=6, bump=0.1)
    M["brass"] = pbr("brass", (0.75, 0.52, 0.25), 0.3, metal=1.0)
    M["rope"] = pbr("rope", (0.45, 0.33, 0.18), 0.85, tint2=(0.3, 0.2, 0.1), tex="wave", scale=60, bump=0.4)
    M["stone"] = pbr("stone", (0.16, 0.155, 0.145), 0.6, tint2=(0.07, 0.07, 0.065), scale=2.5, bump=0.5)
    M["wetstone"] = pbr("wetstone", (0.085, 0.083, 0.078), 0.32, tint2=(0.05, 0.05, 0.048), scale=2.5, bump=0.5)
    M["concrete"] = pbr("concrete", (0.32, 0.31, 0.29), 0.8, tint2=(0.2, 0.19, 0.18), scale=5, bump=0.2)
    M["wood"] = pbr("wood", (0.22, 0.15, 0.09), 0.7, tint2=(0.12, 0.08, 0.05), tex="wave", scale=8, bump=0.15)
    M["woodwet"] = pbr("woodwet", (0.12, 0.09, 0.06), 0.35, tint2=(0.07, 0.05, 0.03), tex="wave", scale=6, bump=0.15)
    M["hull"] = pbr("hull", (0.05, 0.12, 0.2), 0.35, coat=0.5, tint2=(0.03, 0.07, 0.11), scale=2, bump=0.04)
    M["hullred"] = pbr("hullred", (0.32, 0.05, 0.03), 0.55)
    M["cabin"] = pbr("cabin", (0.7, 0.67, 0.6), 0.5, tint2=(0.5, 0.45, 0.38), scale=3)
    M["rubber"] = pbr("rubber", (0.02, 0.02, 0.02), 0.6)
    M["plate"] = pbr("plate", (0.8, 0.79, 0.75), 0.4)
    M["glass_off"] = pbr("glass_off", (0.25, 0.2, 0.15), 0.1, emit=(1.0, 0.6, 0.3), es=0.4)
    M["glass_on"] = pbr("glass_on", (1.0, 0.8, 0.5), 0.1, emit=(1.0, 0.72, 0.38), es=30.0)
    M["glass_grn"] = pbr("glass_grn", (0.6, 1.0, 0.7), 0.1, emit=(0.55, 1.0, 0.6), es=22.0)
    M["window"] = pbr("window", (1.0, 0.7, 0.35), 0.3, emit=(1.0, 0.68, 0.33), es=7.0)
    return M


def lattice(M, mat, base_r, top_r, z0, z1, brace=None):
    legs = []
    for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
        legs.append((V((sx * base_r, sy * base_r, z0)), V((sx * top_r, sy * top_r, z1))))
        rod(legs[-1][0], legs[-1][1], 0.05, mat, verts=10)
    tiers = [0.0, 0.5, 1.0]
    bm = brace or mat
    for i in range(4):
        (a0, a1), (b0, b1) = legs[i], legs[(i + 1) % 4]
        for t0, t1 in zip(tiers[:-1], tiers[1:]):
            p0, p1 = a0.lerp(a1, t0), a1.lerp(a0, 1 - t1)
            q0, q1 = b0.lerp(b1, t0), b1.lerp(b0, 1 - t1)
            rod(p0, q1, 0.028, bm, verts=6)
            rod(q0, p1, 0.028, bm, verts=6)
        for t in tiers[1:]:
            rod(a0.lerp(a1, t), b0.lerp(b1, t), 0.032, bm, verts=6)


def build_buoy(M, kind, lit, number):
    """Channel buoy at the origin: body floats at z = 0; hook at (ARM_FWD, -BUOY_BACK, HOOK_Z_BUOY)."""
    body = M["red"] if kind == "red" else M["white"]
    band = M["white"] if kind == "red" else M["red"]
    if kind == "red":   # can buoy
        prof = [(0, -1.3), (0.9, -1.3), (1.05, -1.1), (1.08, 0.15), (1.08, 0.85), (1.0, 0.98), (0.0, 1.0)]
        lathe(prof, (0, 0, 0), body, mats=[(M["antifoul"], 0.12), (body, 9)])
        deck = 1.0
    else:               # cone (nun) buoy with red bands
        prof = [(0, -1.2), (0.85, -1.2), (1.12, -0.6), (1.15, 0.15), (1.0, 0.55), (0.62, 1.15), (0.0, 1.18)]
        lathe(prof, (0, 0, 0), body, mats=[(M["antifoul"], 0.12), (body, 0.35), (band, 0.75), (body, 9)])
        deck = 1.16
    torus((0, 0, 0.42), 1.13, 0.07, M["rubber"], seg=(48, 8))          # fender ring
    for k in range(6):                                                  # lifting eyes
        a = k * math.pi / 3
        torus((0.98 * math.cos(a), 0.98 * math.sin(a), deck - 0.02), 0.07, 0.018, M["iron"], rot=(90, 0, math.degrees(a)))
    cyl((0, 0, deck + 0.04), 0.72, 0.08, M["iron"], verts=32)
    z0, z1 = deck + 0.08, 3.35
    lattice(M, body, 0.58, 0.27, z0, z1, brace=band if kind == "white" else body)
    # lamp platform, rail, cage, lantern
    box((0, 0, z1 + 0.03), (0.78, 0.78, 0.06), M["iron"], bevel=0.015)
    for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
        rod((sx * 0.37, sy * 0.37, z1), (sx * 0.37, sy * 0.37, z1 + 0.32), 0.015, M["iron"], verts=6)
    for i in range(4):
        a = [(1, 1), (-1, 1), (-1, -1), (1, -1)][i]
        b = [(1, 1), (-1, 1), (-1, -1), (1, -1)][(i + 1) % 4]
        rod((a[0] * 0.37, a[1] * 0.37, z1 + 0.32), (b[0] * 0.37, b[1] * 0.37, z1 + 0.32), 0.015, M["iron"], verts=6)
    glass = (M["glass_on"] if lit else M["glass_off"]) if kind == "red" else (M["glass_grn"] if lit else M["glass_off"])
    lz = z1 + 0.06
    cyl((0, 0, lz + 0.03), 0.2, 0.06, M["iron"], verts=24)
    lathe([(0, 0), (0.15, 0), (0.17, 0.12), (0.17, 0.32), (0.14, 0.42), (0, 0.44)], (0, 0, lz + 0.06), glass, steps=24)
    for k in range(6):
        a = k * math.pi / 3 + 0.3
        rod((0.19 * math.cos(a), 0.19 * math.sin(a), lz + 0.06), (0.19 * math.cos(a), 0.19 * math.sin(a), lz + 0.52), 0.012,
            M["iron"], verts=5)
    torus((0, 0, lz + 0.3), 0.19, 0.012, M["iron"], seg=(24, 5))
    lathe([(0.22, 0), (0.24, 0.02), (0.05, 0.16), (0, 0.17)], (0, 0, lz + 0.52), M["iron"], steps=24)
    # top mark on a short post
    tz = lz + 0.69
    rod((0, 0, tz - 0.02), (0, 0, tz + 0.25), 0.025, M["iron"], verts=8)
    if kind == "red":
        cyl((0, 0, tz + 0.42), 0.17, 0.34, M["red"], verts=24)
    else:
        sphere((0, 0, tz + 0.43), 0.19, M["red"], sub=3)
    # number plate on the camera-facing (-y) side of the tower, mid height
    pz = 2.15
    py = -(0.58 + (0.27 - 0.58) * (pz - z0) / (z1 - z0)) - 0.05
    box((0, py, pz), (0.52, 0.025, 0.42), M["plate"], bevel=0.01)
    if number is not None:     # the game bakes a blank plate and draws the course's number as a decal
        text(str(number), (0, py - 0.016, pz), 0.34, M["red"] if kind == "white" else M["iron"], extrude=0.004)
    # hook arm: davit from the tower head out over the play plane, hook hanging below
    hx, hy, hz = U.ARM_FWD, -U.BUOY_BACK, U.HOOK_Z_BUOY
    pts = [V((0.25, -0.25, z1 - 0.4)), V((0.3, -0.3, z1 + 0.5)), V((0.42, -0.7, hz + 0.45)), V((0.75, -1.3, hz + 0.42)),
           V((hx, hy, hz + 0.3)), V((hx, hy, hz + 0.18))]
    smooth_tube(pts, 0.055, M["iron"])
    rod((0.25, -0.25, z1 - 0.4), (0.27, -0.27, z1 - 1.0), 0.05, M["iron"])
    rod((0.3, -0.35, z1 + 0.3), (0.62, -1.0, hz + 0.38), 0.025, M["iron"], verts=6)      # stay
    torus((hx, hy, hz + 0.12), 0.06, 0.016, M["brass"], rot=(90, 0, 90), seg=(20, 6))
    hook_shape(M, (hx, hy, hz))
    return {"lamp": V((0, 0, lz + 0.28)), "color": (1.0, 0.72, 0.4) if kind == "red" else (0.55, 1.0, 0.6)}


def hook_shape(M, p):
    """A J hook whose throat (where the chain's ring sits) is at p."""
    x, y, z = p
    pts = [V((x, y, z + 0.08)), V((x, y, z - 0.02)), V((x - 0.02, y, z - 0.1)), V((x + 0.08, y, z - 0.12)),
           V((x + 0.12, y, z - 0.04)), V((x + 0.1, y, z + 0.02))]
    smooth_tube(pts, 0.018, M["brass"])


def build_boat(M):
    """Fishing boat at the origin, length along x (bow +x), waterline z = 0."""
    Lh, Bm, D, FB = 8.4, 2.9, 1.3, 1.05
    st, ns = 32, 18
    vs, fs = [], []
    for i in range(st + 1):
        u = i / st
        xx = -Lh / 2 + Lh * u
        half = Bm / 2 * (1 - (max(0, u - 0.5) / 0.5) ** 2.2) * (1 - 0.18 * max(0, 0.12 - u) / 0.12)
        half = max(half, 0.03)
        sheer = FB + 0.55 * max(0, u - 0.55) ** 1.6 * 3 + 0.12 * max(0, 0.2 - u) * 5
        keel = -D * (1 - 0.6 * max(0, u - 0.7) / 0.3)
        for j in range(ns + 1):
            a = math.pi * j / ns
            yy = half * math.cos(a)
            sa = math.sin(a)
            zz = sheer + (keel - sheer) * sa ** 0.6
            vs.append((xx, yy, zz))
    for i in range(st):
        for j in range(ns):
            a = i * (ns + 1) + j
            fs.append((a, a + ns + 1, a + ns + 2, a + 1))
    o = mesh("hull", vs, fs, M["hull"])
    o.data.materials.append(M["hullred"])
    o.data.materials.append(M["white"])
    for f in o.data.polygons:
        z = f.center.z
        f.material_index = 1 if z < -0.02 else (2 if z < 0.12 else 0)
    md = o.modifiers.new("t", "SOLIDIFY")
    md.thickness = 0.06
    # transom
    tr = [(-Lh / 2, Bm / 2 * 0.82 * math.cos(math.pi * j / ns), FB + 0.6 + (-D - FB - 0.6) * math.sin(math.pi * j / ns) ** 0.6)
          for j in range(ns + 1)]
    mesh("transom", tr, [list(range(ns + 1))], M["hull"], smooth=False)
    deck_z = FB - 0.25
    box((0, 0, deck_z), (Lh * 0.92, Bm * 0.86, 0.06), M["woodwet"])
    # gunwale rail
    for side in (1, -1):
        pts = []
        for i in range(0, st + 1, 2):
            v = vs[i * (ns + 1) + (0 if side > 0 else ns)]
            pts.append(V((v[0], v[1] - side * 0.03, v[2] + 0.04)))
        smooth_tube(pts, 0.05, M["wood"])
    # wheelhouse (aft of midships), windows lit
    cx = -1.5
    box((cx, 0, deck_z + 0.85), (2.1, 1.9, 1.7), M["cabin"], bevel=0.06)
    box((cx, 0, deck_z + 1.76), (2.5, 2.2, 0.12), M["hull"], bevel=0.04)
    for wy in (-0.45, 0.45):
        box((cx + 1.06, wy, deck_z + 1.25), (0.04, 0.62, 0.5), M["window"])
    for wx in (-0.5, 0.35):
        box((cx + wx, -0.96, deck_z + 1.22), (0.55, 0.04, 0.45), M["window"])
        box((cx + wx, 0.96, deck_z + 1.22), (0.55, 0.04, 0.45), M["window"])
    box((cx - 1.06, 0, deck_z + 0.75), (0.04, 0.6, 1.2), M["wood"])          # back door
    torus((cx - 0.2, -0.99, deck_z + 0.55), 0.24, 0.05, M["red"], rot=(90, 0, 0), seg=(24, 8))   # life ring
    # mast, crosstree, derrick boom, rigging
    mx = 1.1
    mt = deck_z + 5.6
    rod((mx, 0, deck_z), (mx, 0, mt), 0.07, M["cabin"], verts=12)
    rod((mx, -0.9, mt - 1.3), (mx, 0.9, mt - 1.3), 0.04, M["cabin"], verts=8)
    rod((mx, 0, deck_z + 1.2), (mx + 2.6, 0, deck_z + 3.3), 0.05, M["wood"], verts=8)
    sphere((mx, 0, mt + 0.08), 0.09, M["glass_on"], sub=2)
    rope = M["rope"]
    for a, b in [((mx, 0, mt), (Lh / 2 + 0.05, 0, FB + 0.8)), ((mx, 0, mt), (cx - 1.05, 0, deck_z + 1.85)),
                 ((mx, -0.9, mt - 1.3), (mx - 0.3, -Bm / 2, FB + 0.05)), ((mx, 0.9, mt - 1.3), (mx - 0.3, Bm / 2, FB + 0.05)),
                 ((mx, 0, mt - 0.3), (mx + 2.6, 0, deck_z + 3.3)), ((mx + 2.6, 0, deck_z + 3.3), (mx + 2.4, 0, deck_z + 0.4)),
                 ((cx - 1.05, 0, deck_z + 1.85), (-Lh / 2 + 0.2, 0, FB + 0.6))]:
        rod(a, b, 0.012, rope, verts=5)
    # stern gallows (A-frame) and net drum
    for sy in (-0.9, 0.9):
        rod((-Lh / 2 + 0.5, sy, deck_z), (-Lh / 2 + 0.4, sy * 0.6, deck_z + 2.2), 0.06, M["iron"], verts=8)
    rod((-Lh / 2 + 0.4, -0.55, deck_z + 2.2), (-Lh / 2 + 0.4, 0.55, deck_z + 2.2), 0.06, M["iron"], verts=8)
    cyl((-Lh / 2 + 1.4, 0, deck_z + 0.55), 0.45, 1.4, pbr("net", (0.12, 0.25, 0.18), 0.8, tint2=(0.06, 0.12, 0.09), tex="wave",
                                                          scale=40, bump=0.5), rot=(90, 0, 0))
    # tyre fenders on the camera side
    for fx in (-2.6, -0.4, 1.8):
        torus((fx, -Bm / 2 - 0.05, FB - 0.35), 0.22, 0.08, M["rubber"], rot=(90, 0, 0), seg=(20, 8))
    return {"lights": [(V((cx, 0, deck_z + 1.2)), 25.0, (1.0, 0.68, 0.35)), (V((mx, 0, mt + 0.08)), 6.0, (1.0, 0.75, 0.4))]}


def rock(M, loc, s, rng, scale, rough=0.32):
    o = sphere(loc, s, M["stone"], scale=scale, sub=3)
    o.rotation_euler = tuple(rng.uniform(0, 3) for _ in range(3))
    dm = o.modifiers.new("d", "DISPLACE")
    tx = bpy.data.textures.new("rock", "CLOUDS")
    tx.noise_scale = 0.55 if rough > 0.2 else 1.1
    dm.texture = tx
    dm.strength = rough * s
    return o


def build_breakwater(M, length=U.BW_SEG, seed=5):
    """Rubble mound with a concrete crown wall, x in [0, length], centred on local y = 0. Tiles along x."""
    rng = random.Random(seed)
    wet = M["wetstone"]
    # big rounded boulders as the concept's (22:5x): fewer, larger, smoother, the crest row high against the sky
    rows = ((-2.8, -0.3, 1.5), (-1.1, 1.0, 1.85), (0.8, 2.0, 2.05), (2.6, 1.5, 1.8))
    for row, (yy, zz, s) in enumerate(rows):
        x = rng.uniform(0, 1.2)
        while x < length:
            o = rock(M, (x + rng.uniform(-0.25, 0.25), yy + rng.uniform(-0.3, 0.3), zz + rng.uniform(-0.25, 0.25)),
                     s * rng.uniform(0.85, 1.1), rng, (rng.uniform(1.0, 1.25), rng.uniform(0.85, 1.05), rng.uniform(0.78, 0.95)), rough=0.12)
            o.data.materials[0] = wet
            x += s * rng.uniform(1.35, 1.7)
    box((length / 2, 1.9, 2.55), (length, 0.9, 0.8), M["concrete"], bevel=0.04)      # low crown wall behind the crest
    for bx in np.arange(1.0, length, 4.0):
        cyl((bx, 1.6, 3.03), 0.13, 0.18, M["iron"], verts=12)


def build_gap(M):
    """Harbour mouth: two breakwater heads with beacon posts, open water between (x in [0, BW_GAP])."""
    rng = random.Random(9)
    for x0, sgn, beacon in ((0.0, 1, "red"), (U.BW_GAP, -1, "grn")):
        for k in range(7):
            a = rng.uniform(-1.4, 1.4)
            r = rng.uniform(0.2, 1.4)
            o = rock(M, (x0 + sgn * (0.8 + 0.6 * math.cos(a) * r * 0.6), r * math.sin(a) * 1.8, rng.uniform(-0.3, 1.1)),
                     rng.uniform(1.0, 1.35), rng, (1.1, 1.0, 0.85), rough=0.12)
            o.data.materials[0] = M["wetstone"]
        bx = x0 + sgn * 0.9
        cyl((bx, 0.2, 1.6), 0.8, 1.6, M["concrete"], verts=32)
        cyl((bx, 0.2, 2.6), 0.24, 1.6, M["red"] if beacon == "red" else pbr("green", (0.03, 0.22, 0.08), 0.4), verts=24)
        cyl((bx, 0.2, 3.45), 0.17, 0.12, M["iron"], verts=16)
        sphere((bx, 0.2, 3.62), 0.14, M["glass_on"] if beacon == "red" else M["glass_grn"], sub=3)
        cyl((bx, 0.2, 3.8), 0.18, 0.04, M["iron"], verts=16)
    return {"lights": [(V((0.9, 0.2, 3.62)), 30.0, (1.0, 0.6, 0.35)), (V((U.BW_GAP - 0.9, 0.2, 3.62)), 30.0, (0.55, 1.0, 0.6))]}


def build_pier(M, lit):
    """One pier segment, x in [0, PIER_SEG], deck centre line at local y = 0 (placed at PIER_Y); lamp arm hook at
    (PIER_SEG / 2, -PIER_Y, HOOK_Z_PIER)."""
    Ls, W, dz = U.PIER_SEG, 3.0, 1.7
    for px in np.arange(0.5, Ls, 2.5):
        for py in (-W / 2 + 0.15, W / 2 - 0.15):
            cyl((px, py, dz / 2 - 1.2), 0.17, dz + 2.4, M["woodwet"], verts=14)
            torus((px, py, 0.25), 0.18, 0.03, pbr("weed", (0.05, 0.08, 0.03), 0.9), seg=(16, 6))
        rod((px, -W / 2 + 0.15, 0.2), (px, W / 2 - 0.15, dz - 0.3), 0.06, M["woodwet"], verts=6)
    for py in (-W / 2 + 0.2, W / 2 - 0.2):
        box((Ls / 2, py, dz - 0.15), (Ls, 0.22, 0.28), M["wood"])
    for i, px in enumerate(np.arange(0.12, Ls, 0.25)):
        box((px, 0, dz + 0.04), (0.22, W, 0.06), M["wood"] if i % 3 else M["woodwet"])
    for px in np.arange(0, Ls + 0.01, 2.0):                           # back railing
        rod((px + 0.1, W / 2 - 0.1, dz), (px + 0.1, W / 2 - 0.1, dz + 1.0), 0.04, M["wood"], verts=6)
    rod((0, W / 2 - 0.1, dz + 1.0), (Ls, W / 2 - 0.1, dz + 1.0), 0.04, M["wood"], verts=6)
    rod((0, W / 2 - 0.1, dz + 0.55), (Ls, W / 2 - 0.1, dz + 0.55), 0.03, M["wood"], verts=6)
    for bx in (1.4, 6.6):                                              # bollards + tyres on the front
        lathe([(0, 0), (0.16, 0), (0.12, 0.28), (0.2, 0.34), (0.18, 0.4), (0, 0.4)], (bx, -W / 2 + 0.3, dz + 0.07), M["iron"], steps=16)
        torus((bx, -W / 2 - 0.08, dz - 0.4), 0.24, 0.08, M["rubber"], rot=(90, 0, 0), seg=(20, 8))
    # lamp post with a hook arm reaching to the play plane
    lx, ly = Ls / 2, -W / 2 + 0.25
    rod((lx, ly, dz), (lx, ly, 5.0), 0.08, M["iron"], verts=12)
    cyl((lx, ly, dz + 0.15), 0.16, 0.3, M["iron"], verts=12)
    lathe([(0, 0), (0.15, 0), (0.17, 0.12), (0.17, 0.36), (0, 0.4)], (lx, ly, 5.0), M["glass_on"] if lit else M["glass_off"], steps=20)
    lathe([(0.24, 0), (0.05, 0.18), (0, 0.19)], (lx, ly, 5.4), M["iron"], steps=20)
    hy = -U.PIER_Y
    hz = U.HOOK_Z_PIER
    smooth_tube([V((lx, ly, 4.5)), V((lx, ly - 0.6, hz + 0.6)), V((lx, (ly + hy) / 2 - 0.3, hz + 0.55)), V((lx, hy, hz + 0.32)),
                 V((lx, hy, hz + 0.18))], 0.05, M["iron"])
    torus((lx, hy, hz + 0.12), 0.06, 0.016, M["brass"], rot=(90, 0, 90), seg=(20, 6))
    hook_shape(M, (lx, hy, hz))
    return {"lamp": V((lx, ly, 5.2)), "color": (1.0, 0.72, 0.4)}


# ================================================================== MODE bake
def bake_world():
    storm_sky()
    light("SUN", (0, 0, 10), 0.6, (1.0, 0.65, 0.4), size=4, target=(-20, -40, -6))
    sea = mesh("seaplane", [(-60, -60, -0.01), (60, -60, -0.01), (60, 60, -0.01), (-60, 60, -0.01)], [(0, 1, 2, 3)],
               pbr("bakesea", (0.01, 0.03, 0.026), 0.12), smooth=False)
    sea.hide_render = False
    return sea


def join_mesh(exclude):
    bpy.ops.object.select_all(action="DESELECT")
    objs = [o for o in sc().objects if o.type in ("MESH", "CURVE", "FONT") and o not in exclude]
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")
    objs = [o for o in sc().objects if o.type == "MESH" and o not in exclude]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = "piece"
    return o


def bake_piece(name, build, res=2048, variants=(None,), haze=0.0):
    """Build a piece, unwrap, bake COMBINED lighting per variant into PNG (AgX graded), export OBJ (engine axes)."""
    s = reset()
    agx(s)
    s.cycles.samples = 64 if HALF else 384
    s.cycles.use_denoising = False
    M = mats()
    sea = bake_world()
    first = True
    obj = None
    for var in variants:
        if first:
            info = build(M, var) or {}
            obj = join_mesh([sea])
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(angle_limit=R(60), island_margin=0.004)
            bpy.ops.object.mode_set(mode="OBJECT")
            first = False
        else:   # relight: swap lamp glass emission for this variant
            for slot in obj.material_slots:
                if slot.material and slot.material.name.startswith("glass_off") and var == "lit":
                    slot.material = M["glass_on"] if "white" not in name else M["glass_grn"]
            info = info
        lights = []
        if var == "lit" and info.get("lamp") is not None:
            lights.append(light("POINT", info["lamp"], 40.0, info["color"], size=0.12))
        for p, e, c in info.get("lights", []):
            lights.append(light("POINT", p, e, c, size=0.12))
        im = bpy.data.images.new(name, res, res, alpha=False, float_buffer=True)
        for slot in obj.material_slots:
            m = slot.material
            N = m.node_tree.nodes
            t = N.get("BAKE") or N.new("ShaderNodeTexImage")
            t.name = "BAKE"
            t.image = im
            N.active = t
            t.select = True
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        s.render.bake.margin = 6
        bpy.ops.object.bake(type="COMBINED")
        if haze:
            px = np.empty(res * res * 4, np.float32)
            im.pixels.foreach_get(px)
            px = px.reshape(-1, 4)
            hz = np.array(HORIZON_COL, np.float32) * 0.55
            px[:, :3] = px[:, :3] * (1 - haze) + hz * haze
            im.pixels.foreach_set(px.ravel())
        tag = name + ("_" + var if var else "")
        im.save_render(os.path.join(PCS, tag + ".png"), scene=s)
        print("baked", tag)
        for lo in lights:
            bpy.data.objects.remove(lo)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.wm.obj_export(filepath=os.path.join(PCS, name + ".obj"), export_selected_objects=True, export_uv=True,
                          export_normals=True, export_materials=False, forward_axis="NEGATIVE_Z", up_axis="Y",
                          apply_modifiers=True)
    print("faces", name, len(obj.data.polygons))
    return len(obj.data.polygons)


def make_bakes():
    only = [a for a in argv[1:] if not a.startswith("--") and not a.isdigit()]
    jobs = {
        "buoy_red": lambda: bake_piece("buoy_red", lambda M, v: build_buoy(M, "red", False, None), variants=("unlit", "lit")),
        "buoy_white": lambda: bake_piece("buoy_white", lambda M, v: build_buoy(M, "white", False, None), variants=("unlit", "lit")),
        "boat": lambda: bake_piece("boat", lambda M, v: build_boat(M)),
        "pier": lambda: bake_piece("pier", lambda M, v: build_pier(M, False), variants=("unlit", "lit")),
        "bw": lambda: bake_piece("bw", lambda M, v: build_breakwater(M), haze=0.06),
        "bw_gap": lambda: bake_piece("bw_gap", lambda M, v: build_gap(M), res=1024, haze=0.06),
    }
    path = os.path.join(PCS, "faces.txt")
    counts = {}
    if os.path.exists(path):
        for line in open(path):
            k, v = line.split()
            counts[k] = int(v)
    for k, job in jobs.items():
        if not only or k in only:
            counts[k] = job()
    with open(path, "w") as f:
        for k, v in counts.items():
            f.write("%s %d\n" % (k, v))


# ================================================================== MODE far: the far layer card (ortho, alpha)
def make_far():
    s = reset()
    agx(s)
    storm_sky(0.8)
    s.render.film_transparent = True
    M = mats()
    rng = random.Random(21)
    sil = pbr("farland", (0.05, 0.05, 0.05), 0.8, tint2=(0.03, 0.03, 0.03), scale=0.3, bump=0.2)
    # far shore: periodic hill profile over FAR_W, extruded in depth (repeats seamlessly)
    W = FAR_W
    nseg = 512
    harm = [(1, 2.2, 0.4), (2, 1.4, 1.7), (3, 0.9, 3.0), (5, 0.6, 0.6), (9, 0.35, 2.1), (17, 0.18, 4.4), (31, 0.08, 1.2)]

    def prof(x):
        h = 2.6
        for k, a, ph in harm:
            h += a * math.sin(2 * math.pi * k * x / W + ph)
        hl = 9.0 * math.exp(-((x - 52.0) / 14.0) ** 2)         # the lighthouse headland
        return max(0.4, h + hl)
    vs, fs = [], []
    for i in range(nseg + 1):
        x = -W / 2 - 8 + (W + 16) * i / nseg
        for dy in (-6.0, 0.0, 6.0):
            vs.append((x, FAR_Y + dy, (prof(x) if dy >= 0 else prof(x) * 0.7) - (0 if dy >= 0 else 0.5)))
        vs.append((x, FAR_Y - 6.0, -1.0))
    for i in range(nseg):
        for j in range(3):
            a, b = i * 4 + j, (i + 1) * 4 + j
            fs.append((a, b, b + 1, a + 1))
    mesh("shore", vs, fs, sil)
    # lighthouse on the headland
    LH = V((52.0, FAR_Y - 2.0, prof(52.0) - 0.5))
    lathe([(0, 0), (2.4, 0), (1.75, 12), (1.45, 12.4), (0, 12.4)], LH, M["white"])
    lathe([(1.5, 0), (1.5, 0.6), (0, 0.6)], LH + V((0, 0, 12.4)), M["iron"])
    lathe([(0, 0), (1.2, 0), (1.2, 1.8), (0, 1.8)], LH + V((0, 0, 13.0)), pbr("lantern", (1.0, 0.85, 0.6), 0.2, emit=(1.0, 0.85, 0.6), es=25))
    lathe([(1.45, 0), (0.1, 1.4), (0, 1.45)], LH + V((0, 0, 14.8)), M["red"])
    light("POINT", LH + V((0, 0, 13.9)), 3000, (1.0, 0.85, 0.6), size=0.5)
    # town lights and roofs along the shore, distant masts of a marina
    win = pbr("farwin", (1.0, 0.7, 0.35), 0.5, emit=(1.0, 0.68, 0.35), es=12)
    houses = pbr("farhouse", (0.08, 0.075, 0.07), 0.8)
    for _ in range(60):
        x = rng.uniform(-W / 2, W / 2)
        if abs(x - 52) < 16:
            continue
        z = prof(x) - rng.uniform(0.3, 1.6)
        b = box((x, FAR_Y - 6.5, z), (rng.uniform(1.5, 3.5), 1.0, rng.uniform(1.0, 2.2)), houses)
        if rng.random() < 0.7:
            box((x + rng.uniform(-0.5, 0.5), FAR_Y - 7.05, z + rng.uniform(-0.2, 0.4)), (0.35, 0.05, 0.3), win)
    for _ in range(40):
        x = rng.uniform(-110, -40)
        h = rng.uniform(4, 9)
        rod((x, FAR_Y - 8, -0.5), (x + rng.uniform(-0.2, 0.2), FAR_Y - 8, h), 0.06, M["cabin"], verts=6)
        if rng.random() < 0.4:
            sphere((x, FAR_Y - 8, h), 0.12, win, sub=1)
    # horizon haze band (part of the far layer, so the card carries it)
    haze = card_mat("haze", os.path.join(TEX, "glow.png"), 0.0)
    hz = mesh("hazeband", [(-W / 2 - 20, FAR_Y - 9, FAR_Z0), (W / 2 + 20, FAR_Y - 9, FAR_Z0), (W / 2 + 20, FAR_Y - 9, 6),
                           (-W / 2 - 20, FAR_Y - 9, 6)], [(0, 1, 2, 3)], None, smooth=False)
    hm = bpy.data.materials.new("hazemat")
    N, L = nodes(hm)
    N.remove(N["Principled BSDF"])
    tc = N.new("ShaderNodeTexCoord")
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(tc.outputs["Generated"], sep.inputs["Vector"])
    rp = N.new("ShaderNodeValToRGB")
    rp.color_ramp.elements[0].position, rp.color_ramp.elements[0].color = 0.15, (1, 1, 1, 1)
    rp.color_ramp.elements[1].position, rp.color_ramp.elements[1].color = 1.0, (0, 0, 0, 1)
    L.new(sep.outputs["Z"], rp.inputs["Fac"])
    am = N.new("ShaderNodeMath")
    am.operation = "MULTIPLY"
    am.inputs[1].default_value = 0.55
    L.new(rp.outputs["Color"], am.inputs[0])
    em = N.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*HORIZON_COL, 1)
    em.inputs["Strength"].default_value = 0.9
    tr = N.new("ShaderNodeBsdfTransparent")
    mx = N.new("ShaderNodeMixShader")
    L.new(am.outputs[0], mx.inputs[0])
    L.new(tr.outputs[0], mx.inputs[1])
    L.new(em.outputs[0], mx.inputs[2])
    L.new(mx.outputs[0], N["Material Output"].inputs["Surface"])
    hz.data.materials.append(hm)
    light("SUN", (0, 0, 10), 1.2, (1.0, 0.6, 0.35), size=4, target=(-20, -40, -6))
    # orthographic camera covering exactly the card [−W/2, W/2] x [FAR_Z0, FAR_Z0 + FAR_H]
    cd = bpy.data.cameras.new("ortho")
    cd.type = "ORTHO"
    cd.ortho_scale = W
    co = link(bpy.data.objects.new("ortho", cd))
    co.location = (0, FAR_Y - 60, FAR_Z0 + FAR_H / 2)
    co.rotation_euler = (R(90), 0, 0)
    s.camera = co
    s.render.resolution_x, s.render.resolution_y = FAR_PX
    if HALF:
        s.render.resolution_percentage = 50
    s.cycles.samples = SAMPLES
    s.render.filepath = os.path.join(LAY, "far_layer.png")
    s.render.image_settings.color_mode = "RGBA"
    bpy.ops.render.render(write_still=True)
    # haze toward the horizon colour (distance fog baked in), keep alpha
    a = load_rgba(os.path.join(LAY, "far_layer.png"))
    hz_srgb = np.array([0.42, 0.33, 0.27], np.float32)
    f = 0.42
    m = a[..., 3:4] > 0
    a[..., :3] = np.where(m, a[..., :3] * (1 - f) + hz_srgb * f * a[..., 3:4], a[..., :3])
    save_rgba(a, os.path.join(LAY, "far_layer.png"))


# ================================================================== live parts
def sea_material(frame=0):
    """Engine: base_color texture sea_detail.png x vertex colour, roughness 0.12, normal map sea_normal_NN."""
    m = bpy.data.materials.new("sea")
    N, L = nodes(m)
    p = N["Principled BSDF"]
    p.inputs["IOR"].default_value = 1.33
    p.inputs["Roughness"].default_value = 0.12
    ca = N.new("ShaderNodeVertexColor")
    ca.layer_name = "Col"
    dt = N.new("ShaderNodeTexImage")
    dt.image = img_tex(os.path.join(TEX, "sea_detail.png"))
    mul = N.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    L.new(ca.outputs["Color"], mul.inputs[6])
    L.new(dt.outputs["Color"], mul.inputs[7])
    L.new(mul.outputs[2], p.inputs["Base Color"])
    nt = N.new("ShaderNodeTexImage")
    nt.image = img_tex(os.path.join(TEX, "sea_normal_%02d.png" % frame), "Non-Color")
    nm = N.new("ShaderNodeNormalMap")
    L.new(nt.outputs["Color"], nm.inputs["Color"])
    L.new(nm.outputs["Normal"], p.inputs["Normal"])
    return m


def far_sea_material(frame=0):
    m = sea_material(frame)
    N, L = m.node_tree.nodes, m.node_tree.links
    p = N["Principled BSDF"]
    for l in list(p.inputs["Base Color"].links):
        L.remove(l)
    p.inputs["Base Color"].default_value = (*[c ** 2.2 for c in uw_sea.FAR], 1)
    p.inputs["Roughness"].default_value = 0.1
    return m


TILE = None


def build_sea(x_center, t=0.0):
    """Near sea: pooled tiles of SEA_P, slid along x by SEA_C * t (engine: set_positions every frame), plus a flat
    far plane to the horizon that follows the camera in steps of the ripple repeat."""
    global TILE
    if TILE is None:
        TILE = uw_sea.tile(world_uv=False)
    V_, N_, C_, T_, Q_ = TILE
    frame = int(t * U.RIPPLE_FPS) % U.RIPPLE_FRAMES
    m = sea_material(frame)
    shift = (U.SEA_C * t) % U.SEA_P
    tiles = []
    k0 = math.floor((x_center - 70 - shift) / U.SEA_P)
    k1 = math.floor((x_center + 110 - shift) / U.SEA_P)
    for k in range(k0, k1 + 1):
        o = mesh("sea%d" % k, V_, Q_, m)
        o.location = (k * U.SEA_P + shift, 0, 0)
        me = o.data
        ca = me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
        for vi, c in enumerate(C_):
            ca.data[vi].color_srgb = (*c, 1.0)
        uv = me.uv_layers.new(name="UVMap")
        for li, l in enumerate(me.loops):
            uv.data[li].uv = T_[l.vertex_index]
        me.normals_split_custom_set_from_vertices([tuple(n) for n in N_])
        o.visible_shadow = False
        tiles.append(o)
    return tiles


def float_rig(hook, theta, L, cam_loc, spray=True, trail=True):
    """Glass float on a chain, hooked at `hook`, angle theta (0 = straight down, + = swung ahead)."""
    hook = V(hook)

    def arc(th):
        return hook + V((L * math.sin(th), 0, -L * math.cos(th)))
    F = arc(theta)
    rf = U.FLOAT_R
    glass = pbr("floatglass", (0.22, 0.62, 0.36), 0.04, emit=(0.35, 1.0, 0.5), es=0.35, alpha=0.5)
    glass.node_tree.nodes["Principled BSDF"].inputs["Coat Weight"].default_value = 1.0
    g = uvsphere(F, rf, glass, seg=48, rings=24)
    g.visible_shadow = False
    inner = pbr("floatinner", (0.3, 1.0, 0.5), 0.5, emit=(0.4, 1.0, 0.55), es=2.5, alpha=0.35)
    i = uvsphere(F, rf * 0.8, inner, seg=32, rings=16)
    i.visible_shadow = False
    core = pbr("core", (1.0, 0.95, 0.7), 0.5, emit=(1.0, 0.95, 0.65), es=40.0)
    c = uvsphere(F, 0.1, core, seg=16, rings=8)
    c.visible_shadow = False
    light("POINT", F, 70.0, (0.75, 1.0, 0.6), size=0.1)
    rope = pbr("netrope", (0.42, 0.31, 0.17), 0.85, tint2=(0.28, 0.19, 0.1), tex="wave", scale=60, bump=0.4)
    ax = (hook - F).normalized()
    q = ax.to_track_quat("Z", "Y")
    for k in range(4):
        o = torus(F, rf + 0.012, 0.014, rope, seg=(48, 6))
        o.rotation_euler = (q @ Euler((math.pi / 2, 0, k * math.pi / 4)).to_quaternion()).to_euler()
    for h in (-0.22, 0.0, 0.22):
        r = math.sqrt(rf * rf - h * h) + 0.012
        o = torus(F + ax * h, r, 0.014, rope, seg=(48, 6))
        o.rotation_euler = q.to_euler()
    top = F + ax * (rf + 0.06)
    o = torus(top, 0.06, 0.018, rope, seg=(20, 6))
    o.rotation_euler = (q @ Euler((math.pi / 2, 0, 0)).to_quaternion()).to_euler()
    # chain: one link mesh repeated (engine: pooled link nodes, posed with set_positions / set_rotations)
    iron = pbr("chain", (0.09, 0.08, 0.07), 0.35, metal=0.8, tint2=(0.2, 0.1, 0.05), scale=30)
    a, b = hook + V((0, 0, 0.1)), top
    pitch = 0.085
    n = int((b - a).length / pitch)
    d = (b - a).normalized()
    base = d.to_track_quat("Y", "Z")
    for k in range(n):
        cc = a.lerp(b, (k + 0.5) / n)
        o = torus(cc, 0.05, 0.013, iron, seg=(16, 6))      # ring in local XY: contains the chain axis (Y)
        o.scale = (0.6, 1.0, 1.0)                           # oval link, long along the chain
        o.rotation_euler = (base @ Euler((0, (k % 2) * math.pi / 2 + 0.785, 0)).to_quaternion()).to_euler()
    ring = pbr("ring", (0.75, 0.52, 0.25), 0.3, metal=1.0)
    torus(hook + V((0, 0, 0.04)), 0.065, 0.016, ring, rot=(90, 0, 0), seg=(20, 6))
    if trail:   # soft streak along the arc behind the float: one ribbon mesh in the swing's frame
        tm = card_mat("trail", os.path.join(TEX, "trail.png"), 1.3, tint=(0.7, 1.0, 0.75), additive=True)
        seg = 40
        th0, th1 = theta - R(48), theta - R(2)
        vs, uvl = [], []
        for k in range(seg + 1):
            u = k / seg
            th = th0 + (th1 - th0) * u
            p = arc(th)
            rr = rf * (0.2 + 0.6 * u)
            nrm = (p - hook).normalized()
            vs += [p + nrm * rr + V((0, -0.05, 0)), p - nrm * rr + V((0, -0.05, 0))]
            uvl += [(u, 1.0), (u, 0.0)]
        fs = [(2 * k, 2 * k + 2, 2 * k + 3, 2 * k + 1) for k in range(seg)]
        o = mesh("trail", vs, fs, tm, smooth=False)
        quad_uv(o, uvl)
        o.visible_shadow = False
    return F


def splash(F, cam_loc, rng, n=26, dirx=1.0, t=0.0):
    """Spray where the float skims: camera-facing sprites (engine: pooled quads), lit only by emission."""
    sm = card_mat("spray", os.path.join(TEX, "spray.png"), 0.7, tint=(0.75, 0.9, 0.85), additive=True)
    smg = card_mat("spraygrn", os.path.join(TEX, "spray.png"), 1.2, tint=(0.55, 1.0, 0.65), additive=True)
    wz = U.sea_height(F.x, 0.0, t)
    for k in range(n):
        t = rng.uniform(0, 1)
        back = -dirx * t * 2.4
        up = 0.15 + 1.1 * t * (1 - t) * 2 + rng.uniform(-0.1, 0.25)
        loc = V((F.x + back + rng.uniform(-0.3, 0.3), rng.uniform(-0.6, 0.5), wz + up * rng.uniform(0.4, 1.0)))
        sz = rng.uniform(0.45, 1.1) * (0.7 + t * 0.6)
        near = (loc - F).length < 1.0
        billboard(loc, sz, sz, smg if near else sm, cam_loc, "spray", roll=rng.uniform(0, 360))
    # skim wake: a flat foam streak card on the water along the skim
    fm = card_mat("wake", os.path.join(TEX, "spray.png"), 0.7, tint=(0.8, 0.9, 0.88), alpha_mul=0.8)
    for k in range(5):
        x = F.x - dirx * (0.4 + k * 0.55)
        o = mesh("wake", [(-0.55, -0.35, 0), (0.55, -0.35, 0), (0.55, 0.35, 0), (-0.55, 0.35, 0)], [(0, 1, 2, 3)], fm, smooth=False)
        quad_uv(o, [(0, 0), (1, 0), (1, 1), (0, 1)])
        o.location = (x, 0.0, U.sea_height(x, 0.0, t) + 0.06)
        o.scale = (1.4 - k * 0.15, 1.0, 1)
        o.visible_shadow = False


def rain_cards(cam):
    """Three camera-attached rain layers (engine: unlit alpha quads parented to the camera, scrolled down)."""
    mw = cam.matrix_world
    for dist, tex, k, uvs in ((2.5, "rain_near.png", 0.10, (1.2, 0.8)), (6.0, "rain_mid.png", 0.13, (2.2, 1.4)),
                              (14.0, "rain_far.png", 0.12, (4.0, 2.5))):
        cd = cam.data
        hw = dist * 18.0 / cd.lens * 1.05
        hh = hw * 9 / 16
        m = card_mat("rain%.0f" % dist, os.path.join(TEX, tex), k, tint=(0.8, 0.82, 0.86), uv_scale=uvs, additive=True)
        o = mesh("rain", [(-hw, -hh, -dist), (hw, -hh, -dist), (hw, hh, -dist), (-hw, hh, -dist)], [(0, 1, 2, 3)], m, smooth=False)
        quad_uv(o, [(0, 0), (1, 0), (1, 1), (0, 1)])
        o.matrix_world = mw.copy()
        o.visible_shadow = False
        o.visible_glossy = False


def glow_sprite(loc, size, color, strength, cam_loc):
    m = card_mat("glow", os.path.join(TEX, "glow.png"), strength, tint=color, additive=True)
    o = billboard(loc, size, size, m, cam_loc, "glow")
    o.visible_glossy = False
    return o


def setup_camera(fx):
    s = sc()
    cd = bpy.data.cameras.new("game")
    cd.lens = U.LENS
    cd.sensor_fit = "HORIZONTAL"
    cd.sensor_width = 36
    cd.clip_end = 3000
    co = link(bpy.data.objects.new("game", cd))
    co.location = (fx + U.CAM_DX, U.CAM_Y, U.CAM_Z)
    co.rotation_euler = (R(90 + U.CAM_PITCH), 0, R(-U.CAM_YAW))
    s.camera = co
    bpy.context.view_layer.update()
    return co


def compositor_bloom(s):
    ng = bpy.data.node_groups.new("comp", "CompositorNodeTree")
    s.compositing_node_group = ng
    rl = ng.nodes.new("CompositorNodeRLayers")
    gl = ng.nodes.new("CompositorNodeGlare")
    for v in ("Bloom", "BLOOM"):
        try:
            gl.inputs["Type"].default_value = v
            break
        except (TypeError, ValueError):
            continue
    gl.inputs["Threshold"].default_value = 0.8      # engine bloom is luminance-weighted, no hard threshold
    gl.inputs["Strength"].default_value = 0.4
    gl.inputs["Size"].default_value = 0.6
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    out = ng.nodes.new("NodeGroupOutput")
    ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
    ng.links.new(gl.outputs["Image"], out.inputs[0])


def place_piece(kind, x, p, cam_loc, t=0.0):
    """Import a baked piece OBJ and draw it unlit with its baked texture."""
    name = {"buoy_red": "buoy_red", "buoy_white": "buoy_white", "boat": "boat", "pier": "pier", "bw": "bw",
            "bw_gap": "bw_gap"}[kind]
    lit = p.get("lit", False)
    var = ("_lit" if lit else "_unlit") if kind in ("buoy_red", "buoy_white", "pier") else ""
    key = name + var
    if key not in MATCACHE:
        MATCACHE[key] = unlit_mat(key, os.path.join(PCS, key + ".png"))
    objs = []
    reps = p.get("segs", 1)
    for r in range(reps):
        bpy.ops.wm.obj_import(filepath=os.path.join(PCS, name + ".obj"), forward_axis="NEGATIVE_Z", up_axis="Y")
        o = bpy.context.selected_objects[0]
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)   # importer's axis turn into the mesh
        o.data.materials.clear()
        o.data.materials.append(MATCACHE[key])
        sc_ = p.get("scale", 1.0)
        o.scale = (sc_, sc_, sc_)
        if kind.startswith("buoy"):
            o.location = U.piece_origin(kind, x, p, t)
            o.rotation_euler = (R(p.get("roll", U.BUOY_TILT[0])), R(p.get("pitch", U.BUOY_TILT[1])), 0)
        elif kind == "boat":
            o.location = U.piece_origin(kind, x, p, t)
            o.rotation_euler = (R(p.get("roll", 0)), 0, R(p.get("yaw", 0)))
        elif kind == "pier":
            o.location = (x + r * U.PIER_SEG, U.PIER_Y, 0)
        else:
            o.location = (x, U.BW_Y, 0)
        o.visible_shadow = False
        objs.append(o)
    # live lamp light + halo (lamps light up when hooked)
    if kind.startswith("buoy"):
        sc_ = p.get("scale", 1.0)
        bpy.context.view_layer.update()
        lamp = objs[0].matrix_world @ V((0, 0, 3.69))
        col = (1.0, 0.72, 0.4) if kind == "buoy_red" else (0.6, 1.0, 0.65)
        if lit:
            light("POINT", lamp, 60.0 * sc_, col, size=0.12)
            glow_sprite(lamp, 1.6 * sc_, col, 2.5, cam_loc)
        else:
            glow_sprite(lamp, 0.6 * sc_, (1.0, 0.6, 0.3), 0.6, cam_loc)
    if kind == "pier":
        for r in range(reps):
            lamp = V((x + r * U.PIER_SEG + U.PIER_SEG / 2, U.PIER_Y - 1.25, 5.2))
            if lit:
                light("POINT", lamp, 60.0, (1.0, 0.72, 0.4), size=0.12)
                glow_sprite(lamp, 1.6, (1.0, 0.72, 0.4), 2.5, cam_loc)
            else:
                glow_sprite(lamp, 0.6, (1.0, 0.6, 0.3), 0.6, cam_loc)
    if kind == "boat":
        ang = R(p.get("yaw", 0))
        cab = V((x + math.cos(ang) * -1.5, p["y"] + math.sin(ang) * -1.5, 2.0 + U.piece_origin(kind, x, p, t)[2]))
        light("POINT", cab, 18.0, (1.0, 0.68, 0.35), size=0.3)
        glow_sprite(cab + V((0, -1.2, 0)), 1.6, (1.0, 0.65, 0.3), 0.35, cam_loc)
    if kind == "bw_gap":
        for bx, col in ((x + 0.9, (1.0, 0.55, 0.3)), (x + U.BW_GAP - 0.9, (0.55, 1.0, 0.6))):
            light("POINT", (bx, U.BW_Y + 0.2, 3.62), 25.0, col, size=0.1)
            glow_sprite(V((bx, U.BW_Y + 0.2, 3.62)), 1.4, col, 2.0, cam_loc)
    return objs


MATCACHE = {}
NO_POINT_SHADOWS = False     # True while assembling the target frames (engine parity); bakes keep real shadows


def far_card(cam_x):
    """The far layer on one alpha card, repeated every FAR_W along x (engine: 2 pooled cards, unlit)."""
    m = card_mat("far", os.path.join(LAY, "far_layer.png"), 1.0)
    k = math.floor((cam_x + FAR_W / 2) / FAR_W)
    for j in (k - 1, k, k + 1):
        x0 = j * FAR_W
        o = mesh("far", [(x0 - FAR_W / 2, FAR_Y, FAR_Z0), (x0 + FAR_W / 2, FAR_Y, FAR_Z0),
                         (x0 + FAR_W / 2, FAR_Y, FAR_Z0 + FAR_H), (x0 - FAR_W / 2, FAR_Y, FAR_Z0 + FAR_H)], [(0, 1, 2, 3)], m,
                 smooth=False)
        quad_uv(o, [(0, 0), (1, 0), (1, 1), (0, 1)])
        o.visible_shadow = False


def beam_card(cam_loc, ang=-8.0):
    """Lighthouse beam: one additive card from the lantern (engine: card rotated / scaled from Lua to sweep)."""
    lan = V((52.0, FAR_Y - 2.5, 0))
    # lantern height: same profile as make_far (headland top) + 13.9
    W = FAR_W
    harm = [(1, 2.2, 0.4), (2, 1.4, 1.7), (3, 0.9, 3.0), (5, 0.6, 0.6), (9, 0.35, 2.1), (17, 0.18, 4.4), (31, 0.08, 1.2)]
    h = 2.6 + sum(a * math.sin(2 * math.pi * k * 52.0 / W + ph) for k, a, ph in harm) + 9.0
    lan.z = h - 0.5 + 13.9
    m = card_mat("beam", os.path.join(TEX, "beam.png"), 2.2, tint=(1.0, 0.9, 0.75), additive=True)
    Lb, w0, w1 = 95.0, 1.2, 14.0
    nseg = 32                                  # many short segments: a 2-triangle trapezoid creases the UVs
    vs, uvl = [], []
    for k in range(nseg + 1):
        u = k / nseg
        w = w0 + (w1 - w0) * u
        vs += [(Lb * u, 0, -w / 2), (Lb * u, 0, w / 2)]
        uvl += [(u, 0.0), (u, 1.0)]
    o = mesh("beam", vs, [(2 * k, 2 * k + 2, 2 * k + 3, 2 * k + 1) for k in range(nseg)], m, smooth=False)
    quad_uv(o, uvl)
    o.location = lan
    o.rotation_euler = (0, R(-ang), 0)
    o.visible_shadow = False
    o.visible_glossy = False
    # also a soft glow at the lantern
    glow_sprite(lan + V((0, -1, 0)), 9.0, (1.0, 0.85, 0.6), 1.2, cam_loc)


def frame(which):
    global NO_POINT_SHADOWS
    NO_POINT_SHADOWS = True
    s = reset()
    s.render.resolution_x, s.render.resolution_y = 2560, 1440
    s.render.resolution_percentage = 50 if HALF else 100
    s.cycles.samples = SAMPLES
    s.cycles.max_bounces = 6
    s.cycles.transparent_max_bounces = 64
    pano_world()
    light("SUN", (0, 0, 10), 0.5, (1.0, 0.65, 0.4), size=4, target=(-20, -40, -6))
    rng = random.Random(3 if which == "a" else 4)
    course = U.target_course()
    st = U.STATES["A" if which == "a" else "B"]
    t = st["t"]
    (fx, fy, fz), hk = U.float_pos("A" if which == "a" else "B")
    hook, theta, L = V(hk), R(st["theta"]), st["L"]
    Fx = hook.x + L * math.sin(theta)
    cam = setup_camera(Fx)
    cl = cam.location.copy()
    far_card(cl.x)
    beam_card(cl)
    for kind, x, p in course:
        if abs(x - cl.x) > 60 and kind not in ("bw", "bw_gap"):
            continue
        if kind in ("bw", "bw_gap") and abs(x - cl.x) > 140:
            continue
        pp = dict(p)
        if st["lit_pier"] and kind == "pier":
            pp["lit"] = True
        place_piece(kind, x, pp, cl, t)
    build_sea(cl.x, t)
    F = float_rig(hook, theta, L, cl)
    if st["spray"]:
        splash(F, cl, rng, t=t)
    # target_b: the float is airborne on the up-swing; no spray
    rain_cards(cam)
    compositor_bloom(s)
    # report screen positions of the float, hooks and horizon
    from bpy_extras.object_utils import world_to_camera_view
    for nm, p in (("float", F), ("hook", hook), ("horizon", V((cl.x, 5000, 0)))):
        c = world_to_camera_view(s, cam, p)
        print("SCREEN %s u=%.3f v=%.3f" % (nm, c.x, c.y))
    for hx, hz in U.hooks(course):
        c = world_to_camera_view(s, cam, V((hx, 0, hz)))
        if 0 <= c.x <= 1:
            print("SCREEN hook x=%.1f u=%.3f v=%.3f" % (hx, c.x, c.y))
    out = os.path.join(OUT, ("target" if which == "a" else "target_b") + ("_half" if HALF else "") + ".png")
    s.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("wrote", out)


# ================================================================== MODE side: concept | target
def side():
    a = load_rgba(CONCEPT)
    b = load_rgba(os.path.join(OUT, "target.png"))
    ha, wa = a.shape[:2]
    hb, wb = b.shape[:2]
    # scale the concept to the target's height (nearest-neighbour is enough for a comparison sheet? use bilinear)
    sy = hb / ha
    nw = int(round(wa * sy))
    yi = np.clip((np.arange(hb) + 0.5) / sy - 0.5, 0, ha - 1)
    xi = np.clip((np.arange(nw) + 0.5) / sy - 0.5, 0, wa - 1)
    y0, x0 = np.floor(yi).astype(int), np.floor(xi).astype(int)
    y1, x1 = np.minimum(y0 + 1, ha - 1), np.minimum(x0 + 1, wa - 1)
    fy, fx = (yi - y0)[:, None, None], (xi - x0)[None, :, None]
    sa = (a[y0][:, x0] * (1 - fx) + a[y0][:, x1] * fx) * (1 - fy) + (a[y1][:, x0] * (1 - fx) + a[y1][:, x1] * fx) * fy
    gap = np.ones((hb, 16, 4), np.float32)
    gap[..., :3] = 0.0
    save_rgba(np.concatenate([sa, gap, b], 1), os.path.join(OUT, "side_by_side.png"))


if MODE in ("tex", "all"):
    reset()
    make_textures()
if MODE in ("sky", "all"):
    make_sky()
if MODE in ("bake", "all"):
    make_bakes()
if MODE in ("far", "all"):
    make_far()
if MODE in ("target", "all"):
    frame("a")
if MODE in ("target_b", "all"):
    frame("b")
if MODE in ("side", "all"):
    side()
