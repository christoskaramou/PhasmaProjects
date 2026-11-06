"""Echo Chamber sounds: physically-modelled bells and impacts in a synthetic stone-chamber reverb.

    python tools/make_sounds.py

Everything is synthesized (numpy / scipy), stereo 32 kHz 16-bit:
- bells: church-bell partials (hum, prime, tierce, quint, nominal, upper modes) as slightly detuned
  pairs so they shimmer, a clapper strike transient, and a long stone-room tail;
- glass tinks (plate modes), a tuning fork (fundamental + clang mode), a singing-bowl swell, felt and
  stone thuds, a breathy horn blast, a cracked bell, a tam-tam, a carillon and a room-tone loop.
Frequent sounds get several variants (the engine plays files as-is: no per-play pitch or volume).
"""
from pathlib import Path

import numpy as np
from scipy import signal

OUT = Path(__file__).resolve().parent.parent / "Assets" / "Audio"
SR = 32000
RNG = np.random.default_rng(1234)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


# Mix levels (peak) so the room is balanced: bells lead, hands and UI sit underneath.
LEVEL = {"bell": 0.85, "wrong": 0.8, "win": 0.85, "lose": 0.65, "send": 0.62, "bounce": 0.42, "split": 0.55,
         "charge": 0.5, "damp": 0.55, "absorb": 0.32, "fade": 0.38, "place": 0.5, "rotate": 0.38, "remove": 0.38,
         "deny": 0.42, "click": 0.3, "assemble": 0.55, "star": 0.5, "hint": 0.5}


def write(name, x, peak=None, loop=False):
    """x: (n,) mono or (n, 2) stereo. Trims the silent tail, fades it, normalises to `peak`."""
    x = np.asarray(x, np.float64)
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    env = np.abs(x).max(1)
    m = env.max()
    if m <= 0:
        return
    if not loop:
        idx = np.nonzero(env > m * 10 ** (-54 / 20))[0]
        end = min(len(x), (idx[-1] if len(idx) else len(x)) + int(0.05 * SR))
        x = x[:end]
        fade = min(len(x), int(0.04 * SR))
        x[-fade:] *= np.linspace(1, 0, fade)[:, None]
    if peak is None:
        peak = next((v for k, v in LEVEL.items() if name.startswith(k)), 0.7)
    x = x / m * peak
    import wave
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def band(x, lo, hi, order=2):
    lo, hi = max(20, lo), min(SR / 2 - 100, hi)
    sos = signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, f, order=2):
    return signal.sosfilt(signal.butter(order, min(f, SR / 2 - 100), "lowpass", fs=SR, output="sos"), x)


def highpass(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "highpass", fs=SR, output="sos"), x)


def noise(dur):
    return RNG.standard_normal(int(SR * dur))


def pad(x, dur):
    n = int(SR * dur)
    if x.ndim == 1:
        return np.concatenate([x, np.zeros(max(0, n - len(x)))])
    return np.concatenate([x, np.zeros((max(0, n - len(x)), x.shape[1]))])


def mix(*parts):
    """parts: (signal, start_seconds[, pan -1..1]). Returns stereo."""
    n = 0
    for p in parts:
        n = max(n, int(p[1] * SR) + len(p[0]))
    y = np.zeros((n, 2))
    for p in parts:
        sgl, start = p[0], int(p[1] * SR)
        pan = p[2] if len(p) > 2 else 0.0
        if sgl.ndim == 1:
            l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
            y[start:start + len(sgl), 0] += sgl * l * 1.414
            y[start:start + len(sgl), 1] += sgl * r * 1.414
        else:
            y[start:start + len(sgl)] += sgl
    return y


