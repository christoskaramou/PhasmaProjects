"""Undertow game assets from the phase-0 layers and the shared numbers.

    python tools/gen_assets.py [path/to/PhasmaCook.exe]    (--scene-only: data + scene, no cook / textures)

Writes Assets/Objects/*.pemesh (cooked), Assets/Textures, Assets/Skybox/storm.hdr, Assets/Scenes/main.pescene,
Assets/Scripts/uw_data.lua (the numbers in uw_common.py, for the Lua) and tests/sea_samples.lua (Python sea heights
the Lua must reproduce). The set pieces come from .concepts/next/undertow/layers (tools/scene.py bakes them).

Engine axes: X along the harbour, Y up, Z toward the camera; Blender (x, y, z) -> engine (x, z, -y).
"""
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import uw_common as U  # noqa: E402
import uw_sea  # noqa: E402
import uw_ripple  # noqa: E402
import uw_hits  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
ASSETS = os.path.join(ROOT, "Assets")
OBJECTS = os.path.join(ASSETS, "Objects")
TEXOUT = os.path.join(ASSETS, "Textures")
SKYOUT = os.path.join(ASSETS, "Skybox")
SCENE = os.path.join(ASSETS, "Scenes", "main.pescene")
LAYERS = os.path.normpath(os.path.join(ROOT, "..", ".concepts", "next", "undertow", "layers"))
PCS = os.path.join(LAYERS, "pieces")
LTEX = os.path.join(LAYERS, "tex")

FAR_Y, FAR_W, FAR_H, FAR_Z0 = 120.0, 256.0, 40.0, -3.0      # as scene.py
SKY_D = 1000.0                                             # sky quad distance: nearer than the skybox cube (2000 lost its lower part)
SKY_ASPECT = 0.75                                          # sky quad covers windows down to 4:3 at the fixed fovx
LANTERN = None                                             # set in beam(): engine position of the lighthouse lantern


def e(p):
    """Blender point -> engine point."""
    return (p[0], p[2], -p[1])


# ------------------------------------------------------------------ camera
def cam_basis():
    yaw, pitch = math.radians(U.CAM_YAW), math.radians(U.CAM_PITCH)
    f = np.array([math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)])
    r = np.array([math.cos(yaw), -math.sin(yaw), 0.0])
    u = np.cross(r, f)
    return f, r, u


FOVX = 2 * math.degrees(math.atan(18.0 / U.LENS))
GLITTER_AT = (0.80, 0.44)      # sky point of the glitter light (fraction of the window from the top left), see write_scene


# ------------------------------------------------------------------ OBJ writing
def write_obj(path, V, N, F, T=None, C=None):
    """V, N in engine axes; F triangles (0-based); T uv per vertex; C rgb per vertex (0..1, sRGB)."""
    with open(path, "w") as fo:
        fo.write("o mesh\n")
        for i, p in enumerate(V):
            if C is not None:
                fo.write("v %.5f %.5f %.5f %.4f %.4f %.4f\n" % (p[0], p[1], p[2], C[i][0], C[i][1], C[i][2]))
            else:
                fo.write("v %.5f %.5f %.5f\n" % tuple(p))
        if T is not None:
            for t in T:
                fo.write("vt %.6f %.6f\n" % tuple(t))
        else:
            fo.write("vt 0 0\n")
        for n in N:
            fo.write("vn %.5f %.5f %.5f\n" % tuple(n))
        tris = 0
        V_, N_ = np.asarray(V, float), np.asarray(N, float)
        for a, b, c in F:
            fn = np.cross(V_[b] - V_[a], V_[c] - V_[a])
            if np.linalg.norm(fn) < 1e-12:
                continue
            if np.dot(fn, N_[a] + N_[b] + N_[c]) < 0:
                b, c = c, b
            ta, tb, tc = (a + 1, b + 1, c + 1) if T is not None else (1, 1, 1)
            fo.write(f"f {a+1}/{ta}/{a+1} {b+1}/{tb}/{b+1} {c+1}/{tc}/{c+1}\n")
            tris += 1
    return len(V), tris


def quads_to_tris(Q):
    out = []
    for a, b, c, d in Q:
        out += [(a, b, c), (a, c, d)]
    return out


def torus(R0, r, nu=32, nv=8, sx=1.0):
    """Torus in the XY plane (axis Z), optionally squashed along X (oval chain link)."""
    V, N, F = [], [], []
    for i in range(nu):
        a = 2 * math.pi * i / nu
        for j in range(nv):
            b = 2 * math.pi * j / nv
            c = np.array([math.cos(a), math.sin(a), 0.0])
            n = c * math.cos(b) + np.array([0, 0, 1.0]) * math.sin(b)
            p = c * R0 + n * r
            V.append((p[0] * sx, p[1], p[2]))
            N.append(tuple(n / max(1e-9, np.linalg.norm(n))))
    for i in range(nu):
        for j in range(nv):
            a, b = i * nv + j, ((i + 1) % nu) * nv + j
            c, d = ((i + 1) % nu) * nv + (j + 1) % nv, i * nv + (j + 1) % nv
            F += [(a, b, c), (a, c, d)]
    return V, N, F


