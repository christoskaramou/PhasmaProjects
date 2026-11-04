"""Refract HUD art: piece and enemy icons, glow strips, flares, panels (numpy + PIL). The board is 3D.

Everything is drawn at 2-4x and downsampled. White/grey sprites are tinted in game; sprites with their
own colours (prism, chrome, portal) are used untinted.
"""

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "Assets" / "Textures"
rng = np.random.default_rng(11)


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1  # -1..1, y down


def save(rgba, name, size):
    a = np.clip(rgba, 0, 1)
    img = Image.fromarray((a * 255).astype(np.uint8), "RGBA")
    if size:
        img = img.resize((size, size) if isinstance(size, int) else size, Image.LANCZOS)
    img.save(OUT / f"{name}.png")


def smooth(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def rgba(n, col=(1, 1, 1), alpha=None):
    a = np.zeros((n, n, 4), np.float32)
    a[..., :3] = col
    if alpha is not None:
        a[..., 3] = alpha
    return a


def over(dst, src):
    sa = src[..., 3:4]
    da = dst[..., 3:4]
    oa = sa + da * (1 - sa)
    rgb = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
    return np.concatenate([rgb, oa], -1)


def layer(n, col, alpha):
    a = rgba(n)
    a[..., :3] = np.asarray(col, np.float32) if np.ndim(col) == 1 else col
    a[..., 3] = alpha
    return a


def noise(n, scale, octaves=4, seed=0):
    r = np.random.default_rng(seed)
    acc = np.zeros((n, n), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(scale * 2 ** o))
        base = r.random((s, s)).astype(np.float32)
        img = Image.fromarray((base * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
        acc += np.asarray(img, np.float32) / 255 * amp
        tot += amp
        amp *= 0.5
    return acc / tot


# ---------------------------------------------------------------- beams
def beams():
    # Cross-profile strip, stretched along the beam: a bright core plus a wide soft tail in one texture
    # (one quad per slice, so slices never overlap and band). The core spans the middle 1/2.4.
    w, h = 16, 256
    yy = (np.arange(h, dtype=np.float32) + 0.5) / h * 2 - 1
    core = np.exp(-((yy * 2.4) ** 2) * 7.15)
    tail = np.exp(-(yy ** 2) * 7.15) * 0.25
    glow = core + tail
    glow -= glow.min()
    glow /= glow.max()
    a = np.zeros((h, w, 4), np.float32)
    a[..., :3] = 1
    a[..., 3] = glow[:, None]
    Image.fromarray((a * 255).astype(np.uint8), "RGBA").save(OUT / "beam_glow_h.png")
    Image.fromarray((a * 255).astype(np.uint8), "RGBA").transpose(Image.ROTATE_90).save(OUT / "beam_glow_v.png")
    # Flare: star-shaped highlight for beam hits and photons.
    n = 256
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    flare = np.exp(-r * 6) + 0.6 * np.exp(-abs(x) * 40) * np.exp(-abs(y) * 3) + 0.6 * np.exp(-abs(y) * 40) * np.exp(-abs(x) * 3)
    flare = np.clip(flare, 0, 1)
    save(layer(n, (1, 1, 1), flare), "flare", 96)


# ---------------------------------------------------------------- enemies
def shaded_orb(n, col, rim_col=(1, 1, 1), spec=0.8, lx=-0.45, ly=-0.5, dark=0.25):
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    inside = 1 - smooth(0.9, 0.94, r)
    z = np.sqrt(np.clip(1 - (r / 0.92) ** 2, 0, 1))
    ndl = np.clip((-x * lx - y * ly) / 0.92 * 0.6 + z * 0.65, 0, 1)
    c = np.asarray(col, np.float32)
    shade = dark + (1 - dark) * ndl
    rgb = c * shade[..., None]
    rim = smooth(0.6, 0.92, r) * np.clip((x + y) * 0.6 + 0.3, 0, 1)
    rgb += rim[..., None] * np.asarray(rim_col, np.float32) * 0.45
    sp = np.exp(-(((x - lx * 0.55) ** 2 + (y - ly * 0.55) ** 2) / 0.02)) * spec
    rgb += sp[..., None]
    out = np.concatenate([rgb, inside[..., None]], -1)
    # Soft drop shadow ring outside for contrast on any floor.
    shadow = (1 - smooth(0.92, 1.0, r)) * (1 - inside) * 0.6
    sh = layer(n, (0, 0, 0), shadow)
    return over(sh, out)


def enemies():
    n = 256
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    ang = np.arctan2(y, x)
    # Mote: pale orb with a glowing nucleus (tintable: drawn near-white).
    m = shaded_orb(n, (0.92, 0.94, 1.0), spec=0.9)
    nuc = np.exp(-(r ** 2) / 0.05)
    m[..., :3] = m[..., :3] * (1 - 0.35 * nuc[..., None]) + nuc[..., None] * np.array([0.55, 0.6, 0.85]) * 0.35
    save(m, "en_orb", 96)

    # Dart: a swept teardrop pointing right, with a bright head.
    d = np.zeros((n, n), np.float32)
    body = ((x + 0.15) / 0.75) ** 2 + (y / (0.32 * np.clip(1 - (x + 0.15) / 1.2, 0.05, 1))) ** 2 < 1
    d[body] = 1
    d = np.asarray(Image.fromarray((d * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2)), np.float32) / 255
    shade = 0.55 + 0.45 * np.clip(-y * 1.5 + 0.3, 0, 1) + 0.4 * np.exp(-(((x - 0.35) ** 2) / 0.02 + (y ** 2) / 0.01))
    img = layer(n, np.stack([shade] * 3, -1), d)
    save(img, "en_dart_right", 96)
    # Hulk: armoured hexagonal shell with plates and a glowing slit.
    hexd = np.maximum(abs(x) * 0.866 + abs(y) * 0.5, abs(y)) / 0.85
    inside = 1 - smooth(0.97, 1.0, hexd)
    shade = 0.45 + 0.5 * np.clip(-(x * 0.4 + y * 0.7) + 0.4, 0, 1)
    plate = (abs(np.sin(ang * 3)) > 0.97) & (hexd > 0.35)
    shade = np.where(plate, shade * 0.55, shade)
    inner = hexd < 0.42
    shade = np.where(inner, shade * 0.7, shade)
    slit = (abs(y) < 0.06) & (abs(x) < 0.3)
    rgb = np.stack([shade] * 3, -1)
    rgb[slit] = 1.6
    rim = smooth(0.85, 0.97, hexd) * 0.35
    rgb += rim[..., None]
    sh = layer(n, (0, 0, 0), (1 - smooth(0.97, 1.08, hexd)) * 0.6)
    save(over(sh, layer(n, rgb, inside)), "en_hulk", 96)

    # Splitter: three fused orbs.
    acc = rgba(n, (0, 0, 0), np.zeros((n, n)))
    for k in range(3):
        a = k / 3 * 2 * math.pi - math.pi / 2
        ox, oy = math.cos(a) * 0.36, math.sin(a) * 0.36
        sub = shaded_orb(n, (1, 1, 1), spec=0.7)
        img = Image.fromarray((np.clip(sub, 0, 1) * 255).astype(np.uint8), "RGBA").resize((int(n * 0.6), int(n * 0.6)), Image.LANCZOS)
        canvas = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        canvas.paste(img, (int(n / 2 + ox * n / 2 - n * 0.3), int(n / 2 + oy * n / 2 - n * 0.3)), img)
        acc = over(acc, np.asarray(canvas, np.float32) / 255)
    save(acc, "en_splitter", 96)

    # Chrome orb for mirrorbacks (untinted): sky/ground reflection bands.
    zc = np.sqrt(np.clip(1 - (r / 0.92) ** 2, 0, 1))
    band = np.where(y < 0.05 * np.sin(x * 4), 0.75 + 0.25 * (-y), 0.25 + 0.3 * (y + 0.2))
    rgb = np.stack([band * 0.9, band * 0.95, band * 1.05], -1) * (0.55 + 0.45 * zc[..., None])
    rgb += np.exp(-(((x + 0.3) ** 2 + (y + 0.35) ** 2) / 0.015))[..., None]
    rgb += (smooth(0.75, 0.92, r) * 0.5)[..., None]
    inside = 1 - smooth(0.9, 0.94, r)
    sh = layer(n, (0, 0, 0), (1 - smooth(0.92, 1.0, r)) * (1 - inside) * 0.6)
    save(over(sh, layer(n, rgb, inside)), "en_chrome", 96)

    # Shield ring (tinted): bright band with hex segments and outer glow.
    ring = np.exp(-((r - 0.82) ** 2) / 0.003)
    seg = 0.75 + 0.25 * (np.cos(ang * 6) > -0.8)
    glow = np.exp(-((r - 0.82) ** 2) / 0.03) * 0.5
    save(layer(n, (1, 1, 1), np.clip(ring * seg + glow, 0, 1)), "en_ring", 128)

    # Dark core for shades / eclipse body.
    dark = shaded_orb(n, (0.16, 0.14, 0.22), rim_col=(0.6, 0.6, 0.8), spec=0.35, dark=0.4)
    save(dark, "en_dark", 96)

    # Eclipse corona (tinted): rays around a dark disc.
    rays = (0.5 + 0.5 * np.cos(ang * 14)) ** 4 * np.exp(-np.clip(r - 0.45, 0, None) * 5) * (r > 0.42)
    halo = np.exp(-np.clip(r - 0.45, 0, None) * 7) * (r > 0.42)
    save(layer(n, (1, 1, 1), np.clip(rays * 0.8 + halo * 0.7, 0, 1)), "en_corona", 160)


# ---------------------------------------------------------------- pieces
def pieces():
    n = 512
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    # Emitter: metal housing (untinted greys) with a tintable crystal drawn separately.
    box = np.maximum(abs(x) / 0.72, abs(y + 0.12) / 0.6)
    rnd = np.sqrt(np.clip(np.maximum(abs(x) - 0.52, 0), 0, None) ** 2 + np.clip(np.maximum(abs(y + 0.12) - 0.4, 0), 0, None) ** 2)
    housing = (box < 1) & (rnd < 0.2)
    barrel = (abs(x) < 0.17) & (y < -0.3) & (y > -0.92)
    shape = (housing | barrel).astype(np.float32)
    shape = np.asarray(Image.fromarray((shape * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2)), np.float32) / 255
    metal = 0.34 + 0.28 * np.clip(-(x * 0.5 + y * 0.8), -1, 1) + 0.06 * noise(n, 20, 2, 30)
    metal = np.where(barrel, 0.5 + 0.3 * np.cos(x / 0.17 * 1.4), metal)
    edgeb = smooth(0.82, 0.98, box) * housing
    metal = metal + 0.18 * edgeb * np.clip(-(x + y), -1, 1)
    rgb = np.stack([metal * 0.92, metal * 0.96, metal * 1.08], -1)
    window = r < 0.3
    rgb[window] = 0.06
    shadow = layer(n, (0, 0, 0), np.asarray(Image.fromarray((shape * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(14)), np.float32) / 255 * 0.7)
    em = over(shadow, layer(n, rgb, shape))
    img = Image.fromarray((np.clip(em, 0, 1) * 255).astype(np.uint8), "RGBA").resize((128, 128), Image.LANCZOS)
    img.save(OUT / "emitter_up.png")  # HUD icon
    # Mirror: silver plate on a dark mount, "/" orientation.
    u = (x + y) / math.sqrt(2)   # across the plate
    v = (x - y) / math.sqrt(2)   # along the plate
    plate = (abs(u) < 0.09) & (abs(v) < 0.95)
    mount = r < 0.32
    rgb = np.zeros((n, n, 3), np.float32)
    a = np.zeros((n, n), np.float32)
    rgb[mount] = 0.16
    a[mount] = 0.95
    shine = 0.65 + 0.35 * np.cos(v * 3.5) + 0.3 * (u < 0)
    pr = np.stack([shine * 0.86, shine * 0.95, shine * 1.08], -1)
    rgb[plate] = pr[plate]
    a[plate] = 1
    edge = plate & (abs(u) > 0.06)
    rgb[edge] = np.array([0.55, 0.85, 1.0])
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    sh = layer(n, (0, 0, 0), np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(12)), np.float32) / 255 * 0.6)
    m = over(sh, layer(n, rgb, a))
    save(m, "mirror_slash", 128)

    # Prism: glass triangle, coloured internal dispersion, bright edges.
    top, bl, br = np.array([0, -0.82]), np.array([-0.82, 0.62]), np.array([0.82, 0.62])

    def side(p, q):
        return (q[0] - p[0]) * (y - p[1]) - (q[1] - p[1]) * (x - p[0])
    s1, s2, s3 = side(top, br), side(br, bl), side(bl, top)
    tri = (s1 > 0) & (s2 > 0) & (s3 > 0)
    dist = np.minimum(np.minimum(abs(s1) / 1.68, abs(s2) / 1.64), abs(s3) / 1.68)
    t = (x + 0.82) / 1.64
    disp = np.stack([np.clip(1.5 - abs(t - 0.15) * 4, 0, 1), np.clip(1.5 - abs(t - 0.5) * 4, 0, 1), np.clip(1.5 - abs(t - 0.85) * 4, 0, 1)], -1)
    glass = 0.18 + 0.35 * disp * smooth(0.0, 0.5, y + 0.3)[..., None]
    glass += smooth(0.05, 0.0, dist)[..., None] * 0.9
    glass += (np.exp(-(((x + 0.15) ** 2) / 0.01 + ((y + 0.15) ** 2) / 0.12)) * 0.5)[..., None]
    a = tri.astype(np.float32) * (0.82 + 0.18 * smooth(0.06, 0.0, dist))
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    sh = layer(n, (0, 0, 0), np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(14)), np.float32) / 255 * 0.6)
    save(over(sh, layer(n, glass, a)), "prism", 128)

    # Lens: glass disc in a brass-like ring.
    ringm = (r > 0.62) & (r < 0.78)
    disc = r <= 0.62
    rgb = np.zeros((n, n, 3), np.float32)
    a = np.zeros((n, n), np.float32)
    ring_shade = 0.5 + 0.4 * np.clip(-(x + y), -1, 1)
    rgb[ringm] = np.stack([ring_shade * 0.75, ring_shade * 0.8, ring_shade * 0.95], -1)[ringm]
    a[ringm] = 1
    gl = 0.35 + 0.4 * (1 - r / 0.62)
    rgb[disc] = np.stack([gl * 0.7, gl * 0.9, gl * 1.1], -1)[disc]
    a[disc] = 0.6
    hl = np.exp(-(((x + 0.22) ** 2 + (y + 0.25) ** 2) / 0.012))
    rgb += hl[..., None]
    a = np.maximum(a, hl)
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    sh = layer(n, (0, 0, 0), np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(12)), np.float32) / 255 * 0.5)
    save(over(sh, layer(n, rgb, a)), "lens", 128)

    # Soft round glow (HUD halos).
    g = np.exp(-(r ** 2) * 4.5) * (1 - smooth(0.9, 1.0, r))
    save(layer(n, (1, 1, 1), g), "glow", 128)

    # Energy icon (gold crystal, untinted) and core icon (cyan heart-gem).
    gem = abs(x) / 0.6 + abs(y) / 0.9 < 1
    f2 = np.where(x < 0, 1.0, 0.75)
    rgb = np.stack([f2 * 1.0, f2 * 0.82, f2 * 0.3], -1)
    a = np.asarray(Image.fromarray((gem.astype(np.float32) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    save(layer(n, rgb, a), "icon_energy", 64)


def blur(a, radius):
    return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius)), np.float32) / 255