# ------------------------------------------------------------------ the room
def make_ir(rt60=2.4, dur=3.2, predelay=0.014, bright=0.5, seed=7):
    """Stereo stone-chamber impulse response: discrete early reflections, then a decaying noise tail
    whose high frequencies die faster than the lows (air and stone absorption)."""
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for ch in range(2):
        # Tail: three bands with their own decay times.
        tail = np.zeros(n)
        for lo, hi, k in ((40, 500, 1.0), (500, 3000, 0.75), (3000, 12000, 0.4 * (0.5 + bright))):
            nb = band(rng.standard_normal(n), lo, hi)
            tail += nb * np.exp(-6.91 * t / (rt60 * k))
        tail *= np.clip((t - predelay) / 0.04, 0, 1)
        ir[:, ch] = tail * 0.35
        # Early reflections off the chamber walls.
        for _ in range(14):
            d = predelay + rng.uniform(0.004, 0.09)
            i = int(d * SR)
            ir[i, ch] += rng.uniform(0.25, 0.7) * (1 if rng.random() < 0.5 else -1) * np.exp(-d * 9)
    ir[0, :] += 0
    return ir / np.abs(ir).max()


IR_HALL = None
IR_SMALL = None


def room(x, wet=0.35, ir=None, width=1.0):
    """Dry signal (mono or stereo) through the chamber."""
    ir = IR_HALL if ir is None else ir
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    n = len(x) + len(ir) - 1
    y = np.zeros((n, 2))
    for ch in range(2):
        y[:, ch] = signal.fftconvolve(x[:, ch] if width >= 1 else x.mean(1), ir[:, ch])
    rms_d = np.sqrt((x ** 2).mean()) + 1e-12
    rms_w = np.sqrt((y ** 2).mean()) + 1e-12
    y *= rms_d / rms_w
    return pad(x, n / SR) * (1 - wet) + y * wet * 1.6


# ------------------------------------------------------------------ instruments
# Church-bell partials relative to the nominal's lower octave (the "strike note" = prime):
# (ratio, amplitude, T60 seconds at prime = 523 Hz; scaled by pitch).
BELL = [(0.5, 0.42, 7.5), (1.0, 0.55, 5.0), (1.183, 0.5, 4.0), (1.506, 0.28, 3.4), (2.0, 0.85, 3.2),
        (2.514, 0.25, 2.2), (2.662, 0.32, 2.0), (3.011, 0.22, 1.6), (4.166, 0.16, 1.0), (5.433, 0.1, 0.7),
        (6.796, 0.06, 0.45)]


def bell_dry(f, dur=5.0, strike=1.0, crack=0.0, seed=0):
    rng = np.random.default_rng(seed + int(f))
    t = t_axis(dur)
    y = np.zeros_like(t)
    scale = (523.25 / f) ** 0.6
    for ratio, a, t60 in BELL:
        fr = f * ratio * (1 + rng.normal(0, 0.0007))
        # Each mode is a doublet a fraction of a hertz apart: the slow beating of a real bell.
        beat = rng.uniform(0.4, 2.2) * (1 + crack * 30)
        dec = 6.91 / (t60 * scale * (1 - 0.6 * crack))
        ph = rng.uniform(0, 2 * np.pi)
        y += a * (np.sin(2 * np.pi * fr * t + ph) + 0.6 * np.sin(2 * np.pi * (fr + beat) * t + ph * 1.7)) * np.exp(-dec * t)
    # Clapper strike: a bright metallic click (high inharmonic modes dying in tens of ms) + thud.
    clank = np.zeros_like(t)
    for r in (8.93, 11.4, 14.2, 17.9):
        clank += np.sin(2 * np.pi * f * r * t + rng.uniform(0, 6)) * np.exp(-t * rng.uniform(60, 120))
    knock = band(rng.standard_normal(len(t)), 1500, 9000) * np.exp(-t * 180)
    y = y + strike * (0.35 * clank + 0.5 * knock)
    if crack > 0:
        rattle = band(rng.standard_normal(len(t)), 600, 3000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * f * 0.5 * t)))
        y += crack * 0.6 * rattle * np.exp(-t * 7)
    att = np.clip(t / 0.0015, 0, 1)
    return y * att


