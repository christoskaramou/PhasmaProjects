"""Shadow Puppeteer meshes, scene and game data, all from tools/sp_common.py.

    python tools/gen_meshes.py [path/to/PhasmaCook.exe]     (--scene-only: rewrite scene + sp_data.lua, no export/cook)

1. Blender (tools/scene.py export) writes every live mesh as an OBJ in engine axes and bakes the comb's and ladder's
   albedo into Assets/Textures.
2. Here: the shadow cards (one quad per prop over its silhouette's bounding box) and their silhouette textures,
   rasterised from sp_common.silhouette (the same polygons the rules use); the far backdrop quad.
3. PhasmaCook --batch cooks them into Assets/Objects/*.pemesh.
4. Assets/Scenes/main.pescene: camera, the lantern's and candle's point lights, one node per mesh (the game moves them).
5. Assets/Scripts/sp_data.lua: sp_common exported for the game (no number is typed twice).
Engine axes: X right, Y up, Z toward the camera: engine (x, y, z) = Blender (x, z, -y).
"""
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import sp_common as G  # noqa: E402

OBJECTS = os.path.join(ROOT, "Assets", "Objects")
TEXTURES = os.path.join(ROOT, "Assets", "Textures")
SCENE = os.path.join(ROOT, "Assets", "Scenes", "main.pescene")
DATA = os.path.join(ROOT, "Assets", "Scripts", "sp_data.lua")
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
BACK_D = 60.0
CARD_MARGIN = 0.02            # stage units round each silhouette (keeps the alpha edge inside the quad)
SIL_PPU = 1200                # silhouette texture pixels per stage unit (prop-local)
LSPRITE_E = 4.0               # emissive factor of the lantern sprites (the texture holds inverse-ACES / E: hot core > 1)
LSPRITE_RAW = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".concepts", "next",
                                            "puppet", "lsprite_raw"))

# Meshes Blender exports (tools/scene.py export_all) and how the game uses them.
TRACKED = ["cup", "comb", "ladder", "mouse"]          # props on a floor track (scene.TRACKED)
LEVEL_TAGS = [lv["id"].replace("-", "_") for lv in G.LEVELS]
BLENDER_MESHES = (["cup", "cup_rim", "comb", "ladder", "mouse", "balloon", "lantern_brass", "lantern_glass", "lantern_flame",
                   "candle_holder", "candle_wax_100", "candle_wax_055", "candle_wax_030", "candle_flame_100",
                   "candle_flame_055", "candle_flame_030", "puppet_a", "puppet_a_pins", "puppet_b", "puppet_b_pins", "pp_body",
                   "pp_pins", "pp_leg_l", "pp_leg_r", "pp_arm_l", "pp_arm_r", "paper", "floor"]
                  + ["%s_%s" % (k, t) for t in LEVEL_TAGS for k in ("paper_black", "paper_red", "paper_gold")]
                  + ["%s_%s" % (k, n) for n in TRACKED for k in ("track_slot", "track_brass")])
# shadow cards: one per prop, plus the mouse's mirrored card (it runs back to the left)
CARDS = list(G.PROPS) + ["mouse_l"]


def base_of(name):
    return name[:-2] if name.endswith("_l") else name


def map_tex(mapid):
    """A stage set's bake folder (the first set keeps the root Textures folder)."""
    return TEXTURES if mapid == "stage" else os.path.join(TEXTURES, mapid)


def card_rect(name):
    """The silhouette's bounding box plus a margin, widened so the texture is a multiple of 64 texels each way: odd
    mip sizes (378 -> 189 -> 94) shift each mip by half a texel, which moved the drawn ladder shadow ~1 px."""
    x0, z0, x1, z1 = G.bbox(name)
    x0, z0, x1, z1 = x0 - CARD_MARGIN, z0 - CARD_MARGIN, x1 + CARD_MARGIN, z1 + CARD_MARGIN
    w = math.ceil((x1 - x0) * SIL_PPU / 64) * 64 / SIL_PPU
    h = math.ceil((z1 - z0) * SIL_PPU / 64) * 64 / SIL_PPU
    cx = (x0 + x1) / 2
    return cx - w / 2, z0, cx + w / 2, z0 + h


