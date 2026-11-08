"""Topple Free Build room: a living room at domino scale (1 unit = a domino's height, about 5 cm), its textures and
the data the rules and world need (Assets/Scripts/free_room.lua: the surfaces you can build on, the solid furniture
that blocks placing and stops a falling domino, the lights and the starting camera).

    python tools/gen_room.py [path/to/PhasmaCook.exe]     (--no-cook: textures and data only)

Then it rewrites Assets/Scenes/main.pescene through gen_meshes.write_scene, which lists one hidden template node
per room piece (T_room_*). The game clones them under one root when Free Build opens.

Walls and the ceiling are single faces looking into the room: the camera sees through them from outside (a
dollhouse cut-away), while the engine's shadow pass draws both sides, so the sun only gets in through the window.
Table coordinates as everywhere in Topple: x right, y away from the default camera, h up; engine (x, h, -y).
"""
import math
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_meshes as G  # noqa: E402

ROOT = G.ROOT
TEX = os.path.join(ROOT, "Assets", "Textures")
SKY = os.path.join(ROOT, "Assets", "Skybox")
DATA = os.path.join(ROOT, "Assets", "Scripts", "free_room.lua")
OBJECTS = G.OBJECTS

# ------------------------------------------------------------------ the room, in table units
X0, X1, Y0, Y1 = -40.0, 40.0, -34.0, 34.0   # inner walls (4.0 m by 3.4 m)
WALL_H = 48.0
WIN = dict(y0=-9.0, y1=21.0, h0=14.0, h1=40.0)          # window in the left wall
DOOR = dict(y0=-27.0, y1=-11.0, h1=41.0)                 # door in the right wall
SKIRT_H, SKIRT_T = 2.4, 0.4
SOFA = dict(x0=-30.0, x1=6.0, y0=17.8, y1=33.7, h=16.8)
SEAT_H = 9.0
TABLE = dict(x0=-25.0, x1=-1.0, y0=-4.6, y1=6.6, h=8.8, t=1.45)
RUG = dict(x0=-39.0, x1=13.0, y0=-18.0, y1=20.0, h=0.12)
SHELF = dict(x0=12.0, x1=36.0, y0=26.2, y1=34.0, h=37.92)
SIDE = dict(x=-35.0, y=28.0, r=3.2, h=11.0)
PLANT = dict(x=-32.5, y=-25.9, r=3.6, h=8.7)   # the pot; the leaves reach 13 further out, above a domino chain
# What stands on the Tripo bookshelf's top board (measured from the model: tools/furniture_import.py placement).
SHELF_TOP = [dict(name="vase", x0=16.37, x1=19.69, y0=28.44, y1=31.72, z0=37.92, z1=42.61),
             dict(name="plant pot", x0=27.63, x1=30.87, y0=28.08, y1=31.3, z0=37.92, z1=39.54),
             dict(name="shelf plant", x0=26.96, x1=31.94, y0=27.22, y1=31.97, z0=39.54, z1=42.78)]
STAIRS = dict(x0=12.0, x1=36.0, y0=-23.0, y1=-15.0, step=2.0, rise=0.45, n=5)
BOOK_COLS = ["red", "navy", "mustard", "sage", "plum"]
# Tripo furniture (tools/make_furniture.py): where it stands, its length along x before the yaw (or height), its yaw.
FURNITURE = {
    "furn_sofa": dict(at=((SOFA["x0"] + SOFA["x1"]) / 2, (SOFA["y0"] + SOFA["y1"]) / 2), size_x=36.0, yaw=0.0),
    "furn_coffeetable": dict(at=((TABLE["x0"] + TABLE["x1"]) / 2, (TABLE["y0"] + TABLE["y1"]) / 2), size_x=24.0, yaw=0.0),
    "furn_bookshelf": dict(at=((SHELF["x0"] + SHELF["x1"]) / 2, (SHELF["y0"] + SHELF["y1"]) / 2), size_x=24.0, yaw=0.0),
    "furn_armchair": dict(at=(-32.4, 10.2), size_x=14.5, yaw=90.0),
    "furn_plant": dict(at=(PLANT["x"], PLANT["y"]), size_z=26.0, yaw=30.0),
}


def E(x, y, h):
    return (x, h, -y)


def EN(nx, ny, nh):
    return (nx, nh, -ny)


# ------------------------------------------------------------------ mesh with UVs
class MU:
    def __init__(s):
        s.V, s.N, s.T, s.F = [], [], [], []

    def quad(s, p, n, uv=((0, 0), (1, 0), (1, 1), (0, 1))):
        """p: four engine-space corners in order around the face; n: engine normal."""
        b = len(s.V)
        for i in range(4):
            s.V.append(np.array(p[i], float)); s.N.append(np.array(n, float)); s.T.append(uv[i])
        s.F += [(b, b + 1, b + 2), (b, b + 2, b + 3)]
        return s

    def mesh(s, m, uvf=None):
        """Append a gen_meshes M (engine space) with uv = uvf(v, n) or (0, 0)."""
        b = len(s.V)
        for v, n in zip(m.V, m.N):
            s.V.append(np.array(v, float)); s.N.append(np.array(n, float))
            s.T.append(uvf(v, n) if uvf else (0.0, 0.0))
        s.F += [(a + b, c + b, d + b) for a, c, d in m.F]
        return s

    def __iadd__(s, o):
        b = len(s.V)
        s.V += o.V; s.N += o.N; s.T += o.T
        s.F += [(a + b, c + b, d + b) for a, c, d in o.F]
        return s


def save_obj_uv(path, m):
    V, N = np.array(m.V), np.array(m.N)
    with open(path, "w") as fo:
        fo.write("o mesh\n")
        for p in V:
            fo.write("v %.5f %.5f %.5f\n" % tuple(p))
        for t in m.T:
            fo.write("vt %.5f %.5f\n" % (t[0], t[1]))
        for nn in N:
            L = np.linalg.norm(nn)
            nn = nn / L if L > 1e-9 else np.array([0, 1.0, 0])
            fo.write("vn %.5f %.5f %.5f\n" % tuple(nn))
        tris = 0
        for a, b, c in m.F:
            fn = np.cross(V[b] - V[a], V[c] - V[a])
            if np.linalg.norm(fn) < 1e-9:
                continue
            if np.dot(fn, N[a] + N[b] + N[c]) < 0:
                b, c = c, b
            fo.write(f"f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n")
            tris += 1
    return len(V), tris


