"""Topple tray and shop icons: the game's own toy meshes (tools/gen_meshes.py) rendered in Blender Cycles with the
concept's paints and lamp light, on a transparent background, saved as Assets/Textures/icon_<name>.png (256 px).
icon_house.png comes from tools/make_houses.py (the Tripo cottage).

    python tools/make_icons.py [samples]
"""
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_meshes as G  # noqa: E402

TEX = os.path.join(G.ROOT, "Assets", "Textures")
BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")


def T(x=0.0, y=0.0, z=0.0, rz=0.0, ry=0.0):
    """Engine-space transform: yaw ry about Y, then tilt rz about Z (degrees), then translate."""
    a, b = math.radians(ry), math.radians(rz)
    Ry = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
    Rz = np.array([[math.cos(b), -math.sin(b), 0], [math.sin(b), math.cos(b), 0], [0, 0, 1]])
    M = np.eye(4)
    M[:3, :3] = Ry @ Rz
    M[:3, 3] = (x, y, z)
    return M


def rocket_parts(M):
    return [("launcher", "wood", M)] + [(p, m, M @ T(0, 0.06, 0, rz=-G.ROCKET_TILT)) for p, m in
                                        (("rocket_body", "brick"), ("rocket_band", "cream"), ("rocket_nose", "cream"), ("rocket_fins", "mustard"))]


ICONS = {
    "dominoes": [("domino", c, T(x, 0, z, ry=r)) for c, x, z, r in (("brick", -0.62, 0.12, 12), ("mustard", 0.0, 0.0, 0), ("sage", 0.62, 0.12, -12))]
    + [(f"pips_{k}", "pip", T(x, 0, z, ry=r)) for k, x, z, r in ((0, -0.62, 0.12, 12), (3, 0.0, 0.0, 0), (6, 0.62, 0.12, -12))],
    "bell": [("gallows", "wood", T()), ("bell", "brass", T(0, 2.2, 0))],
    "spring": [("spring_base", "wood", T()), ("spring_coil", "steel", T()), ("spring_cap", "brass", T(0, 0.8, 0))],
    "rocket": rocket_parts(T()),
    "marble": [("chute", "wood", T()), ("@marble", "glass", T(-0.62, 1.1, 0))],
    "block": [("block", "mustard", T())],
}

# Free Build tool icons: little arrangements of dominoes (with pips), and the brass start arrow.
_PAINTS = ["brick", "mustard", "sage", "navy", "cream"]


