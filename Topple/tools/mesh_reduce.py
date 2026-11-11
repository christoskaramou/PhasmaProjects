"""Make a furniture model lighter before it is cooked: meshoptimizer's attribute-aware simplifier on an OBJ, and a
texture brought down to the size it is seen at. Run with a Python that has the `meshoptimizer` package (and numpy,
Pillow), kept outside the repo; the generators call it through MESHOPT_PY (default C:/Users/Christos/tripo_tools/venv).

    python -I mesh_reduce.py obj <in.obj> <out.obj> <faces> [<lock.json>]
    python -I mesh_reduce.py tex <image.png> <px>

obj: the OBJ's corners (position / uv / normal triples) become one vertex each, so UV seams are split vertices that
meshopt_simplifyWithAttributes keeps as seams; positions are the metric, UVs and normals its attributes. Vertices on a
buildable top (lock.json: [{x0, x1, y0, y1, h}, ...] in table axes, x right, y away, h up; the OBJ is in engine axes
x, h, -y) are locked, so the flat tops dominoes stand on keep their outline and height. Prints one line:
REDUCED <faces before> -> <faces after> error <e> locked <n>.
tex: downsized (Lanczos) to px on its longer side when larger, PNG kept.
"""
import ctypes
import os
import json
import sys

import numpy as np

W_UV, W_NORMAL = 1.0, 0.5           # attribute weights against the position error (positions are normalised to the mesh)
LOCK_DH = 0.2                       # how near a top's height a vertex is locked


def read_obj(path):
    V, T, N, head, corners = [], [], [], [], []
    with open(path) as fo:
        for line in fo:
            if line.startswith("v "):
                V.append([float(c) for c in line.split()[1:4]])
            elif line.startswith("vt "):
                T.append([float(c) for c in line.split()[1:3]])
            elif line.startswith("vn "):
                N.append([float(c) for c in line.split()[1:4]])
            elif line.startswith("f "):
                ids = []
                for c in line.split()[1:]:
                    p = (c.split("/") + ["", ""])[:3]
                    ids.append(tuple(int(k) - 1 if k else -1 for k in p))
                for k in range(1, len(ids) - 1):
                    corners += [ids[0], ids[k], ids[k + 1]]
            elif line.startswith(("mtllib", "usemtl", "o ", "g ")) and len(head) < 8:
                head.append(line.rstrip("\n"))
    return np.array(V, np.float32), np.array(T, np.float32), np.array(N, np.float32), head, corners


