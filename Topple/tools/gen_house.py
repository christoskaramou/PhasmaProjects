"""Topple's house: the seven rooms beside the living room, from the specs in tools/house_rooms.py.

    python tools/gen_house.py [tripo_dir] [--only=<id>,<id>] [--no-cook] [--no-tex] [--preview] [--check]

Per room it writes the shell and code-built prop meshes (Assets/Objects/<id>_*.pemesh), the textures
(Assets/Textures/<id>_*.png), Assets/Scripts/rooms/<id>.lua (the schema of free_room.lua plus id, name, pending and
spots), and the scene's hidden template nodes (through gen_meshes.write_scene, which lists the living room first and
leaves its nodes as they were). Every room is validated before anything is written: no furniture or prop box may
overlap another, a wall, the roof or a doorway, no surface may cut through a solid, every raised surface needs
something under it, and the trap gaps must have the clearance their spots promise.

Furniture: when <tripo_dir>/furn_<id>_<item>.glb exists it is imported (tools/furniture_import.py in Blender), fitted
to its design size, baked into place (one mesh per placement: furn_<id>_<item>, furn_<id>_<item>_2, ...), and its
solids and surfaces are measured from the mesh. Otherwise the piece stays out of `pieces`, its solids and surfaces
come from the design size, and it is listed in `pending`.

--preview renders every room in Blender (furniture as its design boxes) to %TEMP%/topple_house/rooms/<id>.png.
--check loads every rooms/<id>.lua with the rules (F.set_room) in luajit and places a domino line on every surface.
Run inside Blender (`blender -b --python tools/gen_house.py -- --render spec.json`) it is the preview's Blender side.
"""
import glob
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

try:
    import bpy  # noqa: F401
    IN_BLENDER = True
except ImportError:
    IN_BLENDER = False

if not IN_BLENDER:
    import numpy as np
    from PIL import Image
    import gen_meshes as G
    import gen_room as R
    import house_rooms as HR
    import mesh_reduce as MR

    ROOT = G.ROOT
    TEX = os.path.join(ROOT, "Assets", "Textures")
    OBJECTS = G.OBJECTS
    ROOMS_DIR = os.path.join(ROOT, "Assets", "Scripts", "rooms")
    WORK = os.path.join(tempfile.gettempdir(), "topple_house")
    PREVIEW_DIR = os.path.join(WORK, "rooms")
    LUAJIT = os.path.normpath(os.path.join(ROOT, "..", "..", "PhasmaEngine", "build-ninja-physics", "Release", "luajit.exe"))
    BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
    E, EN, MU, box, rbox_t = R.E, R.EN, R.MU, R.box, R.rbox_t
    SKIRT_T = HR.SKIRT_T
    # Names other tools already use: a house piece may not take one (the Great Hall's are hall_*).
    TAKEN = set(R.ROOM_NAMES) | set(G.MESHES) | {"hall_floor", "hall_walls", "hall_trim", "hall_wood"}


# ================================================================== geometry helpers
def wmap(Rm, side):
    """Wall coordinates (a along the wall, n into the room from its inner face, h up) to table (x, y, h)."""
    X0, X1, Y0, Y1 = Rm["x0"], Rm["x1"], Rm["y0"], Rm["y1"]
    return {"L": lambda a, n, h: (X0 + n, a, h), "R": lambda a, n, h: (X1 - n, a, h),
            "B": lambda a, n, h: (a, Y1 - n, h), "F": lambda a, n, h: (a, Y0 + n, h)}[side]


INWARD = {"L": (1, 0, 0), "R": (-1, 0, 0), "B": (0, -1, 0), "F": (0, 1, 0)}
ALONG = {"L": (0, 1, 0), "R": (0, 1, 0), "B": (1, 0, 0), "F": (1, 0, 0)}
USIGN = {"L": 1, "R": -1, "B": 1, "F": -1}      # texture u runs left to right seen from inside


def wbox(Rm, side, a0, a1, n0, n1, h0, h1, r=0.1, nseg=3):
    f = wmap(Rm, side)
    p, q = f(a0, n0, h0), f(a1, n1, h1)
    return rbox_t(min(p[0], q[0]), max(p[0], q[0]), min(p[1], q[1]), max(p[1], q[1]), h0, h1, r, nseg)


def wbox_flat(Rm, side, a0, a1, n0, n1, h0, h1, faces="xXyYhH"):
    f = wmap(Rm, side)
    p, q = f(a0, n0, h0), f(a1, n1, h1)
    return box(min(p[0], q[0]), max(p[0], q[0]), min(p[1], q[1]), max(p[1], q[1]), h0, h1, faces)


def tquad(m, pts, n, uv=((0, 0), (1, 0), (1, 1), (0, 1))):
    """A quad from four table-space corners and a table-space normal."""
    m.quad([E(*p) for p in pts], EN(*n), uv)


def obox(o, U, V, W, u0, u1, v0, v1, w0, w1):
    """A flat-shaded box in an oriented frame: origin o (table), unit axes U, V, W (table), extents along each."""
    o, U, V, W = (np.array(t, float) for t in (o, U, V, W))
    m = MU()

    def P(a, b, c):
        p = o + U * a + V * b + W * c
        return E(*p)

    for ax, (lo, hi) in enumerate(((u0, u1), (v0, v1), (w0, w1))):
        for sgn, val in ((-1, lo), (1, hi)):
            if ax == 0:
                c = [(val, v0, w0), (val, v1, w0), (val, v1, w1), (val, v0, w1)]; nn = U * sgn
            elif ax == 1:
                c = [(u0, val, w0), (u1, val, w0), (u1, val, w1), (u0, val, w1)]; nn = V * sgn
            else:
                c = [(u0, v0, val), (u1, v0, val), (u1, v1, val), (u0, v1, val)]; nn = W * sgn
            m.quad([P(*k) for k in c], EN(*nn))
    return m


def lathe_at(prof, x, y, h, segs=32, sharp=()):
    m = MU()
    m.mesh(G.moved(G.lathe(prof, segs, sharp=sharp), E(x, y, h)))
    return m


def tube_t(p0, p1, r, n=12):
    m = MU()
    m.mesh(G.tube(E(*p0), E(*p1), r, n))
    return m


def ball_t(x, y, h, r, nu=20, nv=12):
    m = MU()
    m.mesh(G.ball(E(x, y, h), r, nu, nv))
    return m


def rb(x0, x1, y0, y1, h0, h1, r=0.1, nseg=3, uvs=None):
    m = MU()
    if uvs:
        m.mesh(rbox_t(x0, x1, y0, y1, h0, h1, r, nseg), lambda v, n: _box_uv(v, n, uvs))
    else:
        m.mesh(rbox_t(x0, x1, y0, y1, h0, h1, r, nseg))
    return m


def _box_uv(v, n, S):
    x, y, h = v[0], -v[2], v[1]
    nx, ny, nh = abs(n[0]), abs(n[2]), abs(n[1])
    if nh >= nx and nh >= ny:
        return (x / S, y / S)
    if nx >= ny:
        return (y / S, h / S)
    return (x / S, h / S)


def union(*ms):
    out = MU()
    for m in ms:
        out += m
    return out


# ================================================================== furniture placement
def rot_box(b, yaw, at, z):
    """A local box (front -y) turned by yaw (a multiple of 90) and moved to at, lifted by z."""
    k = int(round(yaw / 90.0)) % 4
    pts = [(b["x0"], b["y0"]), (b["x1"], b["y1"])]
    out = []
    for x, y in pts:
        for _ in range(k):
            x, y = -y, x
        out.append((x, y))
    (xa, ya), (xb, yb) = out
    r = dict(b)
    r["x0"], r["x1"] = round(at[0] + min(xa, xb), 4), round(at[0] + max(xa, xb), 4)
    r["y0"], r["y1"] = round(at[1] + min(ya, yb), 4), round(at[1] + max(ya, yb), 4)
    if "z0" in r:
        r["z0"], r["z1"] = round(r["z0"] + z, 4), round(r["z1"] + z, 4)
    if "h" in r:
        r["h"] = round(r["h"] + z, 4)
    return r


def furniture(Rm, imported):
    """Each placement with its world solids and surfaces. imported: item -> measured local arch (or absent)."""
    out, count = [], {}
    for f in Rm["furniture"]:
        item = f["item"]
        count[item] = count.get(item, 0) + 1
        name = f"furn_{Rm['id']}_{item}" + ("" if count[item] == 1 else f"_{count[item]}")
        arch = imported.get(item) or f["arch"]
        out.append(dict(f, name=name, base=f"furn_{Rm['id']}_{item}", pending=item not in imported,
                        solids=[rot_box(b, f["yaw"], f["at"], f["z"]) for b in arch["solids"]],
                        surfaces=[rot_box(s, f["yaw"], f["at"], f["z"]) for s in arch["surfaces"]],
                        gaps=arch.get("gaps", [])))
    return out


