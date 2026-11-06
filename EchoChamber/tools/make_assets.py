"""Echo Chamber HUD textures (white icons, tinted in game). Sounds: tools/make_sounds.py.

    python tools/make_assets.py
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent / "Assets"
# ------------------------------------------------------------------ textures
S = 4  # supersample


def canvas(n):
    return Image.new("L", (n * S, n * S), 0)


def finish(img, n, blur=0):
    img = img.resize((n, n), Image.LANCZOS)
    if blur:
        img = img.filter(ImageFilter.GaussianBlur(blur))
    rgba = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    rgba.putalpha(img)
    return rgba


def icons():
    out = ROOT / "Textures"
    out.mkdir(parents=True, exist_ok=True)
    n = 128
    k = n * S / 128.0

    def P(x, y):
        return (x * k, y * k)

    def save(name, img):
        finish(img, n).save(out / f"{name}.png")

    # Reflector: an angled mirror plate in a frame.
    im = canvas(n); d = ImageDraw.Draw(im)
    d.line([P(28, 100), P(100, 28)], fill=255, width=int(14 * k))
    d.line([P(18, 110), P(110, 110)], fill=150, width=int(5 * k))
    save("ic_reflector", im)
    # Fork: a tuning fork.
    im = canvas(n); d = ImageDraw.Draw(im)
    d.line([P(64, 112), P(64, 70)], fill=255, width=int(10 * k))
    d.arc([P(38, 44), P(90, 96)], 0, 180, fill=255, width=int(10 * k))
    d.line([P(43, 70), P(43, 16)], fill=255, width=int(10 * k))
    d.line([P(85, 70), P(85, 16)], fill=255, width=int(10 * k))
    save("ic_fork", im)
    # Resonator: concentric rings.
    im = canvas(n); d = ImageDraw.Draw(im)
    for r in (12, 28, 46):
        d.ellipse([P(64 - r, 64 - r), P(64 + r, 64 + r)], outline=255, width=int(8 * k))
    save("ic_resonator", im)
    # Damper: a padded block with quilting.
    im = canvas(n); d = ImageDraw.Draw(im)
    d.rounded_rectangle([P(18, 30), P(110, 98)], radius=int(22 * k), fill=255)
    for x in (46, 82):
        d.ellipse([P(x - 6, 58), P(x + 6, 70)], fill=90)
    save("ic_damper", im)
    # Bell.
    im = canvas(n); d = ImageDraw.Draw(im)
    pts = [P(64 - (20 + 24 * (t ** 1.8)), 34 + 64 * t) for t in np.linspace(0, 1, 30)]
    pts += [P(64 + (20 + 24 * (t ** 1.8)), 34 + 64 * t) for t in np.linspace(1, 0, 30)]
    d.polygon(pts, fill=255)
    d.ellipse([P(44, 18), P(84, 50)], fill=255)
    d.rounded_rectangle([P(20, 96), P(108, 106)], radius=int(5 * k), fill=255)
    d.ellipse([P(56, 104), P(72, 120)], fill=255)
    d.ellipse([P(57, 6), P(71, 20)], outline=255, width=int(5 * k))
    save("ic_bell", im)
    # Play, reset, hint, menu, star, check.
    im = canvas(n); d = ImageDraw.Draw(im)
    d.polygon([P(36, 20), P(108, 64), P(36, 108)], fill=255)
    save("ic_play", im)
    im = canvas(n); d = ImageDraw.Draw(im)
    d.arc([P(22, 22), P(106, 106)], 40, 330, fill=255, width=int(13 * k))
    d.polygon([P(98, 10), P(112, 52), P(70, 44)], fill=255)
    save("ic_reset", im)
    im = canvas(n); d = ImageDraw.Draw(im)
    d.ellipse([P(30, 12), P(98, 80)], fill=255)
    d.rounded_rectangle([P(46, 76), P(82, 100)], radius=int(5 * k), fill=255)
    d.rounded_rectangle([P(50, 104), P(78, 114)], radius=int(4 * k), fill=255)
    d.ellipse([P(46, 26), P(66, 46)], fill=0)
    save("ic_hint", im)
    im = canvas(n); d = ImageDraw.Draw(im)
    for y in (34, 64, 94):
        d.rounded_rectangle([P(22, y - 7), P(106, y + 7)], radius=int(7 * k), fill=255)
    save("ic_menu", im)
    im = canvas(n); d = ImageDraw.Draw(im)
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 56 if i % 2 == 0 else 23
        pts.append(P(64 + r * math.cos(a), 66 + r * math.sin(a)))
    d.polygon(pts, fill=255)
    save("ic_star", im)
    im = canvas(n); d = ImageDraw.Draw(im)
    d.line([P(22, 66), P(52, 96), P(108, 32)], fill=255, width=int(16 * k), joint="curve")
    save("ic_check", im)
    # Chamber grid, power, back arrow (menu).
    im = canvas(n); d = ImageDraw.Draw(im)
    for gx in range(3):
        for gy in range(3):
            d.rounded_rectangle([P(16 + gx * 34, 16 + gy * 34), P(42 + gx * 34, 42 + gy * 34)], radius=int(6 * k), fill=255)
    save("ic_grid", im)
    im = canvas(n); d = ImageDraw.Draw(im)
    d.arc([P(20, 22), P(108, 110)], 300, 240, fill=255, width=int(13 * k))
    d.rounded_rectangle([P(57, 8), P(71, 66)], radius=int(7 * k), fill=255)
    save("ic_power", im)
    im = canvas(n); d = ImageDraw.Draw(im)
    d.line([P(100, 64), P(34, 64)], fill=255, width=int(14 * k))
    d.line([P(64, 30), P(28, 64), P(64, 98)], fill=255, width=int(14 * k), joint="curve")
    save("ic_back", im)
    # Soft round glow, ring glow, top sheen, vignette.
    yy, xx = np.mgrid[0:256, 0:256] / 255.0 - 0.5
    rr = np.sqrt(xx * xx + yy * yy) * 2
    g = np.clip(np.exp(-rr * rr * 4.5) - 0.011, 0, 1)
    Image.fromarray((g / g.max() * 255).astype(np.uint8)).resize((256, 256))
    img = Image.new("RGBA", (256, 256), (255, 255, 255, 0)); img.putalpha(Image.fromarray((g / g.max() * 255).astype(np.uint8)))
    img.save(out / "glow.png")
    ring = np.exp(-((rr - 0.78) / 0.07) ** 2) * (rr < 1)
    img = Image.new("RGBA", (256, 256), (255, 255, 255, 0)); img.putalpha(Image.fromarray((ring / ring.max() * 255).astype(np.uint8)))
    img.save(out / "ring.png")
    sh = np.tile(np.linspace(1, 0, 64)[:, None] ** 1.5, (1, 256))
    img = Image.new("RGBA", (256, 64), (255, 255, 255, 0)); img.putalpha(Image.fromarray((sh * 255).astype(np.uint8)))
    img.save(out / "sheen.png")
    v = np.clip((rr - 0.55) / 0.9, 0, 1) ** 1.6
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0)); img.putalpha(Image.fromarray((v * 255).astype(np.uint8)))
    img.save(out / "vignette.png")
    # Light strip: soft horizontal band that fades at both ends.
    xs = np.linspace(-1, 1, 512)[None, :]
    ys = np.linspace(-1, 1, 64)[:, None]
    st = np.exp(-(ys / 0.28) ** 2) * np.clip(1 - np.abs(xs) ** 3, 0, 1)
    img = Image.new("RGBA", (512, 64), (255, 255, 255, 0)); img.putalpha(Image.fromarray((st * 255).astype(np.uint8)))
    img.save(out / "strip.png")


if __name__ == "__main__":
    icons()
    print("assets written to", ROOT)
