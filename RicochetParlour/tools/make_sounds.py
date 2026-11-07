"""Ricochet Parlour sounds: balls on brass pins, rubber bumpers, felt and walnut, in a small parlour room.

    python tools/make_sounds.py

Synthesized with numpy / scipy, stereo 32 kHz. Modal models of the real objects:
- kick: a soft puff of air (filtered noise) with a felt-tipped thump; the close kick adds a bright tick
- pin: a steel ball on a brass post (short high inharmonic ring); bumper: a rubber "boing" (pitch drop)
- clack: two balls touching (very short, bright, two close modes)
- glass: a glass ball breaking; drop: a ball rolling into the slot and knocking down the wooden pocket
- spawn: a ball released from the top rail; over: a slow descending chime; click: a UI tick
"""
import wave
from pathlib import Path

import numpy as np
from scipy import signal

OUT = Path(__file__).resolve().parent.parent / "Assets" / "Audio"
SR = 32000
RNG = np.random.default_rng(31)


def t_axis(d): return np.arange(int(SR * d)) / SR
def band(x, lo, hi): return signal.sosfilt(signal.butter(2, [lo, min(hi, SR / 2 - 200)], "bandpass", fs=SR, output="sos"), x)
def lowpass(x, f): return signal.sosfilt(signal.butter(2, f, "lowpass", fs=SR, output="sos"), x)
def noise(d): return RNG.standard_normal(int(SR * d))


def make_ir(rt60=0.7, dur=1.1, seed=5):
    """A small wood-panelled room: short, warm tail."""
    rng = np.random.default_rng(seed)
    n = int(SR * dur); t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for ch in range(2):
        tail = np.zeros(n)
        for lo, hi, k in ((80, 700, 1.0), (700, 3500, 0.7), (3500, 11000, 0.35)):
            tail += band(rng.standard_normal(n), lo, hi) * np.exp(-6.91 * t / (rt60 * k))
        ir[:, ch] = tail * np.clip((t - 0.006) / 0.02, 0, 1) * 0.3
        for _ in range(10):
            d = 0.005 + rng.uniform(0.002, 0.03); ir[int(d * SR), ch] += rng.uniform(0.3, 0.7) * np.exp(-d * 20)
    return ir / np.abs(ir).max()


IR = None


def room(x, wet=0.25):
    if x.ndim == 1: x = np.stack([x, x], 1)
    y = np.stack([signal.fftconvolve(x[:, c], IR[:, c]) for c in range(2)], 1)
    y *= (np.sqrt((x ** 2).mean()) + 1e-12) / (np.sqrt((y ** 2).mean()) + 1e-12)
    out = np.zeros_like(y); out[: len(x)] = x * (1 - wet)
    return out + y * wet * 1.5


def write(name, x, peak):
    x = np.asarray(x, float)
    if x.ndim == 1: x = np.stack([x, x], 1)
    env = np.abs(x).max(1); m = env.max()
    idx = np.nonzero(env > m * 10 ** (-54 / 20))[0]
    x = x[: idx[-1] + int(0.03 * SR)]
    f = min(len(x), int(0.02 * SR)); x[-f:] *= np.linspace(1, 0, f)[:, None]
    x = x / m * peak
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def modal(f, ratios, amps, decays, dur):
    t = t_axis(dur)
    y = sum(a * np.sin(2 * np.pi * f * r * t + r) * np.exp(-t * d) for r, a, d in zip(ratios, amps, decays))
    return y * np.clip(t / 0.0005, 0, 1)


def kick(close):
    t = t_axis(0.5)
    puff = band(noise(0.5), 300, 3500) * np.exp(-t * 28) * np.clip(t / 0.004, 0, 1)
    thump = np.sin(2 * np.pi * np.cumsum(180 * (1 + 0.6 * np.exp(-t * 60))) / SR) * np.exp(-t * 30) * 0.6
    ball = modal(2400, [1, 2.76, 5.4], [0.35, 0.2, 0.1], [40, 70, 110], 0.5)          # the ball itself rings a touch
    y = puff * 0.9 + thump + ball
    if close:
        y += band(noise(0.5), 4000, 12000) * np.exp(-t * 300) * 0.8 + modal(3200, [1, 2.3], [0.4, 0.2], [30, 60], 0.5)
    return y