def box(x0, x1, y0, y1, h0, h1, faces="xXyYhH", uvs=None):
    """Axis-aligned box in table coordinates with flat faces. uvs: world units per texture repeat (box projection)."""
    m = MU()

    def uv(a, b):
        return (a / uvs, b / uvs) if uvs else (0.0, 0.0)

    if "H" in faces:   # top
        m.quad([E(x0, y0, h1), E(x1, y0, h1), E(x1, y1, h1), E(x0, y1, h1)], EN(0, 0, 1),
               [uv(x0, y0), uv(x1, y0), uv(x1, y1), uv(x0, y1)])
    if "h" in faces:
        m.quad([E(x0, y0, h0), E(x0, y1, h0), E(x1, y1, h0), E(x1, y0, h0)], EN(0, 0, -1),
               [uv(x0, y0), uv(x0, y1), uv(x1, y1), uv(x1, y0)])
    if "x" in faces:
        m.quad([E(x0, y0, h0), E(x0, y0, h1), E(x0, y1, h1), E(x0, y1, h0)], EN(-1, 0, 0),
               [uv(y0, h0), uv(y0, h1), uv(y1, h1), uv(y1, h0)])
    if "X" in faces:
        m.quad([E(x1, y0, h0), E(x1, y1, h0), E(x1, y1, h1), E(x1, y0, h1)], EN(1, 0, 0),
               [uv(y0, h0), uv(y1, h0), uv(y1, h1), uv(y0, h1)])
    if "y" in faces:
        m.quad([E(x0, y0, h0), E(x1, y0, h0), E(x1, y0, h1), E(x0, y0, h1)], EN(0, -1, 0),
               [uv(x0, h0), uv(x1, h0), uv(x1, h1), uv(x0, h1)])
    if "Y" in faces:
        m.quad([E(x0, y1, h0), E(x0, y1, h1), E(x1, y1, h1), E(x1, y1, h0)], EN(0, 1, 0),
               [uv(x0, h0), uv(x0, h1), uv(x1, h1), uv(x1, h0)])
    return m


def rbox_t(x0, x1, y0, y1, h0, h1, r, nseg=3):
    """A gen_meshes rounded box placed by table-coordinate bounds."""
    c = E((x0 + x1) / 2, (y0 + y1) / 2, (h0 + h1) / 2)
    return G.rbox(c, (x1 - x0, h1 - h0, y1 - y0), r, nseg)


# ------------------------------------------------------------------ pieces
def wall_panel(m, along0, along1, h0, h1, side):
    """One inward-facing rectangle of wall. side: L (x = X0), R (x = X1), B (y = Y1), F (y = Y0)."""
    S = 24.0
    if side == "L":
        m.quad([E(X0, along0, h0), E(X0, along1, h0), E(X0, along1, h1), E(X0, along0, h1)], EN(1, 0, 0),
               [(along0 / S, h0 / S), (along1 / S, h0 / S), (along1 / S, h1 / S), (along0 / S, h1 / S)])
    elif side == "R":
        m.quad([E(X1, along0, h0), E(X1, along0, h1), E(X1, along1, h1), E(X1, along1, h0)], EN(-1, 0, 0),
               [(-along0 / S, h0 / S), (-along0 / S, h1 / S), (-along1 / S, h1 / S), (-along1 / S, h0 / S)])
    elif side == "B":
        m.quad([E(along0, Y1, h0), E(along0, Y1, h1), E(along1, Y1, h1), E(along1, Y1, h0)], EN(0, -1, 0),
               [(along0 / S, h0 / S), (along0 / S, h1 / S), (along1 / S, h1 / S), (along1 / S, h0 / S)])
    else:
        m.quad([E(along0, Y0, h0), E(along1, Y0, h0), E(along1, Y0, h1), E(along0, Y0, h1)], EN(0, 1, 0),
               [(-along0 / S, h0 / S), (-along1 / S, h0 / S), (-along1 / S, h1 / S), (-along0 / S, h1 / S)])


def wall_L():
    m = MU()
    w = WIN
    wall_panel(m, Y0, Y1, 0, w["h0"], "L")
    wall_panel(m, Y0, Y1, w["h1"], WALL_H, "L")
    wall_panel(m, Y0, w["y0"], w["h0"], w["h1"], "L")
    wall_panel(m, w["y1"], Y1, w["h0"], w["h1"], "L")
    # The reveal: the wall's thickness around the opening.
    d = 1.4
    m += box(X0 - d, X0, w["y0"] - 0.001, w["y0"], w["h0"], w["h1"], "Y", 24)
    m += box(X0 - d, X0, w["y1"], w["y1"] + 0.001, w["h0"], w["h1"], "y", 24)
    m += box(X0 - d, X0, w["y0"], w["y1"], w["h1"], w["h1"] + 0.001, "h", 24)
    return m


def wall_R():
    m = MU()
    d = DOOR
    wall_panel(m, Y0, d["y0"], 0, WALL_H, "R")
    wall_panel(m, d["y1"], Y1, 0, WALL_H, "R")
    wall_panel(m, d["y0"], d["y1"], d["h1"], WALL_H, "R")
    return m


def wall_B():
    m = MU()
    wall_panel(m, X0, X1, 0, WALL_H, "B")
    return m


def wall_F():
    m = MU()
    wall_panel(m, X0, X1, 0, WALL_H, "F")
    return m


def ceiling():
    m = MU()
    m.quad([E(X0 - 2, Y0 - 2, WALL_H), E(X0 - 2, Y1 + 2, WALL_H), E(X1 + 2, Y1 + 2, WALL_H), E(X1 + 2, Y0 - 2, WALL_H)], EN(0, 0, -1))
    return m


def floor():
    m = MU()
    S = 16.0
    m.quad([E(X0, Y0, 0), E(X1, Y0, 0), E(X1, Y1, 0), E(X0, Y1, 0)], EN(0, 0, 1),
           [(X0 / S, Y0 / S), (X1 / S, Y0 / S), (X1 / S, Y1 / S), (X0 / S, Y1 / S)])
    return m