# ================================================================== the shell
class Room:
    """Collects one room's pieces: name -> (mesh, look), plus the props' solids and surfaces."""

    def __init__(s, spec):
        s.R = spec
        s.id = spec["id"]
        s.pieces = {}
        s.solids, s.surfaces = [], []
        s.attic = "knee" in spec

    def add(s, suffix, mesh, **look):
        name = f"{s.id}_{suffix}"
        assert name not in TAKEN, "piece name already used elsewhere: " + name
        if name in s.pieces:
            s.pieces[name][0].__iadd__(mesh)
        else:
            look.setdefault("color", (1, 1, 1))
            look.setdefault("rough", 0.6)
            s.pieces[name] = (mesh, look)
        return name

    def tex(s, what):
        return f"Textures/{s.id}_{what}.png"

    # -------------------------------------------------------------- walls
    def top_at(s, side, a):
        """Height of the wall's top at a: flat, or the attic's gable."""
        R = s.R
        if not s.attic:
            return R["wall_h"]
        if side in "FB":
            return R["knee"]
        return R["knee"] + (R["y1"] - abs(a)) * s.slope()

    def slope(s):
        R = s.R
        return (R["wall_h"] - R["knee"]) / R["y1"]

    def openings(s, side):
        R = s.R
        ops = [(w["a0"], w["a1"], w["h0"], w["h1"]) for w in R.get("windows", []) if w["side"] == side]
        ops += [(w["a0"], w["a1"], w["h0"], w["h1"]) for w in R.get("fanlights", []) if w["side"] == side]
        ops += [(d["a0"], d["a1"], 0.0, d["h1"]) for d in R.get("doors", []) if d["side"] == side]
        return ops

    def wall(s, side):
        R = s.R
        m = MU()
        f = wmap(R, side)
        A0, A1 = (R["y0"], R["y1"]) if side in "LR" else (R["x0"], R["x1"])
        ops = s.openings(side)
        cuts = {A0, A1} | {o[0] for o in ops} | {o[1] for o in ops}
        if s.attic and side in "LR":
            cuts.add(0.0)
        cuts = sorted(cuts)
        kind = R["wall"]["kind"]
        brick = s.attic and side in "LR"
        SU = 16.0 if s.attic else 24.0
        VS = 16.0 if s.attic else R["wall_h"]

        def uv(a, h):
            return (USIGN[side] * a / SU, h / VS)

        def piece(a0, a1, h0, h1a, h1b):
            pts = [(a0, h0), (a1, h0), (a1, h1b), (a0, h1a)]
            tquad(m, [f(a, 0.0, h) for a, h in pts], INWARD[side], [uv(a, h) for a, h in pts])

        for s0, s1 in zip(cuts, cuts[1:]):
            if s1 - s0 < 1e-6:
                continue
            t0, t1 = s.top_at(side, s0), s.top_at(side, s1)
            cover = sorted([o for o in ops if o[0] <= s0 + 1e-6 and o[1] >= s1 - 1e-6], key=lambda o: o[2])
            h = 0.0
            for _, _, h0, h1 in cover:
                if h0 > h + 1e-6:
                    piece(s0, s1, h, h0, h0)
                h = max(h, h1)
            if min(t0, t1) > h + 1e-6:
                piece(s0, s1, h, t0, t1)
        # The reveals: the wall's thickness around a window or fanlight.
        d = 1.4
        for w in R.get("windows", []) + R.get("fanlights", []):
            if w["side"] != side:
                continue
            a0, a1, h0, h1 = w["a0"], w["a1"], w["h0"], w["h1"]
            al = np.array(ALONG[side], float)
            tquad(m, [f(a0, -d, h0), f(a0, 0, h0), f(a0, 0, h1), f(a0, -d, h1)], tuple(al), [uv(a0, h0)] * 4)
            tquad(m, [f(a1, -d, h0), f(a1, 0, h0), f(a1, 0, h1), f(a1, -d, h1)], tuple(-al), [uv(a1, h0)] * 4)
            tquad(m, [f(a0, -d, h1), f(a1, -d, h1), f(a1, 0, h1), f(a0, 0, h1)], (0, 0, -1), [uv(a0, h1)] * 4)
        tex = s.tex("brick" if brick else ("boards" if s.attic else "wall"))
        s.add("wall_" + side, m, tex=tex, rough=0.92 if kind not in ("kitchen", "bath") else 0.5)

    def floor(s):
        R = s.R
        S = R["floor"]["S"]
        m = MU()
        X0, X1, Y0, Y1 = R["x0"], R["x1"], R["y0"], R["y1"]
        m.quad([E(X0, Y0, 0), E(X1, Y0, 0), E(X1, Y1, 0), E(X0, Y1, 0)], EN(0, 0, 1),
               [(X0 / S, Y0 / S), (X1 / S, Y0 / S), (X1 / S, Y1 / S), (X0 / S, Y1 / S)])
        glossy = {"checker": 0.3, "mosaic": 0.32, "carpet": 0.98, "pine": 0.6}.get(R["floor"]["kind"], 0.4)
        s.add("flooring", m, tex=s.tex("flooring"), rough=glossy)

    def ceiling(s):
        R = s.R
        if s.attic:
            return s.roof()
        m = MU()
        X0, X1, Y0, Y1, H = R["x0"], R["x1"], R["y0"], R["y1"], R["wall_h"]
        m.quad([E(X0 - 2, Y0 - 2, H), E(X0 - 2, Y1 + 2, H), E(X1 + 2, Y1 + 2, H), E(X1 + 2, Y0 - 2, H)], EN(0, 0, -1))
        s.add("ceiling", m, color=R["ceiling"], rough=0.9)

    # -------------------------------------------------------------- the attic's roof
    def roof_frame(s, back):
        """Origin at the eave (inner face), U along x, V up the slope toward the ridge, W into the room (normal)."""
        R = s.R
        Y = R["y1"] if back else R["y0"]
        rise, run = R["wall_h"] - R["knee"], R["y1"]
        L = math.hypot(rise, run)
        sy = -1 if back else 1
        V = (0.0, sy * run / L, rise / L)
        W = (0.0, sy * rise / L, -run / L)
        return (0.0, Y, R["knee"]), (1.0, 0.0, 0.0), V, W, L

    def roof(s):
        R = s.R
        m = MU()
        S = 16.0
        k = s.slope()
        for back in (False, True):
            o, U, V, W, L = s.roof_frame(back)
            o, U, V, W = (np.array(t, float) for t in (o, U, V, W))
            holes = [(sl["x0"], sl["x1"], (sl["h0"] - R["knee"]) / k, (sl["h1"] - R["knee"]) / k) for sl in R.get("skylights", [])] if back else []
            # v measured along y from the eave; convert to slope distance.
            holes = [(x0, x1, v0 * L / R["y1"], v1 * L / R["y1"]) for x0, x1, v0, v1 in holes]
            X0, X1 = R["x0"] - 0.5, R["x1"] + 0.5
            cuts = sorted({X0, X1} | {h[0] for h in holes} | {h[1] for h in holes})

            def quad(u0, u1, v0, v1):
                P = [o + U * u0 + V * v0, o + U * u1 + V * v0, o + U * u1 + V * v1, o + U * u0 + V * v1]
                uv = [(u0 / S, v0 / S), (u1 / S, v0 / S), (u1 / S, v1 / S), (u0 / S, v1 / S)]
                tquad(m, [tuple(p) for p in P], tuple(W), uv)

            for u0, u1 in zip(cuts, cuts[1:]):
                hs = sorted([h for h in holes if h[0] <= u0 + 1e-6 and h[1] >= u1 - 1e-6], key=lambda h: h[2])
                v = 0.0
                for _, _, v0, v1 in hs:
                    quad(u0, u1, v, v0)
                    v = v1
                quad(u0, u1, v, L + 0.4)
        s.add("roof", m, tex=s.tex("boards"), rough=0.85)
        # Skylight: frame in the slope's own frame, the pane just inside the roof plane.
        o, U, V, W, L = s.roof_frame(True)
        fr, gl = MU(), MU()
        for sl in R.get("skylights", []):
            v0, v1 = (sl["h0"] - R["knee"]) / k * L / R["y1"], (sl["h1"] - R["knee"]) / k * L / R["y1"]
            x0, x1 = sl["x0"], sl["x1"]
            t = 1.0
            fr += obox(o, U, V, W, x0 - t, x0, v0 - t, v1 + t, -0.6, 1.4)
            fr += obox(o, U, V, W, x1, x1 + t, v0 - t, v1 + t, -0.6, 1.4)
            fr += obox(o, U, V, W, x0, x1, v0 - t, v0, -0.6, 1.4)
            fr += obox(o, U, V, W, x0, x1, v1, v1 + t, -0.6, 1.4)
            fr += obox(o, U, V, W, (x0 + x1) / 2 - 0.25, (x0 + x1) / 2 + 0.25, v0, v1, -0.4, 0.3)
            P = [np.array(o) + np.array(U) * a + np.array(V) * b + np.array(W) * (-0.3) for a, b in ((x0, v0), (x1, v0), (x1, v1), (x0, v1))]
            tquad(gl, [tuple(p) for p in P], W)
        if fr.V:
            s.add("skylight", fr, color=(0.42, 0.3, 0.19), rough=0.6)
            s.add("glass", gl, color=(1, 1, 1), rough=0.05, emis=(0.9, 0.9, 0.9), emis_tex="Textures/room_sky.png", transmission=1.0)

    def rafters(s, every):
        """Rafters under both slopes, a ridge beam, collar ties and purlins (the front slope's hide with that side)."""
        R = s.R
        k = s.slope()
        front, back, ties = MU(), MU(), MU()
        xs = [R["x0"] + every / 2 + i * every for i in range(int(round((R["x1"] - R["x0"]) / every)))]
        for back_side in (False, True):
            o, U, V, W, L = s.roof_frame(back_side)
            dst = back if back_side else front
            for x in xs:
                dst += obox(o, U, V, W, x - 0.7, x + 0.7, -0.5, L - 1.2, 0.0, 2.4)
            for frac in (0.42,):
                dst += obox(o, U, V, W, R["x0"] + 0.1, R["x1"] - 0.1, L * frac - 1.0, L * frac + 1.0, 2.4, 4.0)
        H = R["wall_h"]
        ties += box(R["x0"] + 0.1, R["x1"] - 0.1, -1.0, 1.0, H - 4.0, H - 0.6)
        ht = 44.0
        yt = (H - ht) / k
        for x in xs[::2]:
            ties += box(x - 0.8, x + 0.8, -yt - 1.0, yt + 1.0, ht - 1.8, ht)
        s.add("beams", back, color=(0.36, 0.24, 0.14), rough=0.75)
        s.add("beams_F", front, color=(0.36, 0.24, 0.14), rough=0.75, group="F")
        s.add("ties", ties, color=(0.33, 0.22, 0.13), rough=0.75)
        s.collar_h = ht - 1.8

    # -------------------------------------------------------------- trim, windows, doors
    def skirting(s, side):
        R = s.R
        if R.get("skirting", True) is False:
            return MU()
        A0, A1 = (R["y0"], R["y1"]) if side in "LR" else (R["x0"], R["x1"])
        runs = [(A0, A1)]
        for d in R.get("doors", []):
            if d["side"] != side:
                continue
            nxt = []
            for a0, a1 in runs:
                if d["a0"] - 1.3 > a0:
                    nxt.append((a0, min(a1, d["a0"] - 1.3)))
                if d["a1"] + 1.3 < a1:
                    nxt.append((max(a0, d["a1"] + 1.3), a1))
            runs = nxt
        m = MU()
        hh = 2.0 if s.attic else 2.4
        for a0, a1 in runs:
            m.mesh(wbox(R, side, a0, a1, -0.2, SKIRT_T, 0.0, hh, 0.12))
        return m

    def door(s, d):
        R = s.R
        side = d["side"]
        a0, a1, h1 = d["a0"], d["a1"], d["h1"]
        case, leaf, knob, glass = MU(), MU(), MU(), MU()
        case.mesh(wbox(R, side, a0 - 1.3, a0, -0.2, 0.6, 0, h1 + 1.3, 0.15))
        case.mesh(wbox(R, side, a1, a1 + 1.3, -0.2, 0.6, 0, h1 + 1.3, 0.15))
        case.mesh(wbox(R, side, a0 - 1.3, a1 + 1.3, -0.2, 0.6, h1, h1 + 1.3, 0.15))
        if d.get("glazed"):
            st = 2.2
            leaf.mesh(wbox(R, side, a0, a0 + st, -0.1, 0.4, 0, h1, 0.06))
            leaf.mesh(wbox(R, side, a1 - st, a1, -0.1, 0.4, 0, h1, 0.06))
            leaf.mesh(wbox(R, side, a0 + st, a1 - st, -0.1, 0.4, 0, 8.0, 0.06))
            leaf.mesh(wbox(R, side, a0 + st, a1 - st, -0.1, 0.4, 19.0, 22.5, 0.06))
            leaf.mesh(wbox(R, side, a0 + st, a1 - st, -0.1, 0.4, h1 - 2.4, h1, 0.06))
            leaf.mesh(wbox(R, side, a0 + st + 1.0, a1 - st - 1.0, 0.0, 0.62, 9.2, 17.8, 0.12))     # raised panel
            leaf.mesh(wbox(R, side, a0 + st, a1 - st, -0.1, 0.1, 8.0, 19.0, 0.02))                # panel back
            am = (a0 + a1) / 2
            leaf.mesh(wbox(R, side, am - 0.3, am + 0.3, 0.0, 0.5, 22.5, h1 - 2.4, 0.06))          # glazing bar
            leaf.mesh(wbox(R, side, a0 + st, a1 - st, 0.0, 0.5, (22.5 + h1 - 2.4) / 2 - 0.3, (22.5 + h1 - 2.4) / 2 + 0.3, 0.06))
            f = wmap(R, side)
            P = [f(a0 + st, 0.15, 22.5), f(a1 - st, 0.15, 22.5), f(a1 - st, 0.15, h1 - 2.4), f(a0 + st, 0.15, h1 - 2.4)]
            tquad(glass, P, INWARD[side])
            # Brass: letter plate on the middle rail, a knob, a knocker ring.
            knob.mesh(wbox(R, side, am - 3.0, am + 3.0, 0.4, 0.62, 20.0, 21.6, 0.08))
            kx = a1 - st - 0.2 if side in "BL" else a0 + st + 0.2
            knob.mesh(G.ball(E(*f(kx, 1.0, 18.0)), 0.6, 20, 12))
            knob.mesh(G.tube(E(*f(kx, 0.4, 18.0)), E(*f(kx, 1.0, 18.0)), 0.22, 10))
            knob.mesh(G.torus(1.1, 0.16, 32, 8, E(*f(am, 0.75, 30.0)), G.rot("z", math.pi / 2) if side in "LR" else G.rot("x", math.pi / 2)))
        else:
            leaf.mesh(wbox(R, side, a0, a1, -0.1, 0.35, 0, h1, 0.05))
            for (p0, p1, q0, q1) in ((a0 + 1.4, a1 - 1.4, 22.5, h1 - 1.6), (a0 + 1.4, a1 - 1.4, 2.5, 20.0)):
                leaf.mesh(wbox(R, side, p0, p1, 0.3, 0.6, q0, q1, 0.1))
            f = wmap(R, side)
            ka = a1 - 2.2 if side in "LB" else a0 + 2.2
            knob.mesh(G.ball(E(*f(ka, 0.9, 19.0)), 0.55, 20, 12))
            knob.mesh(G.tube(E(*f(ka, 0.4, 19.0)), E(*f(ka, 0.9, 19.0)), 0.2, 10))
        return case, leaf, knob, glass

    def window(s, w, fan=False):
        R = s.R
        side = w["side"]
        a0, a1, h0, h1 = w["a0"], w["a1"], w["h0"], w["h1"]
        m, gl = MU(), MU()
        f_ = 1.1
        m.mesh(wbox(R, side, a0 - f_, a0 + 0.15, -0.9, 0.25, h0 - f_, h1 + f_, 0.12))
        m.mesh(wbox(R, side, a1 - 0.15, a1 + f_, -0.9, 0.25, h0 - f_, h1 + f_, 0.12))
        m.mesh(wbox(R, side, a0 - f_, a1 + f_, -0.9, 0.25, h1 - 0.15, h1 + f_, 0.12))
        if fan:
            m.mesh(wbox(R, side, a0 - f_, a1 + f_, -0.9, 0.25, h0 - f_, h0 + 0.15, 0.12))
            for kk in (1, 2, 3):
                a = a0 + (a1 - a0) * kk / 4
                m.mesh(wbox(R, side, a - 0.2, a + 0.2, -0.75, -0.35, h0, h1, 0.06))
        else:
            m.mesh(wbox(R, side, a0 - 2.0, a1 + 2.0, -0.4, 1.9, h0 - 0.9, h0 + 0.15, 0.18))   # sill
            hm = (h0 + h1) / 2
            m.mesh(wbox(R, side, a0, a1, -0.75, -0.35, hm - 0.5, hm + 0.5, 0.1))
            nb = max(1, int(round((a1 - a0) / 7.0)) - 1)
            for kk in range(1, nb + 1):
                a = a0 + (a1 - a0) * kk / (nb + 1)
                m.mesh(wbox(R, side, a - 0.22, a + 0.22, -0.75, -0.35, h0, h1, 0.06))
            for hh in (h0 + (hm - h0) / 2, hm + (h1 - hm) / 2):
                m.mesh(wbox(R, side, a0, a1, -0.75, -0.35, hh - 0.2, hh + 0.2, 0.06))
        fm = wmap(R, side)
        tquad(gl, [fm(a0, -0.6, h0), fm(a1, -0.6, h0), fm(a1, -0.6, h1), fm(a0, -0.6, h1)], INWARD[side])
        return m, gl

    def curtains(s, w, color):
        """Two gathered curtains either side of the window on a brass rod (as the living room's)."""
        R = s.R
        side = w["side"]
        f = wmap(R, side)
        top, bot = w["h1"] + 4.5, 2.0
        cloth, rod = MU(), MU()
        nin = np.array(INWARD[side], float)
        al = np.array(ALONG[side], float)
        for ya, yb in ((w["a0"] - 7.5, w["a0"] + 1.0), (w["a1"] - 1.0, w["a1"] + 7.5)):
            nu, nv = 40, 24
            V, N, F = [], [], []
            for j in range(nv + 1):
                hh = bot + (top - bot) * j / nv
                for i in range(nu + 1):
                    u = i / nu
                    a = ya + (yb - ya) * u
                    ph = u * 2 * math.pi * 5
                    amp = 0.55 + 0.25 * (1 - j / nv)
                    n = 1.6 + amp * math.sin(ph)
                    dn = amp * math.cos(ph) * 2 * math.pi * 5 / (yb - ya)
                    nt = nin - al * dn
                    nt /= np.linalg.norm(nt)
                    V.append(E(*f(a, n, hh))); N.append(EN(*nt))
            for j in range(nv):
                for i in range(nu):
                    q = j * (nu + 1) + i
                    F += [(q, q + 1, q + nu + 2), (q, q + nu + 2, q + nu + 1)]
            cloth.mesh(G.M().add(V, N, F))
            cloth.mesh(G.M().add(V, [-np.array(n) for n in N], [(a, c, b) for a, b, c in F]))
        hr = w["h1"] + 4.8
        rod.mesh(G.tube(E(*f(w["a0"] - 9.0, 2.0, hr)), E(*f(w["a1"] + 9.0, 2.0, hr)), 0.25, 16))
        for a in (w["a0"] - 9.4, w["a1"] + 9.4):
            rod.mesh(G.ball(E(*f(a, 2.0, hr)), 0.6, 20, 12))
        for a in (w["a0"] - 8.0, w["a1"] + 8.0):
            rod.mesh(G.tube(E(*f(a, 0.0, hr)), E(*f(a, 2.0, hr)), 0.15, 10))
        s.add("curtains", cloth, color=color, rough=0.95)
        s.add("brass", rod, color=(0.86, 0.62, 0.3), rough=0.25, metal=1.0)

    def shell(s):
        R = s.R
        for side in "LRBF":
            s.wall(side)
        s.floor()
        s.ceiling()
        trim = {side: s.skirting(side) for side in "LRBF"}
        knobs = {side: MU() for side in "LRBF"}
        glass = MU()
        for d in R.get("doors", []):
            case, leaf, knob, gl = s.door(d)
            trim[d["side"]] += case
            knobs[d["side"]] += knob
            glass += gl
            s.add("door_" + d["side"], leaf, color=d.get("color", R["trim"]), rough=0.35, group=d["side"])
        for side in "LRBF":
            if trim[side].V:
                s.add("trim_" + side, trim[side], color=R["trim"], rough=0.35, group=side)
            if knobs[side].V:
                s.add("knob_" + side, knobs[side], color=(0.86, 0.62, 0.3), rough=0.25, metal=1.0, group=side)
        frames = MU()
        for w in R.get("windows", []):
            m, gl = s.window(w)
            frames += m
            if w.get("frosted"):
                s.add("frosted", gl, color=(1, 1, 1), rough=0.3, emis=(0.75, 0.8, 0.82), transmission=0.85)
            else:
                glass += gl
            if w.get("curtains"):
                s.curtains(w, w["curtains"])
        for w in R.get("fanlights", []):
            m, gl = s.window(w, fan=True)
            frames += m
            glass += gl
        if frames.V:
            s.add("window", frames, color=R["trim"] if not s.attic else (0.42, 0.3, 0.19), rough=0.35)
        if glass.V:
            s.add("glass", glass, color=(1, 1, 1), rough=0.05, emis=(0.9, 0.9, 0.9), emis_tex="Textures/room_sky.png", transmission=1.0)

    # -------------------------------------------------------------- props
    def solid(s, name, x0, x1, y0, y1, z0, z1, owner):
        s.solids.append(dict(name=name, x0=round(x0, 4), x1=round(x1, 4), y0=round(y0, 4), y1=round(y1, 4), z0=round(z0, 4), z1=round(z1, 4), owner=owner))

    def surface(s, name, x0, x1, y0, y1, h, edge=True, board=False, cover=False):
        d = dict(name=name, x0=round(x0, 4), x1=round(x1, 4), y0=round(y0, 4), y1=round(y1, 4), h=round(h, 4), edge=edge)
        if board:
            d["board"] = True
        if cover:
            d["cover"] = True
        s.surfaces.append(d)

    def props(s):
        for p in s.R.get("props", []):
            getattr(s, "p_" + p["kind"])(p)

    def p_rug(s, p):
        h = p.get("h", 0.12)
        w, d = p["x1"] - p["x0"], p["y1"] - p["y0"]

        def uv(v, n):
            x, y = v[0], -v[2]
            return ((x - p["x0"]) / w, (y - p["y0"]) / d)

        m = MU()
        m.mesh(rbox_t(p["x0"], p["x1"], p["y0"], p["y1"], -0.05, h, min(0.08, h * 0.6), 2), uv)
        s.add("rug", m, tex=s.tex("rug"), rough=0.97)
        s.surface(p["name"], p["x0"], p["x1"], p["y0"], p["y1"], h, edge=False, cover=True)

    def p_parcels(s, p):
        card, tape = MU(), MU()
        for i, (x0, x1, y0, y1, z0, z1) in enumerate(p["boxes"]):
            card += rb(x0, x1, y0, y1, z0, z1, 0.12, 2)
            xm = (x0 + x1) / 2
            tape += rb(xm - 0.8, xm + 0.8, y0 - 0.02, y1 + 0.02, z1 - 0.01, z1 + 0.03, 0.01, 1)
            tape += rb(xm - 0.8, xm + 0.8, y0 - 0.03, y0 + 0.0, z0 + 0.4, z1, 0.01, 1)
            s.solid("parcel", x0, x1, y0, y1, z0, z1, "parcels")
            s.surface("parcel %d" % (i + 1), x0, x1, y0, y1, z1, edge=True)
        s.add("parcels", card, color=(0.62, 0.45, 0.28), rough=0.85)
        s.add("tape", tape, color=(0.78, 0.64, 0.42), rough=0.4)

    def p_doorbell(s, p):
        x0, x1, y0, y1, h = p["x0"], p["x1"], p["y0"], p["y1"], p["h"]
        wood, brass = MU(), MU()
        wood += rb(x0, x1, y0, y1, 0.0, h, 0.2)
        wood += rb(x0 - 0.2, x1 + 0.2, y0 - 0.2, y1, 0.0, 0.5, 0.12)
        xm, ym = (x0 + x1) / 2, (y0 + y1) / 2
        dome = [(0, 1.9), (0.2, 1.88), (0.5, 1.78), (0.8, 1.5), (0.98, 1.1), (1.08, 0.66), (1.2, 0.38), (1.17, 0.3), (0.95, 0.5), (0.7, 1.1), (0.4, 1.6), (0, 1.75)]
        brass.mesh(G.moved(G.lathe(G.smooth_profile(dome, 4), 48), E(xm, ym, h)))
        brass.mesh(G.tube(E(xm, ym, h + 1.85), E(xm, ym, h + 2.25), 0.08, 12))
        brass.mesh(G.ball(E(xm, ym, h + 2.3), 0.16, 16, 10))
        # The bell push on the front, at a domino's height, in a round brass rose.
        brass.mesh(G.tube(E(xm, y0, 1.4), E(xm, y0 - 0.18, 1.4), 0.55, 24))
        brass += tube_t((xm, y0 - 0.18, 1.4), (xm, y0 - 0.42, 1.4), 0.26)
        s.add("bellbox", wood, color=(0.3, 0.14, 0.07), rough=0.38, goal=True)
        s.add("bell", brass, color=(0.86, 0.62, 0.3), rough=0.22, metal=1.0, goal=True)
        s.solid("doorbell", x0 - 0.2, x1 + 0.2, y0 - 0.45, y1, 0.0, h, "doorbell")
        s.solid("doorbell", xm - 1.25, xm + 1.25, ym - 1.25, ym + 1.25, h, h + 2.4, "doorbell")

    def p_toaster(s, p):
        R.TOASTER = dict(x0=p["x0"], x1=p["x1"], y0=p["y0"], y1=p["y1"], h0=p["h0"], h1=p["h1"])
        s.add("toaster", R.goal_toaster(), color=(0.88, 0.88, 0.9), rough=0.16, metal=1.0, goal=True)
        s.add("toaster_trim", R.goal_toaster_trim(), color=(0.04, 0.04, 0.045), rough=0.4, goal=True)
        s.add("toast", R.goal_toast(), color=(0.62, 0.38, 0.16), rough=0.85, goal=True)
        s.solid("toaster", p["x0"], p["x1"] + 0.34, p["y0"], p["y1"], p["h0"], p["h1"], "toaster")

    def p_pendant(s, p):
        x, y = p["at"]
        H = s.R["wall_h"]
        h = p["h"]
        st = p["style"]
        cord, metal, glow = MU(), MU(), MU()
        cord += tube_t((x, y, H), (x, y, h + 3.2), 0.1, 8)
        metal += lathe_at([(0, 0), (1.3, 0), (1.3, 0.3), (0.3, 0.6), (0, 0.6)], x, y, H - 0.6, 32)
        if st == "lantern":       # a hexagonal brass lantern with glass sides
            metal += lathe_at([(0, 0), (0.5, 0), (0.5, 1.2), (0, 1.2)], x, y, h + 2.0, 16)
            for k in range(6):
                a = k * math.pi / 3
                metal += tube_t((x + 2.0 * math.cos(a), y + 2.0 * math.sin(a), h - 3.0), (x + 2.0 * math.cos(a), y + 2.0 * math.sin(a), h + 2.0), 0.12, 8)
            metal += lathe_at([(0, 0), (2.4, 0), (2.4, 0.35), (0, 0.35)], x, y, h - 3.3, 6)
            metal += lathe_at([(0, 0), (2.4, 0), (1.0, 1.2), (0, 1.2)], x, y, h + 1.8, 6)
            glow += lathe_at([(0, 0), (1.95, 0), (1.95, 4.9), (0, 4.9)], x, y, h - 2.95, 6)
            gl = (1.0, 0.85, 0.6)
        elif st == "enamel":      # a green enamel shade over a warm bulb
            metal += lathe_at(G.smooth_profile([(4.2, 0.0), (2.0, 1.4), (0.7, 2.6), (0.5, 3.2)], 4) + [(0.4, 3.2), (0.6, 2.6), (1.9, 1.3), (4.0, 0.0)], x, y, h, 48)
            glow += ball_t(x, y, h + 0.6, 1.0)
            gl = (1.0, 0.82, 0.55)
        elif st == "chandelier":  # a brass stem, five curved arms with candle shades
            metal += tube_t((x, y, h + 3.2), (x, y, h - 1.0), 0.25, 12)
            metal += ball_t(x, y, h - 1.2, 0.9)
            for k in range(5):
                a = k * 2 * math.pi / 5
                px, py = x + 6.0 * math.cos(a), y + 6.0 * math.sin(a)
                pts = [E(x + r * math.cos(a), y + r * math.sin(a), h - 1.2 - 1.6 * math.sin(math.pi * r / 6.0) + (r / 6.0) * 1.2) for r in np.linspace(0.5, 6.0, 12)]
                metal.mesh(G.sweep(pts, 0.14, 8))
                metal += lathe_at([(0, 0), (0.6, 0), (0.7, 0.3), (0.3, 0.5), (0, 0.5)], px, py, h - 0.4, 16)
                glow += lathe_at([(1.3, 0.0), (0.7, 2.0), (0.68, 2.0), (1.28, 0.0)], px, py, h + 0.1, 24)
            gl = (1.0, 0.8, 0.5)
        elif st == "star":        # a paper globe
            glow += ball_t(x, y, h, 3.0, 32, 18)
            gl = (1.0, 0.9, 0.7)
        elif st == "globe":       # an opal glass globe on a short brass gallery
            metal += lathe_at([(0, 0), (1.2, 0), (1.2, 0.8), (0, 0.8)], x, y, h + 2.4, 24)
            glow += ball_t(x, y, h, 2.6, 32, 18)
            gl = (1.0, 0.92, 0.78)
        s.add("cord", cord, color=(0.06, 0.05, 0.05), rough=0.6)
        if st == "enamel":
            s.add("shade", metal, color=(0.2, 0.44, 0.36), rough=0.3)
        else:
            s.add("brass", metal, color=(0.86, 0.62, 0.3), rough=0.25, metal=1.0)
        s.add("glow", glow, color=(0.95, 0.9, 0.8), rough=0.6, emis=gl)

    def p_bulb(s, p):
        x, y = p["at"]
        H = s.R["wall_h"]
        h = p["h"]
        cord, glow, cap = MU(), MU(), MU()
        cord += tube_t((x, y, H - 1.0), (x, y, h + 1.6), 0.09, 8)
        cap += lathe_at([(0, 0), (0.42, 0), (0.42, 0.9), (0.15, 1.1), (0, 1.1)], x, y, h + 0.6, 20)
        glow += lathe_at(G.smooth_profile([(0, -1.2), (0.6, -1.05), (0.85, -0.5), (0.6, 0.3), (0.38, 0.65), (0, 0.65)], 4), x, y, h, 32)
        s.add("cord", cord, color=(0.06, 0.05, 0.05), rough=0.6)
        s.add("brass", cap, color=(0.86, 0.62, 0.3), rough=0.25, metal=1.0)
        s.add("glow", glow, color=(1, 0.95, 0.85), rough=0.2, emis=(1.0, 0.72, 0.36))

    def p_art(s, p):
        side = p["side"]
        R_ = s.R
        frames = MU()
        f = wmap(R_, side)
        for i, (a0, a1, h0, h1, which) in enumerate(p["frames"]):
            fr = 0.9
            frames.mesh(wbox(R_, side, a0 - fr, a1 + fr, 0.0, 0.5, h1, h1 + fr, 0.15))
            frames.mesh(wbox(R_, side, a0 - fr, a1 + fr, 0.0, 0.5, h0 - fr, h0, 0.15))
            frames.mesh(wbox(R_, side, a0 - fr, a0, 0.0, 0.5, h0, h1, 0.15))
            frames.mesh(wbox(R_, side, a1, a1 + fr, 0.0, 0.5, h0, h1, 0.15))
            c = MU()
            P = [f(a0, 0.25, h0), f(a1, 0.25, h0), f(a1, 0.25, h1), f(a0, 0.25, h1)]
            uv = [(0, 0), (1, 0), (1, 1), (0, 1)] if USIGN[side] > 0 else [(1, 0), (0, 0), (0, 1), (1, 1)]
            tquad(c, P, INWARD[side], uv)
            s.add(f"art_{side}{i + 1}", c, tex=f"Textures/room_art{which + 1}.png", rough=0.8, group=side)
        s.add("frames_" + side, frames, color=(0.62, 0.45, 0.18) if s.id in ("dining", "hall") else (0.16, 0.08, 0.04),
              rough=0.35, metal=0.6 if s.id in ("dining", "hall") else 0.0, group=side)

    def p_shelf(s, p):
        R_ = s.R
        side, a0, a1, h, dp = p["side"], p["a0"], p["a1"], p["h"], p["depth"]
        wood, iron, items = MU(), MU(), {}
        wood.mesh(wbox(R_, side, a0, a1, 0.0, dp, h - 0.6, h, 0.1))
        for a in (a0 + 1.5, a1 - 1.5):
            iron.mesh(wbox(R_, side, a - 0.2, a + 0.2, 0.0, dp - 0.6, h - 3.0, h - 0.6, 0.05))
            iron.mesh(wbox(R_, side, a - 0.2, a + 0.2, 0.0, 0.3, h - 3.0, h - 0.6, 0.05))
        f = wmap(R_, side)
        rng = np.random.default_rng(int(h * 10 + a0))
        if p["items"] == "jars":
            a = a0 + 1.0
            cols = ["jar_glass", "jar_lid"]
            for c in cols:
                items[c] = MU()
            while a < a1 - 2.0:
                r = float(rng.uniform(0.9, 1.3))
                hh = float(rng.uniform(2.6, 4.4))
                a += r
                x, y, _ = f(a, dp / 2, 0)
                items["jar_glass"] += lathe_at(G.smooth_profile([(0, 0), (r, 0), (r, hh * 0.85), (r * 0.8, hh), (0, hh)], 3), x, y, h, 24)
                items["jar_lid"] += lathe_at([(0, 0), (r * 0.86, 0), (r * 0.86, 0.5), (0, 0.5)], x, y, h + hh, 24)
                a += r + 0.5
            s.add("jars", items["jar_glass"], color=(0.78, 0.66, 0.42), rough=0.12)
            s.add("lids", items["jar_lid"], color=(0.55, 0.12, 0.08), rough=0.4, group=side)
        else:
            pal = [("books_red", (0.42, 0.07, 0.05)), ("books_navy", (0.06, 0.1, 0.22)), ("books_green", (0.14, 0.26, 0.16)),
                   ("books_tan", (0.55, 0.4, 0.22))]
            for nm, _ in pal:
                items[nm] = MU()
            a = a0 + 0.6
            while a < a1 - 1.0:
                t = float(rng.uniform(0.7, 1.4))
                hh = float(rng.uniform(5.2, 7.2))
                d_ = float(rng.uniform(3.0, min(3.8, dp - 0.1)))
                k = int(rng.integers(0, len(pal)))
                items[pal[k][0]].mesh(wbox(R_, side, a, a + t, 0.15, 0.15 + d_, h, h + hh, 0.06, 2))
                a += t + 0.03
                if rng.random() < 0.08 and a < a1 - 6:
                    a += 2.0
            for nm, col in pal:
                if items[nm].V:
                    s.add(nm, items[nm], color=col, rough=0.55, group=side)
        s.add("shelf", wood, color=(0.32, 0.19, 0.1), rough=0.45, group=side)
        s.add("iron", iron, color=(0.06, 0.06, 0.06), rough=0.5, group=side)

    def p_glass_tower(s, p):
        x, y, h, n = p["x"], p["y"], p["h"], p["tiers"]
        glasses, tray = MU(), MU()
        gh, plate = 1.6, 0.2
        z = h
        prof = G.smooth_profile([(0, 0), (0.62, 0), (0.62, 0.08), (0.7, gh * 0.5), (0.76, gh), (0.7, gh), (0.64, gh * 0.5), (0.55, 0.14), (0, 0.14)], 2)
        for t in range(n):
            for dx in (-2.0, 2.0):
                for dy in (-2.0, 2.0):
                    glasses += lathe_at(prof, x + dx, y + dy, z, 24)
            z += gh
            if t < n - 1:
                glasses += rb(x - 3.0, x + 3.0, y - 3.0, y + 3.0, z, z + plate, 0.06, 1)
                z += plate
        tray += rb(x - 3.0, x + 3.0, y - 3.0, y + 3.0, z, z + 0.4, 0.12)
        s.add("glasses", glasses, color=(0.92, 0.95, 0.96), rough=0.04, transmission=0.9, trap="fragile glass tower")
        s.add("tray", tray, color=(0.3, 0.16, 0.08), rough=0.35, trap="fragile glass tower")

    def p_block_bridge(s, p):
        x0, x1, y0, y1, h = p["x0"], p["x1"], p["y0"], p["y1"], p["h"]
        cols = {"blocks_red": (0.62, 0.12, 0.08), "blocks_yellow": (0.85, 0.62, 0.12), "blocks_blue": (0.12, 0.28, 0.6), "blocks_green": (0.2, 0.46, 0.22)}
        ms = {k: MU() for k in cols}
        names = list(cols)
        pl = 0.6
        bh = (h - pl) / 4
        k = 0
        for tx0 in (x0, x1 - 4.0):
            for lvl in range(4):
                if lvl % 2 == 0:
                    parts = [(tx0, tx0 + 4.0, y0, (y0 + y1) / 2 - 0.02), (tx0, tx0 + 4.0, (y0 + y1) / 2 + 0.02, y1)]
                else:
                    parts = [(tx0, tx0 + 1.98, y0, y1), (tx0 + 2.02, tx0 + 4.0, y0, y1)]
                for a0, a1, b0, b1 in parts:
                    ms[names[k % 4]] += rb(a0, a1, b0, b1, lvl * bh, (lvl + 1) * bh - 0.01, 0.12, 2)
                    k += 1
        # Toy blocks on the bridge's ends, an arch under its middle.
        for kk, nm in enumerate(names):
            s.add(nm, ms[nm], color=cols[nm], rough=0.45, trap="fragile block tower holding a bridge")
        plank = rb(x0, x1, y0, y1, h - pl, h, 0.1, 2)
        s.add("bridge", plank, color=(0.78, 0.6, 0.38), rough=0.5, trap="fragile block tower holding a bridge")

    def p_track(s, p):
        """A wooden toy railway: an oval of two straights and two half circles, grooved for the wheels."""
        cx, cy, rx, ry, h0 = p["cx"], p["cy"], p["rx"], p["ry"], p["h"]
        w, t = 2.0, 0.25
        wood, groove = MU(), MU()
        xa, xb = cx - (rx - ry), cx + (rx - ry)
        for yy in (cy - ry, cy + ry):
            wood += rb(xa, xb, yy - w / 2, yy + w / 2, h0, h0 + t, 0.06, 1)
            for g in (-0.5, 0.5):
                groove += box(xa, xb, yy + g - 0.12, yy + g + 0.12, h0 + t, h0 + t + 0.006, "H")
            s.surface("track", xa, xb, yy - w / 2, yy + w / 2, h0 + t, edge=True)
            s.solid("track", xa, xb, yy - w / 2, yy + w / 2, h0, h0 + t, "track")
        for xc, sgn in ((xb, 1), (xa, -1)):
            nseg = 24
            for i in range(nseg):
                a0 = -math.pi / 2 + math.pi * i / nseg
                a1 = -math.pi / 2 + math.pi * (i + 1) / nseg
                for rr0, rr1, z0, z1, dst in ((ry - w / 2, ry + w / 2, h0, h0 + t, wood),):
                    pts = []
                    for a in (a0, a1):
                        ca, sa = math.cos(a) * sgn, math.sin(a)
                        pts.append([(xc + rr0 * ca, cy + rr0 * sa), (xc + rr1 * ca, cy + rr1 * sa)])
                    (p00, p01), (p10, p11) = pts
                    tquad(dst, [(p00[0], p00[1], z1), (p01[0], p01[1], z1), (p11[0], p11[1], z1), (p10[0], p10[1], z1)], (0, 0, 1))
                    for (q0, q1, nr) in ((p01, p11, 1), (p10, p00, -1)):
                        am = (a0 + a1) / 2
                        nn = (math.cos(am) * sgn * nr, math.sin(am) * nr, 0)
                        tquad(dst, [(q0[0], q0[1], z0), (q1[0], q1[1], z0), (q1[0], q1[1], z1), (q0[0], q0[1], z1)], nn)
                for g in (-0.5, 0.5):
                    q = []
                    for a in (a0, a1):
                        ca, sa = math.cos(a) * sgn, math.sin(a)
                        q.append([(xc + (ry + g - 0.12) * ca, cy + (ry + g - 0.12) * sa), (xc + (ry + g + 0.12) * ca, cy + (ry + g + 0.12) * sa)])
                    (g00, g01), (g10, g11) = q
                    zt = h0 + t + 0.006
                    tquad(groove, [(g00[0], g00[1], zt), (g01[0], g01[1], zt), (g11[0], g11[1], zt), (g10[0], g10[1], zt)], (0, 0, 1))
            # The curve is a ledge (0.25): a falling domino slides over it, nothing stands on it.
            if sgn > 0:
                s.solid("track curve", xb, xb + ry + w / 2, cy - ry - w / 2, cy + ry + w / 2, h0, h0 + t, "track")
            else:
                s.solid("track curve", xa - ry - w / 2, xa, cy - ry - w / 2, cy + ry + w / 2, h0, h0 + t, "track")
        s.add("track", wood, color=(0.8, 0.62, 0.4), rough=0.5)
        s.add("grooves", groove, color=(0.45, 0.32, 0.2), rough=0.6)

    def p_mirror(s, p):
        R_ = s.R
        side, a0, a1, h0, h1 = p["side"], p["a0"], p["a1"], p["h0"], p["h1"]
        fr, gl = MU(), MU()
        f_ = 0.8
        fr.mesh(wbox(R_, side, a0 - f_, a1 + f_, 0.0, 0.6, h1, h1 + f_, 0.2))
        fr.mesh(wbox(R_, side, a0 - f_, a1 + f_, 0.0, 0.6, h0 - f_, h0, 0.2))
        fr.mesh(wbox(R_, side, a0 - f_, a0, 0.0, 0.6, h0, h1, 0.2))
        fr.mesh(wbox(R_, side, a1, a1 + f_, 0.0, 0.6, h0, h1, 0.2))
        fr.mesh(wbox(R_, side, a0 - 1.0, a1 + 1.0, 0.0, 2.2, h0 - 2.6, h0 - 2.0, 0.12))     # a glass shelf's bracket line
        f = wmap(R_, side)
        tquad(gl, [f(a0, 0.3, h0), f(a1, 0.3, h0), f(a1, 0.3, h1), f(a0, 0.3, h1)], INWARD[side])
        s.add("mirror_frame", fr, color=(0.86, 0.62, 0.3), rough=0.25, metal=1.0, group=side)
        s.add("mirror", gl, color=(0.92, 0.94, 0.95), rough=0.03, metal=1.0, group=side)

    def p_bracket(s, p):
        R_ = s.R
        side, a, h, reach = p["side"], p["a"], p["h"], p["reach"]
        f = wmap(R_, side)
        m = MU()
        m.mesh(wbox(R_, side, a - 1.2, a + 1.2, 0.0, 0.3, h - 3.0, h + 1.0, 0.1))
        m.mesh(G.tube(E(*f(a, 0.2, h)), E(*f(a, reach, h)), 0.22, 12))
        m.mesh(G.tube(E(*f(a, 0.2, h - 2.6)), E(*f(a, reach * 0.55, h)), 0.14, 10))
        m.mesh(G.ball(E(*f(a, reach, h)), 0.36, 16, 10))
        m.mesh(G.torus(0.4, 0.08, 20, 6, E(*f(a, reach, h - 0.75)), G.rot("x", math.pi / 2) if side in "LR" else G.rot("z", math.pi / 2)))
        s.add("bracket", m, color=(0.86, 0.62, 0.3), rough=0.25, metal=1.0)

    def p_towel_rail(s, p):
        R_ = s.R
        side, a0, a1, h = p["side"], p["a0"], p["a1"], p["h"]
        f = wmap(R_, side)
        rail, towel = MU(), MU()
        rail.mesh(G.tube(E(*f(a0, 2.0, h)), E(*f(a1, 2.0, h)), 0.2, 14))
        for a in (a0, a1):
            rail.mesh(G.tube(E(*f(a, 0.0, h)), E(*f(a, 2.0, h)), 0.18, 12))
            rail.mesh(G.ball(E(*f(a, 2.0, h)), 0.3, 14, 8))
        # A folded towel hanging over the rail: two layers draping either side.
        for n0, sgn in ((2.0 - 0.35, -1), (2.0 + 0.35, 1)):
            towel.mesh(wbox(R_, side, a0 + 1.0, a1 - 1.0, n0 - 0.18, n0 + 0.18, h - 9.0 + (0 if sgn > 0 else 1.5), h + 0.1, 0.16, 2))
        towel.mesh(G.tube(E(*f(a0 + 1.0, 2.0, h + 0.05)), E(*f(a1 - 1.0, 2.0, h + 0.05)), 0.55, 18))
        s.add("rail", rail, color=(0.86, 0.62, 0.3), rough=0.25, metal=1.0, group=side)
        s.add("towel", towel, color=(0.36, 0.55, 0.58), rough=0.97, group=side)

    def p_weight(s, p):
        x, y, h, r = p["x"], p["y"], p["h"], p["r"]
        m = MU()
        if p.get("style") == "iron":       # an old flat iron, point toward +x, handle up, ring on top
            L, Wd = 2 * r + 1.2, 2 * r
            m += rb(x - L / 2, x + L / 2 - 1.0, y - Wd / 2, y + Wd / 2, h, h + 0.9, 0.3)
            m += obox((x + L / 2 - 1.0, y, h), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.0, 1.0, -Wd / 2 * 0.55, Wd / 2 * 0.55, 0.0, 0.9)
            m += tube_t((x - L / 2 + 0.6, y, h + 0.9), (x - L / 2 + 0.6, y, h + 2.1), 0.2)
            m += tube_t((x + L / 2 - 1.4, y, h + 0.9), (x + L / 2 - 1.4, y, h + 2.1), 0.2)
            m += tube_t((x - L / 2 + 0.4, y, h + 2.1), (x + L / 2 - 1.2, y, h + 2.1), 0.35)
            top_h = h + 2.45
        else:                              # a brass scale weight with a ring
            m += lathe_at(G.smooth_profile([(0, 0), (r, 0), (r, 0.1), (r * 0.98, r * 1.4), (r * 0.6, r * 1.6), (r * 0.35, r * 1.75), (0, r * 1.75)], 3), x, y, h, 32)
            top_h = h + r * 1.75
        m.mesh(G.torus(0.35, 0.09, 20, 6, E(x, y, top_h + 0.35), G.rot("x", math.pi / 2)))
        s.add("weight", m, color=(0.86, 0.62, 0.3) if p.get("style") != "iron" else (0.1, 0.1, 0.11), rough=0.3 if p.get("style") != "iron" else 0.55,
              metal=1.0, trap="weight")

    def p_dictionary(s, p):
        x0, x1, y0, y1, h0, h1 = p["x0"], p["x1"], p["y0"], p["y1"], p["h0"], p["h1"]
        cover, pages, gold = MU(), MU(), MU()
        b = 0.2
        cover += rb(x0, x0 + b, y0, y1, h0, h1, 0.06, 1)
        cover += rb(x1 - b, x1, y0, y1, h0, h1, 0.06, 1)
        cover += rb(x0, x1, y0 - 0.0, y0 + 0.5, h0, h1, 0.22, 3)            # the spine faces the room (-y)
        pages += rb(x0 + b, x1 - b, y0 + 0.4, y1 - 0.12, h0 + 0.18, h1 - 0.18, 0.03, 1)
        for hh in (h0 + 1.2, h0 + 1.5, h1 - 1.5, h1 - 1.2):
            gold += rb(x0 + 0.1, x1 - 0.1, y0 - 0.04, y0 + 0.05, hh - 0.08, hh + 0.08, 0.02, 1)
        gold += rb(x0 + 0.4, x1 - 0.4, y0 - 0.04, y0 + 0.05, (h0 + h1) / 2 - 0.9, (h0 + h1) / 2 + 0.9, 0.04, 1)
        s.add("dictionary", cover, color=(0.28, 0.05, 0.04), rough=0.5, goal=True)
        s.add("dict_pages", pages, color=(0.86, 0.8, 0.66), rough=0.8, goal=True)
        s.add("dict_gold", gold, color=(0.86, 0.66, 0.3), rough=0.3, metal=1.0, goal=True)
        if p.get("solid", True):
            s.solid("dictionary", x0, x1, y0, y1, h0, h1, "dictionary")

    def p_plank(s, p):
        x, y, h, L, w = p["x"], p["y"], p["h"], p["len"], p["width"]
        m = rb(x - 0.2, x + 0.2, y - w / 2, y + w / 2, h, h + L, 0.08, 2)
        s.add("plank", m, color=(0.66, 0.5, 0.32), rough=0.55, trap="plank")
        hook = MU()
        Y1 = s.R["y1"]
        hook.mesh(G.tube(E(x, Y1, h + L), E(x, Y1 - 0.8, h + L), 0.12, 10))
        hook.mesh(G.ball(E(x, Y1 - 0.85, h + L), 0.2, 12, 8))
        s.add("hook", hook, color=(0.86, 0.62, 0.3), rough=0.25, metal=1.0)

    def p_floor_lamp(s, p):
        x, y, h = p["x"], p["y"], p["h"]
        brass, shade = MU(), MU()
        brass += lathe_at(G.smooth_profile([(0, 0), (2.4, 0), (2.4, 0.3), (1.2, 0.7), (0.4, 1.0), (0, 1.0)], 3), x, y, 0.0, 40)
        brass += tube_t((x, y, 0.9), (x, y, h - 4.0), 0.22, 14)
        brass += lathe_at([(0, 0), (0.5, 0), (0.6, 0.4), (0.3, 1.4), (0, 1.4)], x, y, h - 4.4, 20)
        shade += lathe_at([(3.6, 0.0), (2.0, 6.0), (1.98, 6.0), (3.58, 0.0)], x, y, h - 3.4, 48)
        s.add("brass", brass, color=(0.86, 0.62, 0.3), rough=0.25, metal=1.0)
        s.add("glow", shade, color=(0.88, 0.8, 0.62), rough=0.9, emis=(0.6, 0.4, 0.18))
        s.solid("floor lamp", x - 2.4, x + 2.4, y - 2.4, y + 2.4, 0.0, 1.0, "floor lamp")
        s.solid("floor lamp", x - 0.5, x + 0.5, y - 0.5, y + 0.5, 1.0, h - 3.4, "floor lamp")
        s.solid("floor lamp", x - 3.6, x + 3.6, y - 3.6, y + 3.6, h - 3.4, h + 2.6, "floor lamp")

    def p_rafters(s, p):
        s.rafters(p["every"])

    def p_boxes(s, p):
        card, tape = MU(), MU()
        for i, (x0, x1, y0, y1, z0, z1) in enumerate(p["boxes"]):
            card += rb(x0, x1, y0, y1, z0, z1, 0.15, 2)
            ym = (y0 + y1) / 2
            tape += rb(x0 - 0.02, x1 + 0.02, ym - 0.9, ym + 0.9, z1 - 0.01, z1 + 0.03, 0.01, 1)
            s.solid("box", x0, x1, y0, y1, z0, z1, "boxes")
            if not any(b[4] >= z1 - 1e-6 and b[0] < x1 and b[1] > x0 and b[2] < y1 and b[3] > y0 for b in p["boxes"]):
                s.surface("box %d" % (i + 1), x0, x1, y0, y1, z1, edge=True)
        s.add("boxes", card, color=(0.56, 0.42, 0.27), rough=0.88)
        s.add("tape", tape, color=(0.72, 0.6, 0.4), rough=0.45)

    def p_crate_tower(s, p):
        x0, x1, y0, y1, h = p["x0"], p["x1"], p["y0"], p["y1"], p["h"]
        m = MU()
        n = 3
        th = h / n
        for i in range(n):
            z0, z1 = i * th, (i + 1) * th - 0.02
            sh = 0.25 * (1 if i % 2 else -1)
            a0, a1 = x0 + 0.3 + sh, x1 - 0.3 + sh
            for (b0, b1, c0, c1) in ((a0, a1, y0 + 0.3, y0 + 0.7), (a0, a1, y1 - 0.7, y1 - 0.3)):
                for k in range(3):
                    m += rb(b0, b1, c0, c1, z0 + k * th / 3 + 0.05, z0 + (k + 1) * th / 3 - 0.05, 0.05, 1)
            for (b0, b1) in ((a0, a0 + 0.4), (a1 - 0.4, a1)):
                for k in range(3):
                    m += rb(b0, b1, y0 + 0.7, y1 - 0.7, z0 + k * th / 3 + 0.05, z0 + (k + 1) * th / 3 - 0.05, 0.05, 1)
            for (b0, b1) in ((a0, a0 + 0.6), (a1 - 0.6, a1)):
                for (c0, c1) in ((y0 + 0.3, y0 + 0.9), (y1 - 0.9, y1 - 0.3)):
                    m += rb(b0, b1, c0, c1, z0, z1, 0.05, 1)
            m += rb(a0, a1, y0 + 0.3, y1 - 0.3, z1 - 0.35, z1, 0.05, 1)
        s.add("crates", m, color=(0.6, 0.45, 0.28), rough=0.75, trap="fragile crate tower")

    def p_master_switch(s, p):
        x0, x1, y0, y1, h0, h1 = p["x0"], p["x1"], p["y0"], p["y1"], p["h0"], p["h1"]
        body, lever, pipe = MU(), MU(), MU()
        body += rb(x0, x1, y0, y1, h0, h1, 0.2)
        body += rb(x0 - 0.15, x0 + 0.2, y0 + 0.5, y1 - 0.5, h0 + 0.6, h1 - 0.6, 0.1)            # the door
        for z in (h0 + 1.4, h1 - 1.4):
            body += rb(x0 - 0.3, x0, y0 + 0.9, y0 + 1.7, z - 0.4, z + 0.4, 0.08)                  # hinges
        ym = (y0 + y1) / 2
        # The knife switch's handle: a brass arm out of a slot, a red grip, pointing into the room and down (off).
        lever += tube_t((x0 - 0.1, ym, 5.0), (x0 - 2.6, ym, 2.6), 0.22, 14)
        lever += ball_t(x0 - 0.1, ym, 5.0, 0.4)
        grip = tube_t((x0 - 2.6, ym - 1.0, 2.6), (x0 - 2.6, ym + 1.0, 2.6), 0.36, 16)
        pipe += tube_t((x1 - 1.0, ym, h1), (x1 - 1.0, ym, s.top_at("R", ym) - 0.5), 0.32, 14)
        for z in (h1 + 6.0, h1 + 18.0, h1 + 30.0):
            pipe += rb(x1 - 1.6, x1, ym - 0.6, ym + 0.6, z - 0.4, z + 0.4, 0.06, 1)
        s.add("switchbox", body, color=(0.16, 0.24, 0.2), rough=0.45, metal=0.3, goal=True)
        s.add("lever", lever, color=(0.86, 0.62, 0.3), rough=0.25, metal=1.0, goal=True)
        s.add("grip", grip, color=(0.6, 0.06, 0.04), rough=0.35, goal=True)
        s.add("conduit", pipe, color=(0.3, 0.3, 0.3), rough=0.4, metal=1.0)
        s.solid("master switch", x0 - 0.3, x1, y0, y1, h0, h1, "master switch")
        s.solid("master switch lever", x0 - 3.0, x0 - 0.3, ym - 1.4, ym + 1.4, 2.2, 5.4, "master switch")