def uvsphere(r, seg=48, rings=24):
    V, N, T, F = [], [], [], []
    for j in range(rings + 1):
        v = j / rings
        ph = math.pi * v
        for i in range(seg + 1):
            u = i / seg
            th = 2 * math.pi * u
            n = (math.sin(ph) * math.cos(th), math.cos(ph), math.sin(ph) * math.sin(th))
            V.append(tuple(r * c for c in n))
            N.append(n)
            T.append((u, 1 - v))
    for j in range(rings):
        for i in range(seg):
            a = j * (seg + 1) + i
            F += [(a, a + seg + 1, a + seg + 2), (a, a + seg + 2, a + 1)]
    return V, N, T, F


def merge(*parts):
    V, N, F = [], [], []
    for pv, pn, pf in parts:
        b = len(V)
        V += list(pv)
        N += list(pn)
        F += [(a + b, c + b, d + b) for a, c, d in pf]
    return V, N, F


def transformed(part, R=None, t=(0, 0, 0)):
    V, N, F = part
    V, N = np.asarray(V, float), np.asarray(N, float)
    if R is not None:
        V, N = V @ R.T, N @ R.T
    return [tuple(v) for v in V + np.asarray(t)], [tuple(n) for n in N], F


def rot(axis, a):
    c, s = math.cos(a), math.sin(a)
    return {"x": np.array([[1, 0, 0], [0, c, -s], [0, s, c]]), "y": np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]),
            "z": np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])}[axis]


# ------------------------------------------------------------------ meshes (engine axes)
def mesh_sea_tile(path):
    V, Nn, C, T, Q = uw_sea.tile()
    return write_obj(path, [e(v) for v in V], [e(n) for n in Nn], quads_to_tris(Q), T, C)


def mesh_quad_xz(path, x0, x1, z0, z1, y):
    """A vertical card facing the camera (Blender plane y), UV 0..1."""
    P = [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]
    return write_obj(path, [e(p) for p in P], [(0, 0, 1)] * 4, [(0, 1, 2), (0, 2, 3)], [(0, 0), (1, 0), (1, 1), (0, 1)])


def mesh_view_quad(path, dist, hw, hh):
    """Quad perpendicular to the camera's view axis, centred on the axis at `dist` (camera at the origin)."""
    f, r, u = cam_basis()
    c = f * dist
    P = [c - r * hw - u * hh, c + r * hw - u * hh, c + r * hw + u * hh, c - r * hw + u * hh]
    n = e(-f)
    return write_obj(path, [e(p) for p in P], [n] * 4, [(0, 1, 2), (0, 2, 3)], [(0, 0), (1, 0), (1, 1), (0, 1)])


def mesh_sky(path):
    hw = SKY_D * math.tan(math.radians(FOVX / 2))
    return mesh_view_quad(path, SKY_D, hw, hw * SKY_ASPECT)


def mesh_float_glass(path, r):
    V, N, T, F = uvsphere(r)
    return write_obj(path, V, N, F, T)


def mesh_float_net(path):
    """Rope net in the float's frame: +Y points at the hook (engine axes)."""
    rf = U.FLOAT_R
    parts = []
    for k in range(4):        # meridians: rings through the Y axis
        parts.append(transformed(torus(rf + 0.012, 0.014, 48, 6), rot("y", k * math.pi / 4)))
    for h in (-0.22, 0.0, 0.22):   # latitudes: rings around the Y axis
        rr = math.sqrt(rf * rf - h * h) + 0.012
        parts.append(transformed(torus(rr, 0.014, 48, 6), rot("x", math.pi / 2), (0, h, 0)))
    parts.append(transformed(torus(0.06, 0.018, 20, 6), None, (0, rf + 0.06, 0)))
    V, N, F = merge(*parts)
    return write_obj(path, V, N, F)


def mesh_chain_link(path):
    V, N, F = torus(U.CHAIN_LINK[0], U.CHAIN_LINK[1], 16, 6, sx=0.6)     # ring in XY, long along Y (the chain axis)
    return write_obj(path, V, N, F)


def mesh_chain_ring(path):
    V, N, F = torus(0.065, 0.016, 20, 6)
    return write_obj(path, V, N, F)


TRAIL_L = 4.2