def skirting(side):
    """Painted skirting board along one wall, with a rounded top edge (the door breaks the right one)."""
    m = MU()
    t, h = SKIRT_T, SKIRT_H
    runs = {"L": [(Y0, Y1)], "B": [(X0, X1)], "F": [(X0, X1)], "R": [(Y0, DOOR["y0"] - 1.2), (DOOR["y1"] + 1.2, Y1)]}[side]
    for a0, a1 in runs:
        if side == "L":
            m.mesh(rbox_t(X0 - 0.2, X0 + t, a0, a1, 0, h, 0.12))
        elif side == "R":
            m.mesh(rbox_t(X1 - t, X1 + 0.2, a0, a1, 0, h, 0.12))
        elif side == "B":
            m.mesh(rbox_t(a0, a1, Y1 - t, Y1 + 0.2, 0, h, 0.12))
        else:
            m.mesh(rbox_t(a0, a1, Y0 - 0.2, Y0 + t, 0, h, 0.12))
    return m


def trim_L():
    """The left wall's skirting (hidden with the wall's other decor when the camera is behind that wall)."""
    return skirting("L")


def window_frame():
    """Window frame, glazing bars and sill (painted). Never hidden: they shape the sunlight on the floor, and a
    hidden node casts no shadow, so hiding them would change the light as the camera moved."""
    m = MU()
    w = WIN
    f, d = 1.1, 0.9
    x0, x1 = X0 - 0.9, X0 + 0.25
    m.mesh(rbox_t(x0, x1, w["y0"] - f, w["y0"] + 0.15, w["h0"] - f, w["h1"] + f, 0.12))
    m.mesh(rbox_t(x0, x1, w["y1"] - 0.15, w["y1"] + f, w["h0"] - f, w["h1"] + f, 0.12))
    m.mesh(rbox_t(x0, x1, w["y0"] - f, w["y1"] + f, w["h1"] - 0.15, w["h1"] + f, 0.12))
    m.mesh(rbox_t(X0 - 0.4, X0 + 1.9, w["y0"] - 2.0, w["y1"] + 2.0, w["h0"] - 0.9, w["h0"] + 0.15, 0.18))   # sill
    # Sashes: a meeting rail and two glazing bars each way.
    xm0, xm1 = X0 - 0.75, X0 - 0.35
    hm = (w["h0"] + w["h1"]) / 2
    m.mesh(rbox_t(xm0, xm1, w["y0"], w["y1"], hm - 0.5, hm + 0.5, 0.1))
    for k in (1, 2):
        y = w["y0"] + (w["y1"] - w["y0"]) * k / 3
        m.mesh(rbox_t(xm0, xm1, y - 0.22, y + 0.22, w["h0"], w["h1"], 0.06))
    for hh in (w["h0"] + (hm - w["h0"]) / 2, hm + (w["h1"] - hm) / 2):
        m.mesh(rbox_t(xm0, xm1, w["y0"], w["y1"], hh - 0.2, hh + 0.2, 0.06))
    _ = d
    return m


def glass():
    m = MU()
    w = WIN
    x = X0 - 0.6
    m.quad([E(x, w["y0"], w["h0"]), E(x, w["y1"], w["h0"]), E(x, w["y1"], w["h1"]), E(x, w["y0"], w["h1"])], EN(1, 0, 0))
    return m


def curtains():
    """Two gathered linen curtains either side of the window, on a brass rod (the rod is in brass())."""
    m = MU()
    w = WIN
    top, bot = w["h1"] + 4.5, 2.0
    for ya, yb in ((w["y0"] - 7.5, w["y0"] + 1.0), (w["y1"] - 1.0, w["y1"] + 7.5)):
        nu, nv = 40, 24
        V, N, F = [], [], []
        for j in range(nv + 1):
            hh = bot + (top - bot) * j / nv
            for i in range(nu + 1):
                u = i / nu
                y = ya + (yb - ya) * u
                ph = u * 2 * math.pi * 5
                amp = 0.55 + 0.25 * (1 - j / nv)
                x = X0 + 1.6 + amp * math.sin(ph)
                dx = amp * math.cos(ph) * 2 * math.pi * 5 / (yb - ya)
                n = np.array([1.0, 0.0, dx])     # engine: x, y(up), z = -table y
                n /= np.linalg.norm(n)
                V.append(E(x, y, hh)); N.append(n)
        for j in range(nv):
            for i in range(nu):
                a = j * (nu + 1) + i
                F += [(a, a + 1, a + nu + 2), (a, a + nu + 2, a + nu + 1)]
        mm = G.M().add(V, N, F)
        m.mesh(mm)
        # The back of the cloth, so it reads from the window side as well.
        back = G.M().add(V, [-np.array(n) for n in N], [(a, c, b) for a, b, c in F])
        m.mesh(back)
    return m


def trim_R():
    """Door frame, panelled door (painted), and the skirting."""
    m = skirting("R")
    d = DOOR
    x = X1
    m.mesh(rbox_t(x - 0.6, x + 0.2, d["y0"] - 1.3, d["y0"], 0, d["h1"] + 1.3, 0.15))
    m.mesh(rbox_t(x - 0.6, x + 0.2, d["y1"], d["y1"] + 1.3, 0, d["h1"] + 1.3, 0.15))
    m.mesh(rbox_t(x - 0.6, x + 0.2, d["y0"] - 1.3, d["y1"] + 1.3, d["h1"], d["h1"] + 1.3, 0.15))
    m.mesh(rbox_t(x - 0.35, x + 0.1, d["y0"], d["y1"], 0, d["h1"], 0.05))           # the door leaf
    for (a0, a1, h0, h1) in ((d["y0"] + 1.4, d["y1"] - 1.4, 22.5, d["h1"] - 1.6), (d["y0"] + 1.4, d["y1"] - 1.4, 2.5, 20.0)):
        m.mesh(rbox_t(x - 0.6, x - 0.3, a0, a1, h0, h1, 0.1))                        # raised panels
    return m


def trim_B():
    return skirting("B")


def trim_F():
    return skirting("F")


def frames():
    """Two walnut picture frames above the sofa (the canvases are art1 / art2)."""
    m = MU()
    for (a0, a1, h0, h1) in ART:
        f = 0.9
        y = Y1
        m.mesh(rbox_t(a0 - f, a1 + f, y - 0.5, y, h1, h1 + f, 0.15))
        m.mesh(rbox_t(a0 - f, a1 + f, y - 0.5, y, h0 - f, h0, 0.15))
        m.mesh(rbox_t(a0 - f, a0, y - 0.5, y, h0, h1, 0.15))
        m.mesh(rbox_t(a1, a1 + f, y - 0.5, y, h0, h1, 0.15))
    return m


ART = [(-27.0, -13.0, 25.0, 35.0), (-9.0, 1.0, 23.0, 37.0)]