# ================================================================== textures
def _uv(h, w):
    v = (np.arange(h)[:, None] + 0.5) / h * np.ones((1, w))
    u = np.ones((h, 1)) * (np.arange(w)[None, :] + 0.5) / w
    return u, v


def foreign_textures():
    """Texture files other tools write (the Great Hall's hall_floor.png...): no house texture may take one."""
    out = set()
    for fn in os.listdir(HERE):
        if fn.endswith(".py") and fn not in ("gen_house.py", "house_rooms.py"):
            txt = open(os.path.join(HERE, fn), encoding="utf-8", errors="ignore").read()
            out |= set(re.findall(r'"([A-Za-z0-9_]+[.]png)"', txt))
    return out


FOREIGN = []


def _save(rgb, name):
    if not FOREIGN:
        FOREIGN.append(foreign_textures())
    assert name not in FOREIGN[0], "texture name belongs to another tool: " + name
    R.srgb_png(rgb, os.path.join(TEX, name))


def _grain(h, w, rng, along_x=True, k=1.0):
    """Wood grain in [-1, 1]: streaks along x, drifting."""
    u, v = _uv(h, w)
    n = R.periodic_noise(h, w, rng, 8)
    a = v if along_x else u
    return np.sin(2 * np.pi * (a * 48 * k + n * 1.6)) * 0.6 + 0.4 * R.periodic_noise(h, w, rng, 40)


