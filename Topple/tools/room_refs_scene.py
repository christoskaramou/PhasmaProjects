"""Reference pictures of the House rooms' furniture for a later image-to-3D step (nothing is generated here).

Each piece is a simple Blender model at the game's scale (1 unit = 5 cm = a Standard domino's height), sized to the
solids in Assets/Scripts/rooms/<room>.lua, rendered alone as a 3/4 front view. Front faces -Y, Z is up.

    blender -b --factory-startup --python tools/room_refs_scene.py -- <out_dir> [samples] [name,name,...]
    python tools/room_refs_scene.py --post <out_dir>      # light background, contact sheets, refs.md (needs Pillow)

Blender writes raw RGBA renders and their sizes to <out_dir>/raw; --post makes the finished pictures beside it.
"""
import json
import math
import os
import random
import sys

try:
    import bpy
    from mathutils import Euler, Vector
except ImportError:
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------------ catalogue
# name: (room, size class, code-built verdict, optional, description)
# size class drives the suggested polycount: S 8k, M 15k, L 20k triangles.
POLY = {"S": 8000, "M": 15000, "L": 20000}
ROOM_ORDER = ["hall", "kitchen", "dining", "kids", "bath", "study", "attic"]
ROOM_TITLE = {"hall": "Hallway", "kitchen": "Kitchen", "dining": "Dining Room", "kids": "Kids' Room",
              "bath": "Bathroom", "study": "Study", "attic": "Attic"}
META = {
    "furn_hall_bench": ("hall", "L", "Partly: boxes would do, but the slats and green pad read better generated.", False,
                        "Oak shoe bench, slatted shoe shelf, forest-green wool pad."),
    "furn_hall_coatstand": ("hall", "M", "No: curved feet and hooks need a real mesh.", False,
                            "Turned dark-oak coat stand, bent brass hooks, four curved feet."),
    "furn_hall_umbrellastand": ("hall", "S", "Mostly: a lathe pot is easy in code; the umbrella's crook is not.", False,
                                "Green-glazed ceramic umbrella stand, brass bands, navy furled umbrella and a cane."),
    "furn_hall_shoes": ("hall", "S", "No: shoe shapes need a generated mesh.", False,
                        "A pair of brown leather oxfords (the room's shelf holds about three pairs)."),
    "furn_kitchen_counter": ("kitchen", "L", "Yes: panels, knobs and a worktop are all boxes; code is as good.", False,
                             "Sage-green painted shaker base cabinets, brass handles, butcher-block worktop."),
    "furn_kitchen_oven": ("kitchen", "L", "Partly: body is boxes; hob grates and knobs gain from a mesh.", False,
                          "Cream enamel range cooker, four cast-iron burners, chrome rail handle."),
    "furn_kitchen_fridge": ("kitchen", "L", "Partly: a rounded box; handles and badge read better generated.", False,
                            "Rounded retro fridge in cream enamel, chrome lever handles."),
    "furn_kitchen_table": ("kitchen", "L", "Mostly: top and apron are boxes; turned legs need lathing.", False,
                           "Farmhouse table: pine top, sage-painted apron and turned legs, small drawer."),
    "furn_kitchen_chair": ("kitchen", "M", "No: spindles and raked posts are fiddly in code.", False,
                           "Sage-painted spindle-back chair with a pine seat."),
    "furn_kitchen_kettle": ("kitchen", "S", "No: spout and handle need a real mesh.", False,
                            "Copper stovetop kettle, brass handle with black grip."),
    "furn_dining_table": ("dining", "L", "Mostly: boxes plus four lathed legs.", False,
                          "Long mahogany dining table, turned legs, moulded edge."),
    "furn_dining_chair": ("dining", "M", "No: upholstery and nailheads read better generated.", False,
                          "Mahogany dining chair, burgundy velvet seat and back, brass nailheads."),
    "furn_dining_sideboard": ("dining", "L", "Partly: carcass is boxes; raised panels and ring pulls gain.", False,
                              "Mahogany sideboard, four drawers over four panelled doors, brass ring pulls."),
    "furn_dining_recordplayer": ("dining", "S", "No: tonearm and platter want a mesh.", False,
                                 "Walnut turntable with a black record, chrome platter and tonearm."),
    "furn_kids_bed": ("kids", "L", "No: quilt, pillow and arched headboard read better generated.", False,
                      "Sky-blue painted single bed, yellow ball finials, red patchwork quilt."),
    "furn_kids_toybox": ("kids", "M", "Yes: boxes plus three painted shapes.", False,
                         "Red toy chest with a yellow lid, blue base, painted star, circle and triangle."),
    "furn_kids_rockinghorse": ("kids", "L", "No: an animal needs a generated mesh.", False,
                               "Dapple-white rocking horse on bow rockers, red saddle, brown mane."),
    "furn_kids_train": ("kids", "S", "Partly: cylinders and boxes, but small parts are many.", False,
                        "Wooden toy steam engine: blue boiler and cab, red chassis and roof, yellow wheels."),
    "furn_kids_crane": ("kids", "M", "No: lattice mast and jib are many thin parts.", False,
                        "Wooden toy crane: yellow cab on black wheels, red lattice mast and jib, hook on a string."),
    "furn_bath_bathtub": ("bath", "L", "No: the roll-top tub and claw feet need a real mesh.", False,
                          "Roll-top clawfoot tub, white enamel inside, pale celadon outside, brass feet, chrome taps."),
    "furn_bath_sink": ("bath", "M", "Partly: lathed basin and pedestal; taps gain from a mesh.", False,
                       "White porcelain pedestal basin with chrome cross-head taps."),
    "furn_bath_stool": ("bath", "M", "Yes: slats, legs and rails are boxes.", False,
                        "Slatted teak bath bench."),
    "furn_bath_basket": ("bath", "M", "Partly: a lathe shape; the weave is texture work.", False,
                         "Lidded wicker laundry basket."),
    "furn_bath_musicbox": ("bath", "S", "Partly: a box; the crank and inlay are small details.", False,
                           "Rosewood music box with brass inlay, feet and a winding crank."),
    "furn_study_desk": ("study", "L", "Mostly: boxes; bail handles gain from a mesh.", False,
                        "Walnut pedestal desk, green leather top, six drawers with brass bail handles."),
    "furn_study_chair": ("study", "M", "No: tufted leather and arms read better generated.", False,
                         "Walnut library armchair, oxblood leather seat and button-tufted back."),
    "furn_study_globe": ("study", "M", "Partly: sphere and lathe; the map is a texture.", False,
                         "Antique globe, brass meridian, turned walnut stand."),
    "furn_study_cabinet": ("study", "L", "Partly: boxes; the glazed doors and books add detail.", False,
                           "Low walnut cabinet, glazed doors over two drawers, books inside."),
    "furn_attic_trunk": ("attic", "M", "Partly: boxes; straps and brass corners add detail.", False,
                         "Dusty steamer trunk: faded canvas, oak slats, leather straps, tarnished brass."),
    "furn_attic_lamp": ("attic", "M", "No: fringed fabric shade needs a mesh.", False,
                        "Old standard lamp: turned wood column, faded rose silk shade with fringe."),
    "furn_attic_rockingchair": ("attic", "L", "No: spindles, rockers and arms are curved.", False,
                                "Dusty spindle-back rocking chair with a faded patchwork seat pad."),
    # optional extras
    "furn_hall_clock": ("hall", "L", "No: hood, dial and glazed waist need a mesh.", True,
                        "Grandfather clock in dark oak, brass dial and pendulum."),
    "furn_hall_plant": ("hall", "M", "No: leaves need a mesh.", True, "Snake plant in a green-glazed pot."),
    "furn_kitchen_herbs": ("kitchen", "S", "No: foliage.", True, "Three terracotta herb pots on a pine tray."),
    "furn_dining_candelabra": ("dining", "S", "Partly: lathe parts and curved arms.", True,
                               "Five-light brass candelabra with cream candles."),
    "furn_kids_teddy": ("kids", "S", "No: a soft animal needs a mesh.", True, "Honey-brown teddy bear with a red bow."),
    "furn_kids_drum": ("kids", "S", "Partly: lathe plus zigzag cords.", True, "Red toy drum with blue rims and sticks."),
    "furn_bath_towelrail": ("bath", "M", "Partly: rail is tubes; the towel drape is not.", True,
                            "Freestanding chrome towel rail with a folded white towel."),
    "furn_bath_fern": ("bath", "M", "No: fronds need a mesh.", True, "Boston fern in a white porcelain pot."),
    "furn_study_lamp": ("study", "S", "Partly: simple solids.", True, "Brass banker's lamp with a green glass shade."),
    "furn_attic_dressform": ("attic", "M", "No: torso shape needs a mesh.", True,
                             "Dusty linen dress form on a wooden tripod."),
    "furn_attic_suitcases": ("attic", "M", "Mostly: boxes plus handles and latches.", True,
                             "Stack of three old suitcases: tan leather, oxblood, olive canvas."),
}


