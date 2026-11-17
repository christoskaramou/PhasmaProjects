"""Loom game assets: one geometry source (loom_grid.py + scene.py) -> cooked meshes, textures, scene, Lua data.

    python tools/gen_assets.py                 Blender export (scene.py export) + cook + textures + scene + data
    python tools/gen_assets.py --no-blender    reuse the last export in .concepts/next/loom/work/export
    python tools/gen_assets.py --data-only     loom_data.lua + tests/variant_samples.lua only (no Blender, no cook)
    --only=a,b                                 cook only these pieces (names as in Assets/Objects)

Writes Assets/Objects/*.pemesh (PhasmaCook), Assets/Textures (weave pair, backdrop), Assets/Scenes/main.pescene
(camera, sun, one hidden template node T_<name> per piece), Assets/Scripts/loom_data.lua (the numbers in
loom_grid.py plus what was measured on the exported meshes: each cell variant's surface heights and what its
edges show) and tests/variant_samples.lua (Python's variant keys for random cloths, for the Lua mirror test).

Engine axes: Blender (x, y, z) -> engine (x, z, -y); the export already writes engine axes.
"""
import json
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import loom_grid as G  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
ASSETS = os.path.join(ROOT, "Assets")
OBJECTS = os.path.join(ASSETS, "Objects")
TEXOUT = os.path.join(ASSETS, "Textures")
SCENE = os.path.join(ASSETS, "Scenes", "main.pescene")
CONCEPT = os.path.normpath(os.path.join(ROOT, "..", ".concepts", "next", "loom"))
STAGE = os.path.join(CONCEPT, "work", "export")
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
HMAP = 13            # surface height samples per cell side (measured on the exported mesh)


def e(p):
    return (p[0], p[2], -p[1])


# ------------------------------------------------------------------ measuring the exported meshes
def read_obj(path):
    V, C = [], []
    F = []
    with open(path) as fi:
        for line in fi:
            if line.startswith("v "):
                a = [float(x) for x in line.split()[1:]]
                V.append(a[:3])
                C.append(a[3:6] if len(a) >= 6 else [1, 1, 1])
            elif line.startswith("f "):
                F.append([int(t.split("/")[0]) - 1 for t in line.split()[1:4]])
    return np.array(V), np.array(C), np.array(F, int)


def edge_classes(key):
    """What a variant shows at each side's midpoint: 'p' path, '~' water, '-' land. From the same skeletons that
    coloured and carved its mesh (scene.py cell_variant -> land()), so it is what the cooked cell draws."""
    kind, mask = key
    pw = pp = None
    if kind == "~":
        pw = G.water_skeleton(mask)
    elif kind == "p":
        pp = G.skeleton(mask, G.MEANDER_PATH)
    elif kind == "b":
        pw, pp = G.skeleton("ew", 0.0), G.skeleton("ns", 0.0)
    elif kind == "B":
        pw, pp = G.skeleton("ns", 0.0), G.skeleton("ew", 0.0)
    out = {}
    for side, (u, v) in {"n": (0, 0.5), "e": (0.5, 0), "s": (0, -0.5), "w": (-0.5, 0)}.items():
        cls = "-"
        if pw and G.band_dist(u, v, pw) < G.WATER_W:
            cls = "~"
        if pp and G.band_dist(u, v, pp) < G.PATH_W:
            cls = "p"
        out[side] = cls
    return out


def measure_cell(path, key):
    """Surface heights (m above Z0) on a HMAP x HMAP grid over the cell, each the highest vertex of the cloth top
    within its sample square (props rest on the ridges), read from the exported mesh, and its edge classes.
    Engine axes: u = x / CELL, v = -z / CELL. Fails loudly if a cell has no cloth top (the check that would have
    caught heights silently read as 0)."""
    V, C, F = read_obj(path)
    u = V[:, 0] / G.CELL
    v = -V[:, 2] / G.CELL
    h = V[:, 1]                     # cell-local: the node sits at Z0, so the mesh's height is above Z0 already
    top = (np.abs(u) <= 0.5 + 1e-6) & (np.abs(v) <= 0.5 + 1e-6) & (h > -0.0035)
    grid = []
    half = 0.5 / (HMAP - 1)
    for j in range(HMAP):
        row = []
        for i in range(HMAP):
            cu, cv = -0.5 + i / (HMAP - 1), -0.5 + j / (HMAP - 1)
            m = top & (np.abs(u - cu) <= half + 1e-6) & (np.abs(v - cv) <= half + 1e-6)
            if not m.any():
                raise SystemExit("no cloth top near (%.2f, %.2f) in %s" % (cu, cv, path))
            row.append(round(float(h[m].max()), 5))
        grid.append(row)
    edge = edge_classes(key)
    return grid, edge