def tex_boards(name, S, board, base, seed, px=2048, knots=False, grey=0.0):
    """Straight boards along x, S x S units per tile: random joints staggered row to row, grain, dark joints."""
    rng = np.random.default_rng(seed)
    rows = max(1, int(round(S / board)))
    pw = px / rows
    y = np.arange(px)[:, None] * np.ones((1, px))
    x = np.ones((px, 1)) * np.arange(px)[None, :]
    row = np.floor(y / pw).astype(int)
    out = np.zeros((px, px, 3))
    base = np.array(base)
    g = _grain(px, px, rng)
    fine = rng.normal(0, 1, (px, px))
    for r in range(rows):
        sel = row == r
        nb = int(rng.integers(1, 3))
        start = float(rng.uniform(0, px))
        joints = sorted(((start + px * (i + float(rng.uniform(-0.12, 0.12))) / nb) % px) for i in range(nb))
        xx = x[sel]
        idx = np.searchsorted(joints, xx) % nb
        tone = rng.uniform(0.84, 1.1, nb)
        c = base[None, :] * tone[idx][:, None]
        c = c * (1 + 0.07 * g[sel])[:, None] * (1 + 0.012 * fine[sel])[:, None]
        yl = (y[sel] - r * pw) / pw
        dj = np.min(np.abs(((xx[:, None] - np.array(joints)[None, :]) + px / 2) % px - px / 2), axis=1)
        de = np.minimum(yl * pw, (1 - yl) * pw)
        dark = np.clip(1 - np.minimum(dj, de) / 3.0, 0, 1)
        c = c * (1 - 0.5 * dark[:, None])
        out[sel] = c
    if knots:
        for _ in range(int(S * S / 40)):
            kx, ky = rng.uniform(0, px), rng.uniform(0, px)
            r_ = rng.uniform(6, 16)
            d = np.sqrt(((x - kx + px / 2) % px - px / 2) ** 2 + (((y - ky + px / 2) % px - px / 2) * 2.5) ** 2)
            out *= (1 - 0.35 * np.exp(-(d / r_) ** 2))[..., None]
    if grey:
        lum = out.mean(-1, keepdims=True)
        out = out * (1 - grey) + lum * grey * np.array([1.0, 0.98, 0.94])
    _save(out, name)


def tex_herringbone(name, S, base, seed, px=2048):
    """Oak herringbone: boards 4 x 1 (in S/8 units) at 45 degrees, alternating."""
    rng = np.random.default_rng(seed)
    u, v = _uv(px, px)
    X, Y = u * S, v * S
    a = (X + Y) / math.sqrt(2) * 2.0
    b = (X - Y) / math.sqrt(2) * 2.0
    w = S / 8 * math.sqrt(2)          # tile so 4 board-widths repeat exactly
    col = np.floor(b / w)
    par = (col % 2).astype(int)
    al = np.where(par == 0, a, -a) + col * w * 0.5
    L = 4 * w
    brd = np.floor(al / L)
    fa = (al / L) % 1.0
    fb = (b / w) % 1.0
    h = (brd * 92821 + col * 68917) % 997
    tone = 0.86 + 0.24 * ((h * 0.6180339) % 1.0)
    g = _grain(px, px, rng)
    out = np.array(base)[None, None, :] * tone[..., None] * (1 + 0.06 * g)[..., None]
    edge = np.minimum(np.minimum(fa, 1 - fa) * L, np.minimum(fb, 1 - fb) * w)
    out *= (1 - 0.5 * np.clip(1 - edge / 0.06, 0, 1))[..., None]
    _save(out, name)


def tex_checker(name, S, c1, c2, seed, px=2048, n=2):
    """Floor tiles in a checker, n x n per tile, with grout and a soft glaze variation."""
    rng = np.random.default_rng(seed)
    u, v = _uv(px, px)
    t = S / n
    X, Y = u * S, v * S
    i, j = np.floor(X / t), np.floor(Y / t)
    chk = ((i + j) % 2)[..., None]
    out = np.array(c1) * (1 - chk) + np.array(c2) * chk
    out = out * (1 + 0.04 * R.periodic_noise(px, px, rng, 12))[..., None] * (1 + 0.01 * rng.normal(0, 1, (px, px)))[..., None]
    fx, fy = (X / t) % 1.0, (Y / t) % 1.0
    d = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy)) * t
    gr = np.clip(1 - (d - 0.05) / 0.06, 0, 1)
    out = out * (1 - gr[..., None]) + np.array([0.55, 0.52, 0.47]) * gr[..., None]
    _save(out, name)


def tex_mosaic(name, S, seed, px=2048):
    """White hexagon mosaic (about 1.1 units across) with grey grout and a scattering of pale blue tiles."""
    rng = np.random.default_rng(seed)
    u, v = _uv(px, px)
    n = int(round(S / 1.1))
    X, Y = u * n, v * n * 2 / math.sqrt(3)
    # Axial hex grid: nearest centre among two offset rectangular lattices (exact tiling at this ratio).
    cx1, cy1 = np.round(X), np.round(Y / 2) * 2
    cx2, cy2 = np.floor(X) + 0.5, np.floor(Y / 2) * 2 + 1
    s3 = math.sqrt(3) / 2
    d1 = (X - cx1) ** 2 + ((Y - cy1) * s3) ** 2
    d2 = (X - cx2) ** 2 + ((Y - cy2) * s3) ** 2
    near1 = d1 < d2
    cx, cy = np.where(near1, cx1, cx2), np.where(near1, cy1, cy2)
    dx, dy = np.abs(X - cx), np.abs((Y - cy) * s3)
    hexd = np.maximum(dx * s3 + dy * 0.5, dy)      # hexagon distance (pointy sides)
    hsh = (np.mod(cx * 12.9898 + cy * 78.233, 1.0) * 43758.5453) % 1.0
    white, blue = np.array([0.9, 0.9, 0.88]), np.array([0.56, 0.7, 0.76])
    out = np.where((hsh < 0.09)[..., None], blue, white) * (0.95 + 0.06 * ((hsh * 7) % 1.0))[..., None]
    gr = np.clip((hexd - 0.4) / 0.06, 0, 1)
    out = out * (1 - gr[..., None]) + np.array([0.5, 0.5, 0.48]) * gr[..., None]
    out *= (1 + 0.012 * rng.normal(0, 1, (px, px)))[..., None]
    _save(out, name)


def tex_carpet(name, seed, base, px=1024):
    rng = np.random.default_rng(seed)
    n1 = R.periodic_noise(px, px, rng, 40)
    n2 = R.periodic_noise(px, px, rng, 8)
    out = np.array(base) * (1 + 0.05 * n1 + 0.04 * n2)[..., None] * (1 + 0.07 * rng.normal(0, 1, (px, px)))[..., None]
    _save(out, name)


