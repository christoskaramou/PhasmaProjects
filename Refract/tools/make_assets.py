"""Generate Refract's synthesized sounds (standard library). Textures come from make_art.py."""

import math
import random
import struct
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent / "Assets"


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

    def tone(dur, f0, f1, decay, amp=0.35, noise=0.0, harm=0.25):
        n = int(rate * dur)
        ph = 0.0
        for i in range(n):
            t = i / rate
            f = f0 + (f1 - f0) * (t / dur)
            ph += 2 * math.pi * f / rate
            env = min(1.0, t * 300) * math.exp(-t * decay)
            yield (math.sin(ph) + harm * math.sin(2 * ph) + noise * (rnd.random() * 2 - 1)) * env * amp

    def chord(notes, step, dur, decay=5, amp=0.2):
        n = int(rate * dur)
        buf = [0.0] * n
        for k, f in enumerate(notes):
            start = int(k * step * rate)
            for i, v in enumerate(tone(dur - k * step, f, f, decay, amp)):
                if start + i < n:
                    buf[start + i] += v
        return buf

    write(out / "place.wav", list(tone(0.12, 520, 780, 30, 0.3)))
    write(out / "rotate.wav", list(tone(0.07, 1100, 900, 50, 0.18)))
    write(out / "sell.wav", list(tone(0.16, 700, 350, 22, 0.28)))
    write(out / "deny.wav", list(tone(0.14, 180, 150, 18, 0.3, 0.1)))
    write(out / "click.wav", list(tone(0.06, 900, 700, 60, 0.2)))
    write(out / "pop.wav", list(tone(0.1, 1400, 500, 35, 0.16, 0.35)))
    write(out / "leak.wav", list(tone(0.45, 160, 55, 7, 0.55, 0.3)))
    write(out / "wave.wav", chord([392.0, 523.25, 659.25], 0.07, 0.55, 7, 0.2))
    write(out / "surge.wav", list(tone(0.9, 200, 1600, 3, 0.35, 0.15, 0.6)))
    write(out / "boss.wav", chord([110.0, 116.5, 164.8], 0.0, 1.4, 2.5, 0.25))
    write(out / "win.wav", chord([523.25, 659.25, 783.99, 1046.5], 0.09, 1.0))
    write(out / "lose.wav", chord([392.0, 311.1, 261.6, 196.0], 0.14, 1.1))


if __name__ == "__main__":
    sounds()
    print("assets written to", ROOT)
