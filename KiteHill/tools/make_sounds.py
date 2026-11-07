"""Kite Hill sounds: a breezy hillside, cloth kites and wooden gates. Synthesized with numpy / scipy, stereo 32 kHz.

    python tools/make_sounds.py

- chime1..5: flying through a ring (a wooden-bar glockenspiel, rising C D E G A as the rings go by)
- bull: through the middle of a ring (a sparkle on top); rival: a rival takes a ring (a soft distant tock)
- crash: the kite flops onto the grass; relaunch: it shakes itself out and climbs
- gust: a gust blowing through; warn: the grass rustling before it; boost: an updraft (whoosh and cloth snap)
- count / go: the start (wooden ticks, a bright two-note whistle)
- finish: over the line; win: heat won (rising arpeggio); over: the run ends (falling chimes); coin; click
- breeze: the looping wind and distant birds under everything (played as music)
"""
import wave
from pathlib import Path

import numpy as np
from scipy import signal

OUT = Path(__file__).resolve().parent.parent / "Assets" / "Audio"
SR = 32000
RNG = np.random.default_rng(23)


def t_axis(d): return np.arange(int(SR * d)) / SR
def band(x, lo, hi): return signal.sosfilt(signal.butter(2, [lo, min(hi, SR / 2 - 200)], "bandpass", fs=SR, output="sos"), x)
def lowpass(x, f): return signal.sosfilt(signal.butter(2, f, "lowpass", fs=SR, output="sos"), x)
def noise(d): return RNG.standard_normal(int(SR * d))


def air(x, wet=0.12):
    """Open air: a few faint early reflections off the hills, a short diffuse tail, slight stereo spread."""
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    n = int(SR * 0.6)
    t = np.arange(n) / SR
    out = np.zeros((len(x) + n, 2))
    out[: len(x)] += x * (1 - wet)
    for ch in range(2):
        ir = band(RNG.standard_normal(n), 200, 6000) * np.exp(-t * 9) * 0.25
        for d in (0.045 + 0.01 * ch, 0.11 + 0.02 * ch):
            ir[int(d * SR)] += 0.4
        y = signal.fftconvolve(x[:, ch], ir)[: len(out)]
        y *= (np.sqrt((x[:, ch] ** 2).mean()) + 1e-12) / (np.sqrt((y ** 2).mean()) + 1e-12)
        out[: len(y), ch] += y * wet
    return out


def write(name, x, peak, trim=True):
    x = np.asarray(x, float)
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    if trim:
        env = np.abs(x).max(1)
        idx = np.nonzero(env > env.max() * 10 ** (-54 / 20))[0]
        x = x[: idx[-1] + int(0.03 * SR)]
        f = min(len(x), int(0.02 * SR))
        x[-f:] *= np.linspace(1, 0, f)[:, None]
    x = x / np.abs(x).max() * peak
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    print(f"{name:9s} {len(x) / SR:.2f} s")


def modal(f, ratios, amps, decays, dur):
    t = t_axis(dur)
    y = sum(a * np.sin(2 * np.pi * f * r * t + r) * np.exp(-t * d) for r, a, d in zip(ratios, amps, decays))
    return y * np.clip(t / 0.0006, 0, 1)


def mix(dur, *parts):
    y = np.zeros(int(SR * dur))
    for start, x in parts:
        i = int(start * SR)
        n = min(len(x), len(y) - i)
        if n > 0:
            y[i:i + n] += x[:n]
    return y


def bar(f, dur=0.9):
    """A wooden-bar glockenspiel note (mellow: few, quickly fading overtones)."""
    t = t_axis(dur)
    tone = modal(f, [1, 3.93, 9.0], [1, 0.25, 0.06], [4.5, 14, 30], dur)
    knock = band(noise(dur), 1500, 7000) * np.exp(-t * 300) * 0.25
    return tone + knock


def flap(dur, rate=28, lo=300, hi=3500):
    """Cloth snapping in the wind: bursts of band noise at a fluttering rate."""
    t = t_axis(dur)
    am = np.clip(np.sin(2 * np.pi * rate * t + 2 * np.sin(2 * np.pi * 3 * t)), 0, 1) ** 3
    return band(noise(dur), lo, hi) * am