# ---------------------------------------------------------------- UI and effects
def ui():
    n = 256
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)

    # Five-point star for result ratings (tinted gold / grey), shaded per facet.
    from PIL import ImageDraw
    big = 1024
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c0 = big / 2
    outer, inner = big * 0.47, big * 0.2
    pts = []
    for i in range(10):
        ang_i = -math.pi / 2 + i * math.pi / 5
        rr = outer if i % 2 == 0 else inner
        pts.append((c0 + math.cos(ang_i) * rr, c0 + math.sin(ang_i) * rr * 1.0 + big * 0.03))
    for i in range(10):  # facets: each triangle centre -> point -> next point
        p1, p2 = pts[i], pts[(i + 1) % 10]
        light = 0.62 + 0.38 * max(0.0, math.cos(-math.pi / 2 + (i + 0.5) * math.pi / 5 + math.pi * 0.75))
        g = int(255 * light)
        d.polygon([(c0, c0 + big * 0.03), p1, p2], fill=(g, g, g, 255))
    shadow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(pts, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    shadow.alpha_composite(img)
    shadow.resize((128, 128), Image.LANCZOS).save(OUT / "star.png")

    # Upgrade icon: double chevron pointing up.
    m = np.zeros((n, n), np.float32)
    for oy in (-0.18, 0.28):
        arm = abs((y - oy) - (abs(x) * 0.9 - 0.32)) < 0.11
        m[arm & (abs(x) < 0.62)] = 1
    m = blur(m, 2)
    save(layer(n, (1, 1, 1), m), "icon_upgrade", 96)

    # Core icon: cyan gem.
    gem = abs(x) / 0.62 + abs(y) / 0.92 < 1
    f2 = np.where(x < 0, 1.0, 0.72) * np.where(y < 0, 1.0, 0.85)
    rgb = np.stack([f2 * 0.5, f2 * 0.95, f2 * 1.0], -1)
    save(layer(n, rgb, blur(gem.astype(np.float32), 1.5)), "icon_core", 64)

    # Speed, surge and menu glyphs (tinted white).
    img = Image.new("L", (n, n), 0)
    dd = ImageDraw.Draw(img)
    for ox in (-0.55, 0.05):
        dd.polygon([((ox + 1) / 2 * n, 0.2 * n), ((ox + 0.6 + 1) / 2 * n, 0.5 * n), ((ox + 1) / 2 * n, 0.8 * n)], fill=255)
    save(layer(n, (1, 1, 1), np.asarray(img.filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255), "icon_speed", 96)
    bolt = np.zeros((n, n), np.float32)
    pts = [(0.15, -0.85), (-0.42, 0.12), (-0.02, 0.12), (-0.18, 0.85), (0.42, -0.15), (0.02, -0.15)]
    img = Image.new("L", (n, n), 0)
    ImageDraw.Draw(img).polygon([((px + 1) / 2 * n, (py + 1) / 2 * n) for px, py in pts], fill=255)
    bolt = np.asarray(img.filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    save(layer(n, (1, 1, 1), bolt), "icon_surge", 96)
    m = np.zeros((n, n), np.float32)
    for oy in (-0.42, 0.0, 0.42):
        m[(abs(y - oy) < 0.08) & (abs(x) < 0.62)] = 1
    save(layer(n, (1, 1, 1), blur(m, 2)), "icon_menu", 96)
    play = np.zeros((n, n), np.float32)
    play[(x > -0.45) & (abs(y) < 0.62 - (x + 0.45) * 0.62 / 1.05)] = 1
    save(layer(n, (1, 1, 1), blur(play, 2)), "icon_play", 96)

    # Full-screen vignette: transparent centre, dark corners (stretched to the screen).
    w2, h2 = 320, 200
    yy, xx = np.mgrid[0:h2, 0:w2].astype(np.float32)
    u, v = (xx + 0.5) / w2 * 2 - 1, (yy + 0.5) / h2 * 2 - 1
    d = np.sqrt((u * 0.9) ** 2 + (v * 1.0) ** 2)
    a = smooth(0.55, 1.45, d) * 0.85
    img = np.zeros((h2, w2, 4), np.float32)
    img[..., 3] = a
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(OUT / "vignette.png")

    # Banner strip: horizontal light band that fades at both ends and across.
    w2, h2 = 512, 64
    yy, xx = np.mgrid[0:h2, 0:w2].astype(np.float32)
    u, v = (xx + 0.5) / w2 * 2 - 1, (yy + 0.5) / h2 * 2 - 1
    a = (1 - smooth(0.3, 1.0, abs(u))) * np.exp(-(v ** 2) * 3)
    img = np.ones((h2, w2, 4), np.float32)
    img[..., 3] = a
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(OUT / "strip.png")

    # Vertical sheen for panels: white at the top fading out (stretched over any panel).
    h2 = 64
    v = (np.arange(h2, dtype=np.float32) + 0.5) / h2
    a = (1 - v) ** 2.2
    img = np.ones((h2, 4, 4), np.float32)
    img[..., 3] = a[:, None]
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(OUT / "sheen.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    beams()
    enemies()
    pieces()
    ui()
    print("art written to", OUT)
