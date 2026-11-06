"""Resonance Break sounds: tuning forks, breaking glass, a shield crack, in a stone-hall reverb.

    python tools/make_sounds.py

Synthesized with numpy / scipy, stereo 32 kHz. The forks are a real tuning-fork model (a long pure
fundamental plus a short "clang" mode at 6.27x); each lane has its own pitch (A major: A4 C#5 E5 A5).
Breaking glass layers a sharp crack transient, dozens of short high plate modes (the shards) and a
tinkling scatter of small fragments landing.
"""
import wave
from pathlib import Path

import numpy as np
from scipy import signal

OUT = Path(__file__).resolve().parent.parent / "Assets" / "Audio"
SR = 32000
RNG = np.random.default_rng(77)


def t_axis(d): return np.arange(int(SR * d)) / SR
def band(x, lo, hi): return signal.sosfilt(signal.butter(2, [lo, min(hi, SR / 2 - 200)], "bandpass", fs=SR, output="sos"), x)
def lowpass(x, f): return signal.sosfilt(signal.butter(2, f, "lowpass", fs=SR, output="sos"), x)
def noise(d): return RNG.standard_normal(int(SR * d))


def make_ir(rt60=1.8, dur=2.4, seed=3):
    rng = np.random.default_rng(seed)
    n = int(SR * dur); t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for ch in range(2):
        tail = np.zeros(n)
        for lo, hi, k in ((60, 600, 1.0), (600, 3500, 0.7), (3500, 12000, 0.35)):
            tail += band(rng.standard_normal(n), lo, hi) * np.exp(-6.91 * t / (rt60 * k))
        ir[:, ch] = tail * np.clip((t - 0.012) / 0.03, 0, 1) * 0.35
        for _ in range(12):
            d = 0.012 + rng.uniform(0.004, 0.07); ir[int(d * SR), ch] += rng.uniform(0.3, 0.7) * np.exp(-d * 10)
    return ir / np.abs(ir).max()


IR = None


def room(x, wet=0.3):
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
    x = x[: idx[-1] + int(0.04 * SR)]
    f = min(len(x), int(0.03 * SR)); x[-f:] *= np.linspace(1, 0, f)[:, None]
    x = x / m * peak
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def fork(f, dur=1.6):
    t = t_axis(dur)
    y = np.sin(2 * np.pi * f * t) * np.exp(-t * 2.6)
    y += 0.55 * np.sin(2 * np.pi * f * 6.267 * t + 1) * np.exp(-t * 28)
    y += 0.18 * np.sin(2 * np.pi * f * 17.55 * t + 2) * np.exp(-t * 70)
    strike = band(noise(dur), 2000, 9000) * np.exp(-t * 500) * 0.4          # the mallet's tick
    return (y + strike) * np.clip(t / 0.0008, 0, 1)


def glass(seed, dur=1.4, bright=1.0):
    rng = np.random.default_rng(seed)
    t = t_axis(dur)
    crack = band(rng.standard_normal(len(t)), 1500, 12000) * np.exp(-t * 90)
    snap = lowpass(rng.standard_normal(len(t)), 900) * np.exp(-t * 60) * 0.6
    shards = np.zeros_like(t)
    for _ in range(int(40 * bright)):
        f0 = rng.uniform(2500, 9000)
        start = rng.uniform(0, 0.08)
        tt = np.clip(t - start, 0, None)
        shards += rng.uniform(0.1, 0.4) * np.sin(2 * np.pi * f0 * tt) * np.exp(-tt * rng.uniform(25, 70)) * (t >= start)
    # Fragments landing: a scatter of tiny ticks over the next second.
    tinkle = np.zeros_like(t)
    for _ in range(int(26 * bright)):
        s = rng.uniform(0.12, 1.0)
        i = int(s * SR)
        n = int(0.05 * SR)
        if i + n < len(t):
            tt = np.arange(n) / SR
            tinkle[i:i + n] += rng.uniform(0.05, 0.2) * np.sin(2 * np.pi * rng.uniform(4000, 10000) * tt) * np.exp(-tt * 120) * (1 - s * 0.6)
    return crack + snap + shards * 0.7 + tinkle


def main():
    global IR
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.wav"): old.unlink()
    IR = make_ir()
    for i, f in enumerate([440.0, 554.37, 659.25, 880.0], 1):
        write(f"fork{i}", room(fork(f), 0.32), 0.7)
    for i, b in enumerate([1.3, 1.0, 0.75], 1):          # perfect / great / good: fuller to thinner breaks
        write(f"shatter{i}", room(glass(10 + i, 1.4, b), 0.28), 0.62)
    t = t_axis(0.9)
    thud = np.sin(2 * np.pi * np.cumsum(70 * (1 + 1.5 * np.exp(-t * 30))) / SR) * np.exp(-t * 9)
    crack = band(noise(0.9), 300, 4000) * np.exp(-t * 30) * (0.6 + 0.4 * (RNG.random(len(t)) > 0.7))
    write("crack", room(thud + crack * 0.8 + glass(31, 0.9, 0.5) * 0.3, 0.3), 0.75)
    dull = np.sin(2 * np.pi * 160 * t_axis(0.3)) * np.exp(-t_axis(0.3) * 30) + lowpass(noise(0.3), 800) * np.exp(-t_axis(0.3) * 50) * 0.5
    write("dull", room(dull, 0.15), 0.4)
    wv = sum(fork(f, 2.0) * a for f, a in ((440, 0.6), (554.37, 0.5), (659.25, 0.5)))
    write("wave", room(wv, 0.4), 0.5)
    write("repair", room(fork(1318.5, 1.2) * 0.6, 0.4), 0.4)
    t = t_axis(3.5)
    gong = sum(np.sin(2 * np.pi * 98 * r * t + r) * np.exp(-t * (0.8 + r * 0.3)) / r for r in (1, 2.3, 3.1, 4.7, 5.9))
    write("over", room(gong + glass(41, 3.5, 1.5) * 0.4, 0.4), 0.7)
    click = np.sin(2 * np.pi * 1500 * t_axis(0.08)) * np.exp(-t_axis(0.08) * 120)
    write("click", click, 0.3)
    print("sounds written to", OUT)


if __name__ == "__main__":
    main()