def stage_info():
    with open(os.path.join(STAGE, "pieces.json")) as fi:
        return json.load(fi)


# ------------------------------------------------------------------ Lua data
def lua_value(v, ind=""):
    if isinstance(v, dict):
        items = []
        for k in sorted(v, key=str):
            key = k if isinstance(k, str) and k.isidentifier() else "[%s]" % lua_value(k)
            items.append("%s  %s = %s" % (ind, key, lua_value(v[k], ind + "  ")))
        return "{\n" + ",\n".join(items) + "\n" + ind + "}"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_value(x, ind) for x in v) + " }"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(round(v, 7))
    if isinstance(v, int):
        return str(v)
    return json.dumps(v)


def cam_engine():
    return e(G.CAM_POS), e(G.CAM_TARGET)


def write_data(measured):
    pos, tgt = cam_engine()
    data = {
        "CELL": G.CELL, "COLS": G.COLS, "Z0": G.Z0, "ENDS": G.ENDS, "PICKS": G.PICKS, "ROWS_FLAT": G.ROWS_FLAT,
        "ROWS_VIEW": G.ROWS_FLAT + 3, "BEAM_Y": G.BEAM_Y, "BEAM_AXIS": list(G.BEAM_AXIS), "ROLL_R": G.ROLL_R, "ROW_ARC": G.ROW_ARC,
        "REED_Y": G.REED_Y, "HALF_W": G.HALF_W, "HILL_H": G.HILL_H,
        "CAM": {"pos": list(pos), "target": list(tgt), "vfov": G.vfov_deg(), "aspect": G.ASPECT, "f_stop": G.F_STOP,
                "focus": G.focus_distance(), "sensor_h": G.SENSOR_H_MM},
        "SUN_DIR": [-0.76, 0.46, 0.48],
        "BALLS": [[w, x, y] for w, x, y in G.BOBBINS],
        "TRAV_SCALE": G.TRAV_SCALE, "HMAP": HMAP, "EMIS_SCALE": EMIS_SCALE,
        "BALL": {"r0": G.BALL_R0, "r1": G.BALL_R1, "cup_z": G.CUP_Z, "cup_r": G.CUP_R},
        "GROUND": {k: v[0] for k, v in measured.items()},
        "EDGE": {k: v[1] for k, v in measured.items()},
        # the two target frames as game states (rows newest first; the woven row's picks as (col, wool))
        "STATES": {
            "A": {"rows": G.MAP_A, "row": [[c, w] for c, w in G.ROW_A["cells"]], "fill": G.FILL_A, "trav": list(G.TRAVELLER),
                  "trav_uv": [0.0, 0.07 + 0.004 / G.CELL], "heading": -28.0, "shuttle_col": G.ROW_A["cells"][-1][0], "dir": G.ROW_A["dir"]},
            "B": {"rows": G.MAP_B, "row": [[c, w] for c, w in G.ROW_B["cells"]], "fill": G.FILL_B, "trav": list(G.TRAV_B),
                  "trav_uv": [0.0, 0.07 + 0.004 / G.CELL], "heading": -28.0, "shuttle_col": G.ROW_B["cells"][-1][0], "dir": G.ROW_B["dir"]},
        },
    }
    path = os.path.join(ASSETS, "Scripts", "loom_data.lua")
    with open(path, "w") as fo:
        fo.write("-- Generated by tools/gen_assets.py from tools/loom_grid.py and the exported meshes: do not edit.\n")
        fo.write("-- Blender axes (x across the cloth, y toward the reed, z up) except CAM (engine axes, y up).\n")
        fo.write("-- GROUND[name][j][i]: cloth height above Z0 (m) at u = -0.5 + (i-1)/(HMAP-1), v = -0.5 + (j-1)/(HMAP-1),\n")
        fo.write("--   measured on the cooked mesh. EDGE[name].n/e/s/w: what the drawn cell shows at that side's midpoint.\n")
        fo.write("return " + lua_value(data) + "\n")
    print("data ->", path)


