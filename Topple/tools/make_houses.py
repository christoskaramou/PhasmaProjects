"""Table Run's houses: miniature model houses made with Tripo from reference renders, then cooked for the game.

    python tools/make_houses.py refs [out_dir] [samples]   reference pictures (Blender, tools/house_refs_scene.py)
    (Tripo, by hand or with the jev-browser skill: bash ~/.claude/skills/jev-browser/tripo.sh <ref.png> <tripo_dir> 4000,
     30 credits each: house_cottage.glb, house_townhouse.glb, house_farmhouse.glb)
    python tools/make_houses.py import <tripo_dir> [sheet_dir]
        each GLB -> squared to the axes, door toward the game's camera, scaled to its height, base on the felt
        (tools/house_import.py) -> Assets/Objects/<name>.pemesh and Assets/Textures/<name>.png (the cottage also
        renders the shop's icon_house.png); then the scene is rewritten (gen_meshes.write_scene lists them as
        T_<name> templates).
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_meshes as G  # noqa: E402
import mesh_reduce as MR  # noqa: E402

FACES = 6000        # each house once cooked (tools/mesh_reduce.py, meshoptimizer); its texture stays at house_import's 1024

BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
TEX = os.path.join(G.ROOT, "Assets", "Textures")
# name -> (overall height in table units, extra yaw in degrees that brings the door to the front, saturation kept).
# Saturation: the engine draws the toys without the backdrop's AgX tone curve, so their paints are pulled toward grey
# (agx() in topple_world.lua); the Tripo textures get the same, the farmhouse's bright green more, toward the concept's
# sage. The farmhouse is a little smaller: its porch makes its footprint the deepest.
HOUSES = {
    "house_cottage": (1.95, 0.0, 0.72),
    "house_townhouse": (2.2, 0.0, 0.72),
    "house_farmhouse": (1.8, 0.0, 0.5),
}
NAMES = sorted(HOUSES)


def grade(path, sat):
    """Pull a texture's colours toward their own grey (keeps the brightness)."""
    import numpy as np
    from PIL import Image
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255.0
    lum = (a * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(-1, keepdims=True)
    out = lum + (a - lum) * sat
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path)


def find_cook():
    """PhasmaCook from the sibling engine checkout (gen_meshes.find_cook reads argv, which here holds our own args)."""
    eng = os.path.normpath(os.path.join(G.ROOT, "..", "..", "PhasmaEngine"))
    for b in ("build-ninja-physics", "build-ninja"):
        p = os.path.join(eng, b, "Release", "PhasmaCook.exe")
        if os.path.exists(p):
            return p
    raise SystemExit("PhasmaCook.exe not found")


def refs(out, samples):
    r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "house_refs_scene.py"), "--", out, str(samples)],
                       capture_output=True, text=True)
    if "DONE" not in r.stdout:
        print(r.stdout[-3000:], r.stderr[-3000:])
        raise SystemExit("reference render failed")
    print("references in", out)


def import_all(tripo_dir, sheet_dir):
    cook = find_cook()
    with tempfile.TemporaryDirectory(prefix="topple-houses-") as tmp:
        lines = []
        for name in NAMES:
            h, yaw, sat = HOUSES[name]
            glb = os.path.join(tripo_dir, name + ".glb")
            obj = os.path.join(tmp, name + ".obj")
            tex = os.path.join(TEX, name + ".png")
            cmd = [BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "house_import.py"), "--", glb, obj, tex, str(h), str(yaw)]
            cmd.append(os.path.join(sheet_dir, name + "_sides.png") if sheet_dir else "-")
            if name == "house_cottage":
                cmd.append(os.path.join(TEX, "icon_house.png"))      # the shop's house icon
            r = subprocess.run(cmd, capture_output=True, text=True)
            info = [l for l in r.stdout.splitlines() if l.startswith(("SIZE", "TEXTURE", "NO TEXTURE"))]
            print(name, " | ".join(info))
            if "DONE" not in r.stdout or not os.path.exists(obj):
                print(r.stdout[-2000:], r.stderr[-2000:])
                raise SystemExit("import failed: " + name)
            grade(tex, sat)
            light = obj[:-4] + "_light.obj"
            print("   ", MR.run_obj(obj, light, FACES))
            lines.append(f"{light}\t{os.path.join(G.OBJECTS, name + '.pemesh')}\n")
        manifest = os.path.join(tmp, "batch.txt")
        with open(manifest, "w", encoding="utf-8") as f:
            f.writelines(lines)
        r = subprocess.run([cook, "--batch", manifest], cwd=os.path.dirname(cook), capture_output=True, text=True)
        if r.returncode != 0 or f"{len(lines)} ok" not in (r.stdout + r.stderr):
            print((r.stdout + r.stderr)[-3000:])
            raise SystemExit("PhasmaCook failed")
    print("cooked", len(NAMES), "houses")
    G.write_scene(sorted(G.MESHES))
    print("scene:", G.SCENE)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "refs":
        out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(tempfile.gettempdir(), "topple_houses")
        refs(out, int(sys.argv[3]) if len(sys.argv) > 3 else 160)
    elif cmd == "import":
        import_all(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