def canvas(i):
    m = MU()
    a0, a1, h0, h1 = ART[i]
    y = Y1 - 0.25
    m.quad([E(a0, y, h0), E(a0, y, h1), E(a1, y, h1), E(a1, y, h0)], EN(0, -1, 0), [(1, 0), (1, 1), (0, 1), (0, 0)])
    return m


def rug():
    m = MU()
    r = RUG
    w, d = r["x1"] - r["x0"], r["y1"] - r["y0"]

    def uv(v, n):
        x, y = v[0], -v[2]
        return ((x - r["x0"]) / w, (y - r["y0"]) / d)

    m.mesh(rbox_t(r["x0"], r["x1"], r["y0"], r["y1"], -0.05, r["h"], 0.08, 2), uv)
    return m


def moved_t(m, x, y, h, yaw_deg=0.0):
    R = G.rot("y", math.radians(yaw_deg))
    return G.moved(m, E(x, y, h), R)


def walnut():
    """Dark wood: the side table and the picture frames."""
    m = MU()
    # Side table: a turned pedestal on three feet, round top.
    sd = SIDE
    prof = [(0, 0), (0.9, 0), (0.9, 0.5), (0.45, 0.9), (0.55, 3.0), (0.4, 6.5), (0.6, 9.0), (0.5, sd["h"] - 0.5), (0, sd["h"] - 0.5)]
    m.mesh(G.moved(G.lathe(G.smooth_profile(prof, 3), 28), E(sd["x"], sd["y"], 0)))
    for k in range(3):
        a = k * 2 * math.pi / 3 + 0.3
        p0 = E(sd["x"] + math.cos(a) * 0.6, sd["y"] + math.sin(a) * 0.6, 1.0)
        p1 = E(sd["x"] + math.cos(a) * 2.6, sd["y"] + math.sin(a) * 2.6, 0.2)
        m.mesh(G.tube(p0, p1, 0.32, 12))
    m.mesh(G.moved(G.lathe([(0, 0), (sd["r"], 0), (sd["r"] + 0.1, 0.25), (sd["r"], 0.5), (0, 0.5)], 48, sharp=(1, 3)),
                   E(sd["x"], sd["y"], sd["h"] - 0.5)))
    # Picture frames.
    m += frames()
    return m


def books():
    """The staircase of books on the floor: one mesh per cover colour, plus the pages."""
    rng = np.random.default_rng(7)
    covers = {c: MU() for c in BOOK_COLS}
    pages = MU()

    def book(x0, x1, y0, y1, h0, h1, col, yaw=0.0, lie=False):
        """A hardback: cover boards around a cream page block, inset on three sides."""
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        hx, hy, hh = (x1 - x0) / 2, (y1 - y0) / 2, (h1 - h0) / 2
        board = 0.12 if lie else 0.1
        R = G.rot("y", math.radians(yaw))
        if lie:   # lying flat: covers top and bottom, spine on -y
            parts = [(G.rbox((0, -hh + board / 2, 0), (2 * hx, board, 2 * hy), 0.04, 1), covers[col]),
                     (G.rbox((0, hh - board / 2, 0), (2 * hx, board, 2 * hy), 0.04, 1), covers[col]),
                     (G.rbox((0, 0, hy - 0.12), (2 * hx, 2 * hh - 0.02, 0.24), 0.08, 2), covers[col]),
                     (G.rbox((0, 0, -0.06), (2 * hx - 0.3, 2 * hh - 2 * board, 2 * hy - 0.3), 0.02, 1), pages)]
        else:     # standing on a shelf: covers on +-x, spine toward the room (-y)
            parts = [(G.rbox((-hx + board / 2, 0, 0), (board, 2 * hh, 2 * hy), 0.04, 1), covers[col]),
                     (G.rbox((hx - board / 2, 0, 0), (board, 2 * hh, 2 * hy), 0.04, 1), covers[col]),
                     (G.rbox((0, 0, hy - 0.15), (2 * hx, 2 * hh, 0.3), 0.12, 2), covers[col]),
                     (G.rbox((0, -0.1, -0.08), (2 * hx - 2 * board, 2 * hh - 0.3, 2 * hy - 0.3), 0.02, 1), pages)]
        for mm, dst in parts:
            dst.mesh(G.moved(mm, E(cx, cy, (h0 + h1) / 2), R))

    # The staircase: books stacked, each 2 shorter at both ends than the one under it.
    st = STAIRS
    order = ["navy", "mustard", "red", "sage", "plum"]
    for k in range(st["n"]):
        x0, x1 = st["x0"] + st["step"] * k, st["x1"] - st["step"] * k
        book(x0, x1, st["y0"], st["y1"], st["rise"] * k, st["rise"] * (k + 1), order[k], 0.0, True)
    return covers, pages


def brass():
    """Brass: the table lamp's base, the curtain rod and finials (the door knob is knob(), hidden with its wall)."""
    m = MU()
    sd = SIDE
    prof = [(0, 0), (1.5, 0), (1.5, 0.3), (0.9, 0.6), (0.35, 1.2), (0.3, 5.0), (0.55, 5.4), (0.2, 5.8), (0.2, 7.0), (0, 7.0)]
    m.mesh(G.moved(G.lathe(G.smooth_profile(prof, 3), 32), E(sd["x"], sd["y"], sd["h"])))
    w = WIN
    hr = w["h1"] + 4.8
    m.mesh(G.tube(E(X0 + 2.0, w["y0"] - 9.0, hr), E(X0 + 2.0, w["y1"] + 9.0, hr), 0.25, 16))
    for y in (w["y0"] - 9.4, w["y1"] + 9.4):
        m.mesh(G.ball(E(X0 + 2.0, y, hr), 0.6, 20, 12))
    for y in (w["y0"] - 8.0, w["y1"] + 8.0):
        m.mesh(G.tube(E(X0, y, hr), E(X0 + 2.0, y, hr), 0.15, 10))
    return m


def knob():
    """The door knob, on its own so it hides with the door when the camera is behind that wall."""
    m = MU()
    d = DOOR
    m.mesh(G.ball(E(X1 - 0.9, d["y1"] - 2.2, 19.0), 0.55, 20, 12))
    m.mesh(G.tube(E(X1 - 0.4, d["y1"] - 2.2, 19.0), E(X1 - 0.9, d["y1"] - 2.2, 19.0), 0.2, 10))
    return m


