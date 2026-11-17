"""python tests/hit_shapes_test.py   (from the Undertow folder)

The rules' hit shapes (Assets/Scripts/uw_data.lua, HIT) against the meshes the game draws:
  1. every piece mesh used for a hit shape was cooked from the same OBJ (the .pemesh is newer than the OBJ and
     mesh_stats.json has its triangle count),
  2. the grids in uw_data.lua equal grids cut fresh from those OBJs (tools/uw_hits.py),
  3. checked against the geometry by different points: every mesh vertex and triangle centre inside the slab is a
     hit for a float centred on it, and float centres sampled away from the mesh (farther than FLOAT_R + one cell
     diagonal from every sampled mesh point) are not.
"""
import json
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import uw_common as U  # noqa: E402
import uw_hits as H  # noqa: E402

fails = 0


def check(ok, msg):
    global fails
    print(("ok   " if ok else "FAIL ") + msg)
    if not ok:
        fails += 1


def lua_hits():
    """Parse HIT.<kind>.cells from the generated Lua data."""
    src = open(os.path.join(ROOT, "Assets", "Scripts", "uw_data.lua"), encoding="utf-8").read()
    out = {}
    for kind in H.PLACEMENTS:
        m = re.search(r"\n\s+%s = \{\s*box = \{[^}]*\},\s*cells = \{([^}]*)\}" % kind, src)
        nums = [int(v) for v in m.group(1).replace("\n", " ").split(",") if v.strip()] if m else []
        out[kind] = {(nums[i], nums[i + 1]): nums[i + 2] / 1000.0 for i in range(0, len(nums), 3)}
    return out


def is_hit(cells, x, z, r=U.FLOAT_R):
    c = U.HIT_CELL
    for i in range(int(np.floor((x - r) / c)), int(np.floor((x + r) / c)) + 1):
        for k in range(int(np.floor((z - r) / c)), int(np.floor((z + r) / c)) + 1):
            y = cells.get((i, k))
            if y is not None:
                cx, cz = (i + 0.5) * c - x, (k + 0.5) * c - z
                if cx * cx + cz * cz < r * r - y * y:
                    return True
    return False


stats = json.load(open(os.path.join(ROOT, "Assets", "Objects", "mesh_stats.json")))
lua = lua_hits()
rng = np.random.default_rng(1)
for kind, (name, oy, yaw) in H.PLACEMENTS.items():
    obj = os.path.join(H.PCS, name + ".obj")
    pem = os.path.join(ROOT, "Assets", "Objects", name + ".pemesh")
    V, F = H.read_obj(name)
    check(os.path.getmtime(pem) >= os.path.getmtime(obj) and name in stats,
          "%s: %s.pemesh was cooked from %s.obj (%s triangles)" % (kind, name, name, stats.get(name, ["?", "?"])[1]))
    fresh, S = H.grid(kind)
    same = {k: round(v, 3) for k, v in fresh.items()} == {k: round(v, 3) for k, v in lua[kind].items()}
    check(same and len(fresh) > 0, "%s: uw_data grid equals a fresh cut of the mesh (%d cells)" % (kind, len(fresh)))
    W = H.placed(V, oy, yaw)
    cent = W[F].mean(axis=1)
    pts = np.concatenate([W, cent])
    inside = pts[np.abs(pts[:, 1]) < U.FLOAT_R * 0.95]
    miss = [p for p in inside if not is_hit(lua[kind], p[0], p[2])]
    check(len(miss) == 0 and len(inside) > 0,
          "%s: all %d mesh vertices / triangle centres in the slab are hits (%d missed)" % (kind, len(inside), len(miss)))
    # away: random float centres in the box around the piece, farther than R + a cell diagonal from every sample
    lo, hi = S[:, [0, 2]].min(0) - 1.0, S[:, [0, 2]].max(0) + 1.0
    cand = rng.uniform(lo, hi, size=(4000, 2))
    near = S[np.abs(S[:, 1]) < U.FLOAT_R][:, [0, 2]]
    far = []
    for p in cand:
        d = np.sqrt(((near - p) ** 2).sum(1)).min() if len(near) else 1e9
        if d > U.FLOAT_R + U.HIT_CELL * 1.5:
            far.append(p)
        if len(far) >= 300:
            break
    false_hits = sum(1 for p in far if is_hit(lua[kind], p[0], p[1]))
    check(false_hits == 0 and len(far) > 50, "%s: %d float centres clear of the mesh are not hits (%d false)" % (kind, len(far), false_hits))

print(("%d FAILED" % fails) if fails else "hit_shapes_test: all passed")
sys.exit(1 if fails else 0)
