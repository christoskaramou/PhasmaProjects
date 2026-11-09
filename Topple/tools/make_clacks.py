"""Topple's domino hits: real hits cut from recordings of falling dominoes, not synthesized.

    python tools/make_clacks.py [output folder]

Sources: tools/clack_sources (CC0, see Assets/Audio/CREDITS.txt). Needs ffmpeg. Each clip runs from one hit's attack to
just before the next hit, so one domino falling plays one real hit; clips keep the recording's own tone and loudness.
"""
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from scipy import signal

HERE = Path(__file__).resolve().parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "Assets" / "Audio"
SR = 48000
COUNT = 12
# The stretches of each recording where the chain is running (the rest is the set-up and handling noise).
STRETCHES = (("domino_1_freesound_522586.ogg", 1.25, 2.3), ("domino_2_freesound_522585.ogg", 1.48, 2.55))
MIN_LEN, MAX_LEN = 0.018, 0.06


def decode(path):
    raw = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, "<f4").astype(float)


def cut_hits(x):
    """Every hit with a clear attack and at least MIN_LEN of itself before the next one."""
    high = signal.sosfilt(signal.butter(2, 150, "highpass", fs=SR, output="sos"), x)
    n = int(SR * 0.0005)
    env = np.convolve(np.abs(high), np.ones(n) / n, "same")
    th = np.percentile(env, 99.5) * 0.1
    peaks, _ = signal.find_peaks(env, height=th, distance=int(0.012 * SR), prominence=th * 0.5)
    clips = []
    for k, p in enumerate(peaks):
        nxt = peaks[k + 1] if k + 1 < len(peaks) else len(x)
        before = env[max(0, p - int(0.004 * SR)): max(1, p - int(0.001 * SR))]
        if before.mean() > env[p] * 0.45 or nxt - p < int(MIN_LEN * SR):
            continue
        start = max(0, p - int(0.0012 * SR))
        end = min(len(x), start + int(MAX_LEN * SR), nxt - int(0.001 * SR))
        clip = x[start:end].copy()
        if np.abs(clip).max() >= 0.98:           # a clipped hit in the recording
            continue
        clip[: int(0.0004 * SR)] *= np.linspace(0, 1, int(0.0004 * SR))
        fade = min(len(clip) // 3, int(0.006 * SR))
        clip[-fade:] *= np.linspace(1, 0, fade)
        clips.append(clip)
    return clips


def write(name, clip, pan):
    left, right = clip * (1 - max(pan, 0)), clip * (1 + min(pan, 0))
    pcm = (np.clip(np.stack([left, right], 1), -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm)


def main():
    clips = []
    for name, a, b in STRETCHES:
        x = decode(HERE / "clack_sources" / name)
        clips += cut_hits(x[int(a * SR): int(b * SR)])
    clips.sort(key=lambda c: -np.abs(c).max())
    # An even walk from the hardest hit to the softest, so a chain keeps the recording's mix of hard and light hits.
    picks = [clips[i] for i in np.linspace(0, len(clips) - 1, COUNT).astype(int)]
    gain = 0.7 / np.abs(picks[0]).max()
    rng = np.random.default_rng(9)
    for old in OUT.glob("clack*.wav"):
        old.unlink()
    for i, clip in enumerate(picks, 1):
        write(f"clack{i}", clip * gain, rng.uniform(-0.18, 0.18))
        print(f"clack{i:<3d} {len(clip) / SR * 1000:5.1f} ms  peak {np.abs(clip).max() * gain:.2f}")
    print(f"{len(clips)} usable hits, kept {COUNT}")


if __name__ == "__main__":
    main()