def write_variant_samples():
    """Random cloths and Python's variant key of every cell (tests/rules_test.lua compares the Lua mirror)."""
    rnd = random.Random(5)
    kinds = ".hhww~~ppffrHbB"
    out = []
    for t in range(60):
        rows = ["".join(rnd.choice(kinds) for _ in range(G.COLS)) for _ in range(6)]
        if t % 3 == 0:      # blobs and bands, not only noise
            rows = ["".join(rnd.choice("hhh..") if c < 4 else rnd.choice("~p.") for c in range(G.COLS)) for _ in range(6)]
        keys = []
        for r in range(len(rows)):
            for c in range(G.COLS):
                keys.append((c, r, G.key_name(G.variant_key(rows, c, r))))
        out.append((rows, keys))
    path = os.path.join(ROOT, "tests", "variant_samples.lua")
    with open(path, "w") as fo:
        fo.write("-- Generated by tools/gen_assets.py: tools/loom_grid.variant_key on random cloths (rows[1] = row 0, the newest).\n")
        fo.write("return {\n")
        for rows, keys in out:
            fo.write("  { rows = { %s },\n    keys = { %s } },\n" % (", ".join('"%s"' % r for r in rows),
                                                                  ", ".join('{ %d, %d, "%s" }' % k for k in keys)))
        fo.write("}\n")
    # the target frames' cells as the Blender scene places them (scene.py place_cloth): the view test compares
    path2 = os.path.join(ROOT, "tests", "target_keys.lua")
    with open(path2, "w") as fo:
        fo.write("-- Generated by tools/gen_assets.py: the cooked piece every cell of the target frames shows (scene.py place_cloth).\n")
        fo.write("return {\n")
        for st, rows in (("A", G.MAP_A), ("B", G.MAP_B)):
            names = []
            for r in range(len(rows)):
                for c in range(G.COLS):
                    n = G.key_name(G.variant_key(rows, c, r, len(rows) - r))
                    if G.row_pose(r)[0] == "rolled":
                        n += "_r"
                    names.append('"%s"' % n)
            fo.write("  %s = { %s },\n" % (st, ", ".join(names)))
        fo.write("}\n")
    print("samples ->", path, path2)


# ------------------------------------------------------------------ scene
def look_matrix(pos, target, up=(0, 1, 0)):
    pos, target = np.array(pos, float), np.array(target, float)
    z = -(target - pos) / np.linalg.norm(target - pos)
    x = np.cross(up, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return [*x, 0.0, *y, 0.0, *z, 0.0, *pos, 1.0]


def write_scene(names):
    hidden = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, -1000.0, 0, 1.0]
    sc = {"sources": [], "meshes": [], "nodes": []}
    pos, tgt = cam_engine()
    fovx = math.radians(G.hfov_deg())
    cam = {"projection": "perspective", "fovx": fovx, "near_plane": 0.01, "far_plane": 100.0, "speed": 0.5, "euler": [0.0, 3.14159, 0.0]}
    sc["nodes"].append({"name": "Camera_0", "parent": -1, "local_matrix": look_matrix(pos, tgt), "component_flags": 8, "camera": cam})
    sun = np.array(e((-0.76, 0.46, 0.48)))
    sun = sun / np.linalg.norm(sun) * 10
    sc["nodes"].append({"name": "Sun", "parent": -1, "local_matrix": look_matrix(tuple(sun), (0, 0, 0)), "component_flags": 2,
                        "light": {"type": "directional", "color": [1.0, 0.8, 0.6, 3.0]}})
    for name in names:
        sc["sources"].append({"path": f"../Objects/{name}.pemesh"})
        sc["meshes"].append({"source": len(sc["sources"]) - 1, "source_mesh": 0})
        sc["nodes"].append({"name": "T_" + name, "parent": -1, "local_matrix": hidden, "component_flags": 0,
                            "mesh_refs": [len(sc["meshes"]) - 1]})
    sc["lights"] = []
    sc["cameras"] = [{"name": "Camera_0", "position": list(pos), "euler": [0.0, 3.14159, 0.0], "fovx": fovx,
                      "projection": "perspective", "near_plane": 0.01, "far_plane": 100.0, "speed": 0.5, "node_index": 0}]
    sc["active_camera"] = 0
    sc["scene_scripts"] = {"on_play": ["Assets/Scripts/loom.lua"]}
    os.makedirs(os.path.dirname(SCENE), exist_ok=True)
    with open(SCENE, "w") as fo:
        json.dump(sc, fo, indent=1)
    print("scene ->", SCENE, len(names), "templates")


