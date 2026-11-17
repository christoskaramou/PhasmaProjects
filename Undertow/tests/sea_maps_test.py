"""python tests/sea_maps_test.py   (from the Undertow folder)
The game's sea maps are the depth-mapped ones (tools/uw_ripple.world_maps, UVs from uw_common.ripple_v):
  1. sea_normal_*.png / sea_rough.png / sea_detail.png are WORLD_W x WORLD_H (not the Blender target's repeating maps,
     which gen_assets once copied over them)
  2. the ripples fade with distance: slope energy per row falls from the near rows to the far rows (no sparkling foil)
  3. roughness rises with distance (the slope the map leaves out)
  4. the sea mesh's UV v is ripple_v(y)"""
import os
import sys
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import uw_common as U  # noqa: E402
import uw_ripple as R  # noqa: E402
import uw_sea  # noqa: E402
TEX = os.path.join(ROOT, "Assets", "Textures")
fails = 0


def check(ok, msg):
    global fails
    print(("ok   " if ok else "FAIL ") + msg)
    fails += 0 if ok else 1


sizes = {n: Image.open(os.path.join(TEX, n)).size for n in ["sea_normal_%02d.png" % f for f in range(U.RIPPLE_FRAMES)] + ["sea_rough.png", "sea_detail.png"]}
check(all(v == (R.WORLD_W, R.WORLD_H) for v in sizes.values()), "sea maps are the depth-mapped %dx%d ones: %s" % (R.WORLD_W, R.WORLD_H, sorted(set(sizes.values()))))
nm = np.asarray(Image.open(os.path.join(TEX, "sea_normal_00.png")).convert("RGB"), np.float32) / 255.0
slope = np.hypot(nm[..., 0] - 0.5, nm[..., 1] - 0.5).mean(1)          # row 0 = far (v 1)
H = nm.shape[0]
def band(y0, y1):          # rows of world depths y0..y1 (row 0 = v 1 = far)
    r0, r1 = int((1 - U.ripple_v(y1)) * H), int((1 - U.ripple_v(y0)) * H)
    return slope[r0:max(r1, r0 + 1)].mean()
near, mid, far = band(-6, 0), band(10, 25), band(40, 64)
check(near > 1.3 * mid and mid > 1.1 * far, "ripple slope fades with distance: near (y -6..0) %.3f, mid (10..25) %.3f, far (40..64) %.3f" % (near, mid, far))
rg = np.asarray(Image.open(os.path.join(TEX, "sea_rough.png")).convert("RGB"), np.float32)[:, 0, 1] / 255.0
check(rg[-1] < rg[H // 2] < rg[0] and rg[-1] < 0.25, "roughness rises with distance: near %.2f, mid %.2f, far %.2f" % (rg[-1], rg[H // 2], rg[0]))
V, _N, _C, T, _Q = uw_sea.tile()
rows = uw_sea.rows()
worst = 0.0
for j, y in enumerate(rows):
    i = j * (uw_sea.NX + 1)
    worst = max(worst, abs(T[i][1] - U.ripple_v(y)))
check(worst < 1e-9, "sea mesh UV v is ripple_v(y) on every row (worst %.1e)" % worst)
if fails:
    print("%d FAILED" % fails)
    sys.exit(1)
print("sea_maps_test: all passed")