def mesh_plate(kind):
    """Number decal over a buoy's blank plate, in the buoy's own frame (the node takes the buoy's transform)."""
    def make(path):
        cx, cy, cz = U.plate_local(kind)
        hw, hh = U.PLATE_SIZE[0] / 2, U.PLATE_SIZE[1] / 2
        y = cy - 0.004
        P = [(cx - hw, y, cz - hh), (cx + hw, y, cz - hh), (cx + hw, y, cz + hh), (cx - hw, y, cz + hh)]
        return write_obj(path, [e(q) for q in P], [e((0, -1, 0))] * 4, [(0, 1, 2), (0, 2, 3)],
                         [(0, 0), (1, 0), (1, 1), (0, 1)])
    return make


def plate_numbers(kind):
    first = 2 if kind == "buoy_red" else 1
    return [first + 2 * i for i in range(U.PLATE_N)]


def mesh_trail(path):
    """Soft streak along the arc behind the float, in the swing frame (hook at the origin, float straight below at
    angle 0); the game rotates it about Z to the swing angle and scales it by L / TRAIL_L."""
    seg = 40
    rf = U.FLOAT_R
    V, T = [], []
    for k in range(seg + 1):
        uu = k / seg
        ph = math.radians(-48 + 46 * uu)
        p = np.array([TRAIL_L * math.sin(ph), -TRAIL_L * math.cos(ph), 0.05])
        nrm = np.array([math.sin(ph), -math.cos(ph), 0.0])
        w = rf * (0.2 + 0.6 * uu)
        V += [tuple(p + nrm * w), tuple(p - nrm * w)]
        T += [(uu, 1.0), (uu, 0.0)]
    F = []
    for k in range(seg):
        a = 2 * k
        F += [(a, a + 2, a + 3), (a, a + 3, a + 1)]
    return write_obj(path, V, [(0, 0, 1)] * len(V), F, T)


BEAM = (95.0, 1.2, 14.0)      # length, width at the lantern, width at the end (as scene.py beam_card)


def mesh_beam(path):
    (Lb, w0, w1), nseg = BEAM, 32
    V, T, F = [], [], []
    for k in range(nseg + 1):
        uu = k / nseg
        w = w0 + (w1 - w0) * uu
        V += [(Lb * uu, -w / 2, 0.0), (Lb * uu, w / 2, 0.0)]
        # v proportional to the position across (not normalised per row): affine triangles of a tapering card bend a
        # normalised profile into a zigzag; the texture draws the wedge itself
        T += [(uu, 0.5 - w / (2 * w1)), (uu, 0.5 + w / (2 * w1))]
    for k in range(nseg):
        a = 2 * k
        F += [(a, a + 2, a + 3), (a, a + 3, a + 1)]
    return write_obj(path, V, [(0, 0, 1)] * len(V), F, T)


def read_blender_obj(src, dst):
    """The baked pieces were exported by Blender in engine axes already (forward -Z, up Y). Triangulate and drop
    degenerate triangles (collapsed lathe caps): the cook sorts those into a second sub-mesh the scene never draws."""
    V, out, faces = [], [], 0
    with open(src) as fi:
        for line in fi:
            if line.startswith("v "):
                V.append(tuple(float(c) for c in line.split()[1:4]))
                out.append(line)
            elif line.startswith("f "):
                cs = line.split()[1:]
                pi = [int(c.split("/")[0]) - 1 for c in cs]
                for k in range(1, len(cs) - 1):
                    a, b, c = 0, k, k + 1
                    if len({pi[a], pi[b], pi[c]}) < 3:
                        continue
                    pa, pb, pc = (np.array(V[pi[i]]) for i in (a, b, c))
                    if np.linalg.norm(np.cross(pb - pa, pc - pa)) < 1e-10:
                        continue
                    out.append("f %s %s %s\n" % (cs[a], cs[b], cs[c]))
                    faces += 1
            elif line.startswith(("vt ", "vn ", "o ")):
                out.append(line)
    with open(dst, "w") as fo:
        fo.writelines(out)
    return len(V), faces


PIECES = ["buoy_red", "buoy_white", "boat", "pier", "bw", "bw_gap"]
GEN = {
    "sea_tile": mesh_sea_tile, "sky": mesh_sky,
    "far_card": lambda p: mesh_quad_xz(p, -FAR_W / 2, FAR_W / 2, FAR_Z0, FAR_Z0 + FAR_H, FAR_Y),
    "float_glass": lambda p: mesh_float_glass(p, U.FLOAT_R), "float_inner": lambda p: mesh_float_glass(p, U.FLOAT_R * 0.88),
    "float_core": lambda p: mesh_float_glass(p, 0.1), "float_net": mesh_float_net, "chain_link": mesh_chain_link,
    "chain_ring": mesh_chain_ring, "trail": mesh_trail, "beam": mesh_beam,
    "plate_red": mesh_plate("buoy_red"), "plate_white": mesh_plate("buoy_white"),
}
# Scene template variants: copies of one mesh share a material, so every look gets its own mesh entry.
VARIANTS = {
    "buoy_red": ["buoy_red_unlit", "buoy_red_lit"], "buoy_white": ["buoy_white_unlit", "buoy_white_lit"],
    "pier": ["pier_unlit", "pier_lit"],
    "plate_red": ["plate_%02d" % n for n in plate_numbers("buoy_red")],
    "plate_white": ["plate_%02d" % n for n in plate_numbers("buoy_white")],
}