def tex_wall(Rm, name):
    """A full-height wall texture: u repeats every 24 units, v covers the floor to the ceiling once."""
    kind = Rm["wall"]["kind"]
    H = Rm["wall_h"]
    SU = 24.0
    ppu = 1024 / SU
    w, h = 1024, int(round(H * ppu))
    rng = np.random.default_rng(len(name) * 7 + int(H))
    u, v = _uv(h, w)
    X = u * SU
    Z = (1 - v) * H                     # height of each row (row 0 is the top)
    out = np.zeros((h, w, 3))
    noise = R.periodic_noise(h, w, rng, 16)

    def paint(col, k=0.02):
        return np.array(col)[None, None, :] * (1 + k * noise)[..., None] * np.ones((h, w, 1))

    def panels(top, col, pw=12.0, inset=1.4, rail=1.0):
        """Painted wainscot: panels pw wide with a bevelled moulding, a dado rail on top."""
        m = Z < top
        c = paint(col, 0.01)
        fx = (X % pw)
        dx = np.minimum(fx - inset, pw - inset - fx)
        dz = np.minimum(Z - 2.6 - inset, top - rail - inset - Z)
        d = np.minimum(dx, dz)
        shade = np.where(np.abs(d) < 0.35, np.where(dx < dz, 0.8, 0.9), 1.0)
        shade = np.where((d > 0.35) & (d < 0.7), 1.04, shade)
        c = c * shade[..., None]
        c = np.where(((Z > top - rail) & (Z < top))[..., None], c * np.where(Z > top - rail * 0.5, 1.06, 0.86)[..., None], c)
        out[m] = c[m]

    def tiles(top, col, tw, th, offset=True, grout=(0.72, 0.72, 0.7), border=None):
        m = Z < top
        row = np.floor(Z / th)
        xs = X + (row % 2) * tw / 2 if offset else X
        fx, fz = (xs / tw) % 1.0, (Z / th) % 1.0
        hsh = (np.mod(np.floor(xs / tw) * 12.9898 + row * 78.233, 1.0) * 43758.5453) % 1.0
        c = np.array(col)[None, None, :] * (0.96 + 0.06 * hsh)[..., None] * np.ones((h, w, 1))
        # A glaze bevel: lighter near the top edge of each tile, darker at the bottom.
        c = c * (1 + 0.05 * np.clip(1 - fz * th / 0.25, 0, 1) - 0.06 * np.clip(1 - (1 - fz) * th / 0.25, 0, 1))[..., None]
        d = np.minimum(np.minimum(fx, 1 - fx) * tw, np.minimum(fz, 1 - fz) * th)
        gr = np.clip(1 - (d - 0.04) / 0.05, 0, 1)
        c = c * (1 - gr[..., None]) + np.array(grout) * gr[..., None]
        out[m] = c[m]
        if border:
            b0, b1, bc = border
            mb = (Z >= b0) & (Z < b1)
            cb = np.array(bc) * (1 + 0.04 * noise)[..., None] * np.ones((h, w, 1))
            dzb = np.minimum(Z - b0, b1 - Z)
            cb = cb * (1 - 0.3 * np.clip(1 - dzb / 0.08, 0, 1))[..., None]
            out[mb] = cb[mb]

    if kind == "hall":
        out[:] = paint((0.56, 0.62, 0.5))
        st = (X % 6.0)
        band = (np.abs(st - 3.0) < 1.1)
        out[band] = (paint((0.62, 0.68, 0.56)))[band]
        thin = (np.abs(st - 1.9) < 0.07) | (np.abs(st - 4.1) < 0.07)
        out[thin] = (paint((0.78, 0.74, 0.58)))[thin]
        panels(17.0, (0.93, 0.91, 0.86))
        out[(Z > H - 2.0)] = paint((0.93, 0.91, 0.86))[(Z > H - 2.0)]        # picture rail and frieze
    elif kind == "dining":
        out[:] = paint((0.42, 0.08, 0.08), 0.03)
        # Damask: a mirrored motif on a half-drop grid.
        tw, th = 8.0, 12.0
        col = np.floor(X / tw)
        zz = Z + (col % 2) * th / 2
        fx, fz = (X / tw) % 1.0 - 0.5, (zz / th) % 1.0 - 0.5
        ax = np.abs(fx)
        r = np.sqrt((ax * 1.6) ** 2 + (fz * 1.0) ** 2)
        leaf = (np.abs(np.sin(6 * np.arctan2(fz, ax + 1e-6) + 2 * r * 6)) * (1 - r * 1.6)) > 0.28
        stem = (ax < 0.03) & (np.abs(fz) < 0.42)
        bud = ((ax - 0.22) ** 2 + (fz + 0.28) ** 2) < 0.006
        mot = (leaf & (r < 0.6)) | stem | bud
        out[mot] = paint((0.52, 0.12, 0.1), 0.03)[mot]
        panels(18.0, (0.92, 0.88, 0.8), pw=12.0)
        out[(Z > H - 2.0)] = paint((0.92, 0.88, 0.8))[(Z > H - 2.0)]
    elif kind == "kids":
        out[:] = paint((0.66, 0.8, 0.9), 0.02)
        for _ in range(3):         # clouds: soft lobed ellipses, wrapping in u
            cx, cz = rng.uniform(0, SU), rng.uniform(20, H - 6)
            for k in range(5):
                ox, oz, rr = cx + (k - 2) * 1.6, cz + rng.uniform(-0.4, 0.8), rng.uniform(1.4, 2.2)
                dxx = (X - ox + SU / 2) % SU - SU / 2
                d = (dxx / (rr * 1.3)) ** 2 + ((Z - oz) / rr) ** 2
                cl = d < 1
                out[cl] = paint((0.96, 0.97, 0.98), 0.01)[cl]
        for _ in range(14):        # little stars
            sx, sz = rng.uniform(0, SU), rng.uniform(16, H - 3)
            dxx = (X - sx + SU / 2) % SU - SU / 2
            ang = np.arctan2(Z - sz, dxx)
            rr = np.sqrt(dxx ** 2 + (Z - sz) ** 2)
            lim = 0.55 * (0.55 + 0.45 * np.cos(5 * ang))
            stc = rr < lim
            out[stc] = paint((0.98, 0.84, 0.36), 0.01)[stc]
        # Beadboard below a rail.
        m = Z < 14.0
        bb = paint((0.97, 0.96, 0.92), 0.01)
        groove = (X % 1.6) < 0.08
        bb[groove] *= 0.8
        rail = (Z > 13.0)
        bb[rail] *= np.where(Z[rail] > 13.5, 1.04, 0.88)[:, None]
        out[m] = bb[m]
    elif kind == "study":
        out[:] = paint((0.13, 0.24, 0.18), 0.03)
        tw, th = 4.0, 4.0
        col = np.floor(X / tw)
        zz = Z + (col % 2) * th / 2
        fx, fz = (X / tw) % 1.0 - 0.5, (zz / th) % 1.0 - 0.5
        lz = (np.abs(fx) * 1.4 + np.abs(fz)) < 0.13
        dot = (np.abs(fx) + np.abs(fz) * 1.4) < 0.05
        out[lz & ~dot] = paint((0.62, 0.5, 0.26), 0.03)[lz & ~dot]
        # Dark oak panelling below.
        m = Z < 16.0
        g = _grain(h, w, rng, along_x=False, k=0.4)
        wood = np.array((0.3, 0.17, 0.09))[None, None, :] * (1 + 0.08 * g)[..., None] * np.ones((h, w, 1))
        fx2 = X % 8.0
        dx = np.minimum(fx2 - 1.2, 8.0 - 1.2 - fx2)
        dz = np.minimum(Z - 3.4, 16.0 - 2.2 - Z)
        d = np.minimum(dx, dz)
        wood = wood * np.where(np.abs(d) < 0.3, 0.72, np.where((d > 0.3) & (d < 0.6), 1.1, 1.0))[..., None]
        rail = Z > 15.0
        wood[rail] *= np.where(Z[rail] > 15.5, 1.15, 0.8)[:, None]
        out[m] = wood[m]
    elif kind == "kitchen":
        out[:] = paint((0.8, 0.84, 0.74), 0.02)
        tiles(26.0, (0.93, 0.93, 0.9), 3.0, 1.5, border=(26.0, 27.0, (0.18, 0.32, 0.3)))
    elif kind == "bath":
        out[:] = paint((0.7, 0.84, 0.82), 0.02)
        tiles(24.0, (0.95, 0.95, 0.93), 3.0, 3.0, offset=False, border=(24.0, 25.0, (0.12, 0.2, 0.36)))
        m = Z < 1.0
        out[m] = paint((0.12, 0.2, 0.36))[m]
    out *= (1 + 0.012 * rng.normal(0, 1, (h, w)))[..., None]
    _save(out, name)


def tex_brick(name, px=1024, S=16.0, seed=3):
    """Whitewashed brick (the attic's gables): 4.4 x 1.4 unit bricks, the wash worn through here and there."""
    rng = np.random.default_rng(seed)
    u, v = _uv(px, px)
    X, Z = u * S, (1 - v) * S
    bw, bh = 16.0 / 4, 16.0 / 12
    row = np.floor(Z / bh)
    xs = X + (row % 2) * bw / 2
    fx, fz = (xs / bw) % 1.0, (Z / bh) % 1.0
    hsh = (np.mod(np.floor(xs / bw) * 12.9898 + row * 78.233, 1.0) * 43758.5453) % 1.0
    brick = np.array([0.55, 0.3, 0.2]) * (0.85 + 0.25 * hsh)[..., None]
    wash = np.clip(0.78 + 0.22 * R.periodic_noise(px, px, rng, 5) - 0.18 * (hsh > 0.82) + 0.04 * rng.normal(0, 1, (px, px)), 0, 1)
    out = brick * (1 - wash[..., None]) + np.array([0.86, 0.84, 0.8]) * wash[..., None]
    d = np.minimum(np.minimum(fx, 1 - fx) * bw, np.minimum(fz, 1 - fz) * bh)
    gr = np.clip(1 - (d - 0.05) / 0.07, 0, 1)
    out = out * (1 - gr[..., None]) + np.array([0.68, 0.66, 0.62]) * gr[..., None]
    _save(out, name)


def tex_rug(Rm, p):
    """One rug per room, drawn to its own size."""
    kind = p["tex"]
    Wu, Du = p["x1"] - p["x0"], p["y1"] - p["y0"]
    w = 1024 if max(Wu, Du) < 40 else 2048
    if Wu >= Du:
        W, Hh = w, max(64, int(w * Du / Wu))
    else:
        W, Hh = max(64, int(w * Wu / Du)), w
    rng = np.random.default_rng(len(kind) * 31)
    U = (np.arange(W)[None, :] + 0.5) / W * Wu * np.ones((Hh, 1))
    V = ((np.arange(Hh)[:, None] + 0.5) / Hh * Du * np.ones((1, W)))[::-1]
    de = np.minimum(np.minimum(U, Wu - U), np.minimum(V, Du - V))
    out = np.zeros((Hh, W, 3))
    long_ = V if Du > Wu else U
    cross = U if Du > Wu else V
    if kind == "runner":           # a kilim runner: madder field, stepped lozenges, a navy and cream border
        red, navy, cream, gold = np.array([0.55, 0.13, 0.1]), np.array([0.12, 0.15, 0.3]), np.array([0.86, 0.78, 0.6]), np.array([0.78, 0.55, 0.18])
        out[:] = red
        out[de < 1.4] = navy
        out[(de >= 1.4) & (de < 1.8)] = cream
        cw = min(Wu, Du)
        c = np.abs(cross - cw / 2)
        ph = (long_ % 8.0) - 4.0
        dd = np.abs(ph) + c * 0.9
        stepped = np.floor(dd / 0.6) * 0.6
        field = de >= 1.8
        out[field & (stepped < 4.2)] = navy
        out[field & (stepped < 3.0)] = gold
        out[field & (stepped < 1.8)] = cream
        out[field & (stepped < 0.6)] = red
    elif kind == "mat":            # a rag rug: random coloured stripes across
        cols = [np.array(c) for c in ((0.3, 0.42, 0.56), (0.78, 0.7, 0.55), (0.62, 0.22, 0.16), (0.32, 0.46, 0.34), (0.86, 0.82, 0.72))]
        k = np.floor(long_ / 0.45).astype(int)
        hs = (k * 2654435761) % 5
        for i, c in enumerate(cols):
            out[hs == i] = c
        out *= (1 + 0.18 * np.sin(cross * 40 + long_ * 3))[..., None] * 0.9
        out[de < 0.5] = np.array([0.32, 0.26, 0.2])
    elif kind in ("dining", "study", "attic"):
        pal = {"dining": ((0.16, 0.2, 0.36), (0.86, 0.8, 0.64), (0.56, 0.24, 0.14), (0.7, 0.55, 0.3)),
               "study": ((0.5, 0.1, 0.08), (0.12, 0.16, 0.3), (0.82, 0.72, 0.5), (0.2, 0.32, 0.24)),
               "attic": ((0.5, 0.36, 0.3), (0.72, 0.66, 0.52), (0.34, 0.38, 0.42), (0.6, 0.48, 0.3))}[kind]
        a, b, c, d_ = (np.array(x) for x in pal)
        out[:] = a
        out[de < 2.2] = b
        out[(de >= 2.2) & (de < 2.6)] = c
        band = (de >= 2.6) & (de < 5.0)
        out[band] = d_
        along = np.where(np.minimum(U, Wu - U) < np.minimum(V, Du - V), V, U)
        dd = np.abs(((along / 2.8) % 1.0) - 0.5) * 2.8 + np.abs(de - 3.8) * 1.4
        out[band & (dd < 0.9)] = b
        out[band & (dd < 0.4)] = c
        out[(de >= 5.0) & (de < 5.4)] = b
        cu, cv = U - Wu / 2, V - Du / 2
        md = np.abs(cu) / (Wu * 0.28) + np.abs(cv) / (Du * 0.28)
        field = de >= 5.4
        for r0, col in ((1.0, b), (0.84, c), (0.72, d_), (0.56, b), (0.44, a), (0.3, c), (0.16, d_)):
            out[field & (md < r0)] = col
        sm = (np.abs(((cu / 3.6) % 1.0) - 0.5) + np.abs(((cv / 3.6) % 1.0) - 0.5))
        out[field & (md > 1.05) & (sm < 0.15)] = d_
        if kind == "attic":        # faded and worn
            lum = out.mean(-1, keepdims=True)
            out = out * 0.6 + lum * 0.4
            out *= (1 + 0.12 * R.periodic_noise(Hh, W, rng, 6))[..., None]
    elif kind == "playmat":        # a town playmat: grass, grey roads with dashes, a pond, little houses
        out[:] = np.array([0.42, 0.62, 0.3])
        roads = []
        for x in (Wu * 0.18, Wu * 0.82):
            roads.append(np.abs(U - x) < 1.4)
        for y in (Du * 0.2, Du * 0.85):
            roads.append(np.abs(V - y) < 1.4)
        road = np.zeros_like(U, bool)
        for r_ in roads:
            road |= r_
        out[road] = np.array([0.42, 0.42, 0.44])
        dash = (((np.abs(U - Wu * 0.18) < 0.12) | (np.abs(U - Wu * 0.82) < 0.12)) & ((V % 2.0) < 1.0)) | \
               (((np.abs(V - Du * 0.2) < 0.12) | (np.abs(V - Du * 0.85) < 0.12)) & ((U % 2.0) < 1.0))
        out[dash & road] = np.array([0.95, 0.93, 0.85])
        pond = ((U - Wu * 0.52) / 5.0) ** 2 + ((V - Du * 0.52) / 3.2) ** 2 < 1
        out[pond] = np.array([0.3, 0.55, 0.78])
        for hx, hy, col in ((Wu * 0.06, Du * 0.45, (0.78, 0.3, 0.2)), (Wu * 0.93, Du * 0.5, (0.9, 0.7, 0.25)), (Wu * 0.5, Du * 0.06, (0.3, 0.45, 0.75)),
                            (Wu * 0.35, Du * 0.94, (0.85, 0.5, 0.6))):
            hb = (np.abs(U - hx) < 1.3) & (np.abs(V - hy) < 1.0)
            out[hb] = np.array(col)
        out[de < 0.6] = np.array([0.16, 0.36, 0.62])
    elif kind == "bathmat":
        out[:] = np.array([0.6, 0.76, 0.84])
        out[(de > 0.8) & (de < 1.2)] = np.array([0.95, 0.95, 0.92])
        out *= (1 + 0.08 * np.sin(U * 26) * np.sin(V * 26))[..., None]
    out *= (1 + 0.06 * rng.normal(0, 1, (Hh, W)))[..., None]
    out *= (1 + 0.04 * R.periodic_noise(Hh, W, rng, 18))[..., None]
    _save(out, f"{Rm['id']}_rug.png")


def textures(Rm):
    i = Rm["id"]
    fl = Rm["floor"]
    S = fl["S"]
    k = fl["kind"]
    if k == "herringbone":
        tex_herringbone(f"{i}_flooring.png", S, (0.72, 0.52, 0.32), 21)
    elif k == "boards":
        tex_boards(f"{i}_flooring.png", S, fl["board"], fl["tone"], 23)
    elif k == "pine":
        tex_boards(f"{i}_flooring.png", S, 3.2, (0.66, 0.5, 0.34), 25, knots=True, grey=0.25)
    elif k == "checker":
        tex_checker(f"{i}_flooring.png", S, (0.9, 0.88, 0.82), (0.1, 0.1, 0.11), 27)
    elif k == "mosaic":
        tex_mosaic(f"{i}_flooring.png", S, 29)
    elif k == "carpet":
        tex_carpet(f"{i}_flooring.png", 31, (0.66, 0.6, 0.52))
    if "knee" in Rm:
        tex_brick(f"{i}_brick.png")
        tex_boards(f"{i}_boards.png", 16.0, 2.0, (0.6, 0.46, 0.32), 33, knots=True, grey=0.15)
    else:
        tex_wall(Rm, f"{i}_wall.png")
    for p in Rm["props"]:
        if p["kind"] == "rug":
            tex_rug(Rm, p)