# ------------------------------------------------------------------ the backdrop picture, ready for the engine's tone curve
# The engine draws the backdrop as emission and then tone-maps the whole frame with ACESFitted (TonemapPS.hlsl:20,
# Tonemap.hlsl:67); the bake (Blender ACES view) is already display-ready. So the texture holds the inverse of
# ACESFitted applied to the bake, divided by EMIS_SCALE (the material's emissive factor puts it back): drawn
# emissive x EMIS_SCALE -> ACESFitted -> sRGB gives the bake's pixel again.
EMIS_SCALE = 4.0
ACES_IN = np.array([[0.59719, 0.07600, 0.02840], [0.35458, 0.90834, 0.13383], [0.04823, 0.01566, 0.83777]])
ACES_OUT = np.array([[1.60475, -0.10208, -0.00327], [-0.53108, 1.10813, -0.07276], [-0.07367, -0.00605, 1.07602]])


def aces_fitted(x):
    c = x @ ACES_IN
    a = c * (c + 0.0245786) - 0.000090537
    b = c * (0.983729 * c + 0.4329510) + 0.238081
    return np.clip((a / b) @ ACES_OUT, 0, 1)


def inv_aces_fitted(y):
    w = np.clip(y @ np.linalg.inv(ACES_OUT), 0, 1.0)
    A, B, C = 0.983729 * w - 1, 0.4329510 * w - 0.0245786, 0.238081 * w + 0.000090537
    v = (-B - np.sqrt(np.maximum(B * B - 4 * A * C, 0))) / (2 * A)
    return np.maximum(v @ np.linalg.inv(ACES_IN), 0)