# ------------------------------------------------------------------ textures
def srgb_to_lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def write_hdr(path, col):
    h, w = col.shape[:2]
    rgbe = np.zeros((h, w, 4), np.uint8)
    m = col.max(-1)
    ex = np.floor(np.log2(np.maximum(m, 1e-32))) + 1
    sc = np.where(m > 1e-32, 256.0 / np.power(2.0, ex), 0)
    rgbe[..., :3] = np.clip(col * sc[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(m > 1e-32, ex + 128, 0).astype(np.uint8)
    with open(path, "wb") as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n")
        f.write(f"-Y {h} +X {w}\n".encode())
        f.write(rgbe.tobytes())


def sample_equirect(pano, d):
    """Bilinear lookup of an engine-convention equirect (row 0 = up) for Blender directions d (..., 3)."""
    h, w = pano.shape[:2]
    bx, by, bz = d[..., 0], d[..., 1], d[..., 2]
    u = 0.5 + np.arctan2(bx, -by) / (2 * np.pi)
    v = 0.5 - np.arcsin(np.clip(bz, -1, 1)) / np.pi
    x = (u * w - 0.5) % w
    y = np.clip(v * h - 0.5, 0, h - 1)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    x1, y1 = (x0 + 1) % w, np.minimum(y0 + 1, h - 1)
    fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    return (pano[y0, x0] * (1 - fx) + pano[y0, x1] * fx) * (1 - fy) + (pano[y1, x0] * (1 - fx) + pano[y1, x1] * fx) * fy


RAIN_SLANT = 0.12        # streak lean, x per y (as scene.py make_rain); the emitters' drift matches it


def make_rain_streak():
    """A short, soft, slanted streak in the middle 45% of the sprite (the full-height hairline read as long vertical
    lines down the sky, where the target's rain is short leaning dashes)."""
    n = 256
    yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / n
    t = np.clip((yy - 0.275) / 0.45, 0, 1)
    along = np.sin(np.pi * t) ** 0.9 * ((yy > 0.275) & (yy < 0.725))
    cx = 0.5 + RAIN_SLANT * (yy - 0.5)
    streak = np.exp(-((xx - cx) / 0.007) ** 2) * along
    rgba = np.dstack([np.full_like(streak, 0.86), np.full_like(streak, 0.89), np.full_like(streak, 0.92), streak])
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(TEXOUT, "rain_streak.png"))
    a = rgba.copy()
    a[..., :3] *= a[..., 3:4]
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(TEXOUT, "p_rain.png"))