def reduce_obj(src, dst, faces, lock_boxes):
    import meshoptimizer  # noqa: F401  (loads the bundled library)
    V, T, N, head, corners = read_obj(src)
    key, verts, idx = {}, [], np.empty(len(corners), np.uint32)
    for i, c in enumerate(corners):
        k = key.get(c)
        if k is None:
            k = key[c] = len(verts)
            verts.append(c)
        idx[i] = k
    vi = np.array([c[0] for c in verts])
    ti = np.array([c[1] for c in verts])
    ni = np.array([c[2] for c in verts])
    pos = np.ascontiguousarray(V[vi], np.float32)
    uv = T[ti] if len(T) and (ti >= 0).all() else np.zeros((len(verts), 2), np.float32)
    nrm = N[ni] if len(N) and (ni >= 0).all() else np.zeros((len(verts), 3), np.float32)
    attrs = np.ascontiguousarray(np.hstack([uv, nrm]), np.float32)
    weights = np.array([W_UV, W_UV, W_NORMAL, W_NORMAL, W_NORMAL], np.float32)
    lock = np.zeros(len(verts), np.uint8)
    tx, ty, th = pos[:, 0], -pos[:, 2], pos[:, 1]
    for b in lock_boxes:
        lock |= ((tx >= b["x0"] - 0.05) & (tx <= b["x1"] + 0.05) & (ty >= b["y0"] - 0.05) & (ty <= b["y1"] + 0.05)
                 & (np.abs(th - b["h"]) <= LOCK_DH)).astype(np.uint8)
    before = len(idx) // 3
    out = np.empty(len(idx), np.uint32)
    err = ctypes.c_float(0.0)
    # (the package's own handle on the bundled library; its simplify_with_attributes wrapper leaves the C prototype
    # undeclared, so a float or a 64-bit size_t would not pass: declared here as in meshoptimizer.h)
    from meshoptimizer._loader import lib
    f = lib.meshopt_simplifyWithAttributes
    P = ctypes.POINTER
    f.argtypes = [P(ctypes.c_uint), P(ctypes.c_uint), ctypes.c_size_t, P(ctypes.c_float), ctypes.c_size_t, ctypes.c_size_t,
                  P(ctypes.c_float), ctypes.c_size_t, P(ctypes.c_float), ctypes.c_size_t, P(ctypes.c_ubyte), ctypes.c_size_t,
                  ctypes.c_float, ctypes.c_uint, P(ctypes.c_float)]
    f.restype = ctypes.c_size_t
    n = f(out.ctypes.data_as(P(ctypes.c_uint)), idx.ctypes.data_as(P(ctypes.c_uint)), len(idx),
          pos.ctypes.data_as(P(ctypes.c_float)), len(pos), 12, attrs.ctypes.data_as(P(ctypes.c_float)), 20,
          weights.ctypes.data_as(P(ctypes.c_float)), 5, lock.ctypes.data_as(P(ctypes.c_ubyte)), min(len(idx), faces * 3),
          1.0, 0, ctypes.byref(err))
    err = np.array([err.value])
    out = out[:n]
    # (a triangle whose corners are split vertices on a seam can come out with no area: the cooker would turn it into a
    # line and give it a mesh of its own, the one the game draws; dropped)
    t3 = out.reshape(-1, 3)
    p0, p1, p2 = pos[t3[:, 0]], pos[t3[:, 1]], pos[t3[:, 2]]
    area2 = np.linalg.norm(np.cross(p1 - p0, p2 - p0), axis=1)
    ext = float(np.max(pos.max(0) - pos.min(0))) or 1.0
    out = t3[area2 > (ext * 1e-6) ** 2].reshape(-1)
    n = len(out)
    used = np.unique(out)
    remap = np.full(len(verts), -1, np.int64)
    remap[used] = np.arange(len(used))
    with open(dst + ".tmp", "w") as fo:
        for line in head:
            fo.write(line + "\n")
        for p in pos[used]:
            fo.write("v %.5f %.5f %.5f\n" % tuple(p))
        for t in uv[used]:
            fo.write("vt %.5f %.5f\n" % tuple(t))
        for q in nrm[used]:
            fo.write("vn %.5f %.5f %.5f\n" % tuple(q))
        tri = remap[out].reshape(-1, 3) + 1
        for a, b_, c in tri:
            fo.write("f %d/%d/%d %d/%d/%d %d/%d/%d\n" % (a, a, a, b_, b_, b_, c, c, c))
    import os
    os.replace(dst + ".tmp", dst)
    print("REDUCED %d -> %d error %.4f locked %d" % (before, n // 3, float(err[0]), int(lock.sum())))


def reduce_tex(path, px):
    from PIL import Image
    im = Image.open(path)
    w, h = im.size
    if max(w, h) <= px:
        print("TEX %s %dx%d kept" % (path, w, h))
        return
    k = px / max(w, h)
    im = im.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    im.save(path, optimize=True)
    print("TEX %s %dx%d -> %dx%d" % (path, w, h, im.size[0], im.size[1]))


# ------------------------------------------------------------------ for the generators (any Python): run it in MESHOPT_PY
MESHOPT_PY = os.environ.get("MESHOPT_PY", r"C:\Users\Christos\tripo_tools\venv\Scripts\python.exe")


def _run(args):
    import subprocess
    r = subprocess.run([MESHOPT_PY, "-I", os.path.abspath(__file__)] + [str(a) for a in args], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("mesh_reduce failed (MESHOPT_PY=%s): %s" % (MESHOPT_PY, (r.stdout + r.stderr)[-1500:]))
    return r.stdout.strip()


def run_obj(src, dst, faces, lock_boxes=()):
    """src -> dst simplified to `faces` (kept as it is if it has no more), its buildable tops locked. The output line."""
    import tempfile
    with tempfile.TemporaryDirectory(prefix="topple-reduce-") as tmp:
        lj = os.path.join(tmp, "lock.json")
        with open(lj, "w") as fo:
            json.dump([{k: float(b[k]) for k in ("x0", "x1", "y0", "y1", "h")} for b in lock_boxes], fo)
        return _run(["obj", src, dst, faces, lj])


def run_tex(path, px):
    return _run(["tex", path, px])


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "obj":
        reduce_obj(a[1], a[2], int(a[3]), json.load(open(a[4])) if len(a) > 4 else [])
    elif a and a[0] == "tex":
        reduce_tex(a[1], int(a[2]))
    else:
        raise SystemExit(__doc__)