def s2l(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def l2s(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def write_backdrop():
    from PIL import Image
    a = np.asarray(Image.open(os.path.join(CONCEPT, "backdrop.png")).convert("RGB"), float) / 255
    sh = a.shape
    x = inv_aces_fitted(np.minimum(s2l(a).reshape(-1, 3), 0.97)).reshape(sh) / EMIS_SCALE
    rng = np.random.default_rng(1)
    out = np.clip(l2s(x) * 255 + rng.uniform(-0.5, 0.5, sh), 0, 255).round().astype(np.uint8)
    Image.fromarray(out).save(os.path.join(TEXOUT, "backdrop.png"))
    print("backdrop -> Textures/backdrop.png (inverse ACESFitted / %.1f)" % EMIS_SCALE)


# ------------------------------------------------------------------ the wool balls' shadow cards
# The balls are live (they shrink) and the table under them is the baked picture, which takes no engine shadow. Each
# ball gets a soft black ellipse card on the table, sized and placed from the sun (loom_world.lua ball shadows).
def write_shadow_card():
    from PIL import Image, ImageFilter
    n = 256
    yy, xx = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    r = np.sqrt(xx ** 2 + yy ** 2)
    a = np.clip((0.78 - r) / 0.22, 0, 1) ** 1.3
    im = np.zeros((n, n, 4), np.uint8)
    im[..., 3] = (a * 255).round().astype(np.uint8)
    Image.fromarray(im, "RGBA").filter(ImageFilter.GaussianBlur(4)).save(os.path.join(TEXOUT, "ball_shadow.png"))
    path = os.path.join(STAGE, "shadow_card.obj")
    with open(path, "w") as fo:          # unit square on the table (Blender xy, z = 0) in engine axes, up normal
        fo.write("o mesh\n")
        for x, y in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
            fo.write("v %.4f %.4f %.4f\n" % e((x, y, 0.0)))
        for t in ((0, 0), (1, 0), (1, 1), (0, 1)):
            fo.write("vt %d %d\n" % t)
        fo.write("vn 0 1 0\n")
        fo.write("f 1/1/1 2/2/1 3/3/1\nf 1/1/1 3/3/1 4/4/1\n")


# ------------------------------------------------------------------ cook
def find_cook():
    eng = os.path.normpath(os.path.join(ROOT, "..", "..", "PhasmaEngine"))
    for b in ("build-ninja-physics", "build-ninja"):
        p = os.path.join(eng, b, "Release", "PhasmaCook.exe")
        if os.path.exists(p):
            return p
    raise SystemExit("PhasmaCook.exe not found")


# Engine grade of the cooked vertex colours (round 3, measured live against target.png): Cycles' sheen and sky bounce
# pale the wool; the engine's raster light does not, so its cloth came out more saturated (meadow 109,144,65 against
# the bake's 135,151,102). Colours are pulled toward their luminance by ENGINE_SAT (in linear) before cooking, as
# Topple pulled its paints toward grey for the same reason. Geometry, UVs and normals are untouched.
ENGINE_SAT = 0.68


def engine_grade(src, dst):
    def s2l(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    def l2s(c):
        c = min(max(c, 0.0), 1.0)
        return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    with open(src) as fi, open(dst, "w") as fo:
        for line in fi:
            if line.startswith("v "):
                p = line.split()
                if len(p) >= 7:
                    r, g, b = (s2l(float(x)) for x in p[4:7])
                    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    r, g, b = (lum + (x - lum) * ENGINE_SAT for x in (r, g, b))
                    line = "v %s %s %s %.4f %.4f %.4f\n" % (p[1], p[2], p[3], l2s(r), l2s(g), l2s(b))
            fo.write(line)


def cook(names):
    cook_exe = find_cook()
    os.makedirs(OBJECTS, exist_ok=True)
    only = [a[7:].split(",") for a in sys.argv if a.startswith("--only=")]
    todo = [n for n in names if not only or n in only[0]]
    with tempfile.TemporaryDirectory(prefix="loom-cook-") as tmp:
        lines = []
        for n in todo:
            dst = os.path.join(tmp, n + ".obj")
            engine_grade(os.path.join(STAGE, n + ".obj"), dst)
            lines.append(dst + "\t" + os.path.join(OBJECTS, n + ".pemesh") + "\n")
        manifest = os.path.join(tmp, "batch.txt")
        with open(manifest, "w", encoding="utf-8") as fo:
            fo.writelines(lines)
        res = subprocess.run([cook_exe, "--batch", manifest], cwd=os.path.dirname(cook_exe), capture_output=True, text=True)
    if res.returncode != 0 or f"{len(lines)} ok" not in (res.stdout + res.stderr):
        print((res.stdout + res.stderr)[-3000:])
        raise SystemExit("PhasmaCook failed")
    print("cooked", len(lines), "meshes")


def main():
    if "--data-only" in sys.argv:
        measured = {}
        if os.path.exists(os.path.join(STAGE, "pieces.json")):
            for key in G.all_keys():
                n = G.key_name(key)
                measured[n] = measure_cell(os.path.join(STAGE, n + ".obj"), key)
        write_data(measured)
        write_variant_samples()
        if "--backdrop" in sys.argv:
            write_backdrop()
        return
    if "--no-blender" not in sys.argv:
        os.makedirs(STAGE, exist_ok=True)
        log = os.path.join(STAGE, "..", "export.log")
        with open(log, "w") as lf:
            r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "scene.py"), "--", "export", STAGE],
                               stdout=lf, stderr=subprocess.STDOUT)
        if r.returncode != 0:
            raise SystemExit("Blender export failed: see " + log)
    info = stage_info()
    names = info["cells"] + info["rolled"] + info["props"] + ["backdrop", "shadow_card"]
    measured = {G.key_name(k): measure_cell(os.path.join(STAGE, G.key_name(k) + ".obj"), k) for k in G.all_keys()}
    write_data(measured)
    write_variant_samples()
    os.makedirs(TEXOUT, exist_ok=True)
    for t in ("weave_albedo.png", "weave_normal.png"):
        shutil.copyfile(os.path.join(STAGE, t), os.path.join(TEXOUT, t))
    write_backdrop()
    write_shadow_card()
    cook(names)
    stats = {k: v for k, v in info["stats"].items()}
    with open(os.path.join(OBJECTS, "mesh_stats.json"), "w") as fo:
        json.dump(stats, fo, indent=1)
    write_scene(names)


if __name__ == "__main__":
    main()