def make_beam_card():
    """Lighthouse beam card (alpha-blended, emissive 1: above 1 the channels clipped to white with tonemapping off).
    u along the beam (0 at the lantern), v across the card's widest end (mesh_beam maps v linearly); a bright core in a
    broad glow. Measured on the target (2026-11-13): the beam stands ~130 levels over the sky a third of the way out and
    still ~100 at the frame edge, warm (1, 0.91, 0.71): so a strong alpha and a slow fade."""
    bw, bh = 512, 256
    u = np.linspace(0, 1, bw)[None, :]
    v = np.linspace(-1, 1, bh)[:, None]
    hw = (BEAM[1] + (BEAM[2] - BEAM[1]) * u) / BEAM[2]          # wedge half-width in v units
    core = np.exp(-(v / (0.30 * hw)) ** 2) * (1 - u) ** 0.9
    glow = np.exp(-(v / (0.75 * hw)) ** 2) * (1 - u) ** 0.7
    ba = np.clip((0.95 * core + 0.45 * glow) * np.clip(u / 0.012, 0, 1), 0, 1)
    rgb = np.ones((bh, bw, 3)) * np.array([1.0, 0.91, 0.71])
    Image.fromarray((np.dstack([rgb, ba]) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(TEXOUT, "beam_card.png"))


def float_rim_texture(path, w=1024, h=512):
    """The glass shell's emissive map, baked for the play camera (it never turns and the glass never rotates): a green
    body that brightens to a pale yellow-green rim at the silhouette (the target's lit glass edge) and a soft glint
    toward the upper left. Texel (u, t) is the uvsphere vertex at th = 2 pi u, ph = pi (1 - t) (engine axes)."""
    f, r, up = cam_basis()
    v = -np.array(e(f))                                  # from the float toward the camera, engine axes
    lu = np.array(e(-0.55 * r + 0.75 * up + 0.35 * (-f)))
    lu = lu / np.linalg.norm(lu)                         # the glint's direction: up, a little left, toward the camera
    uu, tt = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
    tt = 1.0 - tt                                        # image row 0 is t = 1 (top)
    th, ph = 2 * np.pi * uu, np.pi * (1 - tt)
    n = np.stack([np.sin(ph) * np.cos(th), np.cos(ph), np.sin(ph) * np.sin(th)], -1)
    ndv = np.clip(n @ v, 0, 1)
    rim = (1 - ndv) ** 3
    glint = np.clip(n @ lu, 0, 1) ** 24
    body = 0.5 + 0.5 * rim + 0.6 * glint
    rgb = np.stack([0.55 + 0.45 * np.clip(rim * 1.4 + glint, 0, 1), np.ones_like(rim), 0.62 + 0.25 * rim], -1) * np.clip(body, 0, 1)[..., None]
    edge = ((1 - ndv) ** 10)[..., None]                  # a thin warm-yellow outline at the silhouette (the target's rim light)
    rgb = rgb * (1 - edge) + edge * np.array([1.0, 0.82, 0.30])
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(path)


def float_alpha_texture(path, w=1024, h=512):
    """The glass shell's base colour / alpha map for the play camera: clear (0.12) where it faces the camera, so the
    white core shows through as in the target, and nearly opaque (0.95) in the band outside the core (the inner sphere
    is 0.8 R: there |n.v| < 0.6), which hides the net's back bars (they read as a second, offset cage)."""
    f, _r, _u = cam_basis()
    v = -np.array(e(f))
    uu, tt = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
    tt = 1.0 - tt
    th, ph = 2 * np.pi * uu, np.pi * (1 - tt)
    n = np.stack([np.sin(ph) * np.cos(th), np.cos(ph), np.sin(ph) * np.sin(th)], -1)
    ndv = np.abs(n @ v)
    s = np.clip((0.56 - ndv) / (0.56 - 0.36), 0, 1)        # (the core is 0.88 R: clear inside ~0.83 R, opaque from ~0.93 R)
    a = 0.12 + 0.83 * s * s * (3 - 2 * s)
    rgba = np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a])
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path)