def modal(f, ratios, amps, decays, dur, seed=0, detune=0.002):
    rng = np.random.default_rng(seed)
    t = t_axis(dur)
    y = np.zeros_like(t)
    for r, a, d in zip(ratios, amps, decays):
        y += a * np.sin(2 * np.pi * f * r * (1 + rng.normal(0, detune)) * t + rng.uniform(0, 6)) * np.exp(-t * d)
    return y * np.clip(t / 0.0008, 0, 1)


def glass_tink(f, seed):
    """Free-plate modes of a small glass mirror + a sharp tick."""
    y = modal(f, [1, 2.32, 4.25, 6.63, 9.38], [1, 0.6, 0.35, 0.2, 0.1], [14, 22, 34, 50, 70], 0.9, seed)
    tick = band(noise(0.9), 3000, 12000) * np.exp(-t_axis(0.9) * 400)
    return y + 0.5 * tick


def tuning_fork(f, dur=2.0, seed=0):
    t = t_axis(dur)
    y = np.sin(2 * np.pi * f * t) * np.exp(-t * 2.2)                       # fundamental, long
    y += 0.5 * np.sin(2 * np.pi * f * 6.267 * t + 1) * np.exp(-t * 30)     # clang mode, short
    y += 0.15 * np.sin(2 * np.pi * f * 17.55 * t + 2) * np.exp(-t * 80)
    return y * np.clip(t / 0.001, 0, 1)


def singing_bowl(f, dur, swell, seed=0):
    rng = np.random.default_rng(seed)
    t = t_axis(dur)
    env = np.clip(t / swell, 0, 1) ** 2 * np.exp(-np.clip(t - swell, 0, None) * 2.2)
    y = np.zeros_like(t)
    for r, a in ((1, 1), (2.71, 0.5), (5.15, 0.25), (8.2, 0.1)):
        beat = rng.uniform(1.5, 4)
        y += a * (np.sin(2 * np.pi * f * r * t) + 0.7 * np.sin(2 * np.pi * (f * r + beat) * t + 1.3))
    rub = band(rng.standard_normal(len(t)), f * 0.9, f * 3) * 0.15
    return (y + rub) * env


def thud(f0, dur, noise_amt, seed=0, lp=1200):
    rng = np.random.default_rng(seed)
    t = t_axis(dur)
    fr = f0 * (1 + 1.2 * np.exp(-t * 40))
    body = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 18)
    n = lowpass(rng.standard_normal(len(t)), lp) * np.exp(-t * 45)
    return body + noise_amt * n


def horn_blast(f, dur=0.85, seed=0):
    """Breath through a flared horn: noise through vocal-tract-like resonances plus a soft brassy tone."""
    rng = np.random.default_rng(seed)
    t = t_axis(dur)
    env = np.clip(t / 0.09, 0, 1) ** 1.5 * np.exp(-np.clip(t - 0.12, 0, None) * 4.5)
    breath = rng.standard_normal(len(t))
    y = 0.5 * band(breath, 300, 520) + 0.35 * band(breath, 900, 1400) + 0.2 * band(breath, 2200, 3200)
    saw = signal.sawtooth(2 * np.pi * f * (1 + 0.04 * t) * t)
    k = np.clip(t / 0.15, 0, 1)            # the lip opens up: dark to bright
    tone = lowpass(saw, 900) * (1 - k) + lowpass(saw, 2300) * k
    whoosh = band(rng.standard_normal(len(t)), 150, 6000) * np.clip(t / 0.25, 0, 1) * np.exp(-t * 3)
    return (y * 1.2 + 0.45 * tone) * env + 0.25 * whoosh


