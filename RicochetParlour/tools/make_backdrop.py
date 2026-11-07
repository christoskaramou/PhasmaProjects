"""Bake Ricochet Parlour's backdrop: the static board rendered in Blender Cycles from the game's fixed camera,
graded like the concept render, saved as Assets/Textures/backdrop.png. The game shows it unlit on a quad
that exactly fills the camera's view, and draws the balls, their shadows, trails and effects in 3D on top.

    python tools/make_backdrop.py [samples]

Needs Blender 5.x (BLENDER env var or the default install path) and the engine's luajit (to read the rules'
geometry). The render is 2.4:1 at the game's vertical field of view (46 degrees), so windows wider than
16:9 still have backdrop at the sides; narrower windows crop it.
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUT_PNG = os.path.join(ROOT, "Assets", "Textures", "backdrop.png")
BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
LUAJIT = os.environ.get("LUAJIT", os.path.normpath(os.path.join(ROOT, "..", "..", "PhasmaEngine", "build-ninja-physics", "Release", "luajit.exe")))
WIDTH, HEIGHT = 3456, 1440          # 2.4:1
ASPECT = WIDTH / HEIGHT


def grade(hdr):
    """The concept's finish: gentle bloom, a filmic (ACES-fit) tone curve, a vignette centred on 16:9."""
    H, W = hdr.shape[:2]

    def down(a):
        h, w = a.shape[0] // 2 * 2, a.shape[1] // 2 * 2
        a = a[:h, :w]
        return (a[0::2, 0::2] + a[1::2, 0::2] + a[0::2, 1::2] + a[1::2, 1::2]) * 0.25

    def blur(a):
        k = np.array([1, 4, 6, 4, 1], np.float32) / 16
        for ax in (0, 1):
            a = sum(np.roll(a, i - 2, axis=ax) * k[i] for i in range(5))
        return a

    def up(a):
        return np.stack([np.asarray(Image.fromarray(a[..., c]).resize((W, H), Image.BILINEAR)) for c in range(3)], -1)

    cur, bloom = np.maximum(hdr - 1.6, 0), np.zeros_like(hdr)
    for i in range(7):
        cur = blur(down(cur))
        bloom += up(cur) * (0.6 if i < 2 else 0.85)
    img = hdr + bloom * 0.07
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    u = (xx - W / 2) / (H * 16 / 9)          # same vignette as a 16:9 frame, extended to the sides
    v = yy / H - 0.5
    img *= np.clip(1 - 0.5 * (u * u * 1.4 + v * v * 1.8), 0.05, 1)[..., None] * 1.2
    a, b, c, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    img = np.clip(img * (a * img + b) / (img * (c * img + d) + e), 0, 1)
    img = np.where(img <= 0.0031308, img * 12.92, 1.055 * np.power(img, 1 / 2.4) - 0.055)
    return (img * 255 + 0.5).astype(np.uint8)


def main():
    samples = int(sys.argv[1]) if len(sys.argv) > 1 else 512
    with tempfile.TemporaryDirectory(prefix="rp-backdrop-") as tmp:
        geom = os.path.join(tmp, "geometry.json")
        out = subprocess.run([LUAJIT, os.path.join("tools", "dump_geometry.lua")], cwd=ROOT, capture_output=True, text=True, check=True)
        json.loads(out.stdout)
        with open(geom, "w") as f:
            f.write(out.stdout)
        r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "backdrop_scene.py"), "--",
                            geom, tmp, str(samples), str(WIDTH), str(HEIGHT)], capture_output=True, text=True)
        if "DONE" not in r.stdout:
            print(r.stdout[-3000:], r.stderr[-3000:])
            raise SystemExit("Blender render failed")
        hdr = np.load(os.path.join(tmp, "backdrop.npy")).astype(np.float32)
    Image.fromarray(grade(hdr)).save(OUT_PNG, optimize=True)
    print(OUT_PNG, os.path.getsize(OUT_PNG) // 1024, "KB")


if __name__ == "__main__":
    main()