def shade():
    sd = SIDE
    prof = [(2.4, 0.0), (1.4, 4.4)]
    m = MU()
    m.mesh(G.moved(G.lathe(prof, 48), E(sd["x"], sd["y"], sd["h"] + 5.6)))
    inner = G.lathe([(1.38, 4.4), (2.38, 0.0)], 48)          # the inside, facing in
    m.mesh(G.moved(inner, E(sd["x"], sd["y"], sd["h"] + 5.6)))
    return m


PIECES = {
    "room_floor": (floor, dict(color=(1, 1, 1), rough=0.38, tex="Textures/room_floor.png")),
    "room_wall_L": (wall_L, dict(color=(1, 1, 1), rough=0.9, tex="Textures/room_wallpaper.png", group="L")),
    "room_wall_R": (wall_R, dict(color=(1, 1, 1), rough=0.9, tex="Textures/room_wallpaper.png", group="R")),
    "room_wall_B": (wall_B, dict(color=(1, 1, 1), rough=0.9, tex="Textures/room_wallpaper.png", group="B")),
    "room_wall_F": (wall_F, dict(color=(1, 1, 1), rough=0.9, tex="Textures/room_wallpaper.png", group="F")),
    "room_ceiling": (ceiling, dict(color=(0.85, 0.82, 0.76), rough=0.9)),
    "room_trim_L": (trim_L, dict(color=(0.82, 0.78, 0.68), rough=0.35, group="L")),
    "room_window": (window_frame, dict(color=(0.82, 0.78, 0.68), rough=0.35)),
    "room_trim_R": (trim_R, dict(color=(0.82, 0.78, 0.68), rough=0.35, group="R")),
    "room_trim_B": (trim_B, dict(color=(0.82, 0.78, 0.68), rough=0.35, group="B")),
    "room_trim_F": (trim_F, dict(color=(0.82, 0.78, 0.68), rough=0.35, group="F")),
    "room_glass": (glass, dict(color=(1, 1, 1), rough=0.05, emis=(0.9, 0.9, 0.9), emis_tex="Textures/room_sky.png", transmission=1.0)),
    "room_curtains": (curtains, dict(color=(0.52, 0.2, 0.1), rough=0.95)),
    "room_art1": (lambda: canvas(0), dict(color=(1, 1, 1), rough=0.8, tex="Textures/room_art1.png", group="B")),
    "room_art2": (lambda: canvas(1), dict(color=(1, 1, 1), rough=0.8, tex="Textures/room_art2.png", group="B")),
    "room_rug": (rug, dict(color=(1, 1, 1), rough=0.97, tex="Textures/room_rug.png")),
    "room_walnut": (walnut, dict(color=(0.16, 0.08, 0.04), rough=0.42)),
    "room_brass": (brass, dict(color=(0.86, 0.62, 0.30), rough=0.25, metal=1.0)),
    "room_knob": (knob, dict(color=(0.86, 0.62, 0.30), rough=0.25, metal=1.0, group="R")),
    "room_shade": (shade, dict(color=(0.92, 0.84, 0.68), rough=0.9, emis=(0.55, 0.36, 0.16))),
    "room_pages": (None, dict(color=(0.8, 0.75, 0.62), rough=0.8)),
}
for _f in FURNITURE:
    PIECES[_f] = (None, dict(color=(1, 1, 1), rough=0.8, tex="Textures/%s.png" % _f))
BOOK_LOOK = {"red": (0.42, 0.07, 0.05), "navy": (0.06, 0.1, 0.22), "mustard": (0.66, 0.44, 0.1), "sage": (0.25, 0.36, 0.23),
             "plum": (0.26, 0.08, 0.15)}
for _c, _rgb in BOOK_LOOK.items():
    PIECES["room_books_" + _c] = (None, dict(color=_rgb, rough=0.55))
ROOM_NAMES = sorted(PIECES)


def build_all():
    out = {}
    for name, (fn, _) in PIECES.items():
        if fn:
            out[name] = fn()
    covers, pages = books()
    for c, m in covers.items():
        out["room_books_" + c] = m
    out["room_pages"] = pages
    return out


# ------------------------------------------------------------------ what the rules need
def surfaces():
    s = [dict(name="floor", x0=X0, x1=X1, y0=Y0, y1=Y1, h=0.0, edge=False),
         dict(name="rug", x0=RUG["x0"], x1=RUG["x1"], y0=RUG["y0"], y1=RUG["y1"], h=RUG["h"], edge=False),
         dict(name="coffee table", x0=TABLE["x0"], x1=TABLE["x1"], y0=TABLE["y0"], y1=TABLE["y1"], h=TABLE["h"], edge=True, board=True),
         dict(name="bookshelf", x0=SHELF["x0"], x1=SHELF["x1"], y0=SHELF["y0"], y1=SHELF["y1"] - 0.4, h=SHELF["h"], edge=True, board=True)]
    r = SIDE["r"] * 0.7
    s.append(dict(name="side table", x0=SIDE["x"] - r, x1=SIDE["x"] + r, y0=SIDE["y"] - r, y1=SIDE["y"] + r, h=SIDE["h"], edge=True))
    st = STAIRS
    for k in range(st["n"]):
        s.append(dict(name="book %d" % (k + 1), x0=st["x0"] + st["step"] * k, x1=st["x1"] - st["step"] * k, y0=st["y0"], y1=st["y1"],
                      h=round(st["rise"] * (k + 1), 4), edge=True))
    return s