def silhouette_texture(name, path, ss=4):
    """White RGB, alpha = coverage of the shared silhouette polygons (4x supersampled)."""
    x0, z0, x1, z1 = card_rect(name)
    w, h = int(round((x1 - x0) * SIL_PPU)), int(round((z1 - z0) * SIL_PPU))
    big = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(big)
    for poly in G.silhouette(name):
        d.polygon([((px - x0) / (x1 - x0) * w * ss, (z1 - pz) / (z1 - z0) * h * ss) for px, pz in poly], fill=255)
    # the penumbra: a linear ramp (box blur) as wide as the flame's soft edge, in card-local units (the card is
    # scaled by k, so a width of penumbra / k at the middle lantern depth lands on the paper at that width)
    from PIL import ImageFilter
    ly = (G.LANTERN_Y[0] + G.LANTERN_Y[1]) / 2
    wloc = G.penumbra(base_of(name)) / G.k_of(ly, G.PROPS[base_of(name)]["y"])
    r = wloc * SIL_PPU * ss / 2
    if r >= 0.5:
        big = big.filter(ImageFilter.BoxBlur(r))
    a = big.resize((w, h), Image.LANCZOS)
    im = Image.merge("RGBA", (Image.new("L", (w, h), 255),) * 3 + (a,))
    im.save(path)
    return w, h


def quad_obj(path, corners, uvs, normal):
    with open(path, "w") as f:
        f.write("o quad\n")
        for v in corners:
            f.write("v %.6f %.6f %.6f\n" % tuple(v))
        for t in uvs:
            f.write("vt %.6f %.6f\n" % tuple(t))
        f.write("vn %.6f %.6f %.6f\n" % tuple(normal))
        f.write("f 1/1/1 2/2/1 3/3/1\nf 1/1/1 3/3/1 4/4/1\n")


def card_obj(name, path):
    """Quad in the plane z = 0 (engine), x right / y up, prop-local units; UV 0..1 over the silhouette texture."""
    x0, z0, x1, z1 = card_rect(name)
    quad_obj(path, [(x0, z0, 0), (x1, z0, 0), (x1, z1, 0), (x0, z1, 0)], [(0, 0), (1, 0), (1, 1), (0, 1)], (0, 0, 1))


def camera_basis():
    p = np.array((G.CAM_POS[0], G.CAM_POS[2], -G.CAM_POS[1]))
    t = np.array((G.CAM_LOOK[0], G.CAM_LOOK[2], -G.CAM_LOOK[1]))
    f = t - p
    f /= np.linalg.norm(f)
    right = np.cross(f, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, f)
    return p, f, right, up


def backdrop_obj(path):
    """A quad perpendicular to the view axis at BACK_D that the camera sees edge to edge at the WIDE aspect."""
    p, f, right, up = camera_basis()
    hh = BACK_D * math.tan(math.radians(G.VFOV / 2))
    hw = hh * G.WIDE[0] / G.WIDE[1]
    c = p + f * BACK_D
    quad_obj(path, [c - right * hw - up * hh, c + right * hw - up * hh, c + right * hw + up * hh, c - right * hw + up * hh],
             [(0, 0), (1, 0), (1, 1), (0, 1)], -f)


