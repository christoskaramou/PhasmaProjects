"""Generate Arrow Out's arrowhead textures and synthesized sounds (PIL + standard library)."""

import math
import random
import struct
import wave
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent / "Assets"


def arrowheads():
    out = ROOT / "Textures"
    out.mkdir(parents=True, exist_ok=True)
    s = 512  # draw large, downsample for antialiasing
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Pointing up and filling the square (apex top-centre, flat base on the bottom edge), so the game
    # can place the base exactly where the line's stub ends.
    d.polygon([(s * 0.5, s * 0.01), (s * 0.99, s * 0.99), (s * 0.01, s * 0.99)], fill=(255, 255, 255, 255))
    up = img.resize((128, 128), Image.LANCZOS)
    for name, angle in (("up", 0), ("left", 90), ("down", 180), ("right", 270)):
        up.rotate(angle, resample=Image.BICUBIC).save(out / f"head_{name}.png")


def corners(radius=0.28, thickness=0.13):
    """Quarter-ring bend images; the file name says which corner holds the circle centre.
    radius and thickness are in cells and must match CORNER_R and L.th in arrowout.lua."""
    out = ROOT / "Textures"
    s = 1024
    outer = s
    inner = s * (radius - thickness / 2) / (radius + thickness / 2)
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([-outer, -outer, outer, outer], fill=(255, 255, 255, 255))
    d.ellipse([-inner, -inner, inner, inner], fill=(0, 0, 0, 0))
    tl = img.resize((128, 128), Image.LANCZOS)
    tl.save(out / "corner_tl.png")
    tl.transpose(Image.FLIP_LEFT_RIGHT).save(out / "corner_tr.png")
    tl.transpose(Image.FLIP_TOP_BOTTOM).save(out / "corner_bl.png")
    tl.transpose(Image.ROTATE_180).save(out / "corner_br.png")


def write(path, samples, rate=22050):
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in samples))


def sounds():
    out = ROOT / "Audio"
    out.mkdir(parents=True, exist_ok=True)
    rate = 22050
    rnd = random.Random(7)

    def tone(dur, f0, f1, decay, amp=0.35, noise=0.0):
        n = int(rate * dur)
        ph = 0.0
        for i in range(n):
            t = i / rate
            f = f0 + (f1 - f0) * (t / dur)
            ph += 2 * math.pi * f / rate
            env = min(1.0, t * 300) * math.exp(-t * decay)
            yield (math.sin(ph) + 0.25 * math.sin(2 * ph) + noise * (rnd.random() * 2 - 1)) * env * amp

    write(out / "slide.wav", list(tone(0.22, 420, 980, 14, 0.3, 0.25)))
    write(out / "bump.wav", list(tone(0.28, 140, 70, 16, 0.55, 0.15)))
    write(out / "click.wav", list(tone(0.06, 900, 700, 60, 0.2)))

    def chord(notes, step, dur):
        n = int(rate * dur)
        buf = [0.0] * n
        for k, f in enumerate(notes):
            start = int(k * step * rate)
            for i, v in enumerate(tone(dur - k * step, f, f, 5, 0.22)):
                if start + i < n:
                    buf[start + i] += v
        return buf

    write(out / "win.wav", chord([523.25, 659.25, 783.99, 1046.5], 0.09, 1.0))
    write(out / "lose.wav", chord([392.0, 311.1, 261.6, 196.0], 0.14, 1.1))


if __name__ == "__main__":
    arrowheads()
    corners()
    sounds()
    print("assets written to", ROOT)
