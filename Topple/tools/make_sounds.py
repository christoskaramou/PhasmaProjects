"""Topple sounds: painted wooden toys on a felt games table in a small wood-panelled room.

    python tools/make_sounds.py

Synthesized with numpy / scipy, stereo 32 kHz (modal models, as Ricochet Parlour's):
- (clack*.wav, the domino hits, are real recordings: see tools/make_clacks.py)
- place / remove / tip: a domino set down on felt, picked up, and the flick that starts the chain
- bell: the brass bell on its gallows; boing: the spring launcher; launch / pop: a toy rocket going up and landing
- roll: a glass marble down its wooden chute and across the felt; thunk: a domino against a wooden block
- house: a toy house tipping over; wobble: a domino nudged edge-on that rocks and stays up
- cheer: table cleared (a rising brass arpeggio); over: the run ends (falling chimes); coin; click
- house rooms: string_snap1/2, weight_drop, plank_fall, gate_open (traps); collapse_cards / _blocks / _glass (fragile
  stacks); unlock (a new tool); goal_doorbell, _tv, _toaster, _record, _train, _musicbox, _dictionary, _lights
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


def fit(x, dur, fade=0.3):
    """Cut a (room-processed) sound to dur seconds with a smooth fade, so long rings end without a click."""
    x = np.array(x[: int(SR * dur)], float); n = min(len(x), int(SR * fade))
    w = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n))
    x[-n:] *= w[:, None] if x.ndim == 2 else w
    return x


def sweep_sin(f): return np.sin(2 * np.pi * np.cumsum(f) / SR)
def burst(d, lo, hi, rate): t = t_axis(d); return band(noise(d), lo, hi) * np.exp(-t * rate) * np.clip(t / 0.0005, 0, 1)


def string_snap(f):
    # A taut string cut: the snap, a twang that sags as the tension goes, and the loose end whipping away.
    t = t_axis(0.8)
    fr = f * (0.72 + 0.28 * np.exp(-t * 30))
    tw = sum(sweep_sin(fr * k) / k ** 1.1 * np.exp(-t * (5 + 4 * k)) for k in range(1, 7)) * np.clip(t / 0.0006, 0, 1)
    whip = band(noise(0.8), 1500, 7000) * np.exp(-((t - 0.05) / 0.025) ** 2) * 0.5 + band(noise(0.8), 500, 2500) * np.exp(-((t - 0.1) / 0.035) ** 2) * 0.35
    return tw + burst(0.8, 2500, 12000, 600) * 0.6 + whip * 0.7


def wood_hit(f, amp, dur=0.3, rate=300):
    return (modal(f, [1, 2.45, 4.1], [1, 0.4, 0.2], [45, 70, 100], dur) + burst(dur, 1000, 6000, rate) * 0.5) * amp


def glass(f, amp):
    return (modal(f, [1, 2.32, 4.25, 6.0], [1, 0.35, 0.15, 0.06], [6, 10, 18, 30], 1.5) + burst(1.5, 3500, 10000, 900) * 0.12) * amp


def tine(f, dur=2.0):
    rs = [r for r in (1, 2.0, 6.27) if f * r < 13000]
    return modal(f, rs, [1, 0.08, 0.35][: len(rs)], [1.8, 4, 25][: len(rs)], dur) + burst(dur, 3000, 9000, 800) * 0.12


def house_sounds():
    """The house rooms' traps, rewards and room goals (made after the original set so its RNG stream is unchanged)."""
    for i, f in enumerate((520, 690), 1):
        write(f"string_snap{i}", room(string_snap(f), 0.12), 0.4)
    t = t_axis(0.8)

    def drop(a):
        return (modal(150, [1, 2.3, 3.7, 5.1], [1, 0.5, 0.3, 0.15], [22, 35, 50, 70], 0.8) + modal(1430, [1, 2.71, 4.4], [0.25, 0.12, 0.06], [25, 35, 50], 0.8)
                + lowpass(noise(0.8), 2500) * np.exp(-t * 140) * 0.8) * a
    write("weight_drop", room(mix(1.0, (0, drop(1)), (0.13, drop(0.25)), (0.21, drop(0.08))), 0.18), 0.5)
    slap = lowpass(noise(0.8), 4000) * np.exp(-t * 220) * 1.2 * np.clip(t / 0.0005, 0, 1) + modal(190, [1, 2.6, 4.2, 6.8], [1, 0.6, 0.35, 0.2], [35, 50, 70, 100], 0.8)
    tw = t_axis(0.3)
    whoosh = band(noise(0.3), 200, 1500) * np.exp(-((tw - 0.24) / 0.08) ** 2) * 0.35
    write("plank_fall", room(mix(1.1, (0, whoosh), (0.25, slap), (0.25, modal(820, [1, 2.3], [0.3, 0.15], [60, 90], 0.3)), (0.33, slap[: int(0.3 * SR)] * 0.12)), 0.18), 0.5)
    t = t_axis(0.4)
    ph = np.cumsum(60 + 30 * np.sin(2 * np.pi * 2.2 * t)) / SR
    pulses = np.diff(np.floor(ph), prepend=0) * RNG.uniform(0.6, 1.0, len(t))
    creak = signal.fftconvolve(pulses, modal(900, [1, 1.7, 2.9], [1, 0.5, 0.3], [150, 200, 260], 0.03))[: len(t)] * np.sin(np.pi * t / 0.4) ** 2
    latch = modal(2900, [1, 2.4, 4.1], [0.6, 0.3, 0.15], [120, 180, 250], 0.15) + burst(0.15, 2000, 9000, 500) * 0.5
    write("gate_open", room(mix(0.9, (0, latch), (0.06, creak * 0.5), (0.5, modal(420, [1, 2.2, 3.4], [0.6, 0.25, 0.1], [40, 60, 90], 0.3))), 0.15), 0.38)
    # House of cards: light slaps of card on card and the flutter of falling cards.
    t = t_axis(1.3)
    flutter = band(noise(1.3), 400, 3500) * (0.5 + 0.5 * np.sin(2 * np.pi * 17 * t)) * np.exp(-((t - 0.4) / 0.3) ** 2) * 0.12
    slaps = [(s, burst(0.05, 800, 5000, RNG.uniform(140, 220)) * RNG.uniform(0.3, 1.0)) for s in np.sort(RNG.beta(2, 3.5, 30))]
    pats = [(s, lowpass(burst(0.08, 200, 3000, 120), 1500) * 0.6) for s in (0.92, 1.02)]
    write("collapse_cards", room(mix(1.4, (0, flutter), *slaps, *pats), 0.15), 0.42)
    # Block tower: a cascade of wooden knocks, the last ones landing on felt.
    times = np.cumsum(np.concatenate([[0], RNG.uniform(0.03, 0.12, 13)]))
    blocks = [(s, wood_hit(RNG.uniform(600, 1500), 1.0 - 0.05 * k) if k < 9 else lowpass(wood_hit(RNG.uniform(500, 900), 0.6), 1200))
              for k, s in enumerate(times)]
    write("collapse_blocks", room(mix(1.7, (0, modal(260, [1, 2.1], [0.6, 0.2], [25, 40], 0.4)), *blocks), 0.2), 0.55)
    # Glasses: they tip into each other and ring; no shatter.
    clinks = [(s, glass(f, a)) for s, f, a in ((0, 2200, 1), (0.12, 2750, 0.8), (0.2, 3100, 0.7), (0.33, 2450, 0.6), (0.41, 3500, 0.45),
                                               (0.6, 2900, 0.4), (0.78, 2350, 0.3), (1.0, 3250, 0.2))]
    toks = [(s + 0.02, modal(700, [1, 2.3], [0.25, 0.1], [60, 90], 0.2)) for s in (0.2, 0.41, 0.78)]
    write("collapse_glass", fit(room(mix(2.4, *clinks, *toks), 0.25), 2.3, 0.5), 0.45)
    # Unlock: a wooden mallet grace note into a warm G major chord with a soft bloom.
    t = t_axis(1.6)

    def mallet(f): return modal(f, [1, 3.93, 9.0], [1, 0.25, 0.08], [4, 18, 40], 1.6)
    bloom = sum(np.sin(2 * np.pi * f * t) for f in (196, 392, 493.9, 587.3)) * np.clip(t / 0.15, 0, 1) * np.exp(-t * 2.5) * 0.12
    sparkle = [(0.12 + 0.06 * k, modal(f, [1, 2.4], [0.12, 0.04], [20, 35], 0.4)) for k, f in enumerate((2349, 2794, 3136))]
    unlock = mix(1.8, (0, mallet(587.3) * 0.6), *[(0.09, mallet(f) * a) for f, a in ((392, 1), (493.9, 0.8), (587.3, 0.7), (784, 0.6))], (0.09, bloom), *sparkle)
    write("unlock", fit(room(unlock, 0.25), 1.8, 0.4), 0.5)
    # Room goals.
    def chime(f): return modal(f, [1, 2.76, 5.40, 8.93], [1, 0.45, 0.2, 0.08], [1.6, 3, 5, 8], 2.0) + burst(2.0, 2000, 8000, 700) * 0.3
    write("goal_doorbell", fit(room(mix(2.5, (0, chime(659.25)), (0.5, chime(523.25))), 0.25), 2.45, 0.6), 0.55)
    t = t_axis(1.9)
    hum = sum(sweep_sin((90 + 30 * (1 - np.exp(-t * 3))) * k) / k for k in range(1, 9)) * np.clip(t / 0.6, 0, 1) ** 1.5 * 0.35
    static = band(noise(1.9) * (RNG.random(len(t)) < 0.004), 1500, 6000) * np.exp(-t * 2) * 1.5
    whine = np.sin(2 * np.pi * 15300 * t) * np.clip((t - 0.2) / 0.8, 0, 1) * 0.015
    switch = modal(1100, [1, 2.3, 3.8], [0.7, 0.3, 0.15], [120, 170, 240], 0.3) + modal(140, [1, 2.2], [0.6, 0.2], [50, 70], 0.3)
    write("goal_tv", fit(room(mix(2.1, (0, switch), (0.08, lowpass(hum, 2500) * 2.2 + static + whine)), 0.15), 2.0, 0.4), 0.5)
    t = t_axis(0.6)
    spring = sweep_sin(740 * (1 + 0.06 * np.sin(2 * np.pi * 28 * t))) * np.exp(-t * 12) * np.clip(t / 0.001, 0, 1) * 0.4

    def toast(): return lowpass(burst(0.2, 200, 3000, 80), 1800) * 0.5 + modal(300, [1, 2.2], [0.3, 0.1], [50, 70], 0.2)
    write("goal_toaster", room(mix(0.9, (0, modal(1600, [1, 2.9, 4.7, 6.2], [0.8, 0.4, 0.25, 0.1], [40, 60, 90, 120], 0.6)), (0, modal(220, [1, 2.3], [0.6, 0.2], [40, 55], 0.3)),
                                   (0.005, spring), (0.28, toast()), (0.31, toast() * 0.7)), 0.18), 0.5)
    # Record: the needle drops, then a bar of warm surface crackle turning at 33 1/3.
    t = t_axis(3.4)
    def ticks(rate): return (RNG.random(len(t)) < rate / SR) * RNG.uniform(0.5, 1, len(t)) * RNG.choice([-1, 1], len(t))
    hiss = band(noise(3.4), 300, 4500) * 0.04 * (1 + 0.3 * np.sin(2 * np.pi * 0.556 * t)) + lowpass(noise(3.4), 60) * 0.03
    bed = lowpass(band(ticks(90), 1500, 6000) + lowpass(ticks(4), 2000) * 0.8 + hiss, 6000) * np.clip((t - 0.05) / 0.15, 0, 1)
    needle = burst(0.4, 2000, 9000, 600) * 0.4 + modal(70, [1, 2.1], [1, 0.3], [18, 30], 0.4) + modal(160, [1, 2.4], [0.3, 0.1], [40, 60], 0.4)
    bed *= 0.45 * np.abs(needle).max() / np.abs(bed).max()
    write("goal_record", fit(room(mix(3.4, (0, needle), (0, bed)), 0.15), 3.3, 0.6), 0.5)
    # Toy train: a three-note whistle with a scoop up, then two chuffs of steam.
    t = t_axis(0.75)
    scoop = (0.94 + 0.06 * (1 - np.exp(-t * 12))) * (1 + 0.004 * np.sin(2 * np.pi * 5.5 * t))
    whistle = sum(sweep_sin(f * scoop) + 0.15 * sweep_sin(2 * f * scoop) for f in (740, 932.3, 1108.7)) / 3 + band(noise(0.75), 600, 4000) * 0.15
    whistle *= np.clip(t / 0.04, 0, 1) * np.clip((0.75 - t) / 0.15, 0, 1)
    tc = t_axis(0.35)

    def chuff(): return band(noise(0.35), 250, 2500) * np.clip(tc / 0.008, 0, 1) * np.exp(-tc * 14) * 0.9 + lowpass(noise(0.35), 400) * np.exp(-tc * 20) * 0.4
    write("goal_train", fit(room(mix(1.8, (0, whistle), (0.9, chuff()), (1.22, chuff() * 0.8)), 0.2), 1.9, 0.3), 0.5)
    # Music box: an original six-note phrase on comb tines, the last note with a harmony, over the faint ratchet.
    phrase = [(0.0, 784.0), (0.3, 1174.7), (0.6, 1318.5), (0.9, 1046.5), (1.35, 987.8), (1.65, 1046.5), (1.65, 659.25)]
    tick = [(s, burst(0.02, 2000, 6000, 400) * 0.02) for s in np.arange(0, 3.2, 1 / 14)]
    write("goal_musicbox", fit(room(mix(3.8, *[(s, tine(f) * 0.7) for s, f in phrase], *tick), 0.3), 3.6, 0.8), 0.5)
    # Dictionary: a puff of air from the pages, then the heavy covers meet.
    t = t_axis(0.3); tt = t_axis(1.0)
    air = band(noise(0.3), 300, 3000) * np.exp(-((t - 0.09) / 0.05) ** 2) * 0.35 + band(noise(0.3), 2000, 8000) * np.exp(-((t - 0.08) / 0.03) ** 2) * 0.12
    thud = (modal(85, [1, 1.8, 2.9, 4.3], [1, 0.6, 0.35, 0.15], [16, 28, 45, 70], 1.0) + lowpass(noise(1.0), 1800) * np.exp(-tt * 90) * np.clip(tt / 0.0005, 0, 1)
            + burst(1.0, 1500, 6000, 300) * 0.35)
    write("goal_dictionary", room(mix(1.3, (0, air), (0.13, thud)), 0.2), 0.55)
    # Master switch: a big clunk and latch, then the house lights swelling up in a shimmer.
    t = t_axis(2.3)
    glide = 0.97 + 0.03 * np.clip(t / 1.4, 0, 1)
    swell = np.clip(t / 1.3, 0, 1) ** 2
    shimmer = sum(sweep_sin(f * glide) + sweep_sin(f * glide * 1.003) for f in (523.25, 659.25, 784, 1046.5, 1318.5)) * swell * (1 + 0.15 * np.sin(2 * np.pi * 6 * t)) * 0.08
    shimmer += band(noise(2.3) * (RNG.random(len(t)) < swell * 0.003), 2500, 7000) * 1.2 * swell
    clunk = modal(520, [1, 2.2, 3.6, 5.3], [0.7, 0.35, 0.2, 0.12], [35, 50, 70, 95], 0.5) + modal(110, [1, 2.4], [0.9, 0.3], [25, 35], 0.5) + burst(0.5, 800, 6000, 250) * 0.6
    write("goal_lights", fit(room(mix(2.5, (0, clunk), (0.05, modal(2100, [1, 2.4], [0.3, 0.1], [150, 200], 0.1)), (0.15, shimmer)), 0.25), 2.45, 0.35), 0.55)


def main():
    global IR
    OUT.mkdir(parents=True, exist_ok=True)
    IR = make_ir()
    for old in OUT.glob("*.wav"):
        if not old.name.startswith("clack"): old.unlink()
    for _ in range(6): noise(0.25)  # the RNG draws the synthesized clacks took, so the files below rebuild byte-for-byte
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
    house_sounds()
    print("sounds written to", OUT)


if __name__ == "__main__":
    main()