def solids():
    t = 4.0
    s = [dict(name="wall", x0=X0 - t, x1=X0 + SKIRT_T, y0=Y0 - t, y1=Y1 + t, z0=0, z1=WALL_H),
         dict(name="wall", x0=X1 - SKIRT_T, x1=X1 + t, y0=Y0 - t, y1=Y1 + t, z0=0, z1=WALL_H),
         dict(name="wall", x0=X0 - t, x1=X1 + t, y0=Y1 - SKIRT_T, y1=Y1 + t, z0=0, z1=WALL_H),
         dict(name="wall", x0=X0 - t, x1=X1 + t, y0=Y0 - t, y1=Y0 + SKIRT_T, z0=0, z1=WALL_H),
         dict(name="sofa", x0=SOFA["x0"], x1=SOFA["x1"], y0=SOFA["y0"], y1=SOFA["y1"], z0=0, z1=SOFA["h"]),
         dict(name="bookshelf", x0=SHELF["x0"], x1=SHELF["x1"], y0=SHELF["y0"], y1=SHELF["y1"], z0=0, z1=SHELF["h"]),
         dict(name="side table", x0=SIDE["x"] - 2.8, x1=SIDE["x"] + 2.8, y0=SIDE["y"] - 2.8, y1=SIDE["y"] + 2.8, z0=0, z1=SIDE["h"]),
         dict(name="plant", x0=PLANT["x"] - PLANT["r"] - 0.4, x1=PLANT["x"] + PLANT["r"] + 0.4, y0=PLANT["y"] - PLANT["r"] - 0.4,
              y1=PLANT["y"] + PLANT["r"] + 0.4, z0=0, z1=PLANT["h"])]
    s += [dict(b) for b in SHELF_TOP]
    # The armchair (front toward the room) and the table legs, from make_furniture's SLICE lines.
    s.append(dict(name="armchair", x0=-39.4, x1=-25.4, y0=2.9, y1=17.5, z0=0, z1=15.6))
    T = TABLE
    for x in (-23.5, -2.5):
        for y in (-3.3, 5.3):
            s.append(dict(name="table leg", x0=x - 0.9, x1=x + 0.9, y0=y - 0.9, y1=y + 0.9, z0=0, z1=T["h"]))
    s.append(dict(name="coffee table", x0=T["x0"], x1=T["x1"], y0=T["y0"], y1=T["y1"], z0=T["h"] - T["t"] - 1.2, z1=T["h"]))
    st = STAIRS
    for k in range(st["n"]):
        s.append(dict(name="book %d" % (k + 1), x0=st["x0"] + st["step"] * k, x1=st["x1"] - st["step"] * k, y0=st["y0"], y1=st["y1"],
                      z0=0, z1=round(st["rise"] * (k + 1), 4)))
    return s


SUN_DIR_TABLE = (0.78, -0.22, -0.58)      # where the sunlight travels, table axes (in through the left window)
LAMP_AT = (SIDE["x"], SIDE["y"], SIDE["h"] + 7.6)


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return ("%.4f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return '"' + v + '"'
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_val(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {lua_val(x)}" for k, x in v.items()) + " }"
    raise TypeError(v)


def write_data():
    d = np.array(SUN_DIR_TABLE, float)
    d /= np.linalg.norm(d)
    sun_e = (float(d[0]), float(d[2]), float(-d[1]))
    lines = ["-- Generated by tools/gen_room.py: do not edit by hand (change the room there and re-run it).",
             "-- Table units (a domino is 1 tall); engine position = (x, h, -y).", "return {",
             f"    bounds = {lua_val(dict(x0=X0, x1=X1, y0=Y0, y1=Y1))},",
             f"    wall_h = {lua_val(WALL_H)},",
             "    surfaces = {"]
    lines += ["        " + lua_val(s) + "," for s in surfaces()]
    lines += ["    },", "    solids = {"]
    lines += ["        " + lua_val(s) + "," for s in solids()]
    lines += ["    },", "    pieces = {"]
    for name in ROOM_NAMES:
        look = dict(PIECES[name][1])
        look = {"name": name, **look}
        lines.append("        " + lua_val(look) + ",")
    lines += ["    },",
              f"    sun = {lua_val(dict(dir=sun_e, color=(1.0, 0.86, 0.68), intensity=5.5))},",
              f"    fill = {lua_val(dict(dir=(-0.35, -0.8, -0.45), color=(0.78, 0.86, 1.0), intensity=0.45))},",
              f"    lamp = {lua_val(dict(pos=E(*LAMP_AT), color=(1.0, 0.72, 0.42), intensity=3.0, radius=60.0))},",
              f"    camera = {lua_val(dict(target=(-2.0, -9.0, 1.0), yaw=-62.0, pitch=40.0, dist=96.0))},",
              "}", ""]
    with open(DATA, "w", newline="\n") as f:
        f.write("\n".join(lines))
    print("data:", DATA)


# ------------------------------------------------------------------ textures
def srgb_png(rgb, path):
    """rgb: float array 0..1 already in sRGB."""
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path)


def periodic_noise(h, w, rng, kmax=24, amp_pow=1.2, ky=None):
    """Seamless smooth noise in [-1, 1] from random integer-frequency waves."""
    y = np.arange(h)[:, None] / h
    x = np.arange(w)[None, :] / w
    out = np.zeros((h, w))
    for _ in range(60):
        kx = int(rng.integers(0, kmax))
        kyy = int(rng.integers(0, kmax if ky is None else ky))
        if kx == 0 and kyy == 0:
            continue
        a = 1.0 / (kx * kx + kyy * kyy) ** (amp_pow / 2)
        out += a * np.sin(2 * np.pi * (kx * x + kyy * y) + rng.uniform(0, 2 * np.pi))
    return out / (np.abs(out).max() + 1e-9)


def tex_floor():
    """Oak boards, 16 x 16 units per tile (2048 px): boards 2.67 wide, random lengths, grain and dark joints."""
    rng = np.random.default_rng(11)
    S = 2048
    rows = 6
    pw = S / rows
    y = np.arange(S)[:, None] * np.ones((1, S))
    x = np.ones((S, 1)) * np.arange(S)[None, :]
    row = np.floor(y / pw).astype(int)
    out = np.zeros((S, S, 3))
    base = np.array([0.74, 0.55, 0.36])
    fine = rng.normal(0, 1, (S, S))
    xs = np.arange(S) / S

    def wobble(kmax, amp):
        """Seamless slow wander along x (a few waves per tile)."""
        w = np.zeros(S)
        for k in range(1, kmax + 1):
            w += rng.uniform(-1, 1) / k * np.sin(2 * np.pi * k * xs + rng.uniform(0, 6.3))
        return w * amp

    for r in range(rows):
        sel = row == r
        # One or two boards per row, joints roughly even and staggered row to row (wrapping, so it tiles).
        nb = int(rng.integers(1, 3))
        start = float(rng.uniform(0, S))
        joints = sorted(((start + S * (i + float(rng.uniform(-0.12, 0.12))) / nb) % S) for i in range(nb))
        xx = x[sel]
        idx = np.searchsorted(joints, xx) % nb
        tone = rng.uniform(0.88, 1.06, nb)
        warm = rng.uniform(-0.03, 0.03, nb)
        t = tone[idx][:, None]
        c = base[None, :] * t
        c[:, 0] += warm[idx]
        c[:, 2] -= warm[idx] * 0.6
        yl = (y[sel] - r * pw) / pw
        xi = xx.astype(int)
        # Grain: fine streaks running the length of the board that drift slowly across it, darker late-wood lines,
        # and an occasional figure where the streaks bunch up.
        ph = rng.uniform(0, 10, nb)[idx]
        drift = wobble(4, 0.6)[xi] + wobble(9, 0.08)[xi]
        dens = 11 + 4 * np.sin(2 * np.pi * (yl * 0.7 + ph * 0.1))
        g = np.sin(2 * np.pi * (yl * dens + drift + ph))
        g2 = np.sin(2 * np.pi * (yl * 37 + drift * 2.2 + ph * 3))
        k = 1 - 0.08 * np.clip((g - 0.55) / 0.45, 0, 1) - 0.02 * np.clip(g2, 0, 1) + 0.012 * fine[sel]
        c = c * k[:, None]
        # Joints: dark lines at the board's ends and along its long edges.
        dj = np.min(np.abs(((xx[:, None] - np.array(joints)[None, :]) + S / 2) % S - S / 2), axis=1)
        de = np.minimum(yl * pw, (1 - yl) * pw)
        dark = np.clip(1 - np.minimum(dj, de) / 3.0, 0, 1)
        c = c * (1 - 0.55 * dark[:, None])
        out[sel] = c
    srgb_png(out, os.path.join(TEX, "room_floor.png"))


