"""Free Build room concept render: the game's living room (tools/gen_room.py) with Tripo furniture, a domino run from
the game's own rules frozen mid-run (tools/concept_layout.lua), a ramp and a swinging ball, rendered in Blender
Cycles from the game's camera side, with a light HUD on top.

    python tools/make_room_concept.py <work_dir> [samples]
        <work_dir>/tripo/furn_*.glb   the Tripo furniture (tools/furniture_refs_scene.py references, generated in
                                      Tripo Studio with the jev-browser skill)
        <work_dir>/layout.json        luajit tools/concept_layout.lua <work_dir>/layout.json
    -> <work_dir>/room_concept.png
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_meshes as G  # noqa: E402
import gen_room as R  # noqa: E402

BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
# Room pieces the Tripo furniture replaces (and the code-built books, rebuilt in Blender as the staircase only).
REPLACED = {"room_sofa", "room_tabletop", "room_shelf", "room_pot", "room_leaves", "room_soil", "room_walnut", "room_pages"}     | {"room_books_" + c for c in R.BOOK_COLS}
FURNITURE = R.FURNITURE


def main():
    work = sys.argv[1]
    samples = int(sys.argv[2]) if len(sys.argv) > 2 else 192
    objdir = os.path.join(work, "room_obj")
    os.makedirs(objdir, exist_ok=True)
    meshes = R.build_all()
    pieces = []
    for name in R.ROOM_NAMES:
        if name in REPLACED or name in FURNITURE:
            continue
        path = os.path.join(objdir, name + ".obj")
        R.save_obj_uv(path, meshes[name])
        look = dict(R.PIECES[name][1])
        for k in ("tex", "emis_tex"):
            if look.get(k):
                look[k] = os.path.join(G.ROOT, "Assets", look[k])
        pieces.append(dict(name=name, obj=path, **look))
    G.save_obj(os.path.join(objdir, "domino.obj"), G.MESHES["domino"]())
    for k in range(10):
        G.save_obj(os.path.join(objdir, f"pips_{k}.obj"), G.MESHES[f"pips_{k}"]())
    st = R.STAIRS
    books = [dict(x0=st["x0"] + st["step"] * k, x1=st["x1"] - st["step"] * k, y0=st["y0"], y1=st["y1"], h0=st["rise"] * k, h1=st["rise"] * (k + 1))
             for k in range(st["n"])]
    furn = {}
    for name, f in FURNITURE.items():
        glb = os.path.join(work, "tripo", name + ".glb")
        if os.path.exists(glb):
            furn[name] = dict(glb=glb, **f)
    sd = [R.SUN_DIR_TABLE[0], R.SUN_DIR_TABLE[1], R.SUN_DIR_TABLE[2]]
    spec = dict(pieces=pieces, objdir=objdir, layout=os.path.join(work, "layout.json"), books=books, furniture=furn, sun=sd,
                lamp=list(R.LAMP_AT), side=R.SIDE, art=R.ART, table=R.TABLE, out=os.path.join(work, "room_concept_raw.png"),
                samples=samples, font=os.path.join(G.ROOT, "Assets", "Fonts", "RuntimeUi.ttf"))
    with open(os.path.join(work, "concept_spec.json"), "w") as f:
        json.dump(spec, f)
    r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "room_concept_scene.py"), "--",
                        os.path.join(work, "concept_spec.json")], capture_output=True, text=True)
    if "DONE" not in r.stdout:
        print(r.stdout[-4000:], r.stderr[-3000:])
        raise SystemExit("concept render failed")
    for line in r.stdout.splitlines():
        if line.startswith(("FURN", "DOMINOES")):
            print(line)
    hud(spec, os.path.join(work, "room_concept.png"))
    print("concept:", os.path.join(work, "room_concept.png"))


def hud(spec, out):
    """A light HUD in the game's style: the title panel and the domino counter."""
    from PIL import Image, ImageDraw, ImageFont
    im = Image.open(spec["out"]).convert("RGBA")
    W, H = im.size
    lay = json.load(open(spec["layout"]))
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    u = W / 1920
    walnut, rim, cream, brass, gold = (31, 17, 9, 236), (204, 153, 84, 220), (247, 237, 209, 255), (224, 173, 97, 255), (255, 204, 102, 255)
    big = ImageFont.truetype(spec["font"], int(40 * u))
    mid = ImageFont.truetype(spec["font"], int(24 * u))
    small = ImageFont.truetype(spec["font"], int(15 * u))
    d.rounded_rectangle([24 * u, 18 * u, 384 * u, 110 * u], radius=int(14 * u), fill=walnut, outline=rim, width=max(1, int(2 * u)))
    d.text((44 * u, 30 * u), "TOPPLE", font=big, fill=cream)
    d.text((46 * u, 80 * u), "free build  ·  the living room", font=small, fill=brass)
    x0 = W - 404 * u
    d.rounded_rectangle([x0, 18 * u, W - 24 * u, 136 * u], radius=int(14 * u), fill=walnut, outline=rim, width=max(1, int(2 * u)))
    t1 = f"{lay['count']:,}  dominoes"
    d.text(((x0 + W - 24 * u) / 2, 50 * u), t1, font=mid, fill=cream, anchor="mm")
    d.text(((x0 + W - 24 * u) / 2, 82 * u), f"{lay['fallen']:,} fallen", font=mid, fill=gold, anchor="mm")
    d.text(((x0 + W - 24 * u) / 2, 114 * u), "the chain is running", font=small, fill=brass, anchor="mm")
    Image.alpha_composite(im, ov).convert("RGB").save(out)


if __name__ == "__main__":
    main()
