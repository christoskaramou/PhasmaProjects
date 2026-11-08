"""Free Build's furniture: the Tripo models (tools/furniture_refs_scene.py references, generated in Tripo Studio with
the jev-browser skill), baked into the room and cooked.

    python tools/make_furniture.py <tripo_dir>      (furn_sofa.glb, furn_armchair.glb, ... in <tripo_dir>)
        -> Assets/Objects/<name>.pemesh and Assets/Textures/<name>.png; then the scene is rewritten.
Their placement is gen_room.FURNITURE, also used by the room concept render.
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_meshes as G  # noqa: E402
import gen_room as R  # noqa: E402
import make_houses as H  # noqa: E402


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    tripo = sys.argv[1]
    cook = H.find_cook()
    with tempfile.TemporaryDirectory(prefix="topple-furniture-") as tmp:
        lines = []
        for name, f in R.FURNITURE.items():
            obj, spec = os.path.join(tmp, name + ".obj"), os.path.join(tmp, name + ".json")
            with open(spec, "w") as fo:
                json.dump(f, fo)
            r = subprocess.run([H.BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "furniture_import.py"), "--",
                                os.path.join(tripo, name + ".glb"), obj, os.path.join(R.TEX, name + ".png"), spec], capture_output=True, text=True)
            print(name)
            for line in r.stdout.splitlines():
                if line.startswith(("BOX", "SLICE", "TEXTURE", "NO TEXTURE")):
                    print("   ", line)
            if "DONE" not in r.stdout or not os.path.exists(obj):
                print(r.stdout[-2000:], r.stderr[-2000:])
                raise SystemExit("import failed: " + name)
            lines.append(f"{obj}\t{os.path.join(G.OBJECTS, name + '.pemesh')}\n")
        manifest = os.path.join(tmp, "batch.txt")
        with open(manifest, "w", encoding="utf-8") as fo:
            fo.writelines(lines)
        r = subprocess.run([cook, "--batch", manifest], cwd=os.path.dirname(cook), capture_output=True, text=True)
        if r.returncode != 0 or f"{len(lines)} ok" not in (r.stdout + r.stderr):
            print((r.stdout + r.stderr)[-3000:])
            raise SystemExit("PhasmaCook failed")
    print("cooked", len(lines), "furniture meshes")
    G.write_scene(sorted(G.MESHES))
    print("scene:", G.SCENE)


if __name__ == "__main__":
    main()