def _doms(spots, tilt=None):
    parts = []
    for i, (x, z, yaw) in enumerate(spots):
        rz = tilt[i] if tilt and i < len(tilt) else 0.0
        c = _PAINTS[(i // 2) % 5]
        parts.append(("domino", c, T(x, 0, z, ry=yaw, rz=rz)))
        parts.append((f"pips_{(i * 3) % 10}", "pip", T(x, 0, z, ry=yaw, rz=rz)))
    return parts


def _curve(n, f):
    pts = [f(i / (n - 1)) for i in range(n)]
    out = []
    for i, (x, z) in enumerate(pts):
        x2, z2 = pts[min(i + 1, n - 1)] if i < n - 1 else (2 * x - pts[i - 1][0], 2 * z - pts[i - 1][1])
        out.append((x, z, math.degrees(math.atan2(-(z2 - z), x2 - x))))
    return out


def _spiral():
    """Table-plane Archimedean spiral (outer end first), as engine (x, z, yaw degrees)."""
    out, r, a, b = [], 2.3, 0.0, 0.95 / (2 * math.pi)
    while r > 0.8 and len(out) < 18:
        tx, ty = -b * math.cos(a) - r * math.sin(a), -b * math.sin(a) + r * math.cos(a)
        out.append((r * math.cos(a), -r * math.sin(a), math.degrees(math.atan2(ty, tx))))
        da = 0.62 / math.hypot(r, b)
        a += da
        r -= b * da
    return out


ICONS.update({
    "tool_draw": _doms(_curve(7, lambda t: (t * 3.4 - 1.7, 0.75 * math.sin(t * 2 * math.pi)))),
    "tool_line": _doms([(i * 0.62 - 1.55, 0.0, 0.0) for i in range(6)]),
    "tool_spiral": _doms(_spiral()),
    "tool_field": _doms([(k * 0.62, (i - k / 2) * 0.6, 0.0) for k in range(4) for i in range(k + 1)]),
    "tool_erase": _doms([(-0.62, 0, 0), (0.62, 0, 0)]) + [("domino", "brick", T(0.0, 0.9, 0.0, ry=25, rz=-35)),
                                                           ("pips_4", "pip", T(0.0, 0.9, 0.0, ry=25, rz=-35))],
    "tool_start": [("arrow", "brass", T(-0.7, 0, 0))] + _doms([(0.0, 0, 0), (0.62, 0, 0), (1.24, 0, 0)], [-24.0, 0.0, 0.0]),
    "tool_ball": _doms([(-0.9, 0, 0), (-0.28, 0, 0)], [-24.0, -24.0]) + [("ball", "brick", T(0.75, 0.42, 0))],
    "tool_switch": _doms([(-1.3, 0, 0)], [-24.0]) + [("icon_switch", "wood", T(-0.2, 0, 0)), ("ball", "brick", T(-0.2, 0.32, 0)),
                                                      ("arrow", "brass", T(0.75, 0, 0))] + _doms([(1.3, 0, 0), (1.92, 0, 0)]),
    "tool_ramp": [("icon_step", "wood", T(-1.2 + k * 0.5, 0, 0)) for k in range(5)] + [("ball", "brick", T(1.3, 0.0, 0))],
    "tool_swing": _doms([(1.7, 0, 0)], [-24.0]) + [("icon_post", "wood", T(-0.6, 0, 1.0)), ("icon_post", "wood", T(-0.6, 0, -1.0)),
                                                    ("icon_bar", "wood", T(-0.6, 2.6, 0)), ("icon_string", "cream", T(-0.6, 2.6, 0)),
                                                    ("ball", "brass", T(0.5, 0.3, 0))],
})
# The Free Build ball (the game makes its own with primitives.uv_sphere).
G.MESHES["icon_switch"] = lambda: G.rbox((0, 0.3, 0), (1.3, 0.6, 1.3), 0.08, 3)
G.MESHES["icon_step"] = lambda: G.rbox((0, 0.25, 0), (0.5, 0.5, 1.5), 0.04, 2)
G.MESHES["icon_post"] = lambda: G.tube((0, 0, 0), (0, 2.6, 0), 0.09, 12)
G.MESHES["icon_bar"] = lambda: G.tube((0, 0, -1.09), (0, 0, 1.09), 0.09, 12)
G.MESHES["icon_string"] = lambda: G.tube((0, 0, 0), (1.1, -1.9, 0), 0.03, 8)
G.MESHES["ball"] = lambda: G.lathe([(0.42 * math.sin(k * math.pi / 24), 0.42 - 0.42 * math.cos(k * math.pi / 24)) for k in range(25)], 48)


def main():
    samples = int(sys.argv[1]) if len(sys.argv) > 1 else 128
    if len(sys.argv) > 2:            # only these icons: python tools/make_icons.py 128 tool_ball
        for k in [k for k in ICONS if k not in sys.argv[2:]]:
            del ICONS[k]
    with tempfile.TemporaryDirectory(prefix="topple-icons-") as tmp:
        need = sorted({p for parts in ICONS.values() for p, _, _ in parts if not p.startswith("@")})
        for name in need:
            G.save_obj(os.path.join(tmp, name + ".obj"), G.MESHES[name]())
        spec = {"tmp": tmp, "out": TEX, "samples": samples,
                "icons": {k: [[p, m, M.tolist()] for p, m, M in parts] for k, parts in ICONS.items()}}
        with open(os.path.join(tmp, "spec.json"), "w") as f:
            json.dump(spec, f)
        r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "icon_scene.py"), "--",
                            os.path.join(tmp, "spec.json")], capture_output=True, text=True)
        if "DONE" not in r.stdout:
            print(r.stdout[-3000:], r.stderr[-3000:])
            raise SystemExit("Blender icon render failed")
    print("icons:", ", ".join(ICONS))


if __name__ == "__main__":
    main()
