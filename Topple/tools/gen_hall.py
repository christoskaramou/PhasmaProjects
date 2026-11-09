"""Topple's Great Hall: the floor, walls and woodwork for the millions-of-dominoes room (Assets/Objects/hall_*.pemesh).

    python tools/gen_hall.py [path/to/PhasmaCook.exe]

Then it rewrites Assets/Scenes/main.pescene through gen_meshes.write_scene, which lists one hidden template node per
piece (T_hall_*). Table coordinates as everywhere in Topple: x right, y away from the default camera, h up. The hall's
floor is 2,400 units square (120 m at domino scale), the walls one-sided so the camera can see in from outside.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_meshes as G  # noqa: E402
import gen_room as R  # noqa: E402

E, EN, MU, box = R.E, R.EN, R.MU, R.box

SIDE = 1220.0        # inner walls, just past the 1,200 the dominoes may reach
WALL_H = 130.0       # low enough to leave the sky to the hall and keep the sun's shadow near the edge
BAY = 150.0          # between pilasters
FLOOR_TILE = 128.0   # world units per repeat of the floor texture (eight big stone slabs across)
PIECES = ["hall_floor", "hall_walls", "hall_trim", "hall_wood"]


def hall_floor():
    S = SIDE + 12
    return box(-S, S, -S, S, -1.0, 0.0, "H", uvs=FLOOR_TILE)


def hall_walls():
    """Four inward-facing walls: the camera sees through them from outside, as in the living room."""
    m = MU()
    S, H, T = SIDE, WALL_H, 120.0
    m.quad([E(-S, -S, 0), E(-S, S, 0), E(-S, S, H), E(-S, -S, H)], EN(1, 0, 0), [(-S / T, 0), (S / T, 0), (S / T, H / T), (-S / T, H / T)])
    m.quad([E(S, -S, 0), E(S, -S, H), E(S, S, H), E(S, S, 0)], EN(-1, 0, 0), [(S / T, 0), (S / T, H / T), (-S / T, H / T), (-S / T, 0)])
    m.quad([E(-S, S, 0), E(-S, S, H), E(S, S, H), E(S, S, 0)], EN(0, -1, 0), [(-S / T, 0), (-S / T, H / T), (S / T, H / T), (S / T, 0)])
    m.quad([E(-S, -S, 0), E(S, -S, 0), E(S, -S, H), E(-S, -S, H)], EN(0, 1, 0), [(S / T, 0), (-S / T, 0), (-S / T, H / T), (S / T, H / T)])
    return m


def bays():
    n = int(2 * SIDE / BAY)
    return [(-SIDE + (i + 0.5) * (2 * SIDE / n)) for i in range(n)]


def hall_trim():
    """Cream pilasters round the walls with a chair rail and a cornice."""
    m = MU()
    S, H = SIDE, WALL_H
    d, w = 12.0, 26.0
    for a in bays():
        m += box(-S, -S + d, a - w / 2, a + w / 2, 0, H - 26, "XyYH")
        m += box(S - d, S, a - w / 2, a + w / 2, 0, H - 26, "xyYH")
        m += box(a - w / 2, a + w / 2, S - d, S, 0, H - 26, "xXyH")
        m += box(a - w / 2, a + w / 2, -S, -S + d, 0, H - 26, "xXYH")
    r = 5.0
    for h0, h1 in ((30.0, 34.0), (H - 26.0, H)):
        m += box(-S, -S + r, -S, S, h0, h1, "XH")
        m += box(S - r, S, -S, S, h0, h1, "xH")
        m += box(-S, S, S - r, S, h0, h1, "yH")
        m += box(-S, S, -S, -S + r, h0, h1, "YH")
    return m


def hall_wood():
    """Dark walnut skirting round the whole floor."""
    m = MU()
    S, r, h = SIDE, 6.0, 18.0
    m += box(-S, -S + r, -S, S, 0, h, "XH")
    m += box(S - r, S, -S, S, 0, h, "xH")
    m += box(-S, S, S - r, S, 0, h, "yH")
    m += box(-S, S, -S, -S + r, 0, h, "YH")
    return m


BUILD = {"hall_floor": hall_floor, "hall_walls": hall_walls, "hall_trim": hall_trim, "hall_wood": hall_wood}


def tex_hall_floor():
    """Deep walnut-brown honed stone: dark enough for the paints to stand out on, quiet enough to stay calm far away."""
    rng = np.random.default_rng(21)
    S = 2048
    slabs = 4
    mott = 0.55 * R.periodic_noise(S, S, rng, kmax=10, amp_pow=1.6) + 0.45 * R.periodic_noise(S, S, rng, kmax=48, amp_pow=1.1)
    fine = rng.normal(0, 1, (S, S))
    base = np.array([0.33, 0.25, 0.19])
    out = base[None, None, :] * (1.0 + 0.06 * mott[:, :, None] + 0.01 * fine[:, :, None])
    # Every slab very slightly different: more than this repeats across the floor as a visible weave.
    pitch = S / slabs
    y, x = np.mgrid[0:S, 0:S]
    col, row = (x / pitch).astype(int), (y / pitch).astype(int)
    tone = rng.uniform(0.985, 1.015, (slabs, slabs))
    out *= tone[row % slabs, col % slabs][:, :, None]
    # Thin, soft joints.
    dx = np.minimum((x % pitch), pitch - (x % pitch))
    dy = np.minimum((y % pitch), pitch - (y % pitch))
    joint = np.clip(1.0 - np.minimum(dx, dy) / 2.2, 0.0, 1.0)
    out *= (1.0 - 0.34 * joint[:, :, None])
    R.srgb_png(out, os.path.join(R.TEX, "hall_floor.png"))


def write_hdr(path, rgb):
    """Radiance HDR, uncompressed scanlines."""
    h, w, _ = rgb.shape
    with open(path, "wb") as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n")
        f.write(f"-Y {h} +X {w}\n".encode())
        m = np.maximum(np.maximum(rgb[:, :, 0], rgb[:, :, 1]), rgb[:, :, 2])
        e = np.ceil(np.log2(np.maximum(m, 1e-32)))
        s = 256.0 / np.power(2.0, e)
        data = np.dstack([rgb[:, :, 0] * s, rgb[:, :, 1] * s, rgb[:, :, 2] * s, e + 128.0])
        data[m < 1e-32] = 0
        f.write(np.clip(data, 0, 255).astype(np.uint8).tobytes())


def hall_sky():
    """A clear late-afternoon sky over a warm horizon: the hall's backdrop and its light from above."""
    w, h = 1024, 512
    v, u = np.mgrid[0:h, 0:w]
    el = (0.5 - (v + 0.5) / h) * np.pi              # elevation
    az = ((u + 0.5) / w) * 2 * np.pi
    zenith, horizon = np.array([0.30, 0.50, 0.92]), np.array([1.30, 1.12, 0.92])
    t = np.clip(np.sin(np.maximum(el, 0.0)), 0.0, 1.0) ** 0.42
    sky = horizon[None, None, :] * (1 - t[:, :, None]) + zenith[None, None, :] * t[:, :, None]
    rng = np.random.default_rng(4)
    cloud = R.periodic_noise(h, w, rng, kmax=14, amp_pow=1.4)
    band = np.exp(-((el - 0.42) / 0.3) ** 2) * np.clip(cloud * 1.6, 0.0, 1.0)
    sky = sky + band[:, :, None] * np.array([0.65, 0.62, 0.58])
    ground = np.array([0.36, 0.31, 0.25])
    below = (el < 0)[:, :, None]
    sky = np.where(below, ground[None, None, :], sky)
    write_hdr(os.path.join(R.SKY, "hall.hdr"), np.maximum(sky, 0.0))
    _ = az


