"""Ricochet Parlour textures and environment: the ivory cup plates (used by the backdrop bake), the HUD's
cursor ring, the balls' soft shadow, and a dim lamp-lit parlour HDR for image-based lighting (so the metal balls
reflect a dark room with a warm lamp above, as in the concept render).

    python tools/make_textures.py

All tiles are seamless (noise is built in the frequency domain, so it wraps).
"""
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent / "Assets"
TEX = ROOT / "Textures"
SKY = ROOT / "Skybox"
FONT = ROOT / "Fonts" / "RuntimeUi.ttf"
RNG = np.random.default_rng(2024)


def periodic_noise(n, sx, sy, power=0.0, seed=None):
    """Seamless band-limited noise, normalised to 0..1. sx / sy: feature size in pixels along x / y."""
    rng = np.random.default_rng(seed) if seed is not None else RNG
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    filt = np.exp(-((fx * sx) ** 2 + (fy * sy) ** 2))
    if power:
        r = np.sqrt(fx ** 2 + fy ** 2) + 1e-4
        filt = filt * r ** -power
    spec = np.fft.fft2(rng.standard_normal((n, n))) * filt
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    return out / out.max()


def to_png(arr, path):
    Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8)).save(path)
    print(path.name, arr.shape)


def lerp(a, b, t):
    return np.asarray(a)[None, None, :] + (np.asarray(b) - np.asarray(a))[None, None, :] * t[..., None]


def plates():
    """Ivory number plates under the two brass cups (text in the HUD's own font)."""
    for label in ("50", "100"):
        w, h = 512, 196
        im = Image.new("RGB", (w, h), (222, 208, 180))
        d = ImageDraw.Draw(im)
        # Soft aged edge and an engraved border.
        d.rectangle([10, 10, w - 11, h - 11], outline=(150, 120, 80), width=6)
        d.rectangle([24, 24, w - 25, h - 25], outline=(186, 160, 120), width=2)
        try:
            f = ImageFont.truetype(str(FONT), 150)
        except OSError:
            f = ImageFont.load_default()
        d.text((w / 2, h / 2 + 2), label, font=f, fill=(48, 28, 12), anchor="mm")
        g = np.asarray(im, np.float32) / 255
        grain = periodic_noise(512, 20, 20, seed=8)[:h, :w]
        g = g * (0.94 + 0.06 * grain[..., None])
        to_png(g, TEX / f"plate{label}.png")


def hud():
    n = 256
    yy, xx = np.mgrid[0:n, 0:n] / (n - 1) - 0.5
    r = np.sqrt(xx * xx + yy * yy) * 2
    ring = np.exp(-((r - 0.86) / 0.05) ** 2) * (r < 1)
    img = Image.new("RGBA", (n, n), (255, 255, 255, 0)); img.putalpha(Image.fromarray((ring / ring.max() * 255).astype(np.uint8)))
    img.save(TEX / "ring.png")
    # Ball shadow: a soft blob, darkest at the centre (the lamp is broad, so the edge is wide).
    m = 256
    yy, xx = np.mgrid[0:m, 0:m] / (m - 1) - 0.5
    rr = np.sqrt(xx * xx + yy * yy) * 2
    sh = np.clip(np.exp(-(rr / 0.55) ** 2.2) - 0.01, 0, 1)
    img = Image.new("RGBA", (m, m), (0, 0, 0, 0)); img.putalpha(Image.fromarray((sh / sh.max() * 255).astype(np.uint8)))
    img.save(TEX / "shadow.png")
    print("ring.png, shadow.png")


def room_hdr():
    """Equirect 512x256 Radiance HDR: a dark wood-panelled parlour, a warm lamp overhead, a dim cool window."""
    w, h = 512, 256
    v = (np.arange(h)[:, None] + 0.5) / h             # 0 top .. 1 bottom
    u = (np.arange(w)[None, :] + 0.5) / w
    el = (0.5 - v) * np.pi                            # elevation
    az = (u - 0.5) * 2 * np.pi
    d = np.stack([np.cos(el) * np.sin(az) * np.ones_like(u), np.sin(el) * np.ones_like(u), np.cos(el) * np.cos(az) * np.ones_like(u)], -1)
    wall = np.array([0.18, 0.12, 0.08])
    floor_ = np.array([0.07, 0.045, 0.03])
    ceil = np.array([0.34, 0.25, 0.17])
    up = np.clip(d[..., 1], -1, 1)
    upp, dn = np.clip(up, 0, 1)[..., None], np.clip(-up, 0, 1)[..., None]
    col = np.where(up[..., None] > 0, wall + (ceil - wall) * upp ** 0.7, wall + (floor_ - wall) * dn ** 0.6)
    # Lamp: a warm bright disc overhead (slightly toward the viewer side), plus its glow.
    lamp_dir = np.array([0.05, 0.9, 0.42]); lamp_dir /= np.linalg.norm(lamp_dir)
    cosang = np.clip((d * lamp_dir).sum(-1), -1, 1)
    ang = np.arccos(cosang)
    col = col + np.array([1.0, 0.78, 0.5])[None, None, :] * (30 * (ang < 0.2) + 3.0 * np.exp(-(ang / 0.6) ** 2))[..., None]
    # The wall behind the viewer, lit by the lamp: pin caps and ball fronts reflect it.
    back = np.array([0.0, 0.25, 1.0]); back /= np.linalg.norm(back)
    ba = np.arccos(np.clip((d * back).sum(-1), -1, 1))
    col = col + np.array([0.55, 0.42, 0.28])[None, None, :] * np.exp(-(ba / 0.7) ** 2)[..., None]
    # A dim cool window far to the left: gives the balls a second, cooler highlight.
    win = np.array([-0.9, 0.25, 0.35]); win /= np.linalg.norm(win)
    wa = np.arccos(np.clip((d * win).sum(-1), -1, 1))
    col = col + np.array([0.35, 0.45, 0.6])[None, None, :] * (3.0 * (wa < 0.3))[..., None]
    SKY.mkdir(parents=True, exist_ok=True)
    rgbe = np.zeros((h, w, 4), np.uint8)
    m = col.max(-1)
    e = np.floor(np.log2(np.maximum(m, 1e-32))) + 1
    scale = np.where(m > 1e-32, 256.0 / np.power(2.0, e), 0)
    rgbe[..., :3] = np.clip(col * scale[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8)
    with open(SKY / os.environ.get("RP_HDR_NAME", "parlour.hdr"), "wb") as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n")
        f.write(f"-Y {h} +X {w}\n".encode())
        f.write(rgbe.tobytes())
    print("parlour.hdr", (h, w))


if __name__ == "__main__":
    TEX.mkdir(parents=True, exist_ok=True)
    plates(); hud(); room_hdr()
