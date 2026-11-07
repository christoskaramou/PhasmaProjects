"""Bake Kite Hill's backdrop: the hills, village, windmill tower, sky and clouds rendered in Blender Cycles from
the game's fixed camera, saved as Assets/Textures/backdrop.png. The game shows it unlit on a quad that exactly
fills the camera's view and draws the kites, gates, flyer and windmill sails in 3D on top.

    python tools/make_backdrop.py [samples] [scale]

Needs Blender 5.x (BLENDER env var or the default install path). The render is 2.4:1 at the game's vertical field
of view (42 degrees), so windows wider than 16:9 still have backdrop at the sides; narrower ones crop it.
`scale` (default 1) renders smaller for quick looks (written next to the real one as backdrop_preview.png).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUT_PNG = os.path.join(ROOT, "Assets", "Textures", "backdrop.png")
BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
WIDTH, HEIGHT = 3456, 1440


def main():
    samples = int(sys.argv[1]) if len(sys.argv) > 1 else 256
    scale = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    out = OUT_PNG if scale == 1.0 else os.path.join(ROOT, "tools", "backdrop_preview.png")
    r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "backdrop_scene.py"), "--",
                        out, str(samples), str(int(WIDTH * scale)), str(int(HEIGHT * scale))], capture_output=True, text=True)
    if "DONE" not in r.stdout:
        print(r.stdout[-3000:], r.stderr[-3000:])
        raise SystemExit("Blender render failed")
    print(out, os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    main()
