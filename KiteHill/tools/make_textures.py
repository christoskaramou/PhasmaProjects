"""Kite Hill textures and environment: the soft shadows the sun throws on the pictured grass (a round blob for
the flyer, a diamond for a kite, a long soft bar for a gate's pole and a soft ring for its hoop) and a daytime
sky HDR for image-based lighting (soft blue above, a warm hazy horizon, green hills below and the sun up to the
left behind the hills, as in the backdrop).

    python tools/make_textures.py
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kh_common as K  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent / "Assets"
TEX = ROOT / "Textures"
SKY = ROOT / "Skybox"


def alpha_png(a, path):
    a = np.clip(a / max(1e-9, a.max()), 0, 1)
    img = Image.new("RGBA", (a.shape[1], a.shape[0]), (255, 255, 255, 0))
    img.putalpha(Image.fromarray((a * 255 + 0.5).astype(np.uint8)))
    img.save(path)
    print(path.name, a.shape)


def shadows():
    n = 256
    yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / n - 0.5
    rr = np.sqrt(xx * xx + yy * yy) * 2
    alpha_png(np.clip(np.exp(-(rr / 0.55) ** 2.2) - 0.01, 0, 1), TEX / "shadow.png")
    # A kite: a soft diamond.
    d = np.abs(xx) / 0.42 + np.abs(yy) / 0.48
    alpha_png(np.clip((1.0 - d) / 0.25, 0, 1) ** 1.3, TEX / "shadow_kite.png")
    # A pole: a soft bar along the texture's x.
    def soft(t, core, feather):
        return np.clip(1 - (np.abs(t) - core) / feather, 0, 1) ** 1.6
    alpha_png(soft(xx * 2, 0.8, 0.18) * soft(yy * 2, 0.2, 0.6), TEX / "shadow_pole.png")
    # A hoop: a soft ring.
    alpha_png(np.exp(-((rr - 0.78) / 0.09) ** 2) * (rr < 1), TEX / "shadow_ring.png")


def sky_hdr():
    """Equirect 512x256 Radiance HDR (the engine's convention: centre column looks along +Z, +X at u = 0.75)."""
    w, h = 512, 256
    v = (np.arange(h)[:, None] + 0.5) / h
    u = (np.arange(w)[None, :] + 0.5) / w
    el = (0.5 - v) * np.pi
    az = (u - 0.5) * 2 * np.pi
    d = np.stack([np.cos(el) * np.sin(az) * np.ones_like(u), np.sin(el) * np.ones_like(u), np.cos(el) * np.cos(az) * np.ones_like(u)], -1)
    up = d[..., 1]
    zen = np.array([0.30, 0.48, 0.80])
    hor = np.array([0.82, 0.84, 0.82])
    grass = np.array([0.16, 0.24, 0.07])
    t = np.clip(up, 0, 1)[..., None] ** 0.5
    col = np.where(up[..., None] >= 0, hor + (zen - hor) * t, grass + (hor - grass) * np.exp(up[..., None] * 18))
    s = np.array(K.sun())
    ang = np.arccos(np.clip((d * s).sum(-1), -1, 1))
    col = col + np.array([1.0, 0.9, 0.75])[None, None, :] * (60 * (ang < 0.05) + 1.2 * np.exp(-(ang / 0.35) ** 2))[..., None]
    SKY.mkdir(parents=True, exist_ok=True)
    rgbe = np.zeros((h, w, 4), np.uint8)
    m = col.max(-1)
    e = np.floor(np.log2(np.maximum(m, 1e-32))) + 1
    scale = np.where(m > 1e-32, 256.0 / np.power(2.0, e), 0)
    rgbe[..., :3] = np.clip(col * scale[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8)
    with open(SKY / "sky.hdr", "wb") as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n")
        f.write(f"-Y {h} +X {w}\n".encode())
        f.write(rgbe.tobytes())
    print("sky.hdr", (h, w))


if __name__ == "__main__":
    TEX.mkdir(parents=True, exist_ok=True)
    shadows()
    sky_hdr()
