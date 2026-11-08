"""Topple textures and environment: the toys' soft shadows on the felt (a round blob and a soft box), the
placement ring and direction arrow, and a dim lamp-lit room HDR for image-based lighting (painted wood, brass
and glass reflect a dark room with the warm desk lamp up to the left and a cool window at the back right, as
in the concept render).

    python tools/make_textures.py
"""
import os
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "Assets"
TEX = ROOT / "Textures"
SKY = ROOT / "Skybox"
LAMP_POS, TABLE_MID = np.array([-9.0, 11.5, 3.0]), np.array([-1.0, 0.5, -3.0])        # engine axes


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
    blob = np.clip(np.exp(-(rr / 0.55) ** 2.2) - 0.01, 0, 1)
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0)); img.putalpha(Image.fromarray((blob / blob.max() * 255).astype(np.uint8)))
    img.save(TEX / "shadow.png")
    # Soft box: a flat dark core with wide feathered edges (the lamp is broad), for dominoes and houses.
    def soft(t, core, feather):
        return np.clip(1 - (np.abs(t) - core) / feather, 0, 1) ** 1.6
    box = soft(xx * 2, 0.55, 0.42) * soft(yy * 2, 0.55, 0.42)
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0)); img.putalpha(Image.fromarray((box / box.max() * 255).astype(np.uint8)))
    img.save(TEX / "shadow_box.png")
    print("shadow.png, shadow_box.png")


def markers():
    n = 256
    yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / n - 0.5
    r = np.sqrt(xx * xx + yy * yy) * 2
    alpha_png(np.exp(-((r - 0.86) / 0.05) ** 2) * (r < 1), TEX / "ring.png")
    # Direction arrow (points right): a rounded chevron.
    w, h = 256, 128
    y, x = (np.mgrid[0:h, 0:w] + 0.5)
    x, y = x / w, (y / h - 0.5) * 2
    shaft = (np.abs(y) < 0.16) & (x > 0.06) & (x < 0.62)
    head = (x >= 0.55) & (x <= 0.95) & (np.abs(y) <= (0.95 - x) / 0.4 * 0.9)
    a = (shaft | head).astype(float)
    img = Image.fromarray((a * 255).astype(np.uint8)).resize((w // 2, h // 2), Image.LANCZOS)
    rgba = Image.new("RGBA", img.size, (255, 255, 255, 0)); rgba.putalpha(img)
    rgba.save(TEX / "arrow.png")
    print("arrow.png")


def room_hdr():
    """Equirect 512x256 Radiance HDR (the engine's convention: centre column looks along +Z, +X at u = 0.75)."""
    w, h = 512, 256
    v = (np.arange(h)[:, None] + 0.5) / h
    u = (np.arange(w)[None, :] + 0.5) / w
    el = (0.5 - v) * np.pi
    az = (u - 0.5) * 2 * np.pi
    d = np.stack([np.cos(el) * np.sin(az) * np.ones_like(u), np.sin(el) * np.ones_like(u), np.cos(el) * np.cos(az) * np.ones_like(u)], -1)
    wall = np.array([0.16, 0.09, 0.06])
    felt = np.array([0.05, 0.11, 0.07])
    ceil = np.array([0.22, 0.17, 0.12])
    up = np.clip(d[..., 1], -1, 1)
    upp, dn = np.clip(up, 0, 1)[..., None], np.clip(-up, 0, 1)[..., None]
    col = np.where(up[..., None] > 0, wall + (ceil - wall) * upp ** 0.7, wall + (felt - wall) * dn ** 0.5)
    lamp = LAMP_POS - TABLE_MID; lamp /= np.linalg.norm(lamp)
    ang = np.arccos(np.clip((d * lamp).sum(-1), -1, 1))
    col = col + np.array([1.0, 0.76, 0.5])[None, None, :] * (40 * (ang < 0.12) + 2.5 * np.exp(-(ang / 0.55) ** 2))[..., None]
    # The felt under the lamp glows back up a little.
    pool = np.array([0.0, -1.0, 0.2]); pool /= np.linalg.norm(pool)
    pa = np.arccos(np.clip((d * pool).sum(-1), -1, 1))
    col = col + np.array([0.10, 0.22, 0.14])[None, None, :] * np.exp(-(pa / 0.9) ** 2)[..., None]
    win = np.array([0.7, 0.45, -0.55]); win /= np.linalg.norm(win)
    wa = np.arccos(np.clip((d * win).sum(-1), -1, 1))
    col = col + np.array([0.45, 0.55, 0.75])[None, None, :] * (2.2 * (wa < 0.28))[..., None]
    SKY.mkdir(parents=True, exist_ok=True)
    rgbe = np.zeros((h, w, 4), np.uint8)
    m = col.max(-1)
    e = np.floor(np.log2(np.maximum(m, 1e-32))) + 1
    scale = np.where(m > 1e-32, 256.0 / np.power(2.0, e), 0)
    rgbe[..., :3] = np.clip(col * scale[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8)
    with open(SKY / "room.hdr", "wb") as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n")
        f.write(f"-Y {h} +X {w}\n".encode())
        f.write(rgbe.tobytes())
    print("room.hdr", (h, w))


if __name__ == "__main__":
    TEX.mkdir(parents=True, exist_ok=True)
    shadows(); markers(); room_hdr()