def wind(dur, lo=150, hi=1400, swell=None):
    t = t_axis(dur)
    x = band(noise(dur), lo, hi)
    x += 0.5 * band(noise(dur), hi, hi * 2.5) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.7 * t))
    env = swell if swell is not None else np.ones_like(t)
    return x * env


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.wav"):
        old.unlink()
    for i, f in enumerate((523.25, 587.33, 659.25, 783.99, 880.0), 1):
        write(f"chime{i}", air(mix(0.9, (0, bar(f)), (0, 0.35 * bar(f * 2, 0.6)))), 0.42)
    sparkle = mix(1.2, *[(k * 0.06, bar(f, 0.8) * (1 - 0.15 * k)) for k, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0))])
    write("bull", air(sparkle, 0.2), 0.4)
    t = t_axis(0.3)
    write("rival", air(lowpass(modal(420, [1, 2.7], [1, 0.3], [30, 60], 0.3), 1800) + lowpass(noise(0.3), 800) * np.exp(-t * 80) * 0.3), 0.16)
    # Crash: a cloth flop, a soft thump on the grass, a rustle.
    t = t_axis(0.8)
    thump = np.sin(2 * np.pi * 75 * t) * np.exp(-t * 18) + lowpass(noise(0.8), 500) * np.exp(-t * 14) * 0.6
    write("crash", air(mix(0.8, (0, flap(0.25, 34) * np.linspace(1, 0.3, int(0.25 * SR)) * 0.7), (0.12, thump),
                           (0.15, band(noise(0.5), 2000, 8000) * np.exp(-t_axis(0.5) * 10) * 0.3))), 0.5)
    t = t_axis(0.6)
    write("relaunch", air(flap(0.6, 22) * np.sin(np.pi * t / 0.6) ** 1.5 * 0.8 + wind(0.6, 400, 2500) * np.sin(np.pi * t / 0.6) * 0.3), 0.3)
    # Gust: a rising and falling roar of wind, a little cloth flutter in it.
    t = t_axis(2.4)
    sw = np.sin(np.pi * np.clip(t / 2.4, 0, 1)) ** 1.4
    g = wind(2.4, 120, 1100, sw) + 0.25 * flap(2.4, 18, 600, 3000) * sw
    write("gust", air(g, 0.15), 0.45)
    t = t_axis(0.8)
    rustle = band(noise(0.8), 2500, 9000) * np.clip(t / 0.6, 0, 1) ** 2 * np.exp(-np.clip(t - 0.6, 0, None) * 20)
    whistle = np.sin(2 * np.pi * np.cumsum(900 + 500 * t / 0.8) / SR) * np.clip(t / 0.6, 0, 1) * np.exp(-np.clip(t - 0.6, 0, None) * 25) * 0.15
    write("warn", air(rustle * 0.6 + whistle), 0.28)
    t = t_axis(0.9)
    whoosh = band(noise(0.9), 300, 4000) * np.exp(-((t - 0.25) / 0.18) ** 2)
    write("boost", air(whoosh + mix(0.9, (0.02, flap(0.12, 40) * 1.2)) + 0.3 * np.sin(2 * np.pi * np.cumsum(300 + 600 * t) / SR) * np.exp(-t * 5)), 0.45)
    write("count", air(modal(1250, [1, 2.6], [1, 0.3], [40, 70], 0.3) + band(noise(0.3), 1500, 6000) * np.exp(-t_axis(0.3) * 200) * 0.3), 0.3)
    t = t_axis(1.0)
    tw = lambda f, d: np.sin(2 * np.pi * f * t_axis(d) + 0.02 * np.sin(2 * np.pi * 7 * t_axis(d))) * np.clip(t_axis(d) / 0.02, 0, 1) * np.exp(-t_axis(d) * 3)
    write("go", air(mix(1.0, (0, tw(1568, 0.25) * 0.8), (0.18, tw(2093, 0.8))) + band(noise(1.0), 2000, 6000) * np.exp(-t * 8) * 0.04), 0.35)
    finish = mix(1.6, *[(k * 0.09, bar(f, 1.2) * (1 - 0.1 * k)) for k, f in enumerate((523.25, 659.25, 783.99, 1046.5))])
    write("finish", air(finish, 0.2), 0.45)
    win = mix(2.4, *[(k * 0.12, bar(f, 1.6) + 0.3 * bar(f / 2, 1.6)) for k, f in enumerate((523.25, 659.25, 783.99, 1046.5, 1318.5))])
    write("win", air(win, 0.22), 0.5)
    over = mix(2.4, *[(k * 0.3, bar(f, 1.6)) for k, f in enumerate((783.99, 659.25, 523.25, 392.0))])
    write("over", air(over, 0.22), 0.45)
    write("coin", air(mix(0.5, (0, bar(1975.5, 0.4)), (0.07, bar(2637.0, 0.4)))), 0.38)
    write("click", modal(1500, [1, 2.4], [1, 0.3], [160, 240], 0.1), 0.24)
    # Breeze: 16 s of soft wind with slow swells and a few distant birds; the ends cross-fade so it loops.
    dur = 16.0
    t = t_axis(dur)
    sw = 0.6 + 0.25 * np.sin(2 * np.pi * t / 8.0) + 0.15 * np.sin(2 * np.pi * t / 3.2 + 1)
    bz = wind(dur, 100, 900, sw) * 0.5
    birds = np.zeros_like(t)
    for s in (2.1, 2.35, 7.4, 7.6, 7.82, 12.9, 13.1):
        d = 0.12
        tt = t_axis(d)
        f = 3200 + 900 * np.sin(np.pi * tt / d) + RNG.uniform(-300, 300)
        chirp = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / d) ** 2
        i = int(s * SR)
        birds[i:i + len(chirp)] += chirp * 0.06
    loop = bz + birds
    n = int(1.5 * SR)
    fade = np.linspace(0, 1, n)
    loop[:n] = loop[:n] * fade + loop[-n:] * (1 - fade)
    loop = loop[:-n]
    write("breeze", np.stack([loop, np.roll(loop, 160)], 1), 0.22, trim=False)
    print("sounds written to", OUT)


if __name__ == "__main__":
    main()
