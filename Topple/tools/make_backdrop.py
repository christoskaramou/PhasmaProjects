"""Bake Topple's backdrop: the empty games table rendered in Blender Cycles from the game's fixed camera with the
concept render's grade, saved as Assets/Textures/backdrop.png. The game shows it unlit on a quad that exactly
fills the camera's view and draws every toy in 3D on top.

    python tools/make_backdrop.py [samples]

Needs Blender 5.x (BLENDER env var or the default install path). The render is 2.4:1 at the game's vertical
field of view (29.84 degrees), so windows wider than 16:9 still have backdrop at the sides; narrower ones crop it.
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
    samples = int(sys.argv[1]) if len(sys.argv) > 1 else 384
    r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "backdrop_scene.py"), "--",
                        OUT_PNG, str(samples), str(WIDTH), str(HEIGHT)], capture_output=True, text=True)
    if "DONE" not in r.stdout:
        print(r.stdout[-3000:], r.stderr[-3000:])
        raise SystemExit("Blender render failed")
    print(OUT_PNG, os.path.getsize(OUT_PNG) // 1024, "KB")


if __name__ == "__main__":
    main()