# ================================================================== furniture import (Tripo GLBs)
def import_furniture(Rm, tripo, tmp):
    """item -> measured local arch, for every furn_<id>_<item>.glb in tripo. Writes the texture; returns OBJ paths too."""
    out = {}
    if not tripo:
        return out
    seen = set()
    for f in Rm["furniture"]:
        item = f["item"]
        if item in seen:
            continue
        seen.add(item)
        base = f"furn_{Rm['id']}_{item}"
        glb = os.path.join(tripo, base + ".glb")
        if not os.path.exists(glb):
            continue
        # A fitted import is kept (keyed by the model file and its fit) so a re-run does not import it again.
        fitspec = dict(at=[0.0, 0.0], yaw=0.0, size=list(f["size"]), turn=f.get("turn", 0.0))
        if f.get("fit") == "axes":
            # (fitted inside the whole envelope its spec's solids use: a bed's headboard stands above its mattress box)
            fitspec["size"][2] = max(fitspec["size"][2], max(b["z1"] for b in f["arch"]["solids"]))
        if f.get("shrink", 1.0) != 1.0:
            fitspec["shrink"] = f["shrink"]
        st = os.stat(glb)
        key = "%s_%d_%d_%s" % (base, st.st_size, int(st.st_mtime), hashlib.md5(json.dumps(fitspec, sort_keys=True).encode()).hexdigest()[:10])
        cache = os.path.join(WORK, "import_cache")
        os.makedirs(cache, exist_ok=True)
        obj, log = os.path.join(cache, key + ".obj"), os.path.join(cache, key + ".log")
        tex = os.path.join(TEX, base + ".png")
        if not (os.path.exists(obj) and os.path.exists(log) and os.path.exists(tex)):
            spec = os.path.join(tmp, base + ".json")
            with open(spec, "w") as fo:
                json.dump(fitspec, fo)
            r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "furniture_import.py"), "--",
                                glb, obj, tex, spec], capture_output=True, text=True)
            if "DONE" not in r.stdout or not os.path.exists(obj):
                print(r.stdout[-2000:], r.stderr[-2000:])
                raise SystemExit("import failed: " + base)
            with open(log, "w") as fo:
                fo.write(r.stdout)
        out_txt = open(log).read()
        fit = next((ln for ln in out_txt.splitlines() if ln.startswith("FIT")), "")
        if "NO TEXTURE" in out_txt:
            print("   ", base, "NO TEXTURE")
        # The spec's boxes are the contract: the model is fitted inside them and they stay as they are. The mesh is
        # only checked: inside its box, and its tops where the spec's surfaces are (or dominoes float or sink).
        if f.get("factors"):
            # (a per-axis fit kept exactly as it was cooked: the room's spec was laid on this model; the scaled file in
            # the import cache when it is there, else the same scaling of the uniform import)
            tag = "_axes_%.4f_%.4f_%.4f.obj" % tuple(f["factors"])
            kept = sorted(glob.glob(os.path.join(cache, base + "_*" + tag)), key=os.path.getmtime)
            if kept:
                obj = kept[-1]
            else:
                ax = obj[:-4] + tag
                scale_obj(obj, ax, *f["factors"])
                obj = ax
            fit = fit + "  kept axes x%.3f y%.3f h%.3f" % tuple(f["factors"])
        elif f.get("fit") == "axes":
            # (per-axis: footprint filled, the main surface's top stood at its height; see axis_fit)
            (fx, fy, fz, dx, dy), why = axis_fit(obj, f)
            if why:
                print("   ", base, "CANNOT FIT:", why)
                CANNOT.append((base, why))
            else:
                ax = obj[:-4] + "_top_%.4f_%.4f_%.4f_%.3f_%.3f.obj" % (fx, fy, fz, dx, dy)
                if not os.path.exists(ax):
                    scale_obj(obj, ax, fx, fy, fz, dx, dy)
                obj = ax
                fit = fit + "  axes x%.3f y%.3f h%.3f moved %+.2f %+.2f" % (fx, fy, fz, dx, dy)
        # Lighter before it is cooked (tools/mesh_reduce.py: meshoptimizer's simplifyWithAttributes, UVs and normals as
        # attributes), and its texture at the size it is seen (house_rooms.weight). Its buildable tops are locked only
        # for a piece that asks (lock_tops): the simplifier keeps them within tools/fit_audit.lua's tolerance unaided,
        # and a dense locked top holds the rest of the model back.
        faces, px = HR.weight(f)
        red = obj[:-4] + ("_s%d%s.obj" % (faces, "L" if f.get("lock_tops") else ""))
        if not os.path.exists(red):
            print("   ", base, MR.run_obj(obj, red, faces, f["arch"]["surfaces"] if f.get("lock_tops") else []))
        obj = red
        print("   ", MR.run_tex(tex, px))
        out[item] = dict(f["arch"], obj=obj, measured=False)
        FIT_LOG.append(fit_report(obj, f, base, fit))
        print("   ", FIT_LOG[-1]["line"])
    return out


FIT_LOG = []          # one entry per imported model: what fit_report found
CANNOT = []           # (model, why) for each model axis_fit refused

# A model whose uniform fit leaves its top off the spec's surface is fitted per axis instead (furn(..., fit="axes")):
# its main surface's top (the flat upward faces at the most area's height over that surface) is stood at the surface's
# height and stretched and moved to cover the surface's footprint, so a domino anywhere on the surface stands on it (a
# handle or a rounded lip may stand out of the box by up to FIT_OVERHANG). The spec's boxes never move. Refused
# (reported, the uniform fit kept) when that distorts the model by more than FIT_MAX_STRETCH between axes, when it
# would stand taller than its box, or stand out further than FIT_OVERHANG. tools/fit_audit.lua checks the result.
FIT_MAX_STRETCH = 1.12
FIT_OVERHANG = 1.25
FIT_SHORT = 0.2


def _up_faces(V, Fc):
    tri = np.array([[V[a[0]], V[b[0]], V[c[0]]] for a, b, c in Fc])
    cr = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    area = np.linalg.norm(cr, axis=1) / 2
    return tri, area, cr[:, 2] / np.maximum(1e-12, 2 * area) > 0.85


def top_plateau(V, Fc, srf, around=None):
    """The height of a model's top over a surface's footprint (local coordinates): the area-weighted mode of its upward
    faces there, refined to the area-weighted median of the faces within 0.12 of it (a trunk's straps or a rounded lip
    do not lift it). around: only look within 3 of it."""
    tri, area, up = _up_faces(V, Fc)
    cz, cx, cy = tri[:, :, 2].mean(1), tri[:, :, 0].mean(1), tri[:, :, 1].mean(1)
    sel = up & (cx > srf["x0"] + 0.3) & (cx < srf["x1"] - 0.3) & (cy > srf["y0"] + 0.3) & (cy < srf["y1"] - 0.3)
    if around is not None:
        sel &= np.abs(cz - around) < 3
    if not sel.any():
        return None
    lo_, hi_ = cz[sel].min(), cz[sel].max()
    hist, edges = np.histogram(cz[sel], bins=np.arange(lo_ - 0.05, hi_ + 0.1, 0.1), weights=area[sel])
    zp = edges[int(np.argmax(hist))] + 0.05
    near = sel & (np.abs(cz - zp) < 0.12)
    order = np.argsort(cz[near])
    w = np.cumsum(area[near][order])
    med = float(cz[near][order][np.searchsorted(w, w[-1] / 2)])
    # (narrow raised bits on it - a trunk's straps, a lip - up to 0.3 higher: the top is taken halfway up to them, so
    # neither a domino on the flat nor one on a strap is off by more than half their height)
    bump = cz[sel & (cz > med) & (cz < med + 0.3)]
    return med + (float(np.percentile(bump, 99.5)) - med) / 2 if len(bump) else med


def top_extent(V, Fc, srf, z):
    """The footprint (x0, x1, y0, y1) of a model's flat top at height z near a surface (its upward faces within 0.15 of
    z, centres within 1.5 of the surface's box), or None."""
    tri, area, up = _up_faces(V, Fc)
    cz, cx, cy = tri[:, :, 2].mean(1), tri[:, :, 0].mean(1), tri[:, :, 1].mean(1)
    sel = up & (np.abs(cz - z) < 0.15) & (cx > srf["x0"] - 1.5) & (cx < srf["x1"] + 1.5) & (cy > srf["y0"] - 1.5) & (cy < srf["y1"] + 1.5)
    if not sel.any():
        return None
    P = tri[sel].reshape(-1, 3)
    return float(P[:, 0].min()), float(P[:, 0].max()), float(P[:, 1].min()), float(P[:, 1].max())


def axis_fit(obj, f):
    """(x, y, h factors, x, y offsets) on a uniformly fitted local model, and None, or a reason it cannot be fitted."""
    V, _, _, Fc = read_obj(obj)
    sx, sy, sz = f["size"]
    sz = max(sz, max(b["z1"] for b in f["arch"]["solids"]))
    got = V.max(0) - V.min(0)
    fx, fy, fz, dx, dy = sx / got[0], sy / got[1], sz / got[2], 0.0, 0.0
    srfs = [s_ for s_ in f["arch"]["surfaces"] if not s_["name"].endswith("inside")]
    if srfs:
        main = max(srfs, key=lambda s_: (s_["x1"] - s_["x0"]) * (s_["y1"] - s_["y0"]))
        mx, my = (main["x0"] + main["x1"]) / 2, (main["y0"] + main["y1"]) / 2
        for _ in range(4):
            V2 = V * np.array([fx, fy, 1.0]) + np.array([dx, dy, 0.0])
            top = top_plateau(V2, Fc, main)
            if top is None or top < 0.3 * main["h"]:
                return (1, 1, 1, 0, 0), f"no top under its {main['name']} (h {main['h']:g})"
            fz = main["h"] / top
            ex = top_extent(V2 * np.array([1.0, 1.0, fz]), Fc, main, main["h"])
            if ex is None:
                break
            kx, ky = (main["x1"] - main["x0"]) / max(1e-6, ex[1] - ex[0]), (main["y1"] - main["y0"]) / max(1e-6, ex[3] - ex[2])
            fx, fy = fx * kx, fy * ky
            dx, dy = mx - ((ex[0] + ex[1]) / 2 - dx) * kx, my - ((ex[2] + ex[3]) / 2 - dy) * ky
        st = max(fx, fy, fz) / min(fx, fy, fz)
        if st > FIT_MAX_STRETCH:
            # (the height is kept; the footprint stretched only as far as allowed, its top centred on the surface; refused
            # when that top still falls short of the surface's edges by more than FIT_SHORT)
            want = (fx, fy)
            fx, fy = (min(max(v, fz / FIT_MAX_STRETCH), fz * FIT_MAX_STRETCH) for v in want)
            ex = top_extent(V * np.array([fx, fy, fz]), Fc, dict(main, x0=main["x0"] - dx, x1=main["x1"] - dx, y0=main["y0"] - dy, y1=main["y1"] - dy), main["h"])
            if ex is None:
                return (fx, fy, fz, 0, 0), f"no flat top at its {main['name']}'s height once stretched within {FIT_MAX_STRETCH}"
            dx, dy = mx - (ex[0] + ex[1]) / 2, my - (ex[2] + ex[3]) / 2
            short = max(main["x0"] - (ex[0] + dx), (ex[1] + dx) - main["x1"], main["y0"] - (ex[2] + dy), (ex[3] + dy) - main["y1"], 0.0)
            short = max(short, (main["x1"] - main["x0"] - (ex[1] - ex[0])) / 2, (main["y1"] - main["y0"] - (ex[3] - ex[2])) / 2)
            if short > FIT_SHORT:
                return (fx, fy, fz, dx, dy), (f"stretch {st:.3f} (x{want[0]:.3f} y{want[1]:.3f} h{fz:.3f}) over {FIT_MAX_STRETCH}; within it its top "
                                              f"falls {short:.2f} short of the {main['name']}'s edges")
    fac = (fx, fy, fz, dx, dy)
    if got[2] * fz > sz + f.get("over", 0.0) + 0.05:
        return fac, f"would stand {got[2] * fz:.2f} tall in a {sz:g} box (h{fz:.3f})"
    V3 = V * np.array([fx, fy, fz]) + np.array([dx, dy, 0.0])
    out = max(-sx / 2 - V3[:, 0].min(), V3[:, 0].max() - sx / 2, -sy / 2 - V3[:, 1].min(), V3[:, 1].max() - sy / 2)
    if out > FIT_OVERHANG:
        return fac, f"would stand {out:.2f} out of its box (x{fx:.3f} y{fy:.3f} h{fz:.3f} moved {dx:+.2f} {dy:+.2f})"
    return fac, None


def scale_obj(src, dst, fx, fy, fz, dx=0.0, dy=0.0):
    """A local OBJ (engine axes: x, h, -y) scaled per table axis about its footprint's centre and its base, then moved
    by (dx, dy) in table axes; normals by the inverse, renormalised."""
    with open(src) as fi, open(dst + ".tmp", "w") as fo:
        for line in fi:
            if line.startswith("v "):
                x, y, z = map(float, line.split()[1:4])
                fo.write("v %.5f %.5f %.5f\n" % (x * fx + dx, y * fz, z * fy - dy))
            elif line.startswith("vn "):
                x, y, z = map(float, line.split()[1:4])
                x, y, z = x / fx, y / fz, z / fy
                n = math.sqrt(x * x + y * y + z * z) or 1.0
                fo.write("vn %.5f %.5f %.5f\n" % (x / n, y / n, z / n))
            else:
                fo.write(line)
    os.replace(dst + ".tmp", dst)


def fit_report(obj, f, base, fit):
    """One line on a fitted model: its uniform scale, the stretch an exact fit would have needed, whether it stays in its
    box, and each spec surface's height against the model's top there (within 0.2)."""
    V, _, _, Fc = read_obj(obj)
    sx, sy, sz = f["size"]
    lo, hi = V.min(0), V.max(0)
    got = hi - lo
    k = float(re.search(r"uniform ([0-9.]+)", fit).group(1)) if "uniform" in fit else float("nan")
    need = [sx / max(1e-9, got[0]), sy / max(1e-9, got[1]), sz / max(1e-9, got[2])]
    stretch = (max(need) / min(need) - 1) * 100
    inside = lo[0] >= -sx / 2 - 0.01 and hi[0] <= sx / 2 + 0.01 and lo[1] >= -sy / 2 - 0.01 and hi[1] <= sy / 2 + 0.01 and lo[2] >= -0.01 and hi[2] <= sz + 0.01
    tri = np.array([[V[a[0]], V[b[0]], V[c[0]]] for a, b, c in Fc])
    cr = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    area = np.linalg.norm(cr, axis=1) / 2
    up = cr[:, 2] / np.maximum(1e-12, 2 * area) > 0.9
    cz, cx, cy = tri[:, :, 2].mean(1), tri[:, :, 0].mean(1), tri[:, :, 1].mean(1)
    tops, ok = [], True
    for srf in f["arch"]["surfaces"]:
        h0 = srf["h"]
        sel = up & (np.abs(cz - h0) < 3) & (cx > srf["x0"] - 1) & (cx < srf["x1"] + 1) & (cy > srf["y0"] - 1) & (cy < srf["y1"] + 1)
        if sel.any():
            hist, edges = np.histogram(cz[sel], bins=np.arange(h0 - 3, h0 + 3.05, 0.1), weights=area[sel])
            zp = edges[int(np.argmax(hist))] + 0.05
            h = float(np.percentile(tri[sel & (np.abs(cz - zp) < 0.25)][:, :, 2], 95))
        else:
            over = V[(V[:, 0] > srf["x0"]) & (V[:, 0] < srf["x1"]) & (V[:, 1] > srf["y0"]) & (V[:, 1] < srf["y1"])]
            h = float(over[:, 2].max()) if len(over) else 0.0
        good = abs(h - h0) <= 0.2
        ok &= good
        tops.append(f"{srf['name']} {h:.2f}/{h0:g}{'' if good else ' MISS'}")
    line = (f"{base:26s} k {k:7.3f}  exact fit x{need[0] / need[2] if need[2] else 0:.3f} y{need[1] / need[2]:.3f} (stretch {stretch:5.1f}%)  "
            f"inside {'yes' if inside else 'NO'}  model {got[0]:.1f}x{got[1]:.1f}x{got[2]:.1f} box {sx:g}x{sy:g}x{sz:g}  "
            + ("tops " + "; ".join(tops) if tops else "no surface"))
    return dict(name=base, k=k, need=need, stretch=stretch, inside=bool(inside), tops_ok=ok, got=[float(g) for g in got], line=line,
                faces=len(Fc))


def read_obj(path):
    """Vertices in table axes (the OBJ is in engine axes), uvs, normals and the faces' index triples."""
    V, T, N, F = [], [], [], []
    with open(path) as fo:
        for line in fo:
            if line.startswith("v "):
                x, y, z = map(float, line.split()[1:4]); V.append((x, -z, y))
            elif line.startswith("vt "):
                T.append(tuple(map(float, line.split()[1:3])))
            elif line.startswith("vn "):
                x, y, z = map(float, line.split()[1:4]); N.append((x, -z, y))
            elif line.startswith("f "):
                idx = [tuple(int(k) - 1 if k else -1 for k in (c.split("/") + ["", ""])[:3]) for c in line.split()[1:]]
                for k in range(1, len(idx) - 1):
                    F.append((idx[0], idx[k], idx[k + 1]))
    return np.array(V), T, np.array(N) if N else None, F


