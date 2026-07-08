#!/usr/bin/env python3
# gen_sfx.py — source of Ylem's UI sfx (Assets/Audio/*.wav). Procedural, no samples
# to license. Re-run to retune. Mono 16-bit 44.1k. audio.play("x.wav") resolves to
# Assets/Audio/x.wav, so the files live there under bare names.
import math, os, wave, struct
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets", "Audio")
os.makedirs(OUT, exist_ok=True)


def save(name, sig):
    sig = np.asarray(sig, dtype=np.float64)
    peak = np.max(np.abs(sig)) or 1.0
    sig = sig / peak * 0.85
    # 4 ms fades kill start/end clicks
    f = int(SR * 0.004)
    if len(sig) > 2 * f:
        sig[:f] *= np.linspace(0, 1, f)
        sig[-f:] *= np.linspace(1, 0, f)
    pcm = (np.clip(sig, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote", name, f"{len(sig)/SR*1000:.0f}ms")


def t(dur):
    return np.arange(int(SR * dur)) / SR


def chirp(f0, f1, tt):  # linear-frequency sweep
    return np.sin(2 * np.pi * (f0 * tt + (f1 - f0) / (2 * tt[-1]) * tt * tt))


# electron snap — a bright crisp tick with a tiny downward chirp
tt = t(0.09)
tick = chirp(1500, 1250, tt) * np.exp(-tt / 0.018)
tick += 0.3 * np.sin(2 * np.pi * 2800 * tt) * np.exp(-tt / 0.011)
save("e_tick.wav", tick)

# proton land — a low weighted thump with a click transient
tt = t(0.16)
thump = chirp(135, 68, tt) * np.exp(-tt / 0.05)
click = np.zeros_like(tt)
nc = int(SR * 0.004)
rng = np.random.default_rng(7)
click[:nc] = rng.uniform(-1, 1, nc) * np.exp(-np.arange(nc) / (SR * 0.0015)) * 0.5
save("p_thump.wav", thump + click)

# shell close (He / Ne) — a resonant inharmonic bell chime
tt = t(0.6)
f0 = 660.0
bell = np.zeros_like(tt)
for mult, amp, tau in [(1.0, 1.0, 0.5), (2.0, 0.5, 0.35), (2.99, 0.35, 0.28), (4.23, 0.2, 0.2)]:
    bell += amp * np.sin(2 * np.pi * f0 * mult * tt) * np.exp(-tt / tau)
save("shell_lock.wav", bell)

# birth card — a warm staggered major arpeggio (C E G C), the reward
notes = [523.25, 659.25, 783.99, 1046.5]
total = int(SR * 0.55)
birth = np.zeros(total)
for i, f in enumerate(notes):
    start = int(SR * 0.09 * i)
    nt = t(0.2)
    v = (np.sin(2 * np.pi * f * nt) + 0.25 * np.sin(2 * np.pi * 2 * f * nt)) * np.exp(-nt / 0.13)
    a = int(SR * 0.008)
    v[:a] *= np.linspace(0, 1, a)
    end = min(total, start + len(v))
    birth[start:end] += v[: end - start] * 0.7
save("birth.wav", birth)