def tam_tam(f, dur=4.5, seed=0):
    rng = np.random.default_rng(seed)
    t = t_axis(dur)
    y = np.zeros_like(t)
    for _ in range(40):
        r = rng.uniform(1, 9)
        y += rng.uniform(0.2, 1) / r * np.sin(2 * np.pi * f * r * t + rng.uniform(0, 6)) * np.exp(-t * rng.uniform(0.6, 2.5))
    swell = 1 - np.exp(-t * 6)
    return y * swell * np.clip(t / 0.003, 0, 1) + 0.4 * band(noise(dur), 200, 2500) * np.exp(-t * 25)


# ------------------------------------------------------------------ sound set
NOTES = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66]   # bells 1-7: a major pentatonic run


def sounds():
    global IR_HALL, IR_SMALL
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.wav"):
        old.unlink()
    IR_HALL = make_ir(2.6, 3.4, 0.016, 0.45, 7)
    IR_SMALL = make_ir(0.9, 1.4, 0.008, 0.7, 11)

    for i, f in enumerate(NOTES, 1):
        write(f"bell{i}", room(bell_dry(f, 5.0, seed=i), 0.42))
    write("wrong", room(mix((bell_dry(349.2, 3.0, 1.2, crack=1.0, seed=3), 0), (thud(70, 0.5, 0.8, 4), 0)), 0.35))
    write("hint", room(mix((bell_dry(1568.0, 2.5, 0.5, seed=21) * 0.6, 0, -0.3), (bell_dry(2093.0, 2.5, 0.5, seed=22) * 0.5, 0.09, 0.3)), 0.5))
    # Horn: the pulse leaves (three takes).
    for v in range(3):
        write(f"send{v + 1}", room(horn_blast(110 * (1 + 0.03 * v), 0.9, v), 0.4))
    # Glass mirror tinks (five pitches so chained bounces never sound mechanical).
    for v in range(5):
        write(f"bounce{v + 1}", room(glass_tink(2300 * (1 + 0.06 * v - 0.12), 30 + v), 0.3, IR_SMALL))
    # Fork: tuning fork strike, the two halves swish apart left and right.
    for v in range(2):
        f = 880 * (1 + 0.02 * v)
        sw = band(noise(0.5), 800, 5000) * np.exp(-t_axis(0.5) * 9) * np.clip(t_axis(0.5) / 0.02, 0, 1)
        write(f"split{v + 1}", room(mix((tuning_fork(f, 2.0, v), 0), (sw * 0.35, 0.01, -0.8), (sw * 0.35, 0.03, 0.8)), 0.35))
    write("charge", room(singing_bowl(392.0, 2.2, 0.35, 5), 0.4))
    write("damp", room(thud(85, 0.45, 1.2, 6, 700), 0.15, IR_SMALL))
    for v in range(3):
        write(f"absorb{v + 1}", room(thud(60 + 12 * v, 0.4, 0.9, 40 + v, 500) * 0.6, 0.25, IR_SMALL))
    t = t_axis(1.4)
    shimmer = band(noise(1.4), 3000, 9000) * np.exp(-t * 3) * (0.5 + 0.5 * np.sin(2 * np.pi * 11 * t))
    write("fade", room(shimmer * 0.5 + np.sin(2 * np.pi * np.cumsum(880 - 400 * t) / SR) * np.exp(-t * 3) * 0.3, 0.5))
    # Hands on the board: stone knocks, a ratchet, a lift.
    for v in range(3):
        k = modal(620 * (1 + 0.08 * v), [1, 2.76, 5.4, 8.9], [1, 0.5, 0.25, 0.1], [45, 70, 110, 160], 0.4, 50 + v)
        click = band(noise(0.4), 2000, 9000) * np.exp(-t_axis(0.4) * 600)
        write(f"place{v + 1}", room(k * 0.8 + click * 0.6 + thud(140, 0.4, 0.4, 60 + v) * 0.5, 0.18, IR_SMALL))
    ratchet = mix(*[(band(noise(0.03), 2500, 8000) * np.exp(-t_axis(0.03) * 300), i * 0.035) for i in range(3)],
                  (glass_tink(3100, 77) * 0.25, 0.1))
    write("rotate", room(ratchet, 0.18, IR_SMALL))
    lift = band(noise(0.3), 400, 4000) * np.sin(np.pi * np.clip(t_axis(0.3) / 0.3, 0, 1)) ** 2
    write("remove", room(mix((lift * 0.5, 0), (modal(900, [1, 2.76], [1, 0.4], [60, 90], 0.3, 81) * 0.5, 0.12)), 0.2, IR_SMALL))
    write("deny", room(mix((thud(110, 0.25, 0.7, 90, 900), 0), (thud(100, 0.25, 0.7, 91, 900), 0.11)), 0.12, IR_SMALL))
    click = modal(1800, [1, 2.4], [1, 0.3], [180, 260], 0.12, 95) + band(noise(0.12), 3000, 10000) * np.exp(-t_axis(0.12) * 900) * 0.4
    write("click", click)
    # Chamber assembling: a stone rumble that settles with a few knocks.
    t = t_axis(1.6)
    rumble = lowpass(noise(1.6), 220) * np.sin(np.pi * np.clip(t / 1.2, 0, 1)) ** 1.5
    knocks = [(thud(120 + 30 * i, 0.3, 0.6, 100 + i, 900) * 0.4, 0.3 + i * 0.2, (i % 3 - 1) * 0.5) for i in range(5)]
    write("assemble", room(mix((rumble * 1.4, 0), *knocks), 0.35))
    # Win: a carillon run up the scale and a full chord; lose: a low tam-tam.
    seq = [(bell_dry(f, 4.5, seed=200 + i) * 0.5, i * 0.13, (i - 3) * 0.25) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0])]
    chord = [(bell_dry(f, 5.0, seed=300 + i) * 0.35, 0.9, (i - 1) * 0.4) for i, f in enumerate([523.25, 659.25, 783.99])]
    write("win", room(mix(*seq, *chord), 0.45))
    write("lose", room(tam_tam(98, 4.5, 8), 0.4))
    write("star", room(bell_dry(2093.0, 2.0, 0.6, seed=401) * 0.6, 0.45))
    # Room tone loop (played on the music bus): air, a low stone hum, a distant resonance. Seamless.
    dur = 24.0
    t = t_axis(dur)
    air = np.stack([lowpass(noise(dur), 300) for _ in range(2)], 1) * 0.6
    hum = (np.sin(2 * np.pi * 55 * t) * (0.6 + 0.4 * np.sin(2 * np.pi * t / dur * 2)) + 0.5 * np.sin(2 * np.pi * 82.41 * t + 1)
           * (0.6 + 0.4 * np.sin(2 * np.pi * t / dur * 3 + 1)) + 0.25 * np.sin(2 * np.pi * 110.3 * t)) * 0.18
    amb = air + np.stack([hum, hum * 0.95], 1)
    for k, (f, at) in enumerate([(261.63, 3.0), (392.0, 11.0), (329.63, 18.5)]):
        d = bell_dry(f, 5.0, 0.0, seed=500 + k) * 0.05
        s = int(at * SR)
        amb[s:s + len(d)] += np.stack([d * (0.6 + 0.3 * k), d * (1.0 - 0.3 * k)], 1)[: len(amb) - s]
    wet = room(amb, 0.6)[: len(amb) + int(2 * SR)]
    # Loop: fold the reverb tail back onto the start, crossfade the seam.
    loop = wet[: len(amb)].copy()
    tail = wet[len(amb):]
    loop[: len(tail)] += tail
    xf = int(1.0 * SR)
    ramp = np.linspace(0, 1, xf)[:, None]
    loop[:xf] = loop[:xf] * ramp + loop[-xf:] * (1 - ramp)
    loop = loop[:-xf]
    write("ambience", loop, 0.35, loop=True)


if __name__ == "__main__":
    sounds()
    print("sounds written to", OUT)