# ================================================================== Blender side
if bpy is not None and "--" in sys.argv:
    sys.path.insert(0, HERE)
    import house_refs_scene as H  # noqa: E402  (paint, box, cyl, sphere, setup_render)
    from bpy_extras.object_utils import world_to_camera_view

    ARGS = sys.argv[sys.argv.index("--") + 1:]
    OUT = ARGS[0]
    RAW = os.path.join(OUT, "raw")
    os.makedirs(RAW, exist_ok=True)
    H.SAMPLES = int(ARGS[1]) if len(ARGS) > 1 else 160

    # -------------------------------------------------------------- materials
    def paint(name, rgb, rough=0.5, coat=0.0, metal=0.0):
        return H.paint(name, rgb, rough, coat, metal)

    def velvet(name, rgb):
        m, N, L, p = H.nodes_mat(name)
        p.inputs["Base Color"].default_value = (*rgb, 1)
        p.inputs["Roughness"].default_value = 0.85
        p.inputs["Sheen Weight"].default_value = 0.8
        p.inputs["Sheen Tint"].default_value = (*[min(1, c * 1.6) for c in rgb], 1)
        return m

    def wood(name, rgb, rough=0.4, scale=3.0, kind="RINGS", coat=0.4, dust=0.0):
        """Grain from a distorted wave; dust > 0 greys it and settles more on upward faces."""
        m, N, L, p = H.nodes_mat(name)
        tc = N.new("ShaderNodeTexCoord")
        wv = N.new("ShaderNodeTexWave"); wv.wave_type = kind; wv.inputs["Scale"].default_value = scale
        wv.inputs["Distortion"].default_value = 6.0; wv.inputs["Detail"].default_value = 3.0
        L.new(tc.outputs["Object"], wv.inputs["Vector"])
        mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"
        mix.inputs[6].default_value = (*[c * 0.7 for c in rgb], 1)
        mix.inputs[7].default_value = (*rgb, 1)
        L.new(wv.outputs["Fac"], mix.inputs[0])
        out = mix.outputs[2]
        if dust > 0:
            out = dusted(N, L, tc, out, dust)
        L.new(out, p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = rough
        p.inputs["Coat Weight"].default_value = coat
        return m

    def dusted(N, L, tc, colour_out, amount):
        geo = N.new("ShaderNodeNewGeometry")
        sep = N.new("ShaderNodeSeparateXYZ"); L.new(geo.outputs["Normal"], sep.inputs[0])
        up = N.new("ShaderNodeMapRange"); up.inputs["From Min"].default_value = 0.2; up.inputs["From Max"].default_value = 1.0
        up.inputs["To Min"].default_value = amount * 0.45; up.inputs["To Max"].default_value = amount
        L.new(sep.outputs[2], up.inputs["Value"])
        nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 2.5; nz.inputs["Detail"].default_value = 6
        L.new(tc.outputs["Object"], nz.inputs["Vector"])
        mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
        L.new(up.outputs[0], mul.inputs[0]); L.new(nz.outputs["Fac"], mul.inputs[1])
        mul2 = N.new("ShaderNodeMath"); mul2.operation = "MULTIPLY"; mul2.inputs[1].default_value = 1.6
        L.new(mul.outputs[0], mul2.inputs[0])
        mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.clamp_factor = True
        L.new(mul2.outputs[0], mix.inputs[0]); L.new(colour_out, mix.inputs[6])
        mix.inputs[7].default_value = (0.55, 0.52, 0.47, 1)
        return mix.outputs[2]

    def dusty_paint(name, rgb, rough=0.8, dust=0.35):
        m, N, L, p = H.nodes_mat(name)
        tc = N.new("ShaderNodeTexCoord")
        rgbn = N.new("ShaderNodeRGB"); rgbn.outputs[0].default_value = (*rgb, 1)
        L.new(dusted(N, L, tc, rgbn.outputs[0], dust), p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = rough
        return m

    def checker(name, c1, c2, scale, rough=0.8, sheen=0.5, dust=0.0):
        m, N, L, p = H.nodes_mat(name)
        tc = N.new("ShaderNodeTexCoord")
        ck = N.new("ShaderNodeTexChecker"); ck.inputs["Scale"].default_value = scale
        ck.inputs["Color1"].default_value = (*c1, 1); ck.inputs["Color2"].default_value = (*c2, 1)
        L.new(tc.outputs["Object"], ck.inputs["Vector"])
        out = ck.outputs["Color"]
        if dust:
            out = dusted(N, L, tc, out, dust)
        L.new(out, p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = rough
        p.inputs["Sheen Weight"].default_value = sheen
        return m

    def wicker(name, rgb):
        m, N, L, p = H.nodes_mat(name)
        tc = N.new("ShaderNodeTexCoord")
        a = N.new("ShaderNodeTexWave"); a.wave_type = "BANDS"; a.bands_direction = "Z"; a.inputs["Scale"].default_value = 1.3
        b = N.new("ShaderNodeTexWave"); b.wave_type = "RINGS"; b.rings_direction = "Z"; b.inputs["Scale"].default_value = 1.6
        for w in (a, b):
            w.inputs["Distortion"].default_value = 0.0
            L.new(tc.outputs["Object"], w.inputs["Vector"])
        mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
        L.new(a.outputs["Fac"], mul.inputs[0]); L.new(b.outputs["Fac"], mul.inputs[1])
        mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"
        mix.inputs[6].default_value = (*[c * 0.55 for c in rgb], 1)
        mix.inputs[7].default_value = (*rgb, 1)
        L.new(a.outputs["Fac"], mix.inputs[0])
        L.new(mix.outputs[2], p.inputs["Base Color"])
        bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.9; bump.inputs["Distance"].default_value = 0.15
        L.new(mul.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], p.inputs["Normal"])
        p.inputs["Roughness"].default_value = 0.75
        return m

    def glass(name="glass", tint=(0.92, 0.95, 0.95)):
        m, N, L, p = H.nodes_mat(name)
        p.inputs["Base Color"].default_value = (*tint, 1)
        p.inputs["Roughness"].default_value = 0.03
        p.inputs["Transmission Weight"].default_value = 1.0
        p.inputs["IOR"].default_value = 1.45
        return m

    def globe_map(name):
        m, N, L, p = H.nodes_mat(name)
        tc = N.new("ShaderNodeTexCoord")
        nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 0.35; nz.inputs["Detail"].default_value = 7
        nz.inputs["Roughness"].default_value = 0.6
        L.new(tc.outputs["Object"], nz.inputs["Vector"])
        ramp = N.new("ShaderNodeValToRGB"); ramp.color_ramp.interpolation = "CONSTANT"
        ramp.color_ramp.elements[0].color = (0.16, 0.3, 0.33, 1)
        ramp.color_ramp.elements[1].position = 0.53
        ramp.color_ramp.elements[1].color = (0.72, 0.6, 0.38, 1)
        L.new(nz.outputs["Fac"], ramp.inputs["Fac"])
        L.new(ramp.outputs["Color"], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = 0.35
        p.inputs["Coat Weight"].default_value = 0.6
        return m

    def dapple(name, rgb, spot):
        m, N, L, p = H.nodes_mat(name)
        tc = N.new("ShaderNodeTexCoord")
        vo = N.new("ShaderNodeTexVoronoi"); vo.inputs["Scale"].default_value = 1.8
        L.new(tc.outputs["Object"], vo.inputs["Vector"])
        ramp = N.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (*rgb, 1)
        ramp.color_ramp.elements[0].position = 0.35
        ramp.color_ramp.elements[1].position = 0.6
        ramp.color_ramp.elements[1].color = (*spot, 1)
        L.new(vo.outputs["Distance"], ramp.inputs["Fac"])
        L.new(ramp.outputs["Color"], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = 0.35
        p.inputs["Coat Weight"].default_value = 0.5
        return m

    def brass(name="brass"):
        return paint(name, (0.85, 0.62, 0.3), 0.25, 0, 1)

    def chrome(name="chrome"):
        return paint(name, (0.92, 0.92, 0.94), 0.1, 0, 1)

    # -------------------------------------------------------------- geometry
    def link(o):
        bpy.context.collection.objects.link(o)
        return o

    def rbox(c, size, mat, r=0.2, segs=3, rot=None):
        return H.box(c, size, mat, r, segs, rot)

    def smooth(o):
        for f in o.data.polygons:
            f.use_smooth = True
        return o

    def sphere(c, r, mat, scale=None, rot=None, segs=32):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=segs, ring_count=segs // 2, location=c)
        o = bpy.context.object
        if scale:
            o.scale = scale
        if rot:
            o.rotation_euler = rot
        o.data.materials.append(mat)
        return smooth(o)

    def cyl(c, r, h, mat, verts=32, rot=None, scale=None):
        o = H.cyl(c, r, h, mat, verts, rot)
        if scale:
            o.scale = scale
        return o

    def rod(p0, p1, r0, mat, r1=None, verts=20):
        """A (tapered) cylinder from p0 to p1."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        bpy.ops.mesh.primitive_cone_add(radius1=r0, radius2=r0 if r1 is None else r1, depth=d.length,
                                        vertices=verts, location=(p0 + p1) / 2)
        o = bpy.context.object
        o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        o.data.materials.append(mat)
        return smooth(o)

    def torus(c, R, r, mat, rot=None, scale=None, maj=48):
        bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=maj, minor_segments=12,
                                         location=c)
        o = bpy.context.object
        if rot:
            o.rotation_euler = rot
        if scale:
            o.scale = scale
        o.data.materials.append(mat)
        return smooth(o)

    def tube(pts, r, mat, loc=(0, 0, 0), scale=None, res=10):
        """A round tube along a smooth curve through pts."""
        cu = bpy.data.curves.new("tube", "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = r
        cu.bevel_resolution = 4
        cu.use_fill_caps = True
        cu.resolution_u = res
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(len(pts) - 1)
        for bp, co in zip(sp.bezier_points, pts):
            bp.co = co
            bp.handle_left_type = bp.handle_right_type = "AUTO"
        sp.use_smooth = True
        o = link(bpy.data.objects.new("tube", cu))
        o.location = loc
        if scale:
            o.scale = scale
        o.data.materials.append(mat)
        return o

    def lathe(prof, mat, loc=(0, 0, 0), segs=48, rot=None):
        """Revolve a (r, z) profile around Z."""
        me = bpy.data.meshes.new("lathe")
        verts, faces = [], []
        n = len(prof)
        for i in range(segs):
            a = 2 * math.pi * i / segs
            for r, z in prof:
                verts.append((r * math.cos(a), r * math.sin(a), z))
        for i in range(segs):
            j = (i + 1) % segs
            for k in range(n - 1):
                faces.append((i * n + k, j * n + k, j * n + k + 1, i * n + k + 1))
        me.from_pydata(verts, [], faces)
        me.update()
        o = link(bpy.data.objects.new("lathe", me))
        o.location = loc
        if rot:
            o.rotation_euler = rot
        o.data.materials.append(mat)
        smooth(o)
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=1e-4)
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        o.select_set(False)
        return o

    def loft(rings, mats, band_mat, loc=(0, 0, 0), segs=96):
        """Stacked capsule outlines (half-length L, radius R, z): baths, basins. band_mat(k) -> material index."""
        me = bpy.data.meshes.new("loft")
        verts, faces, fm = [], [], []
        n = len(rings)
        for k, (L, R, z) in enumerate(rings):
            for i in range(segs):
                a = 2 * math.pi * i / segs
                c, s = math.cos(a), math.sin(a)
                sgn = 0 if abs(c) < 1e-9 else (1 if c > 0 else -1)
                verts.append((sgn * L + R * c, R * s, z))
        for k in range(n - 1):
            for i in range(segs):
                j = (i + 1) % segs
                faces.append((k * segs + i, k * segs + j, (k + 1) * segs + j, (k + 1) * segs + i))
                fm.append(band_mat(k))
        me.from_pydata(verts, [], faces)
        me.update()
        o = link(bpy.data.objects.new("loft", me))
        o.location = loc
        for m in mats:
            o.data.materials.append(m)
        for f, mi in zip(o.data.polygons, fm):
            f.material_index = mi
            f.use_smooth = True
        return o

    def blob(fn, mat, loc=(0, 0, 0), rot=None, segs=48):
        """A unit UV sphere whose vertices are moved by fn((x, y, z)) -> (x, y, z)."""
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=segs, ring_count=segs // 2, location=(0, 0, 0))
        o = bpy.context.object
        for v in o.data.vertices:
            v.co = fn(tuple(v.co))
        o.location = loc
        if rot:
            o.rotation_euler = rot
        o.data.materials.append(mat)
        return smooth(o)

    def prism(pts2d, depth, mat, loc, plane="XZ"):
        """A flat shape (2D outline) extruded: plane XZ faces -Y (front decals)."""
        me = bpy.data.meshes.new("prism")
        n = len(pts2d)
        verts = []
        for d in (0.0, depth):
            for u, v in pts2d:
                verts.append((u, d, v) if plane == "XZ" else (u, v, d))
        faces = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            faces.append((i, j, n + j, n + i))
        me.from_pydata(verts, [], faces)
        me.update()
        o = link(bpy.data.objects.new("prism", me))
        o.location = loc
        o.data.materials.append(mat)
        b = o.modifiers.new("bevel", "BEVEL"); b.width = min(0.05, depth * 0.3); b.segments = 2
        return o

    def star_pts(r_out, r_in, n=5, rot=math.pi / 2):
        return [((r_out if i % 2 == 0 else r_in) * math.cos(rot + i * math.pi / n),
                 (r_out if i % 2 == 0 else r_in) * math.sin(rot + i * math.pi / n)) for i in range(2 * n)]

    def rotx(v, deg):
        a = math.radians(deg)
        x, y, z = v
        return (x, y * math.cos(a) - z * math.sin(a), y * math.sin(a) + z * math.cos(a))

    def leaf(L, width, mat, loc, yaw, pitch, curl=0.25, cuts=8, wave=0.0, solid=0.05, twist=0.0):
        """A tapered curved leaf blade along +X, then pitched up (degrees) and yawed around Z."""
        bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
        lf = bpy.context.object
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.subdivide(number_cuts=cuts)
        bpy.ops.object.mode_set(mode="OBJECT")
        for v in lf.data.vertices:
            u, w = v.co.x + 0.5, v.co.y
            wd = math.sin(math.pi * min(1.0, u * 1.02)) ** 0.7 * width
            t = twist * u
            yy = w * wd
            v.co.x = u * L
            v.co.y = yy * math.cos(t)
            v.co.z = -curl * (u * L) ** 2 / L + wave * math.cos(w * 9.0) * wd + yy * math.sin(t)
        lf.location = loc
        lf.rotation_euler = (0, math.radians(-pitch), math.radians(yaw))
        mod = lf.modifiers.new("solid", "SOLIDIFY"); mod.thickness = solid
        lf.data.materials.append(mat)
        return smooth(lf)

    def bail(x, y, z, mat, w=0.6):
        """A brass drop (bail) handle on a back plate, on a front face at y."""
        rbox((x, y - 0.04, z + 0.15), (w * 2.6, 0.08, 0.5), mat, 0.04, 2)
        tube([(-w, -0.08, 0), (-w * 0.9, -0.3, -0.35), (0, -0.4, -0.55), (w * 0.9, -0.3, -0.35), (w, -0.08, 0)],
             0.07, mat, loc=(x, y, z + 0.15))

    # ============================================================== HALL
    def hall_mats():
        return (wood("oak", (0.42, 0.26, 0.12), 0.45), wood("darkoak", (0.14, 0.07, 0.03), 0.4),
                velvet("hallgreen", (0.05, 0.15, 0.09)), brass())

    def hall_bench():
        oak, _, green, _ = hall_mats()
        rbox((0, 0, 9.3), (24, 8, 1.4), oak, 0.25)                              # seat 8.6..10
        rbox((0, 0, 10.2), (22.8, 7.0, 0.5), green, 0.22)                         # wool pad
        for sx in (-1, 1):
            for sy in (-1, 1):
                rbox((sx * 10.9, sy * 3.0, 4.3), (1.4, 1.4, 8.6), oak, 0.15)
            rbox((sx * 10.9, 0, 8.1), (0.6, 4.8, 1.0), oak, 0.1)                 # side rails
            rbox((sx * 10.9, 0, 0.9), (0.6, 4.8, 0.5), oak, 0.08)                # shelf bearers
        for sy in (-1, 1):
            rbox((0, sy * 3.3, 8.1), (20.4, 0.6, 1.0), oak, 0.1)                  # aprons
        for j in range(5):
            rbox((0, -2.8 + j * 1.4, 1.38), (20.6, 1.1, 0.45), oak, 0.1)          # shelf slats 1.15..1.6

    def hall_shoes():
        leather = paint("leather", (0.2, 0.075, 0.025), 0.42, 0.25)
        sole = paint("sole", (0.05, 0.03, 0.02), 0.6)
        lining = paint("lining", (0.06, 0.035, 0.02), 0.8)
        lace = paint("lace", (0.06, 0.035, 0.02), 0.8)

        def shoe_loft(rings, mats, band):
            """Horizontal outlines (L, R, z, cx): capsules, each shifted back by cx."""
            o = loft([(L, R, z) for L, R, z, cx in rings], mats, band, segs=64)
            for k, (L, R, z, cx) in enumerate(rings):
                for v in o.data.vertices[k * 64:(k + 1) * 64]:
                    v.co.x += cx
            o.data.update()
            return o

        for sx, yaw in ((-1.35, 8), (1.35, -4)):
            parts = [shoe_loft([(1.72, 0.0, 0.0, 0), (1.72, 1.07, 0.0, 0), (1.72, 1.08, 0.36, 0), (1.72, 0.0, 0.36, 0)],
                               [sole], lambda k: 0)]
            up = shoe_loft([(1.62, 0.99, 0.34, 0), (1.62, 1.0, 0.8, 0), (1.5, 0.95, 1.15, -0.08),
                            (1.15, 0.84, 1.45, -0.3), (0.75, 0.74, 1.75, -0.7), (0.55, 0.68, 2.05, -0.95),
                            (0.45, 0.4, 2.15, -1.0), (0.45, 0.0, 2.15, -1.0)], [leather], lambda k: 0)
            cut = sphere((-1.25, 0, 2.3), 1.0, lining, scale=(1.05, 0.56, 0.75))     # the foot opening
            cut.hide_render = True
            cut.display_type = "WIRE"
            up.data.materials.append(lining)
            bo = up.modifiers.new("open", "BOOLEAN"); bo.operation = "DIFFERENCE"; bo.object = cut
            bo.solver = "EXACT"; bo.material_mode = "TRANSFER"
            parts += [up, cut]
            for xk, zk in ((0.35, 1.99), (0.65, 1.82), (0.95, 1.69), (1.25, 1.59)):   # laces over the instep
                parts.append(rod((xk, -0.32, zk), (xk, 0.32, zk), 0.05, lace, verts=8))
            e = bpy.data.objects.new("shoe", None)
            link(e)
            for o in parts:
                o.parent = e
            e.rotation_euler = (0, 0, math.radians(yaw))
            e.location = (0, sx, 0)

    def hall_coatstand():
        _, dk, _, br = hall_mats()
        for k in range(4):
            a = math.radians(45 + 90 * k)
            c, s = math.cos(a), math.sin(a)
            tube([(0.4 * c, 0.4 * s, 3.4), (1.6 * c, 1.6 * s, 1.6), (2.8 * c, 2.8 * s, 0.6), (3.3 * c, 3.3 * s, 0.42)],
                 0.42, dk)
            sphere((3.35 * c, 3.35 * s, 0.42), 0.42, dk)
        lathe([(0, 0.4), (0.95, 0.4), (1.05, 1.0), (0.8, 1.6), (0.95, 3.2), (0.7, 3.8), (0.62, 6), (0.6, 30),
               (0.8, 30.6), (0.6, 31.2), (0.55, 34.0), (0.9, 34.6), (1.05, 35.3), (0.7, 35.9), (0, 36.0)], dk, segs=40)
        for z, ang0, reach in ((32.2, 0, 3.2), (27.4, 45, 2.4)):
            torus((0, 0, z - 0.6), 0.66, 0.14, br)
            for k in range(4):
                a = math.radians(ang0 + 90 * k)
                c, s = math.cos(a), math.sin(a)
                tube([(0.4 * c, 0.4 * s, z - 0.6), (reach * 0.55 * c, reach * 0.55 * s, z - 0.4),
                      (reach * c, reach * s, z + 0.6), (reach * 1.05 * c, reach * 1.05 * s, z + 1.3)], 0.2, br)
                sphere((reach * 1.05 * c, reach * 1.05 * s, z + 1.4), 0.3, br)

    def hall_umbrellastand():
        _, dk, _, br = hall_mats()
        glaze = paint("glaze", (0.05, 0.19, 0.13), 0.12, 1.0)
        navy = paint("navy", (0.03, 0.05, 0.14), 0.7)
        lathe([(0, 0), (2.25, 0), (2.5, 0.35), (2.35, 1.0), (2.3, 11.0), (2.6, 11.6), (2.5, 12.0), (2.2, 12.0),
               (2.1, 11.4), (2.1, 1.0), (0, 1.0)], glaze)
        for z in (2.0, 10.2):
            torus((0, 0, z), 2.32, 0.12, br)
        # furled umbrella: canopy rises out of the stand, strap, crook handle
        ux = -0.6
        lathe([(0.12, 4), (0.85, 8), (0.95, 12.5), (0.45, 15.0), (0.13, 16.0), (0, 16.0)], navy, loc=(ux, 0.2, 0))
        torus((ux, 0.2, 13.4), 0.78, 0.1, navy)
        rod((ux, 0.2, 15.8), (ux, 0.2, 17.4), 0.13, dk)
        tube([(0, 0, 17.3), (0, 0, 18.4), (0.55, 0, 19.0), (1.1, 0, 18.4), (1.1, 0, 17.8)], 0.26, dk, loc=(ux, 0.2, 0))
        # walking cane with a brass knob
        rod((0.9, -0.5, 1.0), (1.3, -0.7, 15.0), 0.22, dk)
        sphere((1.32, -0.71, 15.2), 0.42, br)

    # ============================================================== KITCHEN
    def kitchen_mats():
        sage = paint("sage", (0.3, 0.4, 0.31), 0.45, 0.25)
        pine = wood("pine", (0.6, 0.4, 0.2), 0.45, 2.0)
        block = wood("butcher", (0.55, 0.33, 0.15), 0.45, 1.2, "BANDS")
        cream = paint("cream", (0.84, 0.78, 0.64), 0.18, 0.7)
        return sage, pine, block, cream, brass(), chrome()

    def kitchen_counter():
        sage, _, block, _, br, _ = kitchen_mats()
        dsage = paint("dsage", (0.15, 0.2, 0.16), 0.6)
        rbox((0, 0, 17.4), (46, 12, 1.2), block, 0.15)                          # worktop 16.8..18
        rbox((0, 0.45, 9.2), (45.6, 11.1, 15.2), sage, 0.05, 1)                  # carcass 1.6..16.8
        rbox((0, 0.75, 0.8), (45.2, 10.5, 1.6), dsage, 0.05, 1)                  # recessed plinth
        n, W = 5, 45.6
        bw = W / n
        fy = -5.1
        for i in range(n):
            cx = -W / 2 + bw * (i + 0.5)
            fw = bw - 0.45
            rbox((cx, fy - 0.18, 14.7), (fw, 0.36, 3.1), sage, 0.1)                # drawer front
            rbox((cx, fy - 0.18, 7.3), (fw, 0.36, 10.8), sage, 0.1)                # door
            for z in (12.15, 2.45):                                                # shaker frame
                rbox((cx, fy - 0.42, z), (fw, 0.16, 1.1), sage, 0.06)
            for s in (-1, 1):
                rbox((cx + s * (fw / 2 - 0.55), fy - 0.42, 7.3), (1.1, 0.16, 10.8), sage, 0.06)
            # brass bar pull on the drawer, knob on the door near its opening edge
            rod((cx - 1.3, fy - 0.85, 14.7), (cx + 1.3, fy - 0.85, 14.7), 0.16, br)
            for s in (-1, 1):
                rod((cx + s * 1.1, fy - 0.36, 14.7), (cx + s * 1.1, fy - 0.85, 14.7), 0.12, br)
            kx = cx + (fw / 2 - 1.5) * (1 if i % 2 == 0 else -1)
            sphere((kx, fy - 0.75, 10.6), 0.38, br)
            rod((kx, fy - 0.36, 10.6), (kx, fy - 0.7, 10.6), 0.14, br)

    def kitchen_oven():
        _, _, _, cream, _, ch = kitchen_mats()
        cast = paint("castiron", (0.025, 0.025, 0.025), 0.55)
        dglass = paint("ovenglass", (0.02, 0.02, 0.025), 0.05, 1.0)
        rbox((0, 0.3, 9.3), (12, 11.4, 17.4), cream, 0.5)                       # body 0.6..18
        for sx in (-1, 1):
            for sy in (-1, 1):
                cyl((sx * 5.0, 0.3 + sy * 4.6, 0.35), 0.4, 0.7, ch)
        rbox((0, 0.3, 18.0), (11.2, 10.8, 0.24), cast, 0.05, 1)                  # hob plate
        for bx in (-2.7, 2.7):
            for by in (-2.2, 2.9):
                cyl((bx, by, 18.22), 1.0, 0.24, cast)
                torus((bx, by, 18.42), 1.55, 0.11, cast)
                for a in (0, 90):
                    rbox((bx, by, 18.42), (3.3, 0.2, 0.18), cast, 0.03, 1, rot=(0, 0, math.radians(a + 45)))
        rbox((0, -5.47, 16.5), (11.6, 0.12, 2.2), ch, 0.04, 1)                    # control fascia
        for x in (-4.2, -1.4, 1.4, 4.2):
            cyl((x, -5.9, 16.5), 0.55, 0.7, cast, rot=(math.pi / 2, 0, 0))
            rbox((x, -6.27, 16.5), (0.16, 0.06, 0.8), ch, 0.02, 1)
        rbox((0, -5.68, 9.3), (10.8, 0.5, 10.2), cream, 0.35)                   # oven door 4.2..14.4
        rbox((0, -5.95, 9.7), (7.2, 0.08, 5.0), dglass, 0.25)                    # window
        rbox((0, -5.93, 9.7), (7.8, 0.06, 5.6), ch, 0.25)                        # its chrome frame
        rod((-4.6, -7.0, 13.4), (4.6, -7.0, 13.4), 0.24, ch)                     # rail handle
        for x in (-4.1, 4.1):
            rod((x, -5.9, 13.4), (x, -7.0, 13.4), 0.16, ch)
        rbox((0, -5.68, 2.3), (10.8, 0.5, 2.4), cream, 0.3)                     # drawer
        rod((-1.6, -6.3, 2.5), (1.6, -6.3, 2.5), 0.16, ch)

    def kitchen_fridge():
        _, _, _, cream, _, ch = kitchen_mats()
        dark = paint("seam", (0.1, 0.09, 0.08), 0.6)
        rbox((0, 0.25, 19.4), (12, 12.5, 37.2), cream, 1.7, 6)                    # body 0.8..38
        rbox((0, 0.25, 0.5), (10.8, 11.6, 1.0), ch, 0.2)                         # chrome kick plate
        rbox((0, -6.0, 27.2), (8.4, 0.3, 0.16), dark, 0.02, 1)                   # door seam
        rbox((0, -6.08, 24.6), (3.2, 0.18, 0.7), ch, 0.1)                        # badge
        for h0, h1 in ((29.0, 33.4), (17.0, 23.6)):
            tube([(4.4, -5.95, h0), (4.4, -6.85, h0 + 0.7), (4.4, -6.85, h1 - 0.7), (4.4, -5.95, h1)], 0.3, ch)
        for z in (5.0, 35.0, 26.0, 28.4):
            rbox((-6.02, -4.8, z), (0.3, 1.2, 1.4), ch, 0.12)                     # hinges

    def kitchen_table():
        sage, pine, _, _, br, _ = kitchen_mats()
        rbox((0, 0, 14.4), (30, 17, 1.2), pine, 0.2)                            # top 13.8..15
        rbox((0, 0, 13.1), (27.6, 14.6, 1.4), sage, 0.1)                        # apron 12.4..13.8
        rbox((0, -7.35, 13.1), (6.0, 0.2, 1.0), sage, 0.06)                      # drawer
        sphere((0, -7.65, 13.1), 0.3, br)
        prof = [(0, 0), (0.5, 0), (0.62, 0.5), (0.45, 1.5), (0.55, 5.5), (0.72, 6.5), (0.5, 7.4), (0.72, 8.4),
                (0.6, 9.5), (0.75, 10.4), (0, 10.4)]
        for sx in (-1, 1):
            for sy in (-1, 1):
                x, y = sx * 13.25, sy * 6.75
                lathe(prof, sage, loc=(x, y, 0), segs=32)
                rbox((x, y, 12.1), (1.5, 1.5, 3.4), sage, 0.08)

    def kitchen_chair():
        sage, pine, _, _, _, _ = kitchen_mats()
        rbox((0, 0, 8.55), (9, 9, 0.9), pine, 0.25)                            # seat 8.1..9
        prof = [(0, 0), (0.38, 0), (0.45, 0.4), (0.34, 1.2), (0.42, 4.5), (0.5, 5.2), (0.38, 6), (0.45, 8.15), (0, 8.15)]
        for sx in (-1, 1):
            lathe(prof, sage, loc=(sx * 3.9, -3.9, 0), segs=24)
            rod((sx * 3.9, 3.9, 0), (sx * 3.9, 4.6, 19.0), 0.42, sage)          # raked back posts
            sphere((sx * 3.9, 4.6, 19.0), 0.42, sage)
            rod((sx * 3.9, -3.9, 1.8), (sx * 3.9, 3.95, 1.8), 0.2, sage)         # side stretchers
        rod((-3.9, -3.9, 2.6), (3.9, -3.9, 2.6), 0.2, sage)
        rod((-3.9, 3.95, 2.6), (3.9, 3.95, 2.6), 0.2, sage)
        rbox((0, 4.5, 17.9), (7.9, 0.7, 1.9), sage, 0.25, rot=(math.radians(-2), 0, 0))   # top rail
        rbox((0, 4.15, 11.0), (7.9, 0.5, 0.7), sage, 0.15)                       # lower rail
        for k in range(5):
            x = -2.6 + k * 1.3
            rod((x, 4.15, 11.3), (x, 4.48, 17.0), 0.2, sage)

    def kitchen_kettle():
        copper = paint("copper", (0.86, 0.42, 0.24), 0.2, 0, 1)
        black = paint("bakelite", (0.03, 0.025, 0.02), 0.3, 0.5)
        br = brass()
        lathe([(0, 0), (1.85, 0), (2.0, 0.25), (1.95, 1.4), (1.65, 2.5), (1.0, 3.05), (0.75, 3.15), (0, 3.15)], copper)
        lathe([(0, 3.1), (0.78, 3.1), (0.74, 3.35), (0.35, 3.55), (0, 3.6)], copper)
        sphere((0, 0, 3.82), 0.32, black)
        tube([(1.4, 0, 0.9), (2.1, 0, 1.6), (2.55, 0, 2.6), (2.75, 0, 3.0)], 0.26, copper)
        for s in (-1, 1):
            sphere((s * 1.25, 0, 2.75), 0.22, br)
        tube([(-1.25, 0, 2.75), (-1.15, 0, 4.4), (0, 0, 5.05), (1.15, 0, 4.4), (1.25, 0, 2.75)], 0.11, br)
        rod((-0.7, 0, 5.0), (0.7, 0, 5.0), 0.3, black)

    # ============================================================== DINING
    def dining_mats():
        return (wood("mahogany", (0.2, 0.055, 0.03), 0.28, 3.0, "RINGS", 0.6), velvet("burgundy", (0.24, 0.025, 0.045)),
                brass())

    def dining_table():
        mah, _, br = dining_mats()
        rbox((0, 0, 14.4), (44, 20, 1.2), mah, 0.45)                           # top 13.8..15
        rbox((0, 0, 13.65), (43.0, 19.0, 0.4), mah, 0.15)                        # moulding
        rbox((0, 0, 12.9), (40.4, 16.4, 1.6), mah, 0.1)                          # apron 12.1..13.7
        prof = [(0, 0), (0.62, 0), (0.78, 0.45), (0.55, 1.2), (0.6, 4.0), (1.1, 5.5), (1.15, 6.5), (0.7, 8.0),
                (0.6, 9.2), (0.85, 9.8), (0.85, 10.3), (0, 10.3)]
        for sx in (-1, 1):
            for sy in (-1, 1):
                x, y = sx * 20.1, sy * 8.1
                lathe(prof, mah, loc=(x, y, 0), segs=32)
                rbox((x, y, 12.0), (1.8, 1.8, 3.6), mah, 0.1)
                torus((x, y, 0.3), 0.66, 0.1, br)

    def dining_chair():
        mah, burg, br = dining_mats()
        rbox((0, 0, 8.4), (9, 9.5, 0.9), mah, 0.2)                             # seat frame 7.95..8.85
        rbox((0, -0.15, 9.2), (8.6, 8.9, 0.8), burg, 0.36)                      # cushion
        for k in range(13):
            x = -4.0 + k * (8.0 / 12)
            sphere((x, -4.79, 8.7), 0.11, br)                                      # nailheads on the frame
        prof = [(0, 0), (0.36, 0), (0.45, 0.5), (0.33, 1.4), (0.42, 4.5), (0.52, 5.3), (0.4, 6.2), (0.46, 7.95), (0, 7.95)]
        for sx in (-1, 1):
            lathe(prof, mah, loc=(sx * 4.0, -4.2, 0), segs=24)
            rod((sx * 4.0, 4.3, 0), (sx * 4.0, 4.7, 21.0), 0.45, mah)
            rod((sx * 4.0, -4.2, 1.2), (sx * 4.0, 4.3, 1.2), 0.2, mah)
        rod((-4.0, 0.0, 1.2), (4.0, 0.0, 1.2), 0.2, mah)                          # H stretcher
        rbox((0, 4.56, 15.0), (7.4, 0.8, 8.4), burg, 0.4, rot=(math.radians(-1.1), 0, 0))   # back panel 10.8..19.2
        rbox((0, 4.66, 20.2), (9.0, 0.9, 1.5), mah, 0.3)                         # crest rail
        sphere((0, 4.66, 21.0), 0.6, mah, scale=(2.2, 0.7, 0.8))
        rbox((0, 4.44, 10.3), (7.8, 0.7, 0.9), mah, 0.15)                        # lower back rail

    def dining_sideboard():
        mah, _, br = dining_mats()
        rbox((0, 0, 16.5), (36, 9, 1.0), mah, 0.35)                             # top 16..17
        rbox((0, 0.1, 8.7), (35, 8.6, 14.6), mah, 0.08, 1)                      # carcass 1.4..16
        rbox((0, 0, 1.15), (35.4, 8.8, 0.6), mah, 0.12)                          # plinth 0.85..1.45
        for sx in (-1, 1):
            for sy in (-1, 1):
                lathe([(0, 0), (0.55, 0), (0.72, 0.4), (0.6, 0.86), (0, 0.86)], mah, loc=(sx * 16.6, sy * 3.6, 0))
        fy = -4.2
        n = 4
        bw = 35 / n
        for i in range(n):
            cx = -17.5 + bw * (i + 0.5)
            rbox((cx, fy - 0.2, 14.15), (bw - 0.4, 0.4, 3.2), mah, 0.12)            # drawer
            bail(cx, fy - 0.4, 14.1, br, 0.55)
            rbox((cx, fy - 0.2, 7.3), (bw - 0.4, 0.4, 10.0), mah, 0.12)             # door
            rbox((cx, fy - 0.5, 7.3), (bw - 2.4, 0.3, 7.8), mah, 0.5)               # raised panel
            kx = cx + (bw / 2 - 1.0) * (1 if i % 2 == 0 else -1)
            sphere((kx, fy - 0.68, 8.0), 0.34, br)

    def dining_recordplayer():
        wal = wood("rpwalnut", (0.17, 0.08, 0.035), 0.3, 6.0)
        alu = paint("alu", (0.78, 0.78, 0.8), 0.25, 0, 1)
        ch = chrome()
        vinyl = paint("vinyl", (0.015, 0.015, 0.018), 0.22, 0.3)
        label = paint("label", (0.6, 0.08, 0.05), 0.5)
        rubber = paint("rubber", (0.03, 0.03, 0.03), 0.8)
        br = brass()
        rbox((0, 0, 1.25), (9, 7.4, 1.9), wal, 0.25)                            # plinth 0.3..2.2
        rbox((0, 0, 2.22), (8.4, 6.8, 0.06), alu, 0.02, 1)                       # top plate
        for sx in (-1, 1):
            for sy in (-1, 1):
                cyl((sx * 3.9, sy * 3.0, 0.16), 0.38, 0.32, rubber)
        cyl((-1.0, 0.1, 2.5), 3.1, 0.5, ch, 64)                                   # platter 2.25..2.75
        cyl((-1.0, 0.1, 2.8), 3.0, 0.1, vinyl, 64)                                # record
        for r in (2.75, 2.35, 1.95, 1.55):
            torus((-1.0, 0.1, 2.85), r, 0.012, paint("groove%d" % int(r * 100), (0.05, 0.05, 0.06), 0.15), maj=64)
        cyl((-1.0, 0.1, 2.86), 1.0, 0.03, label, 48)
        cyl((-1.0, 0.1, 3.0), 0.08, 0.35, ch, 12)                                 # spindle
        cyl((3.3, 2.4, 2.55), 0.55, 0.65, ch)                                     # tonearm base
        cyl((3.3, 2.4, 3.0), 0.3, 0.3, ch)
        tube([(3.3, 3.5, 3.15), (3.3, 2.4, 3.15), (2.9, 0.2, 3.15), (2.1, -1.6, 3.1)], 0.07, ch)
        cyl((3.3, 3.5, 3.15), 0.32, 0.5, ch, rot=(math.pi / 2, 0, 0))             # counterweight
        rbox((1.85, -2.05, 3.0), (0.5, 0.9, 0.16), ch, 0.04, 1, rot=(0, 0, math.radians(-25)))   # headshell
        cyl((3.75, 0.2, 2.6), 0.08, 0.6, ch, 12)                                  # arm rest
        cyl((3.3, -2.8, 2.38), 0.42, 0.35, br)                                    # speed knob

    # ============================================================== KIDS
    def kids_mats():
        return (paint("kred", (0.62, 0.07, 0.05), 0.35, 0.5), paint("kyellow", (0.88, 0.6, 0.08), 0.35, 0.5),
                paint("kblue", (0.08, 0.26, 0.6), 0.35, 0.5), paint("ksky", (0.42, 0.64, 0.82), 0.4, 0.4),
                paint("kgreen", (0.16, 0.45, 0.2), 0.35, 0.5), paint("kcream", (0.88, 0.85, 0.77), 0.6))

    def kids_bed():
        red, yellow, blue, sky, green, cream = kids_mats()
        quilt = checker("quilt", (0.66, 0.08, 0.06), (0.88, 0.76, 0.5), 0.28, 0.85, 0.6)
        sheet = paint("sheet", (0.9, 0.9, 0.87), 0.8)
        post = [(0, 0), (0.75, 0), (0.9, 0.4), (0.75, 1.0), (0.7, 1)]
        for y, top, board_top in ((17.0, 19.0, 17.5), (-17.0, 11.6, 11.0)):
            for sx in (-1, 1):
                lathe([(0, 0), (0.8, 0), (0.9, 0.5), (0.72, 1.2), (0.72, top - 0.6), (0.85, top - 0.3), (0.6, top),
                       (0, top)], sky, loc=(sx * 9.1, y, 0), segs=32)
                sphere((sx * 9.1, y, top + 0.75), 0.85, yellow)
            rbox((0, y, (3.0 + board_top) / 2), (17.6, 1.0, board_top - 3.0), sky, 0.2)
        # arched headboard top, a star on it
        bpy.ops.mesh.primitive_cylinder_add(radius=8.8, depth=1.0, vertices=64, location=(0, 17.0, 17.4),
                                            rotation=(math.pi / 2, 0, 0))
        arch = bpy.context.object
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        arch.scale = (1, 1, 0.23)
        arch.data.materials.append(sky)
        smooth(arch)
        b = arch.modifiers.new("bevel", "BEVEL"); b.width = 0.2; b.segments = 3; b.limit_method = "ANGLE"
        prism(star_pts(2.0, 0.85), 0.2, yellow, (0, 16.3, 13.2))
        for sx in (-1, 1):
            rbox((sx * 9.1, 0, 4.5), (1.0, 33.4, 2.4), sky, 0.2)                 # side rails 3.3..5.7
        rbox((0, 0, 7.0), (17.4, 33.2, 2.6), sheet, 0.6)                          # mattress 5.7..8.3
        rbox((0, 13.6, 9.2), (11.0, 4.4, 2.0), sheet, 0.95)                       # pillow
        rbox((0, -3.0, 8.85), (18.4, 27.6, 1.2), quilt, 0.5)                      # quilt 8.25..9.45
        rbox((0, 10.2, 9.0), (18.2, 3.0, 1.1), sheet, 0.45)                       # turned-down sheet

    def kids_toybox():
        red, yellow, blue, sky, green, cream = kids_mats()
        rope = paint("rope", (0.62, 0.48, 0.28), 0.9)
        rbox((0, 0, 3.9), (13.6, 7.6, 6.6), red, 0.3)                            # body 0.6..7.2
        rbox((0, 0, 0.5), (14.0, 8.0, 1.0), blue, 0.25)                           # base
        rbox((0, 0, 7.55), (14.0, 8.0, 0.9), yellow, 0.35)                        # lid 7.1..8
        for sx in (-1, 1):
            for sy in (-1, 1):
                rbox((sx * 6.55, sy * 3.55, 3.9), (0.8, 0.8, 6.0), blue, 0.2)     # corner posts
            torus((sx * 6.85, 0, 5.2), 1.1, 0.18, rope, rot=(0, math.pi / 2, 0), scale=(1, 1, 0.75))
        prism(star_pts(1.8, 0.75), 0.15, yellow, (-3.6, -3.95, 3.9))
        cyl((0, -3.88, 3.9), 1.5, 0.15, blue, 48, rot=(math.pi / 2, 0, 0))
        prism([(-1.7, -1.4), (1.7, -1.4), (0, 1.6)], 0.15, green, (3.6, -3.95, 3.9))

    def kids_rockinghorse():
        red, yellow, blue, sky, green, cream = kids_mats()
        coat = dapple("dapple", (0.88, 0.85, 0.78), (0.66, 0.65, 0.63))
        hair = paint("mane", (0.16, 0.08, 0.035), 0.9)
        rockerw = wood("rocker", (0.42, 0.22, 0.1), 0.4)
        black = paint("eye", (0.01, 0.01, 0.01), 0.2, 1.0)
        R = 38.0

        def rz(x):
            return R - math.sqrt(R * R - x * x) + 0.6

        for sy in (-1, 1):
            pts = [(x, 0, rz(x)) for x in [-9.6 + 1.6 * i for i in range(13)]]
            tube(pts, 0.6, rockerw, loc=(0, sy * 2.6, 0), scale=(1, 0.65, 1))
        for x in (-7.0, 7.0):
            rod((x, -2.6, rz(x) + 0.5), (x, 2.6, rz(x) + 0.5), 0.32, rockerw)
        for sx in (-1, 1):
            for sy in (-1, 1):
                x1 = sx * 8.0
                rod((sx * 3.9, sy * 1.2, 9.2), (x1, sy * 2.6, rz(x1) + 0.45), 0.72, coat, 0.44)
                rod((sx * 7.75, sy * 2.53, rz(sx * 7.75) + 0.95), (x1, sy * 2.6, rz(x1) + 0.45), 0.5, hair)   # hoof
        sphere((0, 0, 10.7), 1.0, coat, scale=(6.4, 2.75, 2.85))                     # body
        sphere((5.3, 0, 13.4), 1.0, coat, scale=(1.85, 1.6, 3.4), rot=(0, math.radians(35), 0))   # neck
        sphere((7.6, 0, 15.2), 1.0, coat, scale=(2.7, 1.35, 1.4), rot=(0, math.radians(30), 0))  # head
        sphere((9.5, 0, 14.0), 0.85, coat, scale=(1.1, 1.3, 1.05))                # muzzle
        for sy in (-1, 1):
            bpy.ops.mesh.primitive_cone_add(radius1=0.38, radius2=0.05, depth=1.1, location=(6.5, sy * 0.5, 16.6))
            ear = bpy.context.object; ear.data.materials.append(coat); smooth(ear)
            sphere((8.0, sy * 1.18, 15.65), 0.24, black)
        for t in [-2.8 + 0.5 * i for i in range(12)]:                              # mane along the crest
            a = math.radians(35)
            ax, az = math.sin(a), math.cos(a)
            px, pz = 5.3 + ax * t - az * 1.2, 13.4 + az * t + ax * 1.2
            sphere((px, 0, pz), 0.55, hair)
        tube([(-5.9, 0, 11.6), (-7.3, 0, 11.4), (-8.0, 0, 9.8), (-7.9, 0, 8.0)], 0.45, hair)
        sphere((0, 0, 12.75), 1.0, red, scale=(2.4, 2.65, 0.75))                  # saddle
        torus((0, 0, 13.05), 1.9, 0.12, yellow, scale=(1.2, 1.15, 1))
        for sy in (-1, 1):
            rbox((0, sy * 2.55, 10.6), (0.35, 0.08, 3.2), hair, 0.03, 1)          # stirrup leathers
            torus((0, sy * 2.55, 8.8), 0.42, 0.08, brass(), rot=(math.pi / 2, 0, 0))
        rod((7.1, -1.9, 15.7), (7.1, 1.9, 15.7), 0.16, wood("handle", (0.5, 0.3, 0.12)))
        for sy in (-1, 1):
            sphere((7.1, sy * 1.95, 15.7), 0.3, red)
        torus((9.0, 0, 14.2), 0.95, 0.09, blue, rot=(0, math.radians(80), 0), scale=(1, 1.25, 1))   # bridle

    def kids_train():
        red, yellow, blue, sky, green, cream = kids_mats()
        black = paint("kblack", (0.03, 0.03, 0.03), 0.4, 0.4)
        rbox((0.2, 0, 1.55), (8.2, 2.2, 0.6), red, 0.15)                           # chassis 1.25..1.85
        for x, r in ((-2.7, 0.78), (-0.7, 0.78), (2.5, 0.58)):
            for sy in (-1, 1):
                cyl((x, sy * 1.22, r), r, 0.38, yellow, 32, rot=(math.pi / 2, 0, 0))
                cyl((x, sy * 1.43, r), 0.2, 0.08, red, 16, rot=(math.pi / 2, 0, 0))
            rod((x, -1.1, r), (x, 1.1, r), 0.12, black)
        for sy in (-1, 1):
            rbox((-1.7, sy * 1.47, 0.78), (2.4, 0.08, 0.22), red, 0.04, 1)          # coupling rods
        cyl((1.4, 0, 2.85), 1.0, 4.8, blue, 40, rot=(0, math.pi / 2, 0))           # boiler 1.85..3.85, x -1..3.8
        cyl((3.85, 0, 2.85), 1.06, 0.15, red, 40, rot=(0, math.pi / 2, 0))
        sphere((3.92, 0, 2.85), 0.35, yellow)
        lathe([(0, 0), (0.42, 0), (0.42, 0.55), (0.62, 0.85), (0.62, 1.05), (0, 1.05)], black, loc=(2.8, 0, 3.3))
        sphere((1.2, 0, 3.75), 0.5, yellow)
        rbox((-2.6, 0, 2.95), (2.6, 2.4, 2.2), blue, 0.2)                          # cab 1.85..4.05
        rbox((-2.6, 0, 4.25), (3.2, 2.8, 0.4), red, 0.15)                          # roof
        for sy in (-1, 1):
            rbox((-2.5, sy * 1.2, 3.35), (1.1, 0.06, 0.9), black, 0.08)            # windows
        rbox((4.25, 0, 1.55), (0.4, 2.6, 0.6), red, 0.1)                          # buffer beam
        for sy in (-1, 1):
            cyl((4.6, sy * 0.85, 1.55), 0.22, 0.4, black, 16, rot=(0, math.pi / 2, 0))
        cyl((-4.1, 0, 1.55), 0.15, 0.4, black, 12, rot=(0, math.pi / 2, 0))

    def kids_crane():
        red, yellow, blue, sky, green, cream = kids_mats()
        black = paint("tyre", (0.03, 0.03, 0.03), 0.6)
        string = paint("string", (0.9, 0.88, 0.82), 0.9)
        grey = paint("weight", (0.28, 0.3, 0.33), 0.5, 0.3)
        rbox((0, 0, 3.7), (7.0, 7.0, 4.4), yellow, 0.35)                           # cab body 1.5..5.9
        rbox((0, 0, 6.05), (7.4, 7.4, 0.3), red, 0.12)                             # deck
        rbox((-1.0, -3.52, 4.2), (3.2, 0.08, 2.0), paint("kwin", (0.1, 0.16, 0.22), 0.1, 0.8), 0.15)
        for x in (-2.4, 2.4):
            for sy in (-1, 1):
                cyl((x, sy * 3.7, 1.3), 1.3, 0.7, black, 32, rot=(math.pi / 2, 0, 0))
                cyl((x, sy * 4.07, 1.3), 0.55, 0.06, red, 24, rot=(math.pi / 2, 0, 0))
        tube([(3.5, -2.0, 4.6), (4.3, -2.0, 4.6), (4.3, -2.0, 3.6)], 0.12, cream)   # winding crank
        sphere((4.3, -2.0, 3.45), 0.3, red)
        h0, h1, s = 6.2, 18.0, 1.35
        for sx in (-1, 1):
            for sy in (-1, 1):
                rbox((sx * s, sy * s, (h0 + h1) / 2), (0.45, 0.45, h1 - h0), red, 0.1)
        seg = (h1 - h0) / 4
        for i in range(4):
            z0, z1 = h0 + i * seg, h0 + (i + 1) * seg
            for a, b in (((-s, -s), (s, -s)), ((s, -s), (s, s)), ((s, s), (-s, s)), ((-s, s), (-s, -s))):
                if i % 2:
                    a, b = b, a
                rod((a[0], a[1], z0), (b[0], b[1], z1), 0.12, red)
            for a, b in (((-s, -s), (s, -s)), ((s, -s), (s, s)), ((s, s), (-s, s)), ((-s, s), (-s, -s))):
                rod((a[0], a[1], z1), (b[0], b[1], z1), 0.12, red)
        cyl((0, 0, 18.25), 2.0, 0.5, yellow, 40)                                    # turntable
        rbox((-1.0, 0, 19.6), (2.6, 2.6, 2.2), yellow, 0.3)                         # operator cab
        rbox((-4.2, 0, 19.4), (2.2, 2.6, 2.0), grey, 0.25)                          # counterweight
        # jib truss along +X: two lower chords, one top chord, diagonals
        for sy in (-0.8, 0.8):
            rod((-3.0, sy, 19.0), (11.2, sy * 0.3, 19.0), 0.14, red)
        rod((0.4, 0, 21.0), (11.2, 0, 19.2), 0.14, red)
        rod((-0.8, 0, 20.7), (0.4, 0, 21.0), 0.14, red)
        for k in range(7):
            x = 0.6 + k * 1.5
            ztop = 21.0 - (x - 0.4) / 10.8 * 1.8
            sy = 0.8 - (x + 3.0) / 14.2 * 0.56
            for s2 in (-1, 1):
                rod((x, s2 * sy, 19.0), (x + 0.75, 0, ztop - 0.12), 0.09, red)
        cyl((10.6, 0, 18.7), 0.45, 0.4, yellow, 24, rot=(math.pi / 2, 0, 0))         # pulley
        rod((10.6, 0, 18.3), (10.6, 0, 9.9), 0.05, string)
        rbox((10.6, 0, 9.5), (1.0, 0.6, 0.9), red, 0.15)                           # hook block
        tube([(10.6, 0, 9.05), (10.6, 0, 8.2), (10.95, 0, 7.75), (11.35, 0, 8.05), (11.3, 0, 8.4)], 0.12, brass())

    # ============================================================== BATH
    def bath_mats():
        return (paint("porcelain", (0.9, 0.9, 0.88), 0.08, 0.8), paint("celadon", (0.5, 0.66, 0.6), 0.25, 0.6),
                chrome(), brass(), wood("teak", (0.42, 0.22, 0.09), 0.45, 4.0, "BANDS", 0.3))

    def tap(x, y, z, ch, porcelain, spout_dir=(0, -1)):
        lathe([(0, 0), (0.42, 0), (0.32, 0.2), (0.22, 0.6), (0.24, 1.1), (0, 1.1)], ch, loc=(x, y, z), segs=24)
        for a in (0, 90):
            rbox((x, y, z + 1.2), (1.4, 0.18, 0.18), ch, 0.05, 2, rot=(0, 0, math.radians(a + 45)))
        sphere((x, y, z + 1.3), 0.2, porcelain)
        dx, dy = spout_dir
        tube([(x, y, z + 0.75), (x + dx * 0.7, y + dy * 0.7, z + 0.75), (x + dx * 1.0, y + dy * 1.0, z + 0.45)], 0.14, ch)

    def bath_bathtub():
        porc, cel, ch, br, _ = bath_mats()
        L = 9.4
        rings = [(L, 0.0, 1.8), (L, 4.6, 1.8), (L, 5.9, 2.6), (L, 6.95, 5.0), (L, 7.3, 9.0), (L, 7.45, 11.4),
                 (L, 7.6, 11.85), (L, 7.5, 12.2), (L, 7.1, 12.25), (L, 6.8, 11.95), (L, 6.55, 11.0), (L, 6.2, 7.0),
                 (L, 5.6, 4.6), (L, 4.6, 3.45), (L, 3.0, 3.2), (L, 0.0, 3.2)]
        loft(rings, [cel, porc], lambda k: 0 if k < 5 else 1)
        for sx in (-1, 1):
            for sy in (-1, 1):
                x, y = sx * 11.6, sy * 4.6
                rod((x * 1.03, y * 1.08, 0.8), (x * 0.95, y * 0.9, 2.7), 0.55, br, 1.0)
                sphere((x * 1.03, y * 1.08, 0.7), 0.7, br)
                for k in range(3):
                    a = math.radians(-60 + 60 * k) + math.atan2(y, x)
                    sphere((x * 1.03 + 0.7 * math.cos(a), y * 1.08 + 0.7 * math.sin(a), 0.34), 0.34, br)
        ex = -(L + 7.3)
        for sy in (-1.3, 1.3):
            tap(ex + 0.25, sy, 12.2, ch, porc, spout_dir=(1, 0))

    def bath_sink():
        porc, cel, ch, br, _ = bath_mats()
        rings = [(1.0, 0.0, 12.5), (1.0, 1.6, 12.5), (1.0, 2.6, 13.2), (1.0, 3.5, 14.8), (1.0, 3.95, 16.4),
                 (1.0, 4.05, 16.9), (1.0, 3.9, 17.05), (1.0, 3.5, 16.95), (1.0, 3.3, 16.3), (1.0, 2.6, 15.0),
                 (1.0, 1.6, 14.3), (1.0, 0.0, 14.2)]
        loft(rings, [porc], lambda k: 0)
        ped = [(0.5, 0.0, 0.0), (0.5, 1.8, 0.0), (0.5, 1.75, 0.35), (0.5, 1.25, 1.2), (0.5, 1.0, 5.5), (0.5, 1.1, 10.0),
               (0.5, 1.5, 12.0), (0.5, 1.75, 12.8), (0.5, 0.0, 12.8)]
        loft(ped, [porc], lambda k: 0)
        cyl((0, -0.4, 14.25), 0.45, 0.06, ch, 24)
        for sx in (-1.6, 1.6):
            tap(sx, 3.62, 17.0, ch, porc)

    def bath_stool():
        _, _, _, _, teak = bath_mats()
        for y in (-2.1, -0.7, 0.7, 2.1):
            rbox((0, y, 8.7), (11, 1.25, 0.6), teak, 0.15)                         # slats 8.4..9
        for sy in (-1, 1):
            rbox((0, sy * 2.2, 7.95), (9.6, 0.6, 0.9), teak, 0.1)                  # rails
        for sx in (-1, 1):
            rbox((sx * 4.6, 0, 7.95), (0.6, 3.8, 0.9), teak, 0.1)
            for sy in (-1, 1):
                rbox((sx * 4.6, sy * 2.2, 4.2), (1.2, 1.2, 8.4), teak, 0.12)
            rbox((sx * 4.6, 0, 2.2), (0.5, 3.6, 0.6), teak, 0.08)                  # stretchers
        rbox((0, 0, 2.2), (8.6, 0.5, 0.6), teak, 0.08)

    def bath_basket():
        wk = wicker("wicker", (0.66, 0.5, 0.3))
        rim = paint("cane", (0.5, 0.36, 0.2), 0.7)
        lathe([(0, 0.15), (3.4, 0.15), (3.55, 0.0), (3.7, 0.5), (4.0, 9.6), (3.85, 9.8), (0, 9.8)], wk)
        torus((0, 0, 9.75), 4.0, 0.22, rim, maj=64)
        torus((0, 0, 0.3), 3.6, 0.2, rim, maj=64)
        lathe([(0, 10.65), (2.0, 10.55), (3.6, 10.25), (4.15, 9.95), (4.1, 9.8), (0, 9.95)], wk)
        torus((0, 0, 10.0), 4.1, 0.16, rim, maj=64)
        torus((0, 0, 11.05), 0.55, 0.13, rim, rot=(math.pi / 2, 0, 0))             # lid loop
        for sx in (-1, 1):
            torus((sx * 3.9, 0, 8.2), 0.9, 0.16, rim, rot=(0, math.pi / 2, 0), scale=(1, 1, 0.7))

    def bath_musicbox():
        rose = wood("rosewood", (0.24, 0.07, 0.035), 0.25, 8.0, "RINGS", 0.8)
        br = brass()
        pearl = paint("pearl", (0.88, 0.84, 0.76), 0.2, 0.8)
        rbox((0, 0, 1.15), (4.4, 3.2, 1.8), rose, 0.1)                            # body 0.25..2.05
        rbox((0, 0, 2.4), (4.5, 3.3, 0.75), rose, 0.18)                            # lid 2.05..2.8
        rbox((0, 0, 2.06), (4.42, 3.22, 0.05), paint("seam2", (0.05, 0.02, 0.01), 0.6), 0.01, 1)
        torus((0, 0, 2.78), 1.0, 0.05, br, scale=(1.5, 1.0, 0.4))
        sphere((0, 0, 2.78), 0.55, pearl, scale=(1.4, 1.0, 0.12))
        for sx in (-1, 1):
            for sy in (-1, 1):
                sphere((sx * 1.95, sy * 1.35, 0.2), 0.22, br)
        rbox((0, -1.62, 1.75), (0.5, 0.06, 0.6), br, 0.05, 1)                     # escutcheon
        rod((2.2, 0.4, 1.1), (2.65, 0.4, 1.1), 0.09, br)                           # winding crank
        rod((2.62, 0.4, 1.1), (2.62, 0.4, 0.25 + 0.55), 0.07, br)
        rod((2.62, 0.4, 0.8), (2.95, 0.4, 0.8), 0.1, rose)

    # ============================================================== STUDY
    def study_mats():
        return (wood("swalnut", (0.12, 0.055, 0.025), 0.35, 3.0, "RINGS", 0.5),
                paint("bottlegreen", (0.035, 0.13, 0.065), 0.42, 0.35),
                paint("oxblood", (0.21, 0.03, 0.022), 0.38, 0.45), brass())

    def study_desk():
        wal, gr, _, br = study_mats()
        rbox((0, 0, 14.4), (28, 13, 1.2), wal, 0.25)                            # top 13.8..15
        rbox((0, -0.2, 15.0), (22, 9.4, 0.08), gr, 0.04, 1)                      # leather inset
        for sx in (-1, 1):
            px = sx * 10.0
            rbox((px, 0.1, 0.3), (8.3, 12.8, 0.6), wal, 0.12)                      # plinth
            rbox((px, 0, 7.2), (8, 12.6, 13.2), wal, 0.06, 1)                       # pedestal 0.6..13.8
            for z0, z1 in ((1.0, 4.9), (5.2, 9.1), (9.4, 13.4)):
                rbox((px, -6.42, (z0 + z1) / 2), (7.2, 0.3, z1 - z0), wal, 0.15)
                bail(px, -6.57, (z0 + z1) / 2 + 0.4, br)
        rbox((0, 0, 13.15), (12.2, 12.0, 1.3), wal, 0.05, 1)                       # frieze 12.5..13.8
        rbox((0, -6.1, 13.15), (11.0, 0.3, 1.0), wal, 0.08)
        sphere((0, -6.35, 13.15), 0.25, br)
        rbox((0, 5.8, 9.2), (12.2, 1.0, 8.4), wal, 0.08, 1)                         # modesty panel

    def study_chair():
        wal, _, ox, br = study_mats()
        rbox((0, 0, 8.0), (10, 10, 1.0), wal, 0.2)                               # seat rail 7.5..8.5
        rbox((0, -0.2, 9.0), (9.4, 9.2, 1.0), ox, 0.4)                           # cushion
        for k in range(15):
            sphere((-4.55 + k * 0.65, -4.98, 8.0), 0.1, br)
        prof = [(0, 0), (0.45, 0), (0.55, 0.5), (0.42, 1.4), (0.5, 4.5), (0.6, 5.3), (0.48, 6.2), (0.52, 7.6), (0, 7.6)]
        tilt = -8
        for sx in (-1, 1):
            lathe(prof, wal, loc=(sx * 4.4, -4.4, 0), segs=24)
            rod((sx * 4.4, -4.4, 7.5), (sx * 4.55, -3.9, 13.0), 0.42, wal)        # arm support
            rod((sx * 4.4, 4.3, 0), (sx * 4.4, 5.6, 22.0), 0.5, wal)              # back post
            rbox((sx * 4.55, 0.35, 13.2), (1.0, 9.2, 0.8), wal, 0.25)              # arm
            rbox((sx * 4.55, 0.0, 13.75), (1.1, 7.0, 0.4), ox, 0.18)               # arm pad
        c = Vector((0, 4.9, 15.4))
        rbox(tuple(c), (8.4, 1.0, 11.0), ox, 0.6, rot=(math.radians(tilt), 0, 0))   # back cushion
        for bx in (-2.4, 0, 2.4):
            for bz in (-3.2, 0, 3.2):
                sphere(tuple(c + Vector(rotx((bx, -0.5, bz), tilt))), 0.2, ox)
        top = c + Vector(rotx((0, 0.2, 6.0), tilt))
        rbox(tuple(top), (9.6, 1.1, 1.0), wal, 0.3, rot=(math.radians(tilt), 0, 0))

    def study_globe():
        wal, _, _, br = study_mats()
        lathe([(0, 0), (3.4, 0), (3.4, 0.4), (3.0, 0.75), (2.2, 1.05), (1.0, 1.3), (0, 1.3)], wal)
        lathe([(0, 1.2), (0.8, 1.2), (0.55, 2.5), (0.85, 4.0), (0.45, 5.5), (0.5, 8.4), (0.9, 9.2), (0.6, 9.9),
               (0, 9.9)], wal, segs=40)
        C = (0, 0, 14.65)
        g = sphere(C, 4.4, globe_map("map"), segs=64)
        g.rotation_euler = (0, math.radians(23.4), 0)
        torus(C, 4.72, 0.16, br, rot=(math.pi / 2, 0, 0), maj=96)                     # meridian (xz plane)
        ax = Vector((math.sin(math.radians(23.4)), 0, math.cos(math.radians(23.4))))
        for s in (-1, 1):
            p = Vector(C) + ax * s * 4.72
            sphere(tuple(p), 0.3, br)

    def study_cabinet():
        wal, gr, ox, br = study_mats()
        rbox((0, 0, 14.75), (18, 8, 0.5), wal, 0.25)                            # top 14.5..15
        rbox((0, 0, 3.0), (17.4, 7.6, 4.0), wal, 0.05, 1)                        # lower body 1..5
        for sx in (-1, 1):
            rbox((sx * 8.5, 0, 9.75), (0.4, 7.6, 9.5), wal, 0.05, 1)              # sides
            for sy in (-1, 1):
                rbox((sx * 8.0, sy * 3.1, 0.5), (1.4, 1.4, 1.0), wal, 0.25)       # bracket feet
            rbox((sx * 4.35, -3.95, 3.0), (8.2, 0.3, 3.0), wal, 0.12)            # drawers
            for kx in (-2.2, 2.2):
                sphere((sx * 4.35 + kx, -4.25, 3.0), 0.28, br)
        rbox((0, 3.6, 9.75), (16.6, 0.4, 9.5), wal, 0.03, 1)                       # back
        rbox((0, 0, 9.65), (16.6, 7.0, 0.3), wal, 0.05, 1)                         # shelf
        random.seed(11)
        cols = [(0.32, 0.04, 0.03), (0.04, 0.12, 0.07), (0.05, 0.07, 0.18), (0.5, 0.36, 0.18), (0.2, 0.1, 0.05)]
        bm = [paint("sbook%d" % i, c, 0.6) for i, c in enumerate(cols)]
        for z0 in (5.0, 9.8):
            x = -8.0
            while x < 7.6:
                w = random.uniform(0.7, 1.2); hgt = random.uniform(3.2, 4.2)
                rbox((x + w / 2, 0.3, z0 + hgt / 2), (w, 5.4, hgt), bm[random.randrange(len(bm))], 0.05, 1)
                x += w + 0.04
        gl = glass()
        for sx in (-1, 1):
            cx = sx * 4.2
            rbox((cx, -3.9, 9.75), (7.0, 0.08, 7.9), gl, 0.0)
            for z in (5.45, 14.05):
                rbox((cx, -3.95, z), (8.2, 0.4, 0.8), wal, 0.08)
            for e in (-1, 1):
                rbox((cx + e * 3.75, -3.95, 9.75), (0.7, 0.4, 9.4), wal, 0.08)
            rbox((cx, -3.95, 9.75), (7.0, 0.3, 0.35), wal, 0.05)                    # glazing bar
            sphere((sx * 0.75, -4.3, 9.75), 0.3, br)

    # ============================================================== ATTIC
    def attic_mats():
        return (wood("oldoak", (0.3, 0.18, 0.09), 0.7, 3.0, "RINGS", 0.0, dust=0.28),
                paint("tarnish", (0.48, 0.38, 0.22), 0.5, 0, 0.8),
                dusty_paint("oldleather", (0.16, 0.08, 0.04), 0.65, 0.18))

    def attic_trunk():
        oak, tb, lea = attic_mats()
        canvas = dusty_paint("canvas", (0.2, 0.2, 0.11), 0.85, 0.22)
        rbox((0, 0, 5.6), (17.6, 9.6, 10.4), canvas, 0.25)                        # body 0.4..10.8
        for z in (1.0, 7.35, 10.55):
            rbox((0, 0, z), (17.9, 9.9, 0.7), oak, 0.12)                           # wooden bands
        for sx in (-1, 1):
            for sy in (-1, 1):
                rbox((sx * 8.65, sy * 4.65, 5.6), (0.6, 0.6, 10.2), oak, 0.1)       # corner slats
                rbox((sx * 8.4, sy * 4.4, 0.2), (1.2, 1.2, 0.4), oak, 0.1)          # feet
                for z in (1.0, 10.4):
                    rbox((sx * 8.55, sy * 4.55, z), (1.2, 1.2, 1.1), tb, 0.3)       # brass corners
        for sx in (-4.6, 4.6):
            rbox((sx, -4.98, 5.7), (1.3, 0.12, 9.6), lea, 0.04, 1)                  # straps front, top, back
            rbox((sx, 0, 10.96), (1.3, 10.1, 0.12), lea, 0.04, 1)
            rbox((sx, 4.98, 5.7), (1.3, 0.12, 9.6), lea, 0.04, 1)
            torus((sx, -5.08, 8.6), 0.75, 0.08, tb, rot=(math.pi / 2, 0, 0), scale=(1.0, 0.75, 1))
        rbox((0, -5.0, 7.35), (2.2, 0.25, 1.9), tb, 0.12)                           # lock
        rbox((0, -5.14, 7.1), (0.18, 0.05, 0.5), paint("keyhole", (0.02, 0.02, 0.02), 0.8), 0.02, 1)
        for sx in (-1, 1):
            tube([(0, -1.3, 0), (0, -1.0, -0.6), (0, 0, -0.85), (0, 1.0, -0.6), (0, 1.3, 0)], 0.22, lea,
                 loc=(sx * 9.0, 0, 7.8))
            for sy in (-1.3, 1.3):
                rbox((sx * 8.9, sy, 7.8), (0.2, 0.7, 0.7), tb, 0.06)

    def attic_lamp():
        oak, tb, _ = attic_mats()
        silk = dusty_paint("silk", (0.55, 0.3, 0.26), 0.85, 0.12)
        braid = paint("braid", (0.6, 0.48, 0.26), 0.6, 0, 0.3)
        lathe([(0, 0), (3.5, 0), (3.5, 0.3), (3.1, 0.6), (2.1, 0.95), (1.0, 1.45), (0, 1.45)], oak)
        lathe([(0, 1.3), (0.75, 1.3), (0.55, 2.6), (0.85, 3.6), (0.55, 4.6), (0.5, 12.0), (0.75, 12.8), (0.5, 13.6),
               (0.45, 21.5), (0, 21.5)], oak, segs=32)
        lathe([(0, 21.4), (0.6, 21.4), (0.5, 22.6), (0.3, 23.2), (0, 23.2)], tb)
        cyl((0, 0, 23.9), 0.32, 1.4, paint("bulb", (0.85, 0.8, 0.65), 0.3))
        for k in range(4):                                                            # harp
            a = k * math.pi / 2
            rod((0, 0, 23.0), (2.15 * math.cos(a), 2.15 * math.sin(a), 29.0), 0.05, tb)
        lathe([(3.5, 22.6), (3.3, 24.5), (2.5, 28.6), (2.2, 29.6)], silk, segs=64)   # open shade shell
        torus((0, 0, 22.6), 3.5, 0.1, braid, maj=72)
        torus((0, 0, 29.6), 2.2, 0.09, braid, maj=64)
        for k in range(72):
            a = 2 * math.pi * k / 72
            rod((3.52 * math.cos(a), 3.52 * math.sin(a), 22.6), (3.55 * math.cos(a), 3.55 * math.sin(a), 21.6), 0.045,
                braid, verts=6)
        sphere((0, 0, 29.95), 0.3, tb)
        for k in range(5):
            sphere((0.6, -0.4, 22.0 - k * 0.3), 0.07, tb)                               # pull chain

    def attic_rockingchair():
        oak, tb, _ = attic_mats()
        pad = checker("faded", (0.52, 0.32, 0.28), (0.66, 0.6, 0.45), 0.45, 0.9, 0.4, dust=0.12)
        R = 30.0

        def rz(y):
            return R - math.sqrt(R * R - y * y) + 0.6

        for sx in (-1, 1):
            pts = [(0, y, rz(y)) for y in [-9.0 + 1.5 * i for i in range(13)]]
            tube(pts, 0.6, oak, loc=(sx * 5.0, 0, 0), scale=(0.65, 1, 1))
        rbox((0, 0, 8.55), (11, 10, 0.9), oak, 0.3)                               # seat 8.1..9
        rbox((0, -0.1, 9.25), (8.4, 7.6, 0.55), pad, 0.25)
        for sx in (-1, 1):
            for sy in (-1, 1):
                rod((sx * 4.6, sy * 3.9, 8.3), (sx * 5.0, sy * 4.9, rz(sy * 4.9) + 0.3), 0.42, oak, 0.36)
            rod((sx * 4.75, -4.3, 4.5), (sx * 4.75, 4.3, 4.5), 0.2, oak)          # side stretchers
            rod((sx * 4.8, 4.0, 8.5), (sx * 5.4, 6.6, 22.0), 0.45, oak)           # back posts
            sphere((sx * 5.4, 6.6, 22.15), 0.5, oak)
            rod((sx * 4.7, -3.9, 9.0), (sx * 5.2, -4.4, 14.8), 0.3, oak)          # arm supports
            tube([(sx * 5.1, 5.3, 15.5), (sx * 5.4, 1.0, 15.2), (sx * 5.5, -4.2, 14.9), (sx * 5.4, -5.4, 14.7)],
                 0.42, oak, scale=(1, 1, 1))
        rod((-4.75, 0, 4.5), (4.75, 0, 4.5), 0.2, oak)
        tube([(-5.4, 6.6, 21.3), (0, 7.2, 21.9), (5.4, 6.6, 21.3)], 0.5, oak)       # top rail
        for k in range(7):
            x = -3.6 + k * 1.2
            f = 1 - (x / 5.4) ** 2
            rod((x, 3.6, 9.0), (x * 1.06, 6.5 + 0.6 * f, 21.3 + 0.55 * f), 0.18, oak)

    # ============================================================== EXTRAS
    def hall_clock():
        _, dk, _, br = hall_mats()
        gl = glass()
        dial = paint("dial", (0.86, 0.8, 0.64), 0.4)
        ink = paint("ink", (0.02, 0.02, 0.02), 0.4)
        rbox((0, 0, 0.5), (10.4, 6.0, 1.0), dk, 0.2)                             # plinth
        rbox((0, 0, 6.5), (9.6, 5.4, 11.0), dk, 0.15)                             # base 1..12
        rbox((0, -2.75, 6.5), (6.6, 0.2, 7.4), dk, 0.4)                           # base panel
        rbox((0, 0, 12.3), (10.0, 5.8, 0.6), dk, 0.15)
        rbox((0, 0.3, 20.0), (7.6, 4.4, 15.4), dk, 0.1)                           # waist 12.3..27.7
        rbox((0, -2.0, 20.0), (5.8, 0.15, 13.0), paint("inside", (0.03, 0.02, 0.015), 0.8), 0.0)
        rod((0, -1.8, 26.5), (0, -1.8, 16.5), 0.08, br)
        cyl((0, -1.8, 16.0), 1.3, 0.25, br, 48, rot=(math.pi / 2, 0, 0))            # pendulum bob
        rbox((0, -2.1, 20.0), (5.6, 0.06, 12.8), gl, 0.0)
        for x in (-3.15, 3.15):
            rbox((x, -2.0, 20.0), (0.7, 0.45, 13.6), dk, 0.1)
        for z in (13.4, 26.6):
            rbox((0, -2.0, z), (7.0, 0.45, 0.7), dk, 0.1)
        rbox((0, 0, 28.0), (10.0, 5.8, 0.6), dk, 0.15)
        rbox((0, 0, 33.0), (9.6, 5.4, 9.4), dk, 0.15)                             # hood 28.3..37.7
        cyl((0, -2.72, 33.0), 3.3, 0.12, dial, 64, rot=(math.pi / 2, 0, 0))
        torus((0, -2.8, 33.0), 3.35, 0.16, br, rot=(math.pi / 2, 0, 0), maj=64)
        for k in range(12):
            a = k * math.pi / 6
            rbox((2.75 * math.cos(a), -2.82, 33.0 + 2.75 * math.sin(a)), (0.12, 0.04, 0.5), ink, 0.0,
                 rot=(0, -a + math.pi / 2, 0))
        rbox((0.6, -2.86, 33.9), (0.12, 0.04, 2.0), ink, 0.0, rot=(0, math.radians(-35), 0))
        rbox((0.75, -2.88, 32.6), (0.14, 0.04, 2.6), ink, 0.0, rot=(0, math.radians(-120), 0))
        sphere((0, -2.9, 33.0), 0.18, br)
        for x in (-4.4, 4.4):
            lathe([(0, 0), (0.45, 0), (0.4, 9.4), (0, 9.4)], dk, loc=(x, -2.55, 28.3), segs=20)   # hood columns
        bpy.ops.mesh.primitive_cylinder_add(radius=5.0, depth=5.4, vertices=64, location=(0, 0, 37.7),
                                            rotation=(math.pi / 2, 0, 0))
        crest = bpy.context.object
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        crest.scale = (1, 1, 0.42)
        crest.data.materials.append(dk)
        smooth(crest)
        for x in (-4.4, 0, 4.4):
            sphere((x, -1.0, 39.0 + (1.1 if x == 0 else 0)), 0.45, br)

    def hall_plant():
        glaze = paint("glaze2", (0.05, 0.19, 0.13), 0.12, 1.0)
        soil = paint("soil", (0.06, 0.04, 0.03), 1.0)
        leafm = dapple("snakeleaf", (0.05, 0.16, 0.06), (0.2, 0.32, 0.14))
        rim = paint("leafrim", (0.62, 0.55, 0.18), 0.5)
        lathe([(0, 0), (2.6, 0), (2.8, 0.3), (3.3, 5.2), (3.5, 5.6), (3.3, 5.9), (3.15, 5.6), (0, 5.6)], glaze)
        cyl((0, 0, 5.45), 3.15, 0.2, soil, 48)
        random.seed(3)
        for k in range(11):
            a = k * 2.4
            Lf = random.uniform(10.0, 17.0)
            r0 = 0.4 + 1.2 * (k % 3) / 2
            leaf(Lf, 1.25, leafm, (r0 * math.cos(a), r0 * math.sin(a), 5.3), math.degrees(a),
                 random.uniform(72, 86), curl=0.02, cuts=10, wave=0.04, solid=0.1, twist=random.uniform(-0.4, 0.4))
        _ = rim

    def kitchen_herbs():
        pine = wood("tray", (0.6, 0.4, 0.2), 0.45, 2.0)
        terr = paint("terracotta", (0.58, 0.25, 0.13), 0.75)
        soil = paint("soil2", (0.06, 0.04, 0.03), 1.0)
        basil = paint("basil", (0.12, 0.32, 0.06), 0.45)
        rosemary = paint("rosemary", (0.12, 0.2, 0.12), 0.6)
        parsley = paint("parsley", (0.08, 0.26, 0.05), 0.5)
        rbox((0, 0, 0.2), (12.4, 4.6, 0.4), pine, 0.1)
        for sx in (-1, 1):
            rbox((sx * 6.05, 0, 0.6), (0.3, 4.6, 0.8), pine, 0.08)
        for sy in (-1, 1):
            rbox((0, sy * 2.15, 0.55), (12.4, 0.3, 0.5), pine, 0.06)
        random.seed(5)
        for i, x in enumerate((-4.0, 0.0, 4.0)):
            lathe([(0, 0), (1.3, 0), (1.75, 3.0), (1.95, 3.1), (1.95, 3.7), (1.65, 3.7), (0, 3.5)], terr,
                  loc=(x, 0, 0.4), segs=40)
            cyl((x, 0, 3.95), 1.62, 0.1, soil, 32)
            if i == 0:                                   # basil: broad leaves in a mound
                for k in range(24):
                    a = k * 2.4; r = 0.2 + 1.1 * (k % 4) / 3
                    sphere((x + r * math.cos(a), r * math.sin(a), 4.5 + 0.5 * (3 - k % 4)), 0.85, basil,
                           scale=(1.0, 0.6, 0.25), rot=(random.uniform(-0.6, 0.6), random.uniform(-0.6, 0.6), a))
            elif i == 1:                                 # rosemary: upright needle stems
                for k in range(14):
                    a = k * 2.4; r = 0.2 + 0.9 * random.random()
                    p0 = (x + r * math.cos(a), r * math.sin(a), 4.0)
                    p1 = (x + r * 1.6 * math.cos(a), r * 1.6 * math.sin(a), 4.0 + random.uniform(3.0, 4.6))
                    rod(p0, p1, 0.16, rosemary, 0.06, verts=8)
            else:                                        # parsley: frilly clusters
                for k in range(26):
                    a = k * 2.4; r = 0.2 + 1.3 * random.random()
                    sphere((x + r * math.cos(a), r * math.sin(a), 4.4 + random.uniform(0.2, 1.7)), 0.38, parsley,
                           segs=12)

    def dining_candelabra():
        br = brass()
        wax = paint("wax", (0.9, 0.86, 0.74), 0.5)
        wick = paint("wick", (0.03, 0.02, 0.01), 0.8)
        lathe([(0, 0), (2.2, 0), (2.2, 0.25), (1.6, 0.55), (0.5, 1.2), (0.32, 2.0), (0.55, 2.6), (0.28, 3.4),
               (0.3, 7.0), (0.6, 7.4), (0.3, 7.8), (0, 7.8)], br, segs=40)

        def cup(x, y, z):
            lathe([(0, 0), (0.25, 0), (0.45, 0.4), (0.5, 0.6), (0.8, 0.7), (0.82, 0.8), (0.42, 0.8), (0, 0.8)], br,
                  loc=(x, y, z), segs=32)
            cyl((x, y, z + 0.6 + 2.0), 0.36, 4.0, wax)
            rod((x, y, z + 4.6), (x, y, z + 4.9), 0.04, wick, verts=6)

        cup(0, 0, 7.7)
        for k in range(4):
            a = math.radians(45 + 90 * k)
            c, s = math.cos(a), math.sin(a)
            tube([(0, 0, 6.6), (1.4 * c, 1.4 * s, 5.8), (2.9 * c, 2.9 * s, 6.0), (3.4 * c, 3.4 * s, 6.8)], 0.15, br)
            cup(3.4 * c, 3.4 * s, 6.8)

    def kids_teddy():
        fur = velvet("fur", (0.42, 0.22, 0.08))
        light = velvet("furlight", (0.62, 0.42, 0.22))
        dark = paint("nose", (0.02, 0.015, 0.01), 0.25, 0.6)
        bow = paint("bow", (0.62, 0.05, 0.05), 0.5, 0, 0)
        sphere((0, 0, 2.2), 1.0, fur, scale=(1.55, 1.3, 1.9))                      # body
        sphere((0, -0.75, 2.0), 1.0, light, scale=(1.0, 0.7, 1.25))                 # tummy
        sphere((0, -0.2, 4.75), 1.35, fur)                                          # head
        sphere((0, -1.35, 4.5), 0.62, light, scale=(1.0, 0.85, 0.75))               # muzzle
        sphere((0, -1.9, 4.7), 0.2, dark, scale=(1.3, 1, 1))
        for sx in (-1, 1):
            sphere((sx * 0.5, -1.2, 5.25), 0.14, dark)
            sphere((sx * 1.0, -0.1, 5.9), 0.55, fur, scale=(1, 0.55, 1))           # ears
            sphere((sx * 1.0, -0.38, 5.9), 0.32, light, scale=(1, 0.4, 1))
            sphere((sx * 1.55, -0.5, 2.6), 0.55, fur, scale=(0.8, 0.8, 1.6), rot=(0.3, sx * 0.4, 0))   # arms
            sphere((sx * 0.95, -1.45, 0.65), 0.7, fur, scale=(0.9, 1.6, 0.85))      # legs forward
            sphere((sx * 0.95, -2.5, 0.75), 0.55, light, scale=(0.9, 0.3, 1.0))     # foot pads
            sphere((sx * 0.45, -1.1, 3.55), 0.45, bow, scale=(1.0, 0.5, 0.7), rot=(0, 0, sx * 0.2))
        sphere((0, -1.15, 3.55), 0.22, bow)

    def kids_drum():
        red, yellow, blue, sky, green, cream = kids_mats()
        head = paint("drumhead", (0.9, 0.86, 0.74), 0.6)
        stick = wood("stick", (0.6, 0.42, 0.22), 0.5)
        cyl((0, 0, 2.0), 2.5, 3.2, red, 64)                                         # shell 0.4..3.6
        for z in (0.2, 3.8):
            cyl((0, 0, z), 2.6, 0.4, blue, 64)                                       # hoops
        cyl((0, 0, 4.02), 2.45, 0.04, head, 64)
        for k in range(10):
            a0 = 2 * math.pi * k / 10
            a1 = a0 + math.pi / 10
            rod((2.56 * math.cos(a0), 2.56 * math.sin(a0), 3.6), (2.56 * math.cos(a1), 2.56 * math.sin(a1), 0.4), 0.06,
                yellow, verts=8)
            rod((2.56 * math.cos(a1), 2.56 * math.sin(a1), 0.4), (2.56 * math.cos(a1 + math.pi / 10),
                                                                   2.56 * math.sin(a1 + math.pi / 10), 3.6), 0.06,
                yellow, verts=8)
        for dx, ang in ((-0.6, 20), (0.7, -15)):
            a = math.radians(ang)
            p0 = (dx - 2.2 * math.sin(a), -2.2 * math.cos(a) * 0.4 + 0.3, 4.15)
            p1 = (dx + 2.2 * math.sin(a), 2.2 * math.cos(a) * 0.4 + 0.3, 4.15)
            rod(p0, p1, 0.12, stick, verts=12)
            sphere(p1, 0.25, red)

    def bath_towelrail():
        porc, cel, ch, br, _ = bath_mats()
        towel = velvet("towel", (0.82, 0.82, 0.78))
        stripe = velvet("stripe", (0.42, 0.58, 0.52))
        for sx in (-1, 1):
            x = sx * 5.6
            rod((x, 0, 0.6), (x, 0, 16.0), 0.25, ch)
            sphere((x, 0, 16.1), 0.35, ch)
            tube([(x, -2.4, 0.3), (x, -1.2, 0.35), (x, 0, 0.6), (x, 1.2, 0.35), (x, 2.4, 0.3)], 0.24, ch)
            for sy in (-2.4, 2.4):
                sphere((x, sy, 0.3), 0.3, ch)
        for z in (15.0, 9.0):
            rod((-5.6, 0, z), (5.6, 0, z), 0.2, ch)
        # towel folded over the top bar
        rbox((0, -0.42, 11.4), (8.0, 0.3, 7.4), towel, 0.15)
        rbox((0, 0.42, 12.4), (8.0, 0.3, 5.4), towel, 0.15)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.57, depth=8.0, vertices=32, location=(0, 0, 15.05),
                                            rotation=(0, math.pi / 2, 0))
        o = bpy.context.object; o.data.materials.append(towel); smooth(o)
        rbox((0, -0.6, 8.6), (8.02, 0.08, 0.9), stripe, 0.03, 1)

    def bath_fern():
        porc, *_ = bath_mats()
        soil = paint("soil3", (0.06, 0.04, 0.03), 1.0)
        frond = paint("frond", (0.12, 0.3, 0.06), 0.5)
        lathe([(0, 0), (1.8, 0), (2.0, 0.3), (2.7, 4.6), (2.9, 4.8), (2.9, 5.2), (2.6, 5.2), (0, 5.0)], porc)
        cyl((0, 0, 5.05), 2.6, 0.1, soil, 48)
        random.seed(8)
        for k in range(30):                              # fronds: a curved rachis lined with leaflet pairs
            a = k * 2.4
            pitch = math.radians(random.uniform(55, 75) if k < 8 else random.uniform(15, 50))
            Lf = random.uniform(6.5, 9.5)
            h = Vector((math.cos(a), math.sin(a), 0))
            side = Vector((-math.sin(a), math.cos(a), 0))
            base = Vector((0.5 * math.cos(a), 0.5 * math.sin(a), 5.05))

            def at(t):
                d = Lf * t
                return base + h * d * math.cos(pitch) + Vector((0, 0, d * math.sin(pitch) - 0.09 * d * d))

            tube([tuple(at(t / 6)) for t in range(7)], 0.06, frond, res=6)
            n = 16
            for i in range(1, n):
                t = i / n
                c = at(t)
                ll = 0.95 * (1 - t) ** 0.6 + 0.15
                for sgn in (-1, 1):
                    q = c + side * sgn * ll * 0.85 + h * ll * 0.25
                    sphere(tuple(q), 1.0, frond, scale=(0.2, ll, 0.04),
                           rot=(0, 0, a + sgn * math.radians(-15)), segs=8)

    def study_lamp():
        _, _, _, br = study_mats()
        shade = paint("greenglass", (0.015, 0.2, 0.07), 0.12, 0.0, 0.0)
        inner = paint("opal", (0.92, 0.9, 0.82), 0.3)
        rbox((0, 0, 0.35), (6.4, 3.6, 0.7), br, 0.35)
        lathe([(0, 0.6), (0.5, 0.6), (0.3, 1.2), (0.25, 6.6), (0.4, 7.0), (0, 7.0)], br, segs=24)
        rod((-1.6, 0, 6.6), (1.6, 0, 6.6), 0.12, br)
        # half-cylinder shade along X, open below: the top half of a tube, solidified
        import bmesh
        L = 7.6
        bpy.ops.mesh.primitive_cylinder_add(radius=1.75, depth=L, vertices=128, end_fill_type="NOTHING",
                                            location=(0, 0, 0), rotation=(0, math.pi / 2, 0))
        sh = bpy.context.object
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        bm = bmesh.new(); bm.from_mesh(sh.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-3], context="VERTS")
        bm.to_mesh(sh.data); bm.free()
        sh.location = (0, 0, 7.0)
        sh.scale = (1, 1.15, 1.0)
        sm = sh.modifiers.new("solid", "SOLIDIFY"); sm.thickness = 0.12; sm.material_offset = 1
        sh.shadow_terminator_geometry_offset = 0.5
        sh.data.materials.append(shade)
        sh.data.materials.append(inner)
        smooth(sh)
        for e in (-1, 1):
            tube([(e * L / 2, 1.76 * 1.15 * math.cos(math.pi * i / 12), 7.0 + 1.76 * math.sin(math.pi * i / 12))
                  for i in range(13)], 0.08, br)
        for k in range(6):
            sphere((1.2, -1.2, 6.5 - k * 0.25), 0.07, br)

    def attic_dressform():
        oak, tb, _ = attic_mats()
        linen = dusty_paint("linen", (0.68, 0.58, 0.42), 0.9, 0.15)

        prof = [(0.0, 2.2), (0.12, 2.45), (0.3, 2.15), (0.45, 1.7), (0.6, 2.0), (0.74, 2.45), (0.88, 2.55),
                (0.95, 2.1), (1.0, 0.75)]                       # (height 0..1, half-width): hips, waist, bust, shoulders

        def width(t):
            for (t0, w0), (t1, w1) in zip(prof, prof[1:]):
                if t <= t1:
                    u = (t - t0) / (t1 - t0)
                    u = u * u * (3 - 2 * u)
                    return w0 + (w1 - w0) * u
            return prof[-1][1]

        def torso(c):
            x, y, z = c
            r = math.sqrt(x * x + y * y)
            ring = math.sqrt(max(1e-9, 1 - z * z))
            t = (z + 1) / 2
            cap = min(1.0, (1 - abs(z)) * 7) ** 0.5
            k = width(t) * cap / ring if r > 1e-6 else 0.0
            return (x * k, y * k * 0.72, z * 5.6)

        blob(torso, linen, loc=(0, 0, 25.0))
        lathe([(0, 0), (0.75, 0), (0.6, 0.8), (1.0, 1.3), (0, 1.7)], oak, loc=(0, 0, 30.3))
        rod((0, 0, 3.0), (0, 0, 20.5), 0.5, oak)
        lathe([(0, 0), (0.8, 0), (0.6, 1.0), (0, 1.2)], tb, loc=(0, 0, 13.0))
        for k in range(3):
            a = math.radians(90 + 120 * k)
            tube([(0, 0, 4.5), (2.0 * math.cos(a), 2.0 * math.sin(a), 2.0), (4.2 * math.cos(a), 4.2 * math.sin(a), 0.4)],
                 0.38, oak)
            sphere((4.3 * math.cos(a), 4.3 * math.sin(a), 0.35), 0.38, oak)
        lathe([(0, 2.6), (0.6, 2.6), (0.7, 4.8), (0, 5.0)], oak)

    def attic_suitcases():
        _, tb, lea = attic_mats()
        tan = dusty_paint("tan", (0.42, 0.24, 0.1), 0.65, 0.15)
        ox = dusty_paint("oxsuit", (0.25, 0.05, 0.035), 0.6, 0.15)
        olive = dusty_paint("olive", (0.24, 0.25, 0.14), 0.85, 0.15)
        z = 0.0
        for (w, d, h, mat, yaw) in ((16.0, 10.0, 4.6, tan, -4), (13.0, 8.4, 4.0, ox, 7), (10.0, 7.0, 3.4, olive, -9)):
            e = bpy.data.objects.new("case", None)
            link(e)
            parts = [rbox((0, 0, h / 2), (w, d, h), mat, 0.5)]
            for sx in (-1, 1):
                for sy in (-1, 1):
                    for sz in (0.4, h - 0.4):
                        parts.append(sphere((sx * (w / 2 - 0.35), sy * (d / 2 - 0.35), sz), 0.5, tb, segs=16))
                parts.append(rbox((sx * w * 0.3, -d / 2 - 0.05, h * 0.62), (0.9, 0.2, 0.7), tb, 0.08))   # latches
            parts.append(tube([(-1.6, -d / 2, h * 0.75), (-1.4, -d / 2 - 0.9, h * 0.8), (0, -d / 2 - 1.1, h * 0.82),
                               (1.4, -d / 2 - 0.9, h * 0.8), (1.6, -d / 2, h * 0.75)], 0.28, lea))
            for o in parts:
                o.parent = e
            e.location = (0, 0, z)
            e.rotation_euler = (0, 0, math.radians(yaw))
            z += h

    PIECES = {
        "furn_hall_bench": hall_bench, "furn_hall_coatstand": hall_coatstand,
        "furn_hall_umbrellastand": hall_umbrellastand, "furn_hall_shoes": hall_shoes,
        "furn_kitchen_counter": kitchen_counter, "furn_kitchen_oven": kitchen_oven, "furn_kitchen_fridge": kitchen_fridge,
        "furn_kitchen_table": kitchen_table, "furn_kitchen_chair": kitchen_chair, "furn_kitchen_kettle": kitchen_kettle,
        "furn_dining_table": dining_table, "furn_dining_chair": dining_chair, "furn_dining_sideboard": dining_sideboard,
        "furn_dining_recordplayer": dining_recordplayer,
        "furn_kids_bed": kids_bed, "furn_kids_toybox": kids_toybox, "furn_kids_rockinghorse": kids_rockinghorse,
        "furn_kids_train": kids_train, "furn_kids_crane": kids_crane,
        "furn_bath_bathtub": bath_bathtub, "furn_bath_sink": bath_sink, "furn_bath_stool": bath_stool,
        "furn_bath_basket": bath_basket, "furn_bath_musicbox": bath_musicbox,
        "furn_study_desk": study_desk, "furn_study_chair": study_chair, "furn_study_globe": study_globe,
        "furn_study_cabinet": study_cabinet,
        "furn_attic_trunk": attic_trunk, "furn_attic_lamp": attic_lamp, "furn_attic_rockingchair": attic_rockingchair,
        "furn_hall_clock": hall_clock, "furn_hall_plant": hall_plant, "furn_kitchen_herbs": kitchen_herbs,
        "furn_dining_candelabra": dining_candelabra, "furn_kids_teddy": kids_teddy, "furn_kids_drum": kids_drum,
        "furn_bath_towelrail": bath_towelrail, "furn_bath_fern": bath_fern, "furn_study_lamp": study_lamp,
        "furn_attic_dressform": attic_dressform, "furn_attic_suitcases": attic_suitcases,
    }
    assert set(PIECES) == set(META), set(PIECES) ^ set(META)

    # -------------------------------------------------------------- render
    def mesh_points():
        dg = bpy.context.evaluated_depsgraph_get()
        pts = []
        for o in bpy.context.scene.objects:
            if o.type not in ("MESH", "CURVE") or o.hide_render:
                continue
            eo = o.evaluated_get(dg)
            me = eo.to_mesh()
            mw = eo.matrix_world
            step = max(1, len(me.vertices) // 1500)
            pts += [mw @ v.co for v in list(me.vertices)[::step]]
            eo.to_mesh_clear()
        return pts

    def lights(centre, radius):
        sc = bpy.context.scene
        for o in [o for o in sc.objects if o.type == "LIGHT"]:
            bpy.data.objects.remove(o)
        sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
        sc.view_settings.exposure = -0.55
        rigs = (("SUN", (-0.6, -1.0, 1.3), 2.4, (1.0, 0.95, 0.88), 12.0),       # warm key from front-left
                ("AREA", (1.4, -0.8, 0.9), 1.0, (0.92, 0.95, 1.0), 2.0),          # soft fill from the right
                ("AREA", (-1.3, -1.2, 0.2), 0.45, (1.0, 0.97, 0.92), 2.0),        # low front fill: lifts the shadows
                ("AREA", (0.3, 1.4, 1.2), 0.6, (1.0, 1.0, 1.0), 1.5))             # rim from behind
        for kind, d, e, col, size in rigs:
            L = bpy.data.lights.new(kind, kind)
            L.color = col
            o = link(bpy.data.objects.new(kind, L))
            dv = Vector(d).normalized()
            if kind == "SUN":
                L.energy, L.angle = e * 1.3, math.radians(size)
                o.location = centre + dv * radius * 3
            else:
                dist = radius * 3.0
                L.energy = 120 * e * (dist / 6.0) ** 2
                L.size = radius * size
                o.location = centre + dv * dist
            o.rotation_euler = (-dv).to_track_quat("-Z", "Y").to_euler()

    def frame_and_render(name):
        sc = bpy.context.scene
        cam = bpy.data.cameras.new("cam")
        cam.lens = 85
        co = link(bpy.data.objects.new("cam", cam))
        sc.camera = co
        bpy.context.view_layer.update()
        pts = mesh_points()
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        centre = (lo + hi) / 2
        radius = (hi - lo).length / 2
        view = Vector((0.75, -1.25, 0.72)).normalized()
        dist = radius / (18 / 85) * 1.1
        for _ in range(5):                                # fit the projected silhouette to 80% of the frame
            co.location = centre + view * dist
            co.rotation_euler = (-view).to_track_quat("-Z", "Y").to_euler()
            bpy.context.view_layer.update()
            ndc = [world_to_camera_view(sc, co, p) for p in pts]
            xs, ys = [v.x for v in ndc], [v.y for v in ndc]
            ext = max(max(xs) - min(xs), max(ys) - min(ys))
            cam.shift_x += ((max(xs) + min(xs)) / 2 - 0.5)
            cam.shift_y += ((max(ys) + min(ys)) / 2 - 0.5)
            dist *= ext / 0.8
        lights(centre, radius)
        sc.render.filepath = os.path.join(RAW, name + ".png")
        bpy.ops.render.render(write_still=True)
        return [round((hi[i] - lo[i]) * 5) for i in range(3)]

    only = ARGS[2].split(",") if len(ARGS) > 2 else None
    dims_path = os.path.join(RAW, "dims.json")
    dims = json.load(open(dims_path)) if os.path.exists(dims_path) else {}
    for name, fn in PIECES.items():
        if only and name not in only:
            continue
        H.reset()
        H.setup_render()
        fn()
        dims[name] = frame_and_render(name)
        print("RENDERED", name, dims[name])
        json.dump(dims, open(dims_path, "w"), indent=1)
    print("DONE")


# ================================================================== post step (plain Python + Pillow)
def post(out):
    from PIL import Image, ImageDraw, ImageFont
    raw = os.path.join(out, "raw")
    dims = json.load(open(os.path.join(raw, "dims.json")))
    bg = (236, 233, 227)
    try:
        font = ImageFont.truetype("arial.ttf", 22)
        big = ImageFont.truetype("arialbd.ttf", 34)
    except OSError:
        font = big = ImageFont.load_default()
    done = []
    for name in META:
        src = os.path.join(raw, name + ".png")
        if not os.path.exists(src):
            continue
        im = Image.open(src).convert("RGBA")
        flat = Image.new("RGBA", im.size, bg + (255,))
        flat.alpha_composite(im)
        flat.convert("RGB").save(os.path.join(out, name + ".png"))
        done.append(name)
    for room in ROOM_ORDER:
        names = [n for n in META if META[n][0] == room and n in done]
        names.sort(key=lambda n: META[n][3])
        cols, cell = 3, 420
        rows = (len(names) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, 60 + rows * (cell + 40)), (250, 248, 244))
        d = ImageDraw.Draw(sheet)
        d.text((16, 12), "%s  (furn_%s_*)" % (ROOM_TITLE[room], room), fill=(40, 30, 20), font=big)
        for i, n in enumerate(names):
            x, y = (i % cols) * cell, 60 + (i // cols) * (cell + 40)
            sheet.paste(Image.open(os.path.join(out, n + ".png")).resize((cell - 10, cell - 10), Image.LANCZOS),
                        (x + 5, y))
            w, dp, h = dims[n]
            label = "%s  %dx%dx%d cm%s" % (n.split("_", 2)[2], w, dp, h, "  (optional)" if META[n][3] else "")
            d.text((x + 10, y + cell - 4), label, fill=(150, 90, 20) if META[n][3] else (40, 30, 20), font=font)
        sheet.save(os.path.join(out, "sheet_%s.png" % room))
    lines = ["# Topple House furniture references", "",
             "One 1024x1024 render per piece (`furn_<room>_<item>.png`), plain light background, 3/4 front view.",
             "Made by `Topple/tools/room_refs_scene.py` (Blender 5.1), modelled at game scale (1 unit = 5 cm) to the",
             "solids in `Assets/Scripts/rooms/<room>.lua`. Size = bounding box of the reference model, width (x) x",
             "depth (y) x height, front facing the camera's left-front. Polycount = suggested triangles for the",
             "generated mesh (small 8k, medium 15k, large 20k). Contact sheets: `sheet_<room>.png`.", ""]
    for optional in (False, True):
        lines += ["## %s" % ("Optional extras (not in the contract; approve or drop)" if optional
                             else "Contract pieces (31)"), "",
                  "| Piece | Room | Size cm (w x d x h) | Polycount | Code-built would do? | What it shows |",
                  "|---|---|---|---|---|---|"]
        for n, (room, cls, code, opt, desc) in META.items():
            if opt != optional or n not in done:
                continue
            w, dp, h = dims[n]
            lines.append("| `%s` | %s | %d x %d x %d | %s | %s | %s |" % (n, ROOM_TITLE[room], w, dp, h,
                                                                            "{:,}".format(POLY[cls]), code, desc))
        lines.append("")
    lines += ["## Notes", "",
              "- Room palettes: hall honey oak + forest green + brass; kitchen sage-painted wood, cream enamel, butcher",
              "  block, copper; dining dark mahogany + burgundy velvet + brass; kids sky blue, red, yellow, green paint;",
              "  bath white porcelain, pale celadon, chrome, teak; study walnut, bottle-green and oxblood leather, brass;",
              "  attic dusty oak, faded canvas and silk, tarnished brass.",
              "- Sizes follow the room solids; a few pieces deliberately exceed them: the umbrella and cane stand above",
              "  the 60 cm stand, the bed's finials and the crane's jib/hook reach beyond their solids, the bath taps",
              "  rise above the 60 cm rim, and the hall bench's wool pad sits 2.5 cm above the solid's seat height.",
              "- `furn_hall_shoes` is one pair; the hall's shoe row (18 units long) would hold about three pairs.",
              "- `furn_dining_recordplayer` has no lid so it fits the 18 cm-tall solid; `furn_kids_train` is the",
              "  engine only (the track is code-built).", ""]
    open(os.path.join(out, "refs.md"), "w", newline="\n").write("\n".join(lines))
    print("posted", len(done), "pictures")


if __name__ == "__main__" and bpy is None:
    if len(sys.argv) > 2 and sys.argv[1] == "--post":
        post(sys.argv[2])
    else:
        print(__doc__)