def measure(obj, arch, size, cell=0.4):
    """Solids and surfaces from a fitted mesh (local, front -y, base at 0).

    Solids: every triangle is drawn into the height layers it crosses (clipped to each layer); per layer the
    footprint, holes filled, becomes one rectangle per part (or a few, for an L or a U), and rectangles that carry on
    layer after layer merge into boxes. Surfaces: for each top the design expects, the upward faces nearest its
    height give the real top and its extent, and the boxes under it are trimmed or raised to meet it. A design with a
    surface inside its own walls (the bath's inside) keeps its design boxes, which the footprint would fill in."""
    from scipy import ndimage
    from PIL import ImageDraw
    V, _, _, F = read_obj(obj)
    tri = np.array([[V[a[0]], V[b[0]], V[c[0]]] for a, b, c in F])
    if arch.get("measure") is False or any(s["name"].endswith("inside") for s in arch["surfaces"]):
        return dict(arch, measured=False)
    cr = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    area = np.linalg.norm(cr, axis=1) / 2
    nrm = cr / np.maximum(1e-12, np.linalg.norm(cr, axis=1))[:, None]
    lo = V.min(0) - 2 * cell
    lo[2] = 0.0
    nx, ny = int(math.ceil((V[:, 0].max() - lo[0]) / cell)) + 3, int(math.ceil((V[:, 1].max() - lo[1]) / cell)) + 3
    nz = max(1, int(math.ceil(V[:, 2].max() / cell)))
    ims = [Image.new("1", (nx, ny), 0) for _ in range(nz)]
    drw = [ImageDraw.Draw(im) for im in ims]

    def clip(poly, z, keep_above):
        out = []
        for i in range(len(poly)):
            p, q = poly[i], poly[(i + 1) % len(poly)]
            pin, qin = (p[2] >= z) == keep_above, (q[2] >= z) == keep_above
            if pin:
                out.append(p)
            if pin != qin:
                t = (z - p[2]) / (q[2] - p[2])
                out.append(p + (q - p) * t)
        return out

    for t in tri:
        z0, z1 = t[:, 2].min(), t[:, 2].max()
        k0, k1 = max(0, int(z0 / cell)), min(nz - 1, int(z1 / cell))
        for k in range(k0, k1 + 1):
            poly = list(t)
            if k1 > k0:
                poly = clip(clip(poly, k * cell, True), (k + 1) * cell, False)
            if not poly:
                continue
            pts = [((p[0] - lo[0]) / cell, (p[1] - lo[1]) / cell) for p in poly]
            drw[k].polygon(pts if len(pts) > 2 else pts + pts[:1], fill=1, outline=1)
    rects_by_layer = []
    for k in range(nz):
        g = np.array(ims[k], bool)                         # [row = y cell, col = x cell]
        g = ndimage.binary_fill_holes(ndimage.binary_closing(g, iterations=1))
        lab, n = ndimage.label(g)
        rs = []
        for c, sl in enumerate(ndimage.find_objects(lab)):
            comp = lab[sl] == c + 1
            if comp.sum() >= 0.75 * comp.size:
                rs.append((sl[1].start, sl[1].stop, sl[0].start, sl[0].stop))
            else:
                for (j0, j1, i0, i1) in _rects(comp):
                    if (j1 - j0) * (i1 - i0) >= 4:
                        rs.append((sl[1].start + i0, sl[1].start + i1, sl[0].start + j0, sl[0].start + j1))
        rects_by_layer.append(rs)
    boxes, open_ = [], []
    for k, rs in enumerate(rects_by_layer):
        nxt = []
        for r in rs:
            hit = next((o for o in open_ if o[2] == k - 1 and all(abs(a - b) <= 1 for a, b in zip(o[0], r))), None)
            if hit:
                open_.remove(hit)
                o = hit
                nxt.append([(min(o[0][0], r[0]), max(o[0][1], r[1]), min(o[0][2], r[2]), max(o[0][3], r[3])), o[1], k])
            else:
                nxt.append([r, k, k])
        boxes += open_
        open_ = nxt
    boxes += open_
    name = arch["solids"][0]["name"]
    solids = []
    for (i0, i1, j0, j1), k0, k1 in boxes:
        if (i1 - i0) * (j1 - j0) * (k1 - k0 + 1) < 3:
            continue
        solids.append(dict(name=name, x0=float(lo[0] + i0 * cell), x1=float(lo[0] + i1 * cell), y0=float(lo[1] + j0 * cell),
                           y1=float(lo[1] + j1 * cell), z0=float(k0 * cell), z1=float(min(V[:, 2].max(), (k1 + 1) * cell))))
    if len(solids) > 40:
        print(f"    {len(solids)} boxes measured for {name}: a busy model")
    # Surfaces: the upward faces nearest each top the design expects.
    up = nrm[:, 2] > 0.9
    cz, cx, cy = tri[:, :, 2].mean(1), tri[:, :, 0].mean(1), tri[:, :, 1].mean(1)
    surfs = []
    for s in arch["surfaces"]:
        sel = up & (np.abs(cz - s["h"]) < 3.0) & (cx > s["x0"] - 2) & (cx < s["x1"] + 2) & (cy > s["y0"] - 2) & (cy < s["y1"] + 2)
        if not sel.any():
            print("    no top found near", s["name"], "h", s["h"], ": the design's is kept")
            surfs.append(dict(s, found=False))
            continue
        hist, edges = np.histogram(cz[sel], bins=np.arange(s["h"] - 3.0, s["h"] + 3.05, 0.1), weights=area[sel])
        zp = edges[int(np.argmax(hist))] + 0.05
        pts = tri[sel & (np.abs(cz - zp) < 0.25)].reshape(-1, 3)
        h = round(float(np.percentile(pts[:, 2], 95)), 3)
        d = dict(s, x0=round(float(pts[:, 0].min()) + 0.2, 3), x1=round(float(pts[:, 0].max()) - 0.2, 3),
                 y0=round(float(pts[:, 1].min()) + 0.2, 3), y1=round(float(pts[:, 1].max()) - 0.2, 3), h=h)
        surfs.append(d)
        for b in solids:          # the layers straddle the top: boxes under it end exactly at it
            if b["x0"] < d["x1"] and b["x1"] > d["x0"] and b["y0"] < d["y1"] and b["y1"] > d["y0"] and abs(b["z1"] - h) <= 2 * cell + 0.05:
                b["z1"] = h
    solids = [b for b in solids if b["z1"] - b["z0"] > 1e-3]
    for b in solids:
        for k_ in ("x0", "x1", "y0", "y1", "z0", "z1"):
            b[k_] = round(b[k_], 3)
    return dict(solids=solids, surfaces=surfs, gaps=[], measured=True)


def _rects(grid):
    """Greedy cover of a 2D boolean grid with rectangles (i0, i1, j0, j1), half-open."""
    g = grid.copy()
    out = []
    while g.any():
        i, j = np.argwhere(g)[0]
        j1 = j
        while j1 < g.shape[1] and g[i, j1]:
            j1 += 1
        i1 = i
        while i1 < g.shape[0] and g[i1, j:j1].all():
            i1 += 1
        g[i:i1, j:j1] = False
        out.append((int(i), int(i1), int(j), int(j1)))
    return out


def place_obj(src, dst, yaw, at, z):
    """Copy a local OBJ to its placement (turned by yaw about h, moved to at, lifted by z), engine axes."""
    c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    with open(src) as fi, open(dst, "w") as fo:
        for line in fi:
            if line.startswith("v "):
                x, y, zz = map(float, line.split()[1:4])
                tx, ty, th = x, -zz, y
                tx, ty = tx * c - ty * s_ + at[0], tx * s_ + ty * c + at[1]
                fo.write("v %.5f %.5f %.5f\n" % (tx, th + z, -ty))
            elif line.startswith("vn "):
                x, y, zz = map(float, line.split()[1:4])
                tx, ty = x * c - (-zz) * s_, x * s_ + (-zz) * c
                fo.write("vn %.5f %.5f %.5f\n" % (tx, y, -ty))
            else:
                fo.write(line)


# ================================================================== room data and validation
def build(Rm, imported):
    room = Room(Rm)
    room.shell()
    room.props()
    furn = furniture(Rm, imported)
    return room, furn


def roof_h(Rm, y):
    if "knee" not in Rm:
        return Rm["wall_h"]
    return Rm["knee"] + (Rm["y1"] - abs(y)) * (Rm["wall_h"] - Rm["knee"]) / Rm["y1"]


def wall_solids(Rm):
    X0, X1, Y0, Y1, H = Rm["x0"], Rm["x1"], Rm["y0"], Rm["y1"], Rm["wall_h"]
    t = 4.0
    return [dict(name="wall", x0=X0 - t, x1=X0 + SKIRT_T, y0=Y0 - t, y1=Y1 + t, z0=0, z1=H),
            dict(name="wall", x0=X1 - SKIRT_T, x1=X1 + t, y0=Y0 - t, y1=Y1 + t, z0=0, z1=H),
            dict(name="wall", x0=X0 - t, x1=X1 + t, y0=Y1 - SKIRT_T, y1=Y1 + t, z0=0, z1=H),
            dict(name="wall", x0=X0 - t, x1=X1 + t, y0=Y0 - t, y1=Y0 + SKIRT_T, z0=0, z1=H)]


def room_data(Rm, room, furn):
    solids = wall_solids(Rm)
    for f in furn:
        solids += [dict(b) for b in f["solids"]]
    solids += [{k: v for k, v in b.items() if k != "owner"} for b in room.solids]
    surfaces = [dict(name="floor", x0=Rm["x0"], x1=Rm["x1"], y0=Rm["y0"], y1=Rm["y1"], h=0.0, edge=False)]
    surfaces += [{k: v for k, v in s.items() if k != "cover"} for s in room.surfaces]
    for f in furn:
        surfaces += [dict(s) for s in f["surfaces"]]
    pieces = []
    for name in sorted(room.pieces):
        pieces.append({"name": name, **room.pieces[name][1]})
    for f in furn:
        if not f["pending"]:
            pieces.append(dict(name=f["name"], color=(1, 1, 1), rough=0.8, tex=f"Textures/{f['base']}.png", **({"goal": True} if f.get("goal") else {})))
    pending = [f["name"] for f in furn if f["pending"]]
    return dict(solids=solids, surfaces=surfaces, pieces=pieces, pending=pending)


def overlap3(a, b, eps=1e-3):
    return a["x0"] < b["x1"] - eps and a["x1"] > b["x0"] + eps and a["y0"] < b["y1"] - eps and a["y1"] > b["y0"] + eps and \
        a["z0"] < b["z1"] - eps and a["z1"] > b["z0"] + eps


def validate(Rm, room, furn):
    """Every problem found, as text (empty: the room is sound)."""
    err = []
    X0, X1, Y0, Y1 = Rm["x0"] + SKIRT_T, Rm["x1"] - SKIRT_T, Rm["y0"] + SKIRT_T, Rm["y1"] - SKIRT_T
    owners = [(f["name"], f["solids"]) for f in furn]
    props = {}
    for b in room.solids:
        props.setdefault(b["owner"], []).append(b)
    owners += list(props.items())
    wall_mounted = {"doorbell", "master switch"}
    for name, sol in owners:
        for b in sol:
            if name not in wall_mounted and (b["x0"] < X0 - 1e-6 or b["x1"] > X1 + 1e-6 or b["y0"] < Y0 - 1e-6 or b["y1"] > Y1 + 1e-6):
                err.append(f"{name}: {b['name']} runs into a wall ({b['x0']}..{b['x1']}, {b['y0']}..{b['y1']})")
            if b["x0"] < Rm["x0"] - 1e-6 or b["x1"] > Rm["x1"] + 1e-6 or b["y0"] < Rm["y0"] - 1e-6 or b["y1"] > Rm["y1"] + 1e-6:
                err.append(f"{name}: {b['name']} is outside the room")
            for y in (b["y0"], b["y1"]):
                if b["z1"] > roof_h(Rm, y) - 0.5:
                    err.append(f"{name}: {b['name']} (top {b['z1']}) goes through the ceiling or roof at y {y}")
    for i in range(len(owners)):
        for j in range(i + 1, len(owners)):
            for a in owners[i][1]:
                for b in owners[j][1]:
                    if overlap3(a, b):
                        err.append(f"{owners[i][0]} ({a['name']}) overlaps {owners[j][0]} ({b['name']})")
    # Doorways: a clear zone 10 deep in front of each door, as high as the door.
    for d in Rm.get("doors", []):
        f = wmap(Rm, d["side"])
        p, q = f(d["a0"] - 0.5, 0.0, 0.0), f(d["a1"] + 0.5, 10.0, d["h1"])
        zone = dict(x0=min(p[0], q[0]), x1=max(p[0], q[0]), y0=min(p[1], q[1]), y1=max(p[1], q[1]), z0=0.0, z1=d["h1"])
        for name, sol in owners:
            for b in sol:
                if overlap3(zone, b):
                    err.append(f"{name}: {b['name']} blocks the {d['side']} door")
    # Surfaces: none may cut through a solid; a raised one needs something under it; all inside the room.
    data = room_data(Rm, room, furn)
    covers = {s["name"] for s in room.surfaces if s.get("cover")}
    for s in data["surfaces"]:
        if s["x0"] < Rm["x0"] - 1e-6 or s["x1"] > Rm["x1"] + 1e-6 or s["y0"] < Rm["y0"] - 1e-6 or s["y1"] > Rm["y1"] + 1e-6:
            err.append(f"surface {s['name']} is outside the room")
        if s["x1"] - s["x0"] < 0.6 or s["y1"] - s["y0"] < 0.6:
            err.append(f"surface {s['name']} is too narrow for a domino")
        for b in data["solids"]:
            if b["name"] == "wall":
                continue
            if s["x0"] < b["x1"] - 1e-3 and s["x1"] > b["x0"] + 1e-3 and s["y0"] < b["y1"] - 1e-3 and s["y1"] > b["y0"] + 1e-3 \
                    and b["z0"] < s["h"] - 1e-3 and b["z1"] > s["h"] + 1e-3:
                if s["name"] in covers and b["z0"] <= 1e-6:
                    continue          # furniture standing on the floor through a rug
                err.append(f"surface {s['name']} (h {s['h']}) cuts through {b['name']} ({b['z0']}..{b['z1']})")
        if s["h"] > 0.5 and s["name"] not in covers:
            ok = False
            for b in data["solids"]:
                if abs(b["z1"] - s["h"]) < 1e-3 and b["x0"] <= s["x0"] + 0.5 and b["x1"] >= s["x1"] - 0.5 and b["y0"] <= s["y0"] + 0.5 and b["y1"] >= s["y1"] - 0.5:
                    ok = True
            if not ok:
                err.append(f"surface {s['name']} (h {s['h']}) has nothing under it")
    # Gaps: the clearance each trap spot promises.
    fits = {"standard": (1.05, 1.45), "mini": (0.75, 0.95)}
    for t in Rm["spots"]["traps"]:
        if t["kind"] != "gap":
            continue
        over = [b for b in data["solids"] if b["name"] != "wall" and b["z0"] > 1e-6 and b["x0"] < t["x1"] and b["x1"] > t["x0"] and b["y0"] < t["y1"] and b["y1"] > t["y0"]]
        clear = min((b["z0"] for b in over), default=None)
        want = fits["mini" if "Mini" in t["trap"] else "standard"]
        if clear is None or not (want[0] <= clear <= want[1]) or abs(clear - t["z1"]) > 1e-3:
            err.append(f"gap '{t['trap']}': clearance {clear}, wanted {want} and the spot's {t['z1']}")
    for f in furn:
        for g in f["gaps"]:
            hit = [b for b in f["solids"] if b["name"] == g["solid"]]
            if not hit or any(abs(b["z0"] - g["z0"]) > 1e-3 for b in hit):
                err.append(f"{f['name']}: gap under {g['solid']} is not {g['z0']}")
    # Spots: the goal stands in free space or beside its object; traps' boxes are clear of furniture.
    gl = Rm["spots"]["goal"]
    for b in data["solids"]:
        if b["x0"] < gl["x"] < b["x1"] and b["y0"] < gl["y"] < b["y1"] and b["z0"] < gl["h"] + 0.5 < b["z1"]:
            err.append(f"goal spot is inside {b['name']}")
    for t in Rm["spots"]["traps"]:
        if t["kind"] == "support":
            for b in data["solids"]:
                if overlap3(dict(t), b):
                    err.append(f"trap '{t['trap']}' overlaps {b['name']}")
    return err


def lua_val(v):
    if isinstance(v, (list, tuple)) and len(v) and all(isinstance(x, dict) for x in v):
        return "{ " + ", ".join(lua_val(x) for x in v) + " }"
    return R.lua_val(v)


def write_room(Rm, data):
    d = np.array(Rm["sun"]["dir"], float)
    d /= np.linalg.norm(d)
    sun_e = (round(float(d[0]), 4), round(float(d[2]), 4), round(float(-d[1]), 4))
    lamp = Rm["lamp"]
    cam = Rm["camera"]
    lines = ["-- Generated by tools/gen_house.py from tools/house_rooms.py: do not edit by hand (change the spec and re-run it).",
             "-- Table units (a domino is 1 tall); engine position = (x, h, -y). Same schema as free_room.lua, plus:",
             "-- id, name; pending (Tripo furniture not imported yet: its solids and surfaces are here, its mesh is not);",
             "-- spots (where the goal object and each trap are meant to go); pieces may carry goal = true (the chapter's",
             "-- goal object, always shown) or trap = \"<trap>\" (shown only when a challenge installs that trap).",
             "return {",
             f"    id = {lua_val(Rm['id'])},",
             f"    name = {lua_val(Rm['name'])},",
             f"    bounds = {lua_val(dict(x0=Rm['x0'], x1=Rm['x1'], y0=Rm['y0'], y1=Rm['y1']))},",
             f"    wall_h = {lua_val(Rm['wall_h'])},"]
    if "knee" in Rm:
        lines.append(f"    knee_h = {lua_val(Rm['knee'])},")
    lines.append("    surfaces = {")
    lines += ["        " + lua_val(s) + "," for s in data["surfaces"]]
    lines += ["    },", "    solids = {"]
    lines += ["        " + lua_val(s) + "," for s in data["solids"]]
    lines += ["    },", "    pieces = {"]
    lines += ["        " + lua_val(p) + "," for p in data["pieces"]]
    lines += ["    },", "    pending = { " + ", ".join(lua_val(n) for n in data["pending"]) + " },"]
    sp = Rm["spots"]
    lines += ["    spots = {", "        goal = " + lua_val(sp["goal"]) + ",", "        traps = {"]
    lines += ["            " + lua_val(t) + "," for t in sp["traps"]]
    lines += ["        },", "    },",
              f"    sun = {lua_val(dict(dir=sun_e, color=HR.SUN_COLOR, intensity=Rm['sun']['intensity']))},",
              f"    fill = {lua_val(dict(dir=Rm['fill']['dir'], color=(0.78, 0.86, 1.0), intensity=Rm['fill']['intensity']))},",
              f"    lamp = {lua_val(dict(pos=E(*lamp['at']), color=lamp['color'], intensity=lamp['intensity'], radius=lamp['radius']))},",
              f"    camera = {lua_val(dict(target=cam['target'], yaw=cam['yaw'], pitch=cam['pitch'], dist=cam['dist']))},",
              "}", ""]
    os.makedirs(ROOMS_DIR, exist_ok=True)
    path = os.path.join(ROOMS_DIR, Rm["id"] + ".lua")
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines))
    return path


# ================================================================== scene listing (gen_meshes.write_scene)
def scene_names():
    """The house's template meshes, in room order, read back from the generated rooms/<id>.lua."""
    out = []
    if IN_BLENDER:
        return out
    for Rm in HR.ROOMS:
        path = os.path.join(ROOMS_DIR, Rm["id"] + ".lua")
        if not os.path.exists(path):
            continue
        txt = open(path).read()
        block = txt.split("    pieces = {", 1)[1].split("\n    },", 1)[0]
        out += re.findall(r'\{ name = "([^"]+)"', block)
    return out