def tex_wallpaper():
    """A warm stone-coloured paper with soft stripes and a small sprig between them (24 x 24 units per tile)."""
    rng = np.random.default_rng(5)
    S = 1024
    y = np.arange(S)[:, None] / S * np.ones((1, S))
    x = np.ones((S, 1)) * np.arange(S)[None, :] / S
    base = np.array([0.84, 0.78, 0.66])
    out = np.ones((S, S, 3)) * base
    stripes = 8
    sx = (x * stripes) % 1.0
    band = (np.abs(sx - 0.5) < 0.035).astype(float) + 0.5 * (np.abs(sx - 0.5) < 0.06)
    out *= (1 - 0.05 * band)[..., None]
    # Sprigs: small diamonds between the stripes on a staggered grid.
    gy = (y * 12) % 1.0
    off = (np.floor(y * 12) % 2) * 0.5
    gx = (x * stripes + off) % 1.0
    d = np.abs(gx - 0.0) + np.abs(gx - 1.0) * 0
    d = np.minimum(np.abs(gx), np.abs(1 - gx)) * 1.0 / stripes * 12 + np.abs(gy - 0.5)
    sprig = np.clip(1 - d / 0.09, 0, 1)
    out = out * (1 - 0.07 * sprig[..., None]) + np.array([0.55, 0.62, 0.45]) * 0.06 * sprig[..., None]
    out *= (1 + 0.015 * rng.normal(0, 1, (S, S)))[..., None]
    srgb_png(out, os.path.join(TEX, "room_wallpaper.png"))


def tex_rug():
    """A wool rug: navy outer band, cream line, a mustard band of lozenges, a madder-red field with a medallion."""
    rng = np.random.default_rng(9)
    W_u, D_u = RUG["x1"] - RUG["x0"], RUG["y1"] - RUG["y0"]
    w, h = 2048, int(2048 * D_u / W_u)
    u = (np.arange(w)[None, :] + 0.5) / w * W_u * np.ones((h, 1))
    v = (np.arange(h)[:, None] + 0.5) / h * D_u * np.ones((1, w))
    v = v[::-1]   # image rows run down; v up
    de = np.minimum(np.minimum(u, W_u - u), np.minimum(v, D_u - v))
    red, navy = np.array([0.55, 0.14, 0.1]), np.array([0.12, 0.15, 0.28])
    cream, mustard = np.array([0.86, 0.79, 0.62]), np.array([0.75, 0.53, 0.18])
    out = np.ones((h, w, 3)) * red
    out[de < 2.6] = navy
    out[(de >= 2.6) & (de < 3.0)] = cream
    band = (de >= 3.0) & (de < 6.2)
    out[band] = mustard
    # Lozenges along the band.
    along = np.where(np.minimum(u, W_u - u) < np.minimum(v, D_u - v), v, u)
    dd = np.abs(((along / 3.2) % 1.0) - 0.5) * 3.2 + np.abs(de - 4.6) * 1.4
    out[band & (dd < 1.0)] = navy
    out[band & (dd < 0.45)] = red
    out[(de >= 6.2) & (de < 6.6)] = cream
    # Field: a large central medallion of nested lozenges and small motifs scattered round it.
    cu, cv = u - W_u / 2, v - D_u / 2
    md = np.abs(cu) / (W_u * 0.3) + np.abs(cv) / (D_u * 0.3)
    field = de >= 6.6
    for r0, col in ((1.0, navy), (0.86, cream), (0.8, red), (0.62, mustard), (0.5, navy), (0.36, cream), (0.25, red), (0.12, mustard)):
        out[field & (md < r0)] = col
    sm = (np.abs(((cu / 4.0) % 1.0) - 0.5) + np.abs(((cv / 4.0) % 1.0) - 0.5))
    out[field & (md > 1.05) & (sm < 0.16)] = cream
    out[field & (md > 1.05) & (sm < 0.07)] = navy
    # Wool: fine fibre noise, gentle wear toward the middle.
    out *= (1 + 0.06 * rng.normal(0, 1, (h, w)))[..., None]
    out *= (1 + 0.04 * periodic_noise(h, w, rng, 18))[..., None]
    out = out * (0.92 + 0.08 * np.clip(md, 0, 1))[..., None]
    srgb_png(out, os.path.join(TEX, "room_rug.png"))


def tex_sky():
    """What the window shows: a bright afternoon sky over a garden hedge."""
    rng = np.random.default_rng(2)
    S = 512
    v = np.arange(S)[:, None] / S * np.ones((1, S))
    u = np.ones((S, 1)) * np.arange(S)[None, :] / S
    top, hor = np.array([0.55, 0.72, 0.92]), np.array([0.98, 0.95, 0.88])
    out = top + (hor - top) * (v ** 1.6)[..., None]
    sun = np.exp(-((u - 0.25) ** 2 + (v - 0.22) ** 2) / 0.02)
    out = out + np.array([1.0, 0.95, 0.8]) * 0.6 * sun[..., None]
    hedge = 0.72 + 0.05 * np.sin(u * 23) + 0.03 * periodic_noise(S, S, rng, 30)
    leaf = (v > hedge)
    out[leaf] = (np.array([0.22, 0.38, 0.16]) * (0.8 + 0.4 * rng.random((S, S))[..., None]))[leaf]
    srgb_png(out, os.path.join(TEX, "room_sky.png"))


