"""Every Cycles bake for Shadow Puppeteer (Blender 5.1, tools/scene.py):

    python tools/make_bakes.py [all|game|targets] [SAMPLES]

game:    Assets/Textures/backdrop.png (static theatre, no lantern; emissive of the live paper and floor and the far quad),
         albedo.png (paper and floor base colour), front_I_J.png (RGBA front cards: theatre lit by the lantern at
         sp_common.FRONT_X[I], FRONT_Y[J]; paper and floor cut out).
targets: .concepts/next/puppet/target.png, target_b.png, backdrop.png (2560x1440 references).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import sp_common as G  # noqa: E402

BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
MAP = os.environ.get("SP_MAP", "stage")            # sp_common.MAPS id; the first set keeps the root folder
TEX = os.path.join(ROOT, "Assets", "Textures") if MAP == "stage" else os.path.join(ROOT, "Assets", "Textures", MAP)
REF = os.path.normpath(os.path.join(ROOT, "..", ".concepts", "next", "puppet"))
LOGS = os.path.join(REF, "logs")


def run(mode, out, samples, res=None):
    args = [BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "scene.py"), "--", mode, out, str(samples)]
    if res:
        args += [str(res[0]), str(res[1])]
    os.makedirs(LOGS, exist_ok=True)
    with open(os.path.join(LOGS, "bake_%s_%s.log" % (MAP, mode)), "w") as log:
        r = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT)
    print(mode, "->", out, "exit", r.returncode, flush=True)
    if r.returncode != 0 or not os.path.exists(out):
        raise SystemExit("bake failed: " + mode)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    spp = int(sys.argv[2]) if len(sys.argv) > 2 else 256
    if what == "fronts":
        for i in range(len(G.FRONT_X)):
            for j in range(len(G.FRONT_Y)):
                run("front_%d_%d" % (i, j), os.path.join(TEX, "front_%d_%d.png" % (i, j)), max(64, spp // 2))
    if what in ("all", "game", "set"):           # set: one stage set's backdrop, albedo and front cards (no sprites)
        os.makedirs(TEX, exist_ok=True)
        run("backdrop_wide", os.path.join(TEX, "backdrop.png"), spp)
        run("albedo_wide", os.path.join(TEX, "albedo.png"), 32)
        for i in range(len(G.FRONT_X)):
            for j in range(len(G.FRONT_Y)):
                run("front_%d_%d" % (i, j), os.path.join(TEX, "front_%d_%d.png" % (i, j)), max(64, spp // 2))
    if what in ("all", "game", "lsprites"):
        # the lantern sprites: 2x supersampled renders of the target's lantern alone (gen_meshes crops them)
        S = G.LSPRITE_SS
        for i in range(len(G.FRONT_X)):
            for j in range(len(G.FRONT_Y)):
                run("lsprite_%d_%d" % (i, j), os.path.join(LOGS, "..", "lsprite_raw", "lsprite_%d_%d.png" % (i, j)), spp,
                    (2560 * S, 1369 * S))
    if what in ("all", "targets"):
        for mode in ("target", "target_b", "backdrop"):
            run(mode, os.path.join(REF, mode + ".png"), spp, (2560, 1440))
        for mode in ("target", "target_b"):                      # the Player's maximised window: pixel-for-pixel
            run(mode, os.path.join(REF, mode + "_2560x1369.png"), spp, (2560, 1369))


if __name__ == "__main__":
    main()
