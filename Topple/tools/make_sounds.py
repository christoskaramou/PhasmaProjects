"""Topple sounds: painted wooden toys on a felt games table in a small wood-panelled room.

    python tools/make_sounds.py

Synthesized with numpy / scipy, stereo 32 kHz (modal models, as Ricochet Parlour's):
- (clack*.wav, the domino hits, are real recordings: see tools/make_clacks.py)
- place / remove / tip: a domino set down on felt, picked up, and the flick that starts the chain
- bell: the brass bell on its gallows; boing: the spring launcher; launch / pop: a toy rocket going up and landing
- roll: a glass marble down its wooden chute and across the felt; thunk: a domino against a wooden block
- house: a toy house tipping over; wobble: a domino nudged edge-on that rocks and stays up
- cheer: table cleared (a rising brass arpeggio); over: the run ends (falling chimes); coin; click
"""
import sys
import wave
from pathlib import Path

import numpy as np
from scipy import signal

OUT = Path(__file__).resolve().parent.parent / "Assets" / "Audio"
SR = 32000
RNG = np.random.default_rng(17)


def t_axis(d): return np.arange(int(SR * d)) / SR
def band(x, lo, hi): return signal.sosfilt(signal.butter(2, [lo, min(hi, SR / 2 - 200)], "bandpass", fs=SR, output="sos"), x)
def lowpass(x, f): return signal.sosfilt(signal.butter(2, f, "lowpass", fs=SR, output="sos"), x)
def noise(d): return RNG.standard_normal(int(SR * d))


def make_ir(rt60=0.6, dur=1.0, seed=5):
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


def room(x, wet=0.2):
    if x.ndim == 1: x = np.stack([x, x], 1)
    y = np.stack([signal.fftconvolve(x[:, c], IR[:, c]) for c in range(2)], 1)
    y *= (np.sqrt((x ** 2).mean()) + 1e-12) / (np.sqrt((y ** 2).mean()) + 1e-12)
    out = np.zeros_like(y); out[: len(x)] = x * (1 - wet)
    return out + y * wet * 1.5


def write(name, x, peak, floor_db=-54):
    x = np.asarray(x, float)
    if x.ndim == 1: x = np.stack([x, x], 1)
    env = np.abs(x).max(1); m = env.max()
    idx = np.nonzero(env > m * 10 ** (floor_db / 20))[0]
    x = x[: idx[-1] + int(0.03 * SR)]
    f = min(len(x), int(0.02 * SR)); x[-f:] *= np.linspace(1, 0, f)[:, None]
    x = x / m * peak
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    print(f"{name:8s} {len(x) / SR:.2f} s")


def modal(f, ratios, amps, decays, dur):
    t = t_axis(dur)
    y = sum(a * np.sin(2 * np.pi * f * r * t + r) * np.exp(-t * d) for r, a, d in zip(ratios, amps, decays))
    return y * np.clip(t / 0.0004, 0, 1)


def mix(dur, *parts):
    y = np.zeros(int(SR * dur))
    for start, x in parts:
        i = int(start * SR)
        n = min(len(x), len(y) - i)
        if n > 0:
            y[i:i + n] += x[:n]
    return y


def clack(f):
    t = t_axis(0.25)
    body = modal(f, [1, 2.31, 3.9, 5.6], [1, 0.55, 0.3, 0.15], [70, 95, 140, 200], 0.25)
    knock = band(noise(0.25), 1500, 9000) * np.exp(-t * 420) * 0.9
    felt = lowpass(noise(0.25), 600) * np.exp(-t * 60) * 0.25
    return body + knock + felt