def tex_art():
    rng = np.random.default_rng(4)
    W, H = 448, 320
    v = np.arange(H)[:, None] / H * np.ones((1, W))
    u = np.ones((H, 1)) * np.arange(W)[None, :] / W
    # 1: hills at dusk.
    sky_t, sky_b = np.array([0.93, 0.74, 0.45]), np.array([0.97, 0.88, 0.7])
    a = sky_t + (sky_b - sky_t) * v[..., None]
    sun = ((u - 0.68) ** 2 * (W / H) ** 2 + (v - 0.36) ** 2) < 0.012
    a[sun] = np.array([0.95, 0.5, 0.25])
    for k, (lvl, col) in enumerate(((0.55, (0.55, 0.6, 0.45)), (0.66, (0.36, 0.45, 0.33)), (0.78, (0.2, 0.28, 0.3)), (0.9, (0.55, 0.25, 0.15)))):
        line = lvl + 0.06 * np.sin(u * (5 + k * 2) + k) + 0.03 * np.sin(u * 17 + k * 3)
        a[v > line] = np.array(col)
    a *= (1 + 0.03 * rng.normal(0, 1, (H, W)))[..., None]
    srgb_png(a, os.path.join(TEX, "room_art1.png"))
    # 2: mid-century shapes on cream (portrait: rotate the frame's aspect by drawing tall).
    W2, H2 = 320, 448
    v = np.arange(H2)[:, None] / H2 * np.ones((1, W2))
    u = np.ones((H2, 1)) * np.arange(W2)[None, :] / W2
    b = np.ones((H2, W2, 3)) * np.array([0.9, 0.85, 0.74])
    shapes = [((0.35, 0.3), 0.22, (0.78, 0.5, 0.17)), ((0.62, 0.52), 0.26, (0.55, 0.2, 0.12)),
              ((0.4, 0.74), 0.18, (0.13, 0.2, 0.32)), ((0.7, 0.2), 0.1, (0.3, 0.42, 0.3))]
    for (cx, cy), r, col in shapes:
        d = ((u - cx) * (W2 / H2)) ** 2 + (v - cy) ** 2
        half = (v > cy) if r > 0.2 else np.ones_like(v, bool)
        b[(d < r * r) & half] = np.array(col)
    b[(np.abs(u - 0.5) < 0.006)] = np.array([0.12, 0.1, 0.09])
    b *= (1 + 0.03 * rng.normal(0, 1, (H2, W2)))[..., None]
    srgb_png(b, os.path.join(TEX, "room_art2.png"))


def tex_day_hdr():
    """Equirect HDR for the room's ambient light: warm walls, a pale ceiling, the floor, a bright window to the
    left (-x). Same convention as make_textures.room_hdr (centre column along +Z, +X at u = 0.75)."""
    w, h = 512, 256
    v = (np.arange(h)[:, None] + 0.5) / h
    u = (np.arange(w)[None, :] + 0.5) / w
    el = (0.5 - v) * np.pi
    az = (u - 0.5) * 2 * np.pi
    d = np.stack([np.cos(el) * np.sin(az) * np.ones_like(u), np.sin(el) * np.ones_like(u), np.cos(el) * np.cos(az) * np.ones_like(u)], -1)
    # Seen as the background too (the camera looks into the room from outside it), so below the horizon it falls
    # away to a deep brown-black and the room reads as a lit set in the dark; the light the room gets from the IBL is
    # mostly the warm upper half.
    wall, ceil, flo = np.array([0.42, 0.36, 0.28]), np.array([0.62, 0.58, 0.52]), np.array([0.018, 0.013, 0.01])
    up = np.clip(d[..., 1], -1, 1)
    upp, dn = np.clip(up, 0, 1)[..., None], np.clip(-up, 0, 1)[..., None]
    col = np.where(up[..., None] > 0, wall + (ceil - wall) * upp ** 0.6, wall * np.exp(-dn * 9.0) + flo)
    win = np.array([-1.0, 0.35, -0.2]); win /= np.linalg.norm(win)
    wa = np.arccos(np.clip((d * win).sum(-1), -1, 1))
    col = col + np.array([0.85, 0.9, 1.0])[None, None, :] * (6.0 * (wa < 0.35) + 0.9 * np.exp(-(wa / 0.9) ** 2))[..., None]
    rgbe = np.zeros((h, w, 4), np.uint8)
    m = col.max(-1)
    e = np.floor(np.log2(np.maximum(m, 1e-32))) + 1
    scale = np.where(m > 1e-32, 256.0 / np.power(2.0, e), 0)
    rgbe[..., :3] = np.clip(col * scale[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8)
    os.makedirs(SKY, exist_ok=True)
    with open(os.path.join(SKY, "day.hdr"), "wb") as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n")
        f.write(f"-Y {h} +X {w}\n".encode())
        f.write(rgbe.tobytes())


def textures():
    os.makedirs(TEX, exist_ok=True)
    tex_floor(); tex_wallpaper(); tex_rug(); tex_sky(); tex_art(); tex_day_hdr()
    print("textures written")


# ------------------------------------------------------------------ cook
def cook_room():
    cook = G.find_cook()
    meshes = build_all()
    os.makedirs(OBJECTS, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="topple-room-") as tmp:
        lines = []
        for name in ROOM_NAMES:
            if name not in meshes:      # the Tripo furniture: tools/make_furniture.py
                continue
            src = os.path.join(tmp, name + ".obj")
            nv, nt = save_obj_uv(src, meshes[name])
            print(f"{name:20s} {nv:7d} verts {nt:7d} tris")
            lines.append(f"{src}\t{os.path.join(OBJECTS, name + '.pemesh')}\n")
        manifest = os.path.join(tmp, "batch.txt")
        with open(manifest, "w", encoding="utf-8") as f:
            f.writelines(lines)
        r = subprocess.run([cook, "--batch", manifest], cwd=os.path.dirname(cook), capture_output=True, text=True)
        if r.returncode != 0 or f"{len(lines)} ok" not in (r.stdout + r.stderr):
            print((r.stdout + r.stderr)[-3000:])
            raise SystemExit("PhasmaCook failed")
        print("cooked", len(lines), "room meshes")


def main():
    textures()
    write_data()
    if "--no-cook" not in sys.argv:
        cook_room()
    G.write_scene(sorted(G.MESHES))
    print("scene:", G.SCENE)


if __name__ == "__main__":
    main()