def look_matrix(pos, target, up=(0, 1, 0)):
    pos, target = np.array(pos, float), np.array(target, float)
    z = -(target - pos) / np.linalg.norm(target - pos)
    x = np.cross(up, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return [*x, 0.0, *y, 0.0, *z, 0.0, *pos, 1.0]


def lsprite_names():
    return ["lsprite_%d_%d" % (i, j) for i in range(len(G.FRONT_X)) for j in range(len(G.FRONT_Y))]


def lsprite_obj(i, j, path):
    """The sprite's card: engine axes, relative to the lantern's base point (where the game places the lantern)."""
    _, cs = G.lantern_sprite(i, j)
    quad_obj(path, [(x, z, -y) for x, y, z in cs], [(0, 0), (1, 0), (1, 1), (0, 1)], (0, 0, 1))


def lsprite_textures():
    """Crop each 2x render to its rectangle: lsprite_I_J.png (alpha; colour unused) and lsprite_I_J_em.png (inverse ACES
    of the AgX display colour / LSPRITE_E, so after the engine's tone map the card shows the bake). Colour bleeds into
    transparent texels so filtering never pulls a dark fringe in."""
    import engine_tone as T
    from scipy import ndimage
    done = 0
    for i in range(len(G.FRONT_X)):
        for j in range(len(G.FRONT_Y)):
            src = os.path.join(LSPRITE_RAW, "lsprite_%d_%d.png" % (i, j))
            if not os.path.exists(src):
                continue
            rect, _ = G.lantern_sprite(i, j)
            im = np.asarray(Image.open(src).convert("RGBA").crop(rect), float) / 255
            rgb, a = im[:, :, :3], im[:, :, 3]
            solid = a > 0.5
            if solid.any():
                _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
                rgb = np.where((a < 0.02)[:, :, None], rgb[iy, ix], rgb)
            x = T.inv_aces(T.srgb_to_lin(rgb.reshape(-1, 3))).reshape(rgb.shape) / LSPRITE_E
            em = (np.clip(T.lin_to_srgb(np.clip(x, 0, 1)), 0, 1) * 255 + 0.5).astype(np.uint8)
            Image.fromarray(em).save(os.path.join(TEXTURES, "lsprite_%d_%d_em.png" % (i, j)))
            al = (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
            Image.merge("RGBA", (Image.new("L", al.shape[::-1], 255),) * 3 + (Image.fromarray(al),)).save(
                os.path.join(TEXTURES, "lsprite_%d_%d.png" % (i, j)))
            done += 1
    print("lantern sprites:", done)
    return done


# The comb's teeth in the target are lit cream (clearcoat reflecting the bright paper; the engine has no IBL): the game
# adds that reflection as emissive on the teeth only (comb_teeth_mask.png, baked in the comb's UVs). Linear values,
# fitted 2026-11-13 from the teeth's p80 (game 164/113/32 after the comb factor vs target 179/122/71).
COMB_TEETH_EM = (0.10, 0.05, 0.08)
# 2026-11-13: one flat value averaged the target's orange (left) and cream (right) teeth into mauve. Per-column fit
# instead (state A, teeth p85, inverse ACES of target minus game): (fraction across the teeth, left to right on
# screen; linear emissive). The comb's UVs are a packed atlas: the mask's G channel holds each texel's x (scene.py).
COMB_TEETH_RAMP = [(0.0, (0, 0, 0)), (0.12, (0, 0, 0)), (0.24, (0.06, 0.01, 0)), (0.36, (0.06, 0.02, 0)),
                   (0.48, (0.13, 0.07, 0.04)), (0.60, (0.22, 0.13, 0.08)), (0.72, (0.36, 0.20, 0.135)),
                   (0.84, (0.47, 0.31, 0.23)), (1.0, (0.43, 0.30, 0.21))]


def comb_emissive(em=None, out="comb_teeth_em.png"):
    import engine_tone as T
    msk = os.path.join(TEXTURES, "comb_teeth_mask.png")
    if not os.path.exists(msk):
        return False
    rgb = np.asarray(Image.open(msk).convert("RGB"), float) / 255
    m = rgb[:, :, :1]
    if em is None:
        xs = rgb[:, :, 1][m[:, :, 0] > 0.5]                  # comb x of the teeth texels -> 0..1 across the teeth
        f = np.clip((rgb[:, :, 1] - xs.min()) / max(1e-6, xs.max() - xs.min()), 0, 1)
        ramp = np.stack([np.interp(f, [r[0] for r in COMB_TEETH_RAMP], [r[1][c] for r in COMB_TEETH_RAMP]) for c in range(3)], -1)
        lin = m * ramp
    else:
        lin = m * np.array(em)[None, None, :]
    Image.fromarray((np.clip(T.lin_to_srgb(lin.reshape(-1, 3)).reshape(lin.shape), 0, 1) * 255 + 0.5).astype(np.uint8)).save(
        os.path.join(TEXTURES, out))
    return True


def mesh_names():
    return BLENDER_MESHES + ["shadow_" + n for n in CARDS] + ["shadowpen_" + n for n in CARDS] + ["backdrop"] + lsprite_names()


def write_scene():
    I = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]
    cam_e = (G.CAM_POS[0], G.CAM_POS[2], -G.CAM_POS[1])
    look_e = (G.CAM_LOOK[0], G.CAM_LOOK[2], -G.CAM_LOOK[1])
    sc = {"sources": [], "meshes": [], "nodes": []}
    sc["nodes"].append({"name": "Camera_0", "parent": -1, "local_matrix": look_matrix(cam_e, look_e), "component_flags": 8,
                        "camera": {"projection": "perspective", "fovx": 1.2, "near_plane": 0.05, "far_plane": 200.0,
                                   "speed": 3.5, "euler": [0.0, 3.14159, 0.0]}})
    lx, ly = G.STATE_A["lantern"]
    for name, pos, col in (("LanternLight", (lx, G.LZ, -ly), [1.0, 0.62, 0.3, 4.0]),
                           ("CandleLight", (0.0, 0.2, 0.0), [1.0, 0.6, 0.3, 0.05]),
                           ("BounceLight", (0.0, 0.9, -G.SY - 0.6), [1.0, 0.6, 0.3, 0.0])):
        m = I[:12] + [pos[0], pos[1], pos[2], 1.0]
        sc["nodes"].append({"name": name, "parent": -1, "local_matrix": m, "component_flags": 2,
                            "light": {"type": "point", "color": col, "radius": 40.0}})
    for n in mesh_names():
        sc["sources"].append({"path": f"../Objects/{n}.pemesh"})
        sc["meshes"].append({"source": len(sc["sources"]) - 1, "source_mesh": 0})
        sc["nodes"].append({"name": "N_" + n, "parent": -1, "local_matrix": I, "component_flags": 0,
                            "mesh_refs": [len(sc["meshes"]) - 1]})
    sc["lights"] = []
    sc["cameras"] = [{"name": "Camera_0", "position": list(cam_e), "euler": [0.0, 3.14159, 0.0], "fovx": 1.2,
                      "projection": "perspective", "near_plane": 0.05, "far_plane": 200.0, "speed": 3.5, "node_index": 0}]
    sc["active_camera"] = 0
    sc["scene_scripts"] = {"on_play": ["Assets/Scripts/puppet.lua"]}
    os.makedirs(os.path.dirname(SCENE), exist_ok=True)
    with open(SCENE, "w") as f:
        json.dump(sc, f, indent=1)


def paper_rect_wide():
    """Pixel rectangle (x0, y0, x1, y1) of the paper in the WIDE bakes."""
    W, H = G.WIDE
    a = G.to_pixel((G.SCREEN_U[0], G.SY, G.SCREEN_V[1]), W, H)
    b = G.to_pixel((G.SCREEN_U[1], G.SY, G.SCREEN_V[0]), W, H)
    return int(a[0]) + 1, int(a[1]) + 1, int(b[0]) - 1, int(b[1]) - 1


def shadow_colour(mapid="stage"):
    """The paper without the lantern (fill only): mean of the baked backdrop over the paper, display sRGB 0..1."""
    path = os.path.join(map_tex(mapid), "backdrop.png")
    if not os.path.exists(path):
        return [0.2, 0.15, 0.1]
    im = np.asarray(Image.open(path).convert("RGB"), float) / 255
    x0, y0, x1, y1 = paper_rect_wide()
    return [round(float(c), 4) for c in im[y0:y1, x0:x1].reshape(-1, 3).mean(0)]


def front_covers(mapid="stage"):
    """Front-card bakes whose alpha is 1 everywhere a paper-plane layer could show outside the paper: outside the
    paper rectangle and above its bottom edge (below it the live floor hides the paper plane by depth)."""
    W, H = G.WIDE
    x0, y0, x1, y1 = paper_rect_wide()
    ok = []
    for i in range(len(G.FRONT_X)):
        for j in range(len(G.FRONT_Y)):
            path = os.path.join(map_tex(mapid), "front_%d_%d.png" % (i, j))
            if not os.path.exists(path):
                continue
            a = np.asarray(Image.open(path).convert("RGBA"))[:, :, 3]
            yy, xx = np.mgrid[0:H, 0:W]
            near_paper = (xx >= x0 - 3) & (xx <= x1 + 3) & (yy >= y0 - 3)
            m = (yy < y1) & ~near_paper                  # outside the paper, above its bottom edge
            lo = int(a[m].min()) if m.any() else 255
            if lo >= 250:
                ok.append("front_%d_%d" % (i, j))
            else:
                print("%s front card %d_%d leaves alpha %d outside the paper" % (mapid, i, j, lo))
    return ok


def emissive_bake(mapid="stage"):
    """backdrop.png is display-referred (AgX). The engine tone-maps (ACESFitted) everything 3D, so the live paper and
    floor get backdrop_em.png = inverse ACES of it: after the tone map they show the bake unchanged. Every stage set
    gets the floor fix measured on the first (the missing bounce of the lantern off paper and boards), tinted by its
    paper's colour relative to the first set's."""
    import engine_tone as T
    src = os.path.join(map_tex(mapid), "backdrop.png")
    if not os.path.exists(src):
        return 0.0
    d = np.asarray(Image.open(src).convert("RGB"), float) / 255
    # the bake has nothing under the 5 mm board gaps, so each seam is a black line in the floor's ambient; the live
    # floor's own bevels and underlay draw the seam under the lantern (target: a lit bevel line), so fill them here
    # (grey closing, floor rows inside the paper's width only: curtains and the candle holder stay untouched)
    from scipy import ndimage
    x0, _, x1, y1 = paper_rect_wide()
    fl = d[y1 + 3:, x0:x1]
    d[y1 + 3:, x0:x1] = np.stack([ndimage.grey_closing(fl[:, :, c], size=(5, 5)) for c in range(3)], -1)
    x = T.inv_aces(T.srgb_to_lin(d.reshape(-1, 3))).reshape(d.shape)
    # the floor's missing light, measured in the Player against the targets (tools/floor_calib.py; no GI in the engine)
    fix = os.path.join(HERE, "floor_fix.png")
    if os.path.exists(fix):
        f = np.asarray(Image.open(fix).convert("RGB"), float) / 255 * 0.4 - 0.1
        if mapid != "stage":
            tint = np.array(G.MAP_BY_ID[mapid]["paper"]) / np.array(G.MAP_BY_ID["stage"]["paper"])
            f = np.where(f > 0, f * tint, f)
        y0 = x.shape[0] - f.shape[0]
        x[y0:] = np.maximum(0.0, x[y0:] + f)
    clipped = float((x > 1).any(axis=2).mean())
    Image.fromarray((np.clip(T.lin_to_srgb(np.minimum(x, 1)), 0, 1) * 255 + 0.5).astype(np.uint8)).save(
        os.path.join(map_tex(mapid), "backdrop_em.png"))
    return clipped


def write_data(sil_sizes):
    import engine_tone as T
    looks = {}
    s0 = shadow_colour("stage")
    for m in G.MAPS:
        mid = m["id"]
        clipped = emissive_bake(mid)
        print(mid, "backdrop_em.png written (%.4f %% of pixels above the invertible range)" % (100 * clipped))
        # the shadow on each set's paper: the reference shadow grey scaled by that set's unlit paper over the first's
        sc = shadow_colour(mid)
        disp = [G.LOOK_DISPLAY["shadow"][c] * sc[c] / max(1e-4, s0[c]) for c in range(3)]
        looks[mid] = {"shadow": T.emissive_factor(disp), "covers": front_covers(mid),
                      "tex": "Textures/" if mid == "stage" else "Textures/%s/" % mid, "paper": list(m["paper"])}
    extra = {"EMISSIVE": {k: T.emissive_factor(v) for k, v in G.LOOK_DISPLAY.items()}, "FRONT_COVERS": looks["stage"]["covers"],
             "MAPLOOK": looks, "SHADOW_RGB": shadow_colour(), "CARD": {n: list(card_rect(n)) for n in CARDS},
             "MESHES": mesh_names(), "BACK_D": BACK_D, "LSPRITE_E": LSPRITE_E, "PAPER_PX_WIDE": list(paper_rect_wide())}
    G.write_lua(DATA, extra)


def find_cook():
    for a in sys.argv[1:]:
        if not a.startswith("--"):
            return a
    eng = os.path.normpath(os.path.join(ROOT, "..", "..", "PhasmaEngine"))
    for b in ("build-ninja-physics", "build-ninja"):
        p = os.path.join(eng, b, "Release", "PhasmaCook.exe")
        if os.path.exists(p):
            return p
    raise SystemExit("PhasmaCook.exe not found; pass its path")


def main():
    os.makedirs(TEXTURES, exist_ok=True)
    sizes = {}
    for n in CARDS:
        sizes[n] = silhouette_texture(n, os.path.join(TEXTURES, "silhouette_%s.png" % n))
    if "--scene-only" not in sys.argv:
        cook = find_cook()
        os.makedirs(OBJECTS, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="puppet-meshes-") as tmp:
            r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "scene.py"), "--",
                                "export", tmp, TEXTURES], capture_output=True, text=True)
            if r.returncode != 0 or not os.path.exists(os.path.join(tmp, "faces.txt")):
                print((r.stdout + r.stderr)[-3000:])
                raise SystemExit("Blender export failed")
            print(open(os.path.join(tmp, "faces.txt")).read())
            for n in CARDS:
                card_obj(n, os.path.join(tmp, "shadow_%s.obj" % n))
                card_obj(n, os.path.join(tmp, "shadowpen_%s.obj" % n))     # same card, own material (penumbra)
            backdrop_obj(os.path.join(tmp, "backdrop.obj"))
            for i in range(len(G.FRONT_X)):
                for j in range(len(G.FRONT_Y)):
                    lsprite_obj(i, j, os.path.join(tmp, "lsprite_%d_%d.obj" % (i, j)))
            lines = [f"{os.path.join(tmp, n + '.obj')}\t{os.path.join(OBJECTS, n + '.pemesh')}\n" for n in mesh_names()]
            manifest = os.path.join(tmp, "batch.txt")
            with open(manifest, "w", encoding="utf-8") as f:
                f.writelines(lines)
            r = subprocess.run([cook, "--batch", manifest], cwd=os.path.dirname(cook), capture_output=True, text=True)
            if r.returncode != 0 or f"{len(lines)} ok" not in (r.stdout + r.stderr):
                print((r.stdout + r.stderr)[-3000:])
                raise SystemExit("PhasmaCook failed")
            print("cooked", len(lines), "meshes")
    lsprite_textures()
    print("comb_teeth_em.png:", comb_emissive())
    write_scene()
    write_data(sizes)
    print("scene:", SCENE, "data:", DATA)


if __name__ == "__main__":
    main()
