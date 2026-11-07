"""Ricochet Parlour mesh and scene. The board itself is a pre-rendered backdrop (tools/make_backdrop.py); this
writes the one mesh that shows it, a quad that exactly fills the fixed camera's view at distance BACK_D, and
Assets/Scenes/main.pescene: the camera, the warm "Lamp" spot and "Key" directional that light the balls, and
the backdrop template node.

    python tools/gen_meshes.py [path/to/PhasmaCook.exe]      (--scene-only: rewrite the scene, no cook)

Engine axes: X right, Y up, Z toward the camera. The camera numbers here, in rp_world.lua (W.CAM) and in
tools/backdrop_scene.py must stay identical, or the balls will not sit on the pictured felt.
"""
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OBJECTS = os.path.join(ROOT, "Assets", "Objects")
SCENE = os.path.join(ROOT, "Assets", "Scenes", "main.pescene")
CAM_POS, CAM_LOOK, VFOV = (1.3, 4.4, 12.6), (0.15, 4.05, 0.0), 46.0
BACK_D, BACK_ASPECT = 30.0, 3456 / 1440


def camera_basis():
    p, t = np.array(CAM_POS), np.array(CAM_LOOK)
    f = t - p
    f /= np.linalg.norm(f)
    right = np.cross(f, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, f)
    return p, f, right, up


def backdrop_obj(path):
    """A quad perpendicular to the view axis at BACK_D that the camera sees edge to edge (2.4:1). On a plane
    of constant depth, interpolated UVs equal the projective ones, so the picture maps exactly."""
    p, f, right, up = camera_basis()
    hh = BACK_D * math.tan(math.radians(VFOV / 2))
    hw = hh * BACK_ASPECT
    c = p + f * BACK_D
    corners = [c - right * hw - up * hh, c + right * hw - up * hh, c + right * hw + up * hh, c - right * hw + up * hh]
    uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
    n = -f
    with open(path, "w") as fo:
        fo.write("o backdrop\n")
        for v in corners:
            fo.write("v %.6f %.6f %.6f\n" % tuple(v))
        for t in uvs:
            fo.write("vt %.6f %.6f\n" % t)
        fo.write("vn %.6f %.6f %.6f\n" % tuple(n))
        fo.write("f 1/1/1 2/2/1 3/3/1\nf 1/1/1 3/3/1 4/4/1\n")


def look_matrix(pos, target, up=(0, 1, 0)):
    """Column-major 4x4 whose local -Z points from pos to target (lights shine along local -Z)."""
    pos, target = np.array(pos, float), np.array(target, float)
    z = -(target - pos) / np.linalg.norm(target - pos)
    x = np.cross(up, z); x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return [*x, 0.0, *y, 0.0, *z, 0.0, *pos, 1.0]


def write_scene():
    I = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]
    lamp_pos, aim = (0.4, 10.5, 4.5), (0.0, 4.0, 0.0)          # the bake's lamp, in engine axes
    sc = {"sources": [{"path": "../Objects/backdrop.pemesh"}], "meshes": [{"source": 0, "source_mesh": 0}], "nodes": []}
    sc["nodes"].append({"name": "Camera_0", "parent": -1, "local_matrix": look_matrix(CAM_POS, CAM_LOOK), "component_flags": 8,
                        "camera": {"projection": "perspective", "fovx": 1.2, "near_plane": 0.1, "far_plane": 200.0, "speed": 3.5,
                                   "euler": [0.0, 3.14159, 0.0]}})
    sc["nodes"].append({"name": "Key", "parent": -1, "local_matrix": look_matrix(lamp_pos, aim), "component_flags": 2,
                        "light": {"type": "directional", "color": [1.0, 0.86, 0.66, 3.0]}})
    sc["nodes"].append({"name": "Lamp", "parent": -1, "local_matrix": look_matrix(lamp_pos, aim), "component_flags": 2,
                        "light": {"type": "spot", "color": [1.0, 0.84, 0.6, 8.0], "range": 30.0, "params": [18.0, 26.0, 0.0, 0.0]}})
    # The backdrop sits in place (it is drawn as-is, unlit); the game finds it by name.
    sc["nodes"].append({"name": "T_backdrop", "parent": -1, "local_matrix": I, "component_flags": 0, "mesh_refs": [0]})
    sc["lights"] = []
    sc["cameras"] = [{"name": "Camera_0", "position": list(CAM_POS), "euler": [0.0, 3.14159, 0.0], "fovx": 1.2, "projection": "perspective",
                      "near_plane": 0.1, "far_plane": 200.0, "speed": 3.5, "node_index": 0}]
    sc["active_camera"] = 0
    sc["scene_scripts"] = {"on_play": ["Assets/Scripts/rp.lua"]}
    os.makedirs(os.path.dirname(SCENE), exist_ok=True)
    with open(SCENE, "w") as f:
        json.dump(sc, f, indent=1)


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
    if "--scene-only" not in sys.argv:
        cook = find_cook()
        os.makedirs(OBJECTS, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="rp-meshes-") as tmp:
            src = os.path.join(tmp, "backdrop.obj")
            backdrop_obj(src)
            manifest = os.path.join(tmp, "batch.txt")
            with open(manifest, "w", encoding="utf-8") as f:
                f.write(f"{src}\t{os.path.join(OBJECTS, 'backdrop.pemesh')}\n")
            r = subprocess.run([cook, "--batch", manifest], cwd=os.path.dirname(cook), capture_output=True, text=True)
            if r.returncode != 0 or "1 ok" not in (r.stdout + r.stderr):
                print((r.stdout + r.stderr)[-2000:])
                raise SystemExit("PhasmaCook failed")
            print("cooked backdrop.pemesh")
    write_scene()
    print("scene:", SCENE)


if __name__ == "__main__":
    main()