def main():
    global IR
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.wav"): old.unlink()
    IR = make_ir()
    write("kick", room(kick(False), 0.2), 0.55)
    write("kick_close", room(kick(True), 0.22), 0.7)
    t = t_axis(0.25)
    write("whiff", room(band(noise(0.25), 400, 2500) * np.sin(np.pi * np.clip(t / 0.25, 0, 1)) ** 2 * 0.6, 0.15), 0.3)
    # Steel ball on a brass post.
    write("pin", room(modal(3100, [1, 2.52, 4.1, 6.3], [1, 0.5, 0.3, 0.15], [55, 80, 120, 170], 0.4)
                      + band(noise(0.4), 3000, 12000) * np.exp(-t_axis(0.4) * 600) * 0.4, 0.2), 0.42)
    # Rubber bumper: a short "boing" with a falling pitch and a soft knock.
    t = t_axis(0.35)
    boing = np.sin(2 * np.pi * np.cumsum(260 * (1 + 0.5 * np.exp(-t * 25))) / SR) * np.exp(-t * 14)
    write("bumper", room(boing + lowpass(noise(0.35), 900) * np.exp(-t * 80) * 0.5, 0.2), 0.5)
    # Two balls touching.
    write("clack", room(modal(4200, [1, 1.07, 2.9], [1, 0.8, 0.3], [90, 95, 160], 0.2), 0.15), 0.4)
    # Glass ball breaking.
    t = t_axis(1.0)
    crack = band(noise(1.0), 2000, 12000) * np.exp(-t * 110)
    shards = sum(RNG.uniform(0.1, 0.35) * np.sin(2 * np.pi * RNG.uniform(3500, 9500) * np.clip(t - s, 0, None))
                 * np.exp(-np.clip(t - s, 0, None) * RNG.uniform(30, 80)) * (t >= s) for s in RNG.uniform(0, 0.06, 30))
    tinkle = np.zeros_like(t)
    for _ in range(18):
        s = RNG.uniform(0.15, 0.8); i = int(s * SR); n = int(0.04 * SR); tt = np.arange(n) / SR
        tinkle[i:i + n] += RNG.uniform(0.05, 0.15) * np.sin(2 * np.pi * RNG.uniform(4000, 9000) * tt) * np.exp(-tt * 140)
    write("glass", room(crack + shards * 0.7 + tinkle, 0.25), 0.62)
    # A ball rolls into the slot and knocks down through the wooden pocket.
    t = t_axis(0.9)
    roll = lowpass(noise(0.9), 500) * np.clip(1 - t / 0.25, 0, 1) * 0.5
    y = roll.copy()
    for k, s in enumerate((0.22, 0.34, 0.42)):
        i = int(s * SR)
        hit = modal(260 - 30 * k, [1, 2.3, 4.1], [1, 0.4, 0.2], [35, 60, 90], 0.45) * (0.9 - 0.25 * k)
        y[i:i + len(hit)] += hit[: len(y) - i]
    write("drop", room(y, 0.3), 0.7)
    # A new ball released from the top rail: a light tick and a short roll.
    t = t_axis(0.5)
    write("spawn", room(modal(2800, [1, 2.7], [0.6, 0.3], [70, 110], 0.5) + lowpass(noise(0.5), 1200) * np.exp(-t * 10) * 0.25, 0.25), 0.35)
    # Bonus cup: a bright brass ding with a quick upward second note.
    cup = np.zeros(int(SR * 1.4))
    for k, f in enumerate((1318.5, 1975.5)):
        c = modal(f, [1, 2.0, 2.76], [1, 0.35, 0.2], [3.5, 5, 7], 1.2) * (1 - 0.3 * k)
        i = int(k * 0.08 * SR); cup[i:i + len(c)] += c[: len(cup) - i]
    write("cup", room(cup, 0.3), 0.5)
    # Game over: three descending brass chimes.
    y = np.zeros(int(SR * 2.6))
    for k, f in enumerate((784.0, 659.25, 523.25)):
        c = modal(f, [1, 2.0, 2.76, 5.4], [1, 0.4, 0.25, 0.1], [2.2, 3, 4.5, 8], 2.0)
        i = int(k * 0.32 * SR); y[i:i + len(c)] += c[: len(y) - i]
    write("over", room(y, 0.3), 0.6)
    write("click", modal(1600, [1, 2.4], [1, 0.3], [160, 240], 0.1), 0.28)
    print("sounds written to", OUT)


if __name__ == "__main__":
    main()