def main():
    global IR
    OUT.mkdir(parents=True, exist_ok=True)
    IR = make_ir()
    for old in OUT.glob("*.wav"):
        if not old.name.startswith("clack"): old.unlink()
    t = t_axis(0.2)
    write("place", room(modal(900, [1, 2.4], [0.6, 0.3], [90, 140], 0.2) + lowpass(noise(0.2), 900) * np.exp(-t * 70) * 0.5, 0.1), 0.25)
    write("remove", room(modal(1300, [1, 2.2], [0.5, 0.2], [60, 110], 0.2) + band(noise(0.2), 400, 2500) * np.exp(-t * 50) * 0.4, 0.1), 0.22)
    write("tip", room(clack(2900) * 0.6 + band(noise(0.25), 800, 5000) * np.sin(np.pi * np.clip(t_axis(0.25) / 0.25, 0, 1)) ** 2 * 0.3, 0.1), 0.32)
    # Brass bell: inharmonic partials, long ring with a slow beat.
    t = t_axis(2.4)
    bell = modal(988, [0.5, 1.0, 1.19, 1.5, 2.0, 2.52, 3.0], [0.35, 1, 0.6, 0.35, 0.3, 0.18, 0.12], [1.2, 1.6, 2.2, 2.6, 3.4, 4.5, 6], 2.4)
    bell *= 1 + 0.08 * np.sin(2 * np.pi * 3.2 * t)
    write("bell", room(bell + band(noise(2.4), 3000, 10000) * np.exp(-t * 180) * 0.4, 0.3), 0.5)
    # Spring launcher: a twangy boing with vibrato and the brass cap's tick.
    t = t_axis(0.7)
    f = 190 * (1 + 0.35 * np.exp(-t * 9)) * (1 + 0.05 * np.sin(2 * np.pi * 22 * t))
    boing = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 6) + 0.3 * np.sin(2 * np.pi * np.cumsum(f * 2.7) / SR) * np.exp(-t * 11)
    write("boing", room(boing + modal(2600, [1, 2.7], [0.4, 0.2], [60, 100], 0.7), 0.15), 0.45)
    # Rocket: a fizzing whoosh that climbs, crackling.
    t = t_axis(1.0)
    sweep = band(noise(1.0), 600, 7000) * np.exp(-((t - 0.35) / 0.28) ** 2)
    crackle = np.zeros_like(t)
    for _ in range(40):
        i = int(RNG.uniform(0.05, 0.8) * SR); n = int(0.006 * SR)
        crackle[i:i + n] += RNG.uniform(0.2, 0.6) * band(noise(0.006), 3000, 12000)
    write("launch", room(sweep * 0.8 + crackle * 0.6, 0.2), 0.45)
    # Landing: a soft pop with sparkles and a little thump.
    t = t_axis(0.9)
    pop = band(noise(0.9), 300, 4000) * np.exp(-t * 40) + np.sin(2 * np.pi * 110 * t) * np.exp(-t * 25) * 0.6
    sparkle = sum(RNG.uniform(0.05, 0.15) * np.sin(2 * np.pi * RNG.uniform(3000, 7000) * np.clip(t - s, 0, None))
                  * np.exp(-np.clip(t - s, 0, None) * 60) * (t >= s) for s in RNG.uniform(0.02, 0.5, 24))
    write("pop", room(pop + sparkle, 0.25), 0.5)
    # Marble: down the wooden chute (bright rumble), then softer across the felt.
    t = t_axis(1.1)
    rumble = band(noise(1.1), 120, 1800) * (np.clip(t / 0.05, 0, 1) * np.where(t < 0.35, 1.0, 0.45) * np.exp(-np.clip(t - 0.35, 0, None) * 2.2))
    clinks = mix(1.1, (0.02, modal(3400, [1, 2.7], [0.5, 0.2], [80, 120], 0.2)), (0.36, modal(2600, [1, 2.4], [0.3, 0.1], [90, 140], 0.2)))
    write("roll", room(rumble * 0.7 + clinks, 0.15), 0.35)
    t = t_axis(0.35)
    write("thunk", room(modal(380, [1, 1.9, 3.1], [1, 0.4, 0.15], [30, 50, 80], 0.35) + lowpass(noise(0.35), 1200) * np.exp(-t * 60) * 0.5, 0.18), 0.5)
    house = mix(0.8, (0.0, modal(240, [1, 2.1, 3.3], [1, 0.4, 0.2], [18, 30, 45], 0.6)), (0.0, lowpass(noise(0.6), 900) * np.exp(-t_axis(0.6) * 12) * 0.6),
                (0.08, clack(1500) * 0.35), (0.14, clack(1250) * 0.25))
    write("house", room(house, 0.22), 0.55)
    t = t_axis(0.45)
    rock = sum(modal(1700 + 120 * k, [1, 2.3], [0.5, 0.2], [80, 120], 0.45) * (t >= k * 0.09) * np.exp(-k * 0.6) for k in range(4))
    write("wobble", room(rock, 0.12), 0.3)
    cheer = mix(2.4, *[(k * 0.11, modal(f, [1, 2.0, 2.76], [1, 0.35, 0.2], [2.5, 4, 6], 1.8) * (0.9 - 0.1 * k))
                       for k, f in enumerate((523.25, 659.25, 783.99, 1046.5))])
    write("cheer", room(cheer, 0.3), 0.55)
    over = mix(2.6, *[(k * 0.32, modal(f, [1, 2.0, 2.76, 5.4], [1, 0.4, 0.25, 0.1], [2.2, 3, 4.5, 8], 2.0))
                      for k, f in enumerate((784.0, 659.25, 523.25))])
    write("over", room(over, 0.3), 0.55)
    write("coin", room(mix(0.5, (0, modal(2637, [1, 2.4, 3.9], [1, 0.4, 0.2], [18, 30, 45], 0.4)), (0.07, modal(3520, [1, 2.4], [0.8, 0.3], [20, 35], 0.4))), 0.2), 0.4)
    write("click", modal(1600, [1, 2.4], [1, 0.3], [160, 240], 0.1), 0.26)
    print("sounds written to", OUT)


if __name__ == "__main__":
    main()