# ================================================================== the luajit check
LUA_CHECK = r"""
local F = dofile("Assets/Scripts/topple_free.lua")
local ids = { ... }
local fails = 0
for _, id in ipairs(ids) do
    local room = dofile("Assets/Scripts/rooms/" .. id .. ".lua")
    for _, k in ipairs({ "id", "name", "bounds", "wall_h", "surfaces", "solids", "pieces", "sun", "fill", "lamp", "camera" }) do
        if room[k] == nil then print("FAIL " .. id .. ": no " .. k); fails = fails + 1 end
    end
    F.set_room(room)
    local placed, total = 0, 0
    for _, s in ipairs(room.surfaces) do
        total = total + 1
        local best = 0
        local w, d = s.x1 - s.x0, s.y1 - s.y0
        local want = math.max(w, d) >= 2.0 and 2 or 1
        -- Lines along the long side at several offsets across it, then the short side.
        local tries = {}
        for k = 1, 9 do
            local f = k / 10
            if w >= d then tries[#tries + 1] = { s.x0 + 0.4, s.y0 + d * f, s.x1 - 0.4, s.y0 + d * f }
            else tries[#tries + 1] = { s.x0 + w * f, s.y0 + 0.4, s.x0 + w * f, s.y1 - 0.4 } end
        end
        for _, t in ipairs(tries) do
            local b = F.new_board()
            b:begin_action()
            b:place_line(t[1], t[2], t[3], t[4], function() return "cream" end, s.h)
            b:end_action()
            local n = 0
            for _, p in pairs(b.pieces) do if math.abs(p.z - s.h) < 1e-4 then n = n + 1 end end
            if n > best then best = n end
            if best >= want then break end
        end
        if best >= want then placed = placed + 1
        else print(string.format("FAIL %s: no domino line on '%s' (h %.2f), best %d", id, s.name, s.h, best)); fails = fails + 1 end
    end
    -- And a chain runs on the floor: a line across the room's clear middle falls when tipped.
    local b = F.new_board()
    local B = room.bounds
    b:begin_action()
    local n = b:place_line(B.x0 + 2, B.y0 + 1.6, B.x1 - 2, B.y0 + 1.6, function() return "cream" end, 0)
    b:end_action()
    local fallen = F.simulate(b).toppled
    print(string.format("%-8s %d/%d surfaces take a line; floor line %d dominoes, %d fell", id, placed, total, n, fallen))
    if n < 10 or fallen < n * 0.9 then print("FAIL " .. id .. ": the floor chain did not run"); fails = fails + 1 end
end
if fails > 0 then error(fails .. " failures") end
print("PASS rooms load and take dominoes")
"""


def lua_check(ids):
    src = os.path.join(WORK, "rooms_check.lua")
    os.makedirs(WORK, exist_ok=True)
    with open(src, "w", newline="\n") as f:
        f.write(LUA_CHECK)
    r = subprocess.run([LUAJIT, src] + ids, cwd=ROOT, capture_output=True, text=True)
    print((r.stdout + r.stderr).strip())
    return r.returncode == 0


# ================================================================== cook, preview
def cook(meshes):
    """meshes: name -> MU or an OBJ path."""
    # (not G.find_cook: it takes the first argument as the cook's path, and here that is the Tripo folder)
    eng = os.path.normpath(os.path.join(ROOT, "..", "..", "PhasmaEngine"))
    ck = os.environ.get("PHASMA_COOK") or next((os.path.join(eng, b, "Release", "PhasmaCook.exe") for b in ("build-ninja-physics", "build-ninja")
                                               if os.path.exists(os.path.join(eng, b, "Release", "PhasmaCook.exe"))), None)
    if not ck:
        raise SystemExit("PhasmaCook.exe not found (set PHASMA_COOK)")
    os.makedirs(OBJECTS, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="topple-house-") as tmp:
        lines = []
        for name, m in meshes.items():
            if isinstance(m, str):
                src = m
            else:
                src = os.path.join(tmp, name + ".obj")
                R.save_obj_uv(src, m)
            lines.append(f"{src}\t{os.path.join(OBJECTS, name + '.pemesh')}\n")
        manifest = os.path.join(tmp, "batch.txt")
        with open(manifest, "w", encoding="utf-8") as f:
            f.writelines(lines)
        r = subprocess.run([ck, "--batch", manifest], cwd=os.path.dirname(ck), capture_output=True, text=True)
        if r.returncode != 0 or f"{len(lines)} ok" not in (r.stdout + r.stderr):
            print((r.stdout + r.stderr)[-3000:])
            raise SystemExit("PhasmaCook failed")
    print("cooked", len(meshes), "meshes")


def preview(Rm, room, furn, objdir):
    """Blender render of the room from its starting camera; furniture not yet imported is drawn as its design boxes."""
    os.makedirs(objdir, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    objs = []
    # As in the game: a wall's decor is hidden while the camera is behind that wall.
    c = Rm["camera"]
    cp = math.cos(math.radians(c["pitch"]))
    px = c["target"][0] + c["dist"] * cp * math.cos(math.radians(c["yaw"]))
    py = c["target"][1] + c["dist"] * cp * math.sin(math.radians(c["yaw"]))
    behind = {"L": px < Rm["x0"], "R": px > Rm["x1"], "B": py > Rm["y1"], "F": py < Rm["y0"]}
    for name, (m, look) in sorted(room.pieces.items()):
        if look.get("group") and behind[look["group"]]:
            continue
        p = os.path.join(objdir, name + ".obj")
        R.save_obj_uv(p, m)
        lk = dict(look)
        for k in ("tex", "emis_tex"):
            if k in lk:
                lk[k] = os.path.join(ROOT, "Assets", lk[k])
        objs.append(dict(path=p, name=name, look=lk))
    pal = [(0.55, 0.38, 0.24), (0.42, 0.46, 0.5), (0.6, 0.52, 0.4), (0.36, 0.42, 0.34), (0.58, 0.34, 0.3), (0.5, 0.44, 0.56)]
    boxes = []
    for i, f in enumerate(furn):
        if f["pending"]:
            boxes.append(dict(name=f["name"], color=pal[sum(map(ord, f["item"])) % len(pal)], solids=f["solids"]))
        else:
            objs.append(dict(path=os.path.join(objdir, f["name"] + ".obj"), name=f["name"], look=dict(color=(1, 1, 1), rough=0.8, tex=os.path.join(TEX, f["base"] + ".png"))))
    spec = dict(room=Rm["id"], objs=objs, boxes=boxes, camera=Rm["camera"], sun=Rm["sun"], fill=Rm["fill"], lamp=Rm["lamp"],
                hdr=os.path.join(ROOT, "Assets", "Skybox", "day.hdr"), out=os.path.join(PREVIEW_DIR, Rm["id"] + ".png"))
    sp = os.path.join(objdir, "spec.json")
    with open(sp, "w") as fo:
        json.dump(spec, fo)
    return sp


def render(specs):
    for sp in specs:
        r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.abspath(__file__), "--", "--render", sp], capture_output=True, text=True)
        out = json.load(open(sp))["out"]
        ok = os.path.exists(out) and "RENDERED" in r.stdout
        print("preview:", out if ok else "FAILED")
        if not ok:
            print(r.stdout[-3000:], r.stderr[-3000:])


# ================================================================== main
def refit(tripo, bases):
    """--refit=<base,...>: re-import (from the cache) and re-cook only these furniture models, placed as the spec says.
    Writes nothing else: not the rooms' data, not the scene, not the other meshes."""
    meshes = {}
    with tempfile.TemporaryDirectory(prefix="topple-refit-") as tmp:
        for Rm in HR.ROOMS:
            want = [f for f in Rm["furniture"] if f"furn_{Rm['id']}_{f['item']}" in bases]
            if not want:
                continue
            sub = dict(Rm, furniture=want)
            imported = import_furniture(sub, tripo, tmp)
            refused = {b for b, _ in CANNOT}
            for f in furniture(sub, imported):
                if f["base"] in refused:
                    print("not re-cooked (cannot fit):", f["name"])
                elif not f["pending"]:
                    dst = os.path.join(tmp, f["name"] + ".obj")
                    place_obj(imported[f["item"]]["obj"], dst, f["yaw"], f["at"], f["z"])
                    meshes[f["name"]] = dst
        print("re-cooking:", ", ".join(sorted(meshes)))
        if meshes and "--no-cook" not in sys.argv:
            cook(meshes)
    return meshes


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    tripo = args[0] if args else None
    rf = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--refit=")), None)
    if rf:
        refit(tripo, set(rf))
        return
    only = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")), None)
    rooms = [r for r in HR.ROOMS if not only or r["id"] in only]
    if "--check" in sys.argv and len(sys.argv) == 2:
        raise SystemExit(0 if lua_check([r["id"] for r in rooms]) else 1)
    work = os.path.join(WORK, "objs")
    bad = False
    built = []
    with tempfile.TemporaryDirectory(prefix="topple-furn-") as tmp:
        for Rm in rooms:
            imported = import_furniture(Rm, tripo, tmp)
            room, furn = build(Rm, imported)
            err = validate(Rm, room, furn)
            pend = [f["name"] for f in furn if f["pending"]]
            print(f"{Rm['id']:8s} {Rm['x1'] - Rm['x0']:.0f} x {Rm['y1'] - Rm['y0']:.0f} x {Rm['wall_h']:.0f}  pieces {len(room.pieces)}  "
                  f"furniture {len(furn)} ({len(pend)} pending)  {'OK' if not err else 'INVALID'}")
            for e in err:
                print("   ", e)
            bad = bad or bool(err)
            built.append((Rm, room, furn, imported))
        if bad:
            raise SystemExit("validation failed: nothing written")
        meshes = {}
        specs = []
        for Rm, room, furn, imported in built:
            if "--no-tex" not in sys.argv:
                textures(Rm)
            data = room_data(Rm, room, furn)
            print("data:", write_room(Rm, data))
            for name, (m, _) in room.pieces.items():
                meshes[name] = m
            for f in furn:
                if not f["pending"]:
                    dst = os.path.join(tmp, f["name"] + ".obj")
                    place_obj(imported[f["item"]]["obj"], dst, f["yaw"], f["at"], f["z"])
                    meshes[f["name"]] = dst
            if "--preview" in sys.argv:
                od = os.path.join(work, Rm["id"])
                for f in furn:
                    if not f["pending"]:
                        os.makedirs(od, exist_ok=True)
                        place_obj(imported[f["item"]]["obj"], os.path.join(od, f["name"] + ".obj"), f["yaw"], f["at"], f["z"])
                specs.append(preview(Rm, room, furn, od))
        if "--no-cook" not in sys.argv:
            cook(meshes)
    G.write_scene(sorted(G.MESHES))
    print("scene:", G.SCENE)
    if specs:
        render(specs)
    if "--check" in sys.argv:
        if not lua_check([r["id"] for r in rooms]):
            raise SystemExit("room check failed")


# ================================================================== Blender side of --preview
def blender_render(spec_path):
    import bpy
    from mathutils import Vector
    spec = json.load(open(spec_path))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    col = sc.collection

    def mat(name, L):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        N, Lk = m.node_tree.nodes, m.node_tree.links
        p = N["Principled BSDF"]
        c = L.get("color", (1, 1, 1))
        p.inputs["Base Color"].default_value = (*c, 1)
        p.inputs["Roughness"].default_value = L.get("rough", 0.5)
        p.inputs["Metallic"].default_value = L.get("metal", 0.0)
        if L.get("tex"):
            t = N.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(L["tex"])
            mix = N.new("ShaderNodeMixRGB"); mix.blend_type = "MULTIPLY"; mix.inputs[0].default_value = 1.0
            mix.inputs[1].default_value = (*c, 1)
            Lk.new(t.outputs["Color"], mix.inputs[2]); Lk.new(mix.outputs[0], p.inputs["Base Color"])
        out = N["Material Output"]
        surf = p.outputs["BSDF"]
        if L.get("transmission"):
            tr = N.new("ShaderNodeBsdfTransparent")
            em = N.new("ShaderNodeEmission")
            if L.get("emis_tex"):
                t = N.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(L["emis_tex"])
                Lk.new(t.outputs["Color"], em.inputs["Color"]); em.inputs["Strength"].default_value = 1.6
            else:
                em.inputs["Color"].default_value = (*L.get("emis", (0.8, 0.8, 0.8)), 1); em.inputs["Strength"].default_value = 0.6
            if L.get("emis") or L.get("emis_tex"):
                lp = N.new("ShaderNodeLightPath")
                mx = N.new("ShaderNodeMixShader")
                Lk.new(lp.outputs["Is Camera Ray"], mx.inputs["Fac"])
                Lk.new(tr.outputs["BSDF"], mx.inputs[1]); Lk.new(em.outputs["Emission"], mx.inputs[2])
                surf = mx.outputs[0]
            else:              # clear glass: see-through with a little gloss
                gl = N.new("ShaderNodeBsdfGlossy"); gl.inputs["Roughness"].default_value = 0.05
                mx = N.new("ShaderNodeMixShader"); mx.inputs["Fac"].default_value = 0.45
                Lk.new(tr.outputs["BSDF"], mx.inputs[1]); Lk.new(gl.outputs["BSDF"], mx.inputs[2])
                surf = mx.outputs[0]
        elif L.get("emis"):
            p.inputs["Emission Color"].default_value = (*L["emis"], 1)
            p.inputs["Emission Strength"].default_value = 2.5
        # Seen from behind by the camera, a face is not there (the game's one-sided walls); light still sees it.
        geo = N.new("ShaderNodeNewGeometry")
        lp2 = N.new("ShaderNodeLightPath")
        mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
        Lk.new(geo.outputs["Backfacing"], mul.inputs[0]); Lk.new(lp2.outputs["Is Camera Ray"], mul.inputs[1])
        tr2 = N.new("ShaderNodeBsdfTransparent")
        mx2 = N.new("ShaderNodeMixShader")
        Lk.new(mul.outputs[0], mx2.inputs["Fac"])
        Lk.new(surf, mx2.inputs[1]); Lk.new(tr2.outputs["BSDF"], mx2.inputs[2])
        Lk.new(mx2.outputs[0], out.inputs["Surface"])
        return m

    for o in spec["objs"]:
        before = set(bpy.data.objects)
        bpy.ops.wm.obj_import(filepath=o["path"], forward_axis="NEGATIVE_Z", up_axis="Y")
        for ob in set(bpy.data.objects) - before:
            ob.data.materials.clear()
            ob.data.materials.append(mat(o["name"], o["look"]))
            for poly in ob.data.polygons:
                poly.use_smooth = True
            if o["look"].get("emis") and not o["look"].get("transmission"):
                ob.visible_shadow = False      # the lamp's light sits inside its glowing shade
            if o["name"].endswith(("_ceiling", "_roof")):
                # The game's image light reaches the room unblocked; the ceiling still keeps the sun out.
                ob.visible_diffuse = False
                ob.visible_glossy = False
    for b in spec["boxes"]:
        m = mat(b["name"], dict(color=b["color"], rough=0.6))
        for s in b["solids"]:
            bpy.ops.mesh.primitive_cube_add(size=1, location=((s["x0"] + s["x1"]) / 2, (s["y0"] + s["y1"]) / 2, (s["z0"] + s["z1"]) / 2))
            ob = bpy.context.active_object
            ob.scale = (s["x1"] - s["x0"], s["y1"] - s["y0"], s["z1"] - s["z0"])
            bev = ob.modifiers.new("b", "BEVEL"); bev.width = 0.12; bev.segments = 2
            ob.data.materials.append(m)
    # Lights: the sun along its direction, a soft fill, the lamp.
    def aim(ob, d):
        ob.rotation_euler = Vector((-d[0], -d[1], -d[2])).to_track_quat("Z", "Y").to_euler()

    sd = spec["sun"]["dir"]
    L = math.sqrt(sum(c * c for c in sd))
    sd = [c / L for c in sd]
    sun = bpy.data.lights.new("sun", "SUN"); sun.energy = spec["sun"]["intensity"] * 1.1; sun.color = (1.0, 0.88, 0.72); sun.angle = math.radians(1.5)
    so = bpy.data.objects.new("sun", sun); col.objects.link(so); aim(so, sd)
    fl = bpy.data.lights.new("fill", "SUN"); fl.energy = spec["fill"]["intensity"] * 0.6; fl.color = (0.78, 0.86, 1.0); fl.angle = math.radians(20)
    fo = bpy.data.objects.new("fill", fl); col.objects.link(fo); aim(fo, spec["fill"]["dir"])
    lp = spec["lamp"]
    pl = bpy.data.lights.new("lamp", "POINT"); pl.energy = lp["intensity"] * 2500; pl.color = lp["color"]; pl.shadow_soft_size = 1.2
    po = bpy.data.objects.new("lamp", pl); col.objects.link(po); po.location = lp["at"]
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    env = w.node_tree.nodes.new("ShaderNodeTexEnvironment"); env.image = bpy.data.images.load(spec["hdr"])
    bg = w.node_tree.nodes["Background"]; bg.inputs["Strength"].default_value = 0.8
    w.node_tree.links.new(env.outputs["Color"], bg.inputs["Color"])
    # Camera: the room's starting view (the game's vertical fov is 40 degrees).
    c = spec["camera"]
    t = c["target"]
    cp, sp_ = math.cos(math.radians(c["pitch"])), math.sin(math.radians(c["pitch"]))
    pos = (t[0] + c["dist"] * cp * math.cos(math.radians(c["yaw"])), t[1] + c["dist"] * cp * math.sin(math.radians(c["yaw"])), t[2] + c["dist"] * sp_)
    cam = bpy.data.cameras.new("cam"); cam.sensor_fit = "VERTICAL"; cam.angle_y = math.radians(40); cam.clip_start = 1.0; cam.clip_end = 1000
    co = bpy.data.objects.new("cam", cam); col.objects.link(co); co.location = pos
    co.rotation_euler = (Vector(t) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = co
    sc.render.engine = "CYCLES"
    sc.cycles.samples = int(os.environ.get("HOUSE_SAMPLES", "96"))
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.cycles.transparent_max_bounces = 16
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                if any(d.type == kind for d in prefs.devices):
                    for d in prefs.devices:
                        d.use = d.type == kind
                    sc.cycles.device = "GPU"
                    break
            except TypeError:
                continue
    except Exception as e:  # noqa: BLE001
        print("GPU setup failed, CPU render:", e)
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.render.resolution_x, sc.render.resolution_y = int(os.environ.get("HOUSE_W", "1600")), int(os.environ.get("HOUSE_H", "900"))
    sc.render.filepath = spec["out"]
    bpy.ops.render.render(write_still=True)
    print("RENDERED", spec["out"])


if __name__ == "__main__":
    if IN_BLENDER:
        a = sys.argv[sys.argv.index("--") + 1:]
        blender_render(a[a.index("--render") + 1])
    else:
        main()