def pictures():
    """The pictures the hall comes with, and the Picture tool's icon."""
    out = os.path.join(R.ROOT, "Assets", "Pictures")
    os.makedirs(out, exist_ok=True)
    # A sunset over layered hills.
    W, H = 1280, 800
    y = np.linspace(0, 1, H)[:, None]
    stops = np.array([[0.13, 0.13, 0.36], [0.55, 0.22, 0.45], [0.96, 0.46, 0.25], [1.0, 0.8, 0.42]])
    t = np.clip(y / 0.68, 0, 1) * 3
    i = np.minimum(t.astype(int), 2)
    sky = stops[i[:, 0]] + (stops[i[:, 0] + 1] - stops[i[:, 0]]) * (t - i)
    img = np.repeat(sky[:, None, :], W, axis=1)
    xx, yy = np.meshgrid(np.arange(W), np.arange(H))
    glow = np.exp(-(((xx - 820) ** 2 + (yy - 520) ** 2) / 240.0 ** 2))[:, :, None]
    img = img + glow * np.array([0.5, 0.3, 0.05])
    img[((xx - 820) ** 2 + (yy - 520) ** 2) < 92 ** 2] = (1.0, 0.92, 0.66)
    hills = [(0.62, 46, 0.0031, (0.42, 0.2, 0.34)), (0.72, 58, 0.0043, (0.27, 0.14, 0.3)), (0.84, 40, 0.0057, (0.12, 0.08, 0.18))]
    for k, (base, amp, freq, col) in enumerate(hills):
        ridge = H * base + amp * np.sin(xx * freq + k * 2.1) + amp * 0.45 * np.sin(xx * freq * 2.7 + k)
        img[yy > ridge] = col
    R.srgb_png(img, os.path.join(out, "sunset.png"))
    # A poster: the game's name in bands of its paints.
    S = (1400, 800)
    bands = [(128, 33, 18), (199, 133, 33), (82, 112, 77), (26, 41, 82), (214, 196, 158)]
    im = Image.new("RGB", S, (26, 22, 34))
    d = ImageDraw.Draw(im)
    for i in range(46):
        d.polygon([(700, 400), (700 + 1800 * np.cos(i * np.pi / 23), 400 + 1800 * np.sin(i * np.pi / 23)),
                   (700 + 1800 * np.cos((i + 1) * np.pi / 23), 400 + 1800 * np.sin((i + 1) * np.pi / 23))], fill=bands[i % 5])
    font = ImageFont.truetype(os.path.join(R.ROOT, "Assets", "Fonts", "RuntimeUi.ttf"), 300)
    for off, fill in ((14, (16, 12, 18)), (0, (250, 240, 214))):
        d.text((700 + off, 400 + off), "TOPPLE", font=font, fill=fill, anchor="mm")
    im.save(os.path.join(out, "topple.png"))
    # The tool's icon: a framed landscape.
    im = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((26, 46, 230, 210), 14, fill=(214, 196, 158, 255), outline=(120, 76, 36, 255), width=10)
    d.ellipse((150, 70, 196, 116), fill=(199, 133, 33, 255))
    d.polygon([(38, 198), (104, 104), (160, 198)], fill=(128, 33, 18, 255))
    d.polygon([(112, 198), (168, 132), (218, 198)], fill=(26, 41, 82, 255))
    im.save(os.path.join(R.TEX, "icon_tool_picture.png"))
    # The Split tool's icon: one line into three.
    im = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for end, fill in (((226, 44), (128, 33, 18, 255)), ((236, 128), (214, 196, 158, 255)), ((226, 212), (82, 112, 77, 255))):
        d.line([(112, 128), end], fill=fill, width=26)
    d.line([(20, 128), (116, 128)], fill=(199, 133, 33, 255), width=30)
    im.save(os.path.join(R.TEX, "icon_tool_split.png"))


def main():
    tex_hall_floor()
    hall_sky()
    pictures()
    cook = G.find_cook()
    os.makedirs(G.OBJECTS, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="topple-hall-") as tmp:
        lines = []
        for name in PIECES:
            src = os.path.join(tmp, name + ".obj")
            nv, nt = R.save_obj_uv(src, BUILD[name]())
            print(f"{name:20s} {nv:7d} verts {nt:7d} tris")
            lines.append(f"{src}\t{os.path.join(G.OBJECTS, name + '.pemesh')}\n")
        manifest = os.path.join(tmp, "batch.txt")
        with open(manifest, "w", encoding="utf-8") as f:
            f.writelines(lines)
        r = subprocess.run([cook, "--batch", manifest], cwd=os.path.dirname(cook), capture_output=True, text=True)
        if r.returncode != 0 or f"{len(lines)} ok" not in (r.stdout + r.stderr):
            print((r.stdout + r.stderr)[-3000:])
            raise SystemExit("PhasmaCook failed")
    G.write_scene(sorted(G.MESHES))
    print("scene:", G.SCENE)


if __name__ == "__main__":
    main()