def make_textures():
    os.makedirs(TEXOUT, exist_ok=True)
    float_rim_texture(os.path.join(TEXOUT, "float_glass_rim.png"))
    float_alpha_texture(os.path.join(TEXOUT, "float_glass_alpha.png"))
    os.makedirs(SKYOUT, exist_ok=True)
    for name in os.listdir(PCS):
        if name.endswith(".png"):
            shutil.copyfile(os.path.join(PCS, name), os.path.join(TEXOUT, name))
    shutil.copyfile(os.path.join(LAYERS, "far_layer.png"), os.path.join(TEXOUT, "far_layer.png"))
    for name in os.listdir(LTEX):
        # (the layer folder's sea_normal_* / sea_detail are the Blender target's repeating maps: the game makes its own
        # depth-mapped ones below; copying these over them silently put the target's maps in the game, 18:31-22:10)
        if name.endswith(".png") and not name.startswith(("sea_normal_", "sea_detail", "sea_rough")):
            shutil.copyfile(os.path.join(LTEX, name), os.path.join(TEXOUT, name))
    uw_ripple.world_maps(TEXOUT)
    pano = np.asarray(Image.open(os.path.join(LAYERS, "sky_pano.png")).convert("RGB"), np.float32) / 255.0
    # Sky as the game camera sees it (the camera never turns, so the sky never moves on screen): one quad.
    W, H = 3072, int(3072 * SKY_ASPECT)
    f, r, u = cam_basis()
    t = math.tan(math.radians(FOVX / 2))
    xs = ((np.arange(W) + 0.5) / W * 2 - 1) * t
    ys = (1 - (np.arange(H) + 0.5) / H * 2) * t * SKY_ASPECT
    X, Y = np.meshgrid(xs, ys)
    d = f[None, None, :] + X[..., None] * r[None, None, :] + Y[..., None] * u[None, None, :]
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    view = sample_equirect(pano, d)
    Image.fromarray((np.clip(view, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(TEXOUT, "sky_view.png"))
    # IBL / reflections: the same panorama, 2048 wide, linear radiance.
    small = np.asarray(Image.open(os.path.join(LAYERS, "sky_pano.png")).convert("RGB").resize((2048, 1024), Image.LANCZOS),
                       np.float32) / 255.0
    # IBL only lights the live objects (sea, float, chain). Half the saturation, and the horizon band (elevation ~3
    # deg) brightened x2.5 in HDR: the near water's mirror sits on darker sky (the sea mesh tilts its near normals), so
    # only ripple faces turned away catch the band, as the target's warm, bright dashes (21:5x, live: variants s30 / s60
    # / s100 x band 1-2.5 compared on states A and B).
    lum = (small * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
    small = lum + (small - lum) * 0.5
    el = 90.0 - (np.arange(small.shape[0]) + 0.5) / small.shape[0] * 180.0
    band = 1.0 + 1.5 * np.exp(-0.5 * ((el - 3.0) / 5.0) ** 2)
    write_hdr(os.path.join(SKYOUT, "storm.hdr"), srgb_to_lin(small) * band[:, None, None])
    # particle textures: the rain streak, the spray puff, the halo
    make_rain_streak()
    make_beam_card()
    # Spray droplet: one small crisp drop with a faint rim (the old sprite was a misty puff that read as speckle on hulls).
    n = 64
    yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / n * 2 - 1
    rr = np.hypot(xx, yy)
    drop = np.clip(np.exp(-(rr / 0.28) ** 2) + 0.25 * np.exp(-(rr / 0.6) ** 2), 0, 1) * (rr < 1)
    Image.fromarray((np.dstack([np.full_like(drop, 0.95), np.full_like(drop, 0.98), np.full_like(drop, 1.0), drop]) * 255
                     + 0.5).astype(np.uint8), "RGBA").save(os.path.join(TEXOUT, "spray.png"))
    # Buoy number decals: red (port) buoys dark iron digits, white ones dark red digits (sampled from the target, 2026-11-13).
    from PIL import ImageDraw, ImageFont
    font = ImageFont.truetype(os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", "arialbd.ttf"), 150)
    for kind, col in (("buoy_red", (40, 30, 26)), ("buoy_white", (66, 28, 22))):
        for num in plate_numbers(kind):
            im = Image.new("RGBA", (256, 200), col + (0,))
            d = ImageDraw.Draw(im)
            d.text((128, 102), str(num), font=font, fill=col + (255,), anchor="mm")
            im.save(os.path.join(TEXOUT, "plate_%02d.png" % num))
    for f in range(U.RIPPLE_FRAMES, 32):          # frames of the older, longer ripple loop
        old = os.path.join(TEXOUT, "sea_normal_%02d.png" % f)
        if os.path.exists(old):
            os.remove(old)
    # Particles draw colour * texture with screen blending (ParticlePS.hlsl): their textures must be premultiplied.
    for src, dst in (("rain_streak.png", "p_rain.png"), ("glow.png", "p_glow.png"), ("spray.png", "p_spray.png")):
        a = np.asarray(Image.open(os.path.join(TEXOUT, src)).convert("RGBA"), np.float32) / 255.0
        a[..., :3] *= a[..., 3:4]
        Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(TEXOUT, dst))
    print("textures ->", TEXOUT)


# ------------------------------------------------------------------ data for the Lua
def lua_value(v, ind=""):
    if isinstance(v, dict):
        items = []
        for k in sorted(v):
            key = k if isinstance(k, str) and k.isidentifier() else "[%s]" % lua_value(k)
            items.append("%s  %s = %s" % (ind, key, lua_value(v[k], ind + "  ")))
        return "{\n" + ",\n".join(items) + "\n" + ind + "}"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_value(x, ind) for x in v) + " }"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    return json.dumps(v)


def write_data():
    f, r, u = cam_basis()
    data = {
        "FLOAT_R": U.FLOAT_R, "HOOK_Z_BUOY": U.HOOK_Z_BUOY, "HOOK_Z_PIER": U.HOOK_Z_PIER, "CHAIN_MIN": U.CHAIN_MIN,
        "CHAIN_MAX": U.CHAIN_MAX, "REACH": U.REACH, "BUOY_BACK": U.BUOY_BACK, "ARM_FWD": U.ARM_FWD, "SPACING": U.SPACING,
        "CAM": {"dx": U.CAM_DX, "y": U.CAM_Y, "z": U.CAM_Z, "yaw": U.CAM_YAW, "pitch": U.CAM_PITCH, "fovx": FOVX,
                "follow": U.CAM_FOLLOW, "front": list(e(f)), "up": list(e(u))},
        "SEA_P": U.SEA_P, "SEA_C": U.SEA_C, "SEA_BREATH": U.SEA_BREATH, "SEA_NEAR_Y": U.SEA_NEAR_Y, "SEA_FADE_Y": U.SEA_FADE_Y, "RIPPLE_P": U.RIPPLE_P,
        "RIPPLE_FRAMES": U.RIPPLE_FRAMES, "RIPPLE_FPS": U.RIPPLE_FPS, "SWELLS": [list(s) for s in U.SWELLS], "CHOP": U.CHOP,
        "BOB_K": U.BOB_K, "SINK": U.SINK, "BUOY_TILT": U.BUOY_TILT,
        "BW_Y": U.BW_Y, "GAP_X": U.GAP_X, "BW_SEG": U.BW_SEG, "BW_GAP": U.BW_GAP, "PIER_Y": U.PIER_Y, "PIER_SEG": U.PIER_SEG,
        "FAR": {"y": FAR_Y, "w": FAR_W, "h": FAR_H, "z0": FAR_Z0, "lantern": [52.0, FAR_Y - 2.5]},
        "TRAIL_L": TRAIL_L, "SKY_D": SKY_D,
        "COURSE": [[k, x, p] for k, x, p in U.target_course()],
        "STATES": {k: {"hook": list(v["hook"]), "theta": v["theta"], "L": v["L"], "t": v["t"], "spray": v["spray"],
                       "lit_pier": v["lit_pier"]} for k, v in U.STATES.items()},
        "LAMP_LOCAL": 3.69,       # buoy lamp centre above the buoy origin (scene.py)
        "PLATE_N": U.PLATE_N, "CHAIN_LINK": list(U.CHAIN_LINK),
        "RULES": {"G": U.G, "DT": U.DT, "REEL": U.REEL, "PUMP_THETA": U.PUMP_THETA, "PUMP_ACC": U.PUMP_ACC, "START": U.START, "SKIP_ANGLE": U.SKIP_ANGLE,
                  "SKIP_SPEED": U.SKIP_SPEED, "SKIP_KEEP": U.SKIP_KEEP, "SKIP_BOUNCE": U.SKIP_BOUNCE,
                  "SKIM_DRAG": U.SKIM_DRAG, "RIDE_DEPTH": U.RIDE_DEPTH, "HOOK_CLEAR": U.HOOK_CLEAR, "BOAT_RUNUP": U.BOAT_RUNUP, "BOAT_IN_Y": U.BOAT_IN_Y, "GAP_IN_Y": U.GAP_IN_Y, "HIT_CELL": U.HIT_CELL,
                  "LAMP_PTS": U.LAMP_PTS, "CLEAN_PTS": U.CLEAN_PTS, "LEVEL_LEN": U.LEVEL_LEN, "LEVELS": U.LEVELS,
                  "LEVEL": {k: [list(v) if isinstance(v, tuple) else v for v in vals] for k, vals in U.LEVEL.items()},
                  "AMP": U.AMP},
        "HIT": uw_hits.all_grids(),
    }
    path = os.path.join(ASSETS, "Scripts", "uw_data.lua")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fo:
        fo.write("-- Generated by tools/gen_assets.py from tools/uw_common.py: do not edit.\n")
        fo.write("-- Blender axes (x along the harbour, y depth, z up); the world converts to engine (x, z, -y).\n")
        fo.write("return " + lua_value(data) + "\n")
    # Python sea heights for the parity test
    rng = np.random.default_rng(3)
    rows = []
    for _ in range(64):
        x, y, t = float(rng.uniform(-60, 300)), float(rng.uniform(-14, 62)), float(rng.uniform(0, 40))
        rows.append([x, y, t, U.sea_height(x, y, t)])
    for st in ("A", "B"):
        (fx, fy, fz), (hx, hy, hz) = U.float_pos(st)
        rows.append([fx, 0.0, U.STATES[st]["t"], U.sea_height(fx, 0.0, U.STATES[st]["t"])])
    tp = os.path.join(ROOT, "tests", "sea_samples.lua")
    os.makedirs(os.path.dirname(tp), exist_ok=True)
    with open(tp, "w") as fo:
        fo.write("-- Generated by tools/gen_assets.py: uw_common.sea_height(x, y, t) sampled in Python.\n")
        fo.write("return {\n" + "".join("  { %.6f, %.6f, %.6f, %.9f },\n" % tuple(r_) for r_ in rows) + "}\n")
    hooks = {st: U.float_pos(st) for st in U.STATES}
    print("data -> uw_data.lua, tests/sea_samples.lua; states", hooks)


# ------------------------------------------------------------------ scene
def look_matrix(pos, target, up=(0, 1, 0)):
    pos, target = np.array(pos, float), np.array(target, float)
    z = -(target - pos) / np.linalg.norm(target - pos)
    x = np.cross(up, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return [*x, 0.0, *y, 0.0, *z, 0.0, *pos, 1.0]


def write_scene(names):
    hidden = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, -1000.0, 0, 1.0]
    sc = {"sources": [], "meshes": [], "nodes": []}
    f, r, u = cam_basis()
    (fx, _, _), _ = U.float_pos("A")
    cpos = e((fx + U.CAM_DX, U.CAM_Y, U.CAM_Z))
    clook = tuple(np.array(cpos) + np.array(e(f)) * 10)
    cam = {"projection": "perspective", "fovx": math.radians(FOVX), "near_plane": 0.1, "far_plane": 3000.0, "speed": 3.5,
           "euler": [0.0, 3.14159, 0.0]}
    sc["nodes"].append({"name": "Camera_0", "parent": -1, "local_matrix": look_matrix(cpos, clook), "component_flags": 8, "camera": cam})
    # Glitter light: the target's mid-sea glitter is Cycles reflecting the lighthouse beam and the bright sky band under
    # it; the engine reflects neither (the beam is an alpha card, IBL is blurred). The only directional light (it lights
    # just the live sea, float and chain: set pieces are unlit) therefore comes from the sky just above the beam, at
    # GLITTER_AT (fraction of the window), so its specular lays a glitter path on the chop below it.
    gx, gy = GLITTER_AT
    t = math.tan(math.radians(FOVX / 2))
    d = np.array(f) + (2 * gx - 1) * t * np.array(r) + (1 - 2 * gy) * t * (1369 / 2560) * np.array(u)
    sun_from = tuple(np.array(e(tuple(d / np.linalg.norm(d)))) * 100)
    sc["nodes"].append({"name": "Sun", "parent": -1, "local_matrix": look_matrix(sun_from, (0, 0, 0)), "component_flags": 2,
                        "light": {"type": "directional", "color": [1.0, 0.65, 0.4, 0.5]}})
    for name in names:
        sc["sources"].append({"path": f"../Objects/{name}.pemesh"})
        src = len(sc["sources"]) - 1
        for v in VARIANTS.get(name, [name]):
            sc["meshes"].append({"source": src, "source_mesh": 0})
            sc["nodes"].append({"name": "T_" + v, "parent": -1, "local_matrix": hidden, "component_flags": 0,
                                "mesh_refs": [len(sc["meshes"]) - 1]})
    sc["lights"] = []
    sc["cameras"] = [{"name": "Camera_0", "position": list(cpos), "euler": [0.0, 3.14159, 0.0], "fovx": math.radians(FOVX),
                      "projection": "perspective", "near_plane": 0.1, "far_plane": 3000.0, "speed": 3.5, "node_index": 0}]
    sc["active_camera"] = 0
    sc["scene_scripts"] = {"on_play": ["Assets/Scripts/undertow.lua"]}
    os.makedirs(os.path.dirname(SCENE), exist_ok=True)
    with open(SCENE, "w") as fo:
        json.dump(sc, fo, indent=1)
    print("scene ->", SCENE)


# ------------------------------------------------------------------ main
def find_cook():
    for a in sys.argv[1:]:
        if not a.startswith("--"):
            return a
    eng = os.path.normpath(os.path.join(ROOT, "..", "..", "PhasmaEngine"))
    for b in ("build-ninja-physics", "build-ninja"):
        p = os.path.join(eng, b, "Release", "PhasmaCook.exe")
        if os.path.exists(p):
            return p
    raise SystemExit("PhasmaCook.exe not found; pass its path")


def cook_all(names):
    cook = find_cook()
    os.makedirs(OBJECTS, exist_ok=True)
    only = [a[7:] for a in sys.argv if a.startswith("--only=")]
    todo = [n for n in names if not only or n in only[0].split(",")]
    if not todo:
        print("nothing to cook")
        return
    stats = {}
    with tempfile.TemporaryDirectory(prefix="undertow-meshes-") as tmp:
        lines = []
        for name in todo:
            path = os.path.join(tmp, name + ".obj")
            if name in PIECES:
                nv, nt = read_blender_obj(os.path.join(PCS, name + ".obj"), path)
            else:
                nv, nt = GEN[name](path)
            stats[name] = (nv, nt)
            print(f"{name:12s} {nv:7d} verts {nt:7d} faces")
            lines.append(path + "\t" + os.path.join(OBJECTS, name + ".pemesh") + "\n")
        manifest = os.path.join(tmp, "batch.txt")
        with open(manifest, "w", encoding="utf-8") as fo:
            fo.writelines(lines)
        res = subprocess.run([cook, "--batch", manifest], cwd=os.path.dirname(cook), capture_output=True, text=True)
        if res.returncode != 0 or f"{len(lines)} ok" not in (res.stdout + res.stderr):
            print((res.stdout + res.stderr)[-3000:])
            raise SystemExit("PhasmaCook failed")
        print("cooked", len(lines), "meshes")
    path = os.path.join(OBJECTS, "mesh_stats.json")
    old = json.load(open(path)) if os.path.exists(path) else {}
    old.update(stats)
    with open(path, "w") as fo:
        json.dump(old, fo, indent=1)


def main():
    names = sorted(PIECES + list(GEN))
    write_data()
    if "--scene-only" not in sys.argv:
        make_textures()
        cook_all(names)
    write_scene(names)


if __name__ == "__main__":
    main()
