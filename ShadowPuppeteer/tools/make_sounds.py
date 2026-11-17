"""Cut and level Shadow Puppeteer's sounds from CC0 Freesound recordings.
    python -I tools/make_sounds.py <candidates_dir> <Assets/Audio dir>
<candidates_dir> holds analysis.json and the downloaded previews (.concepts/next/puppet/snd_dl: snd/search.py +
snd/analyse.py, adapted from Loom's; every candidate's own sound page was checked to carry only the CC0 licence link).
For each sound the chosen recording is cut to its loudest event and its active RMS is set to the median of its
category's analysed candidates (their typical range); the ambience loops with a 2 s crossfade and sits AMB_DB under
that median so the effects stay on top. Writes <name>.wav (16-bit, 44.1 kHz) and CREDITS.txt."""
import json, subprocess, sys
from pathlib import Path
import numpy as np

SR = 44100
# name: (category, freesound id, cut length s (None: the whole event), mono)
PICK = {
    "ambience": ("ambience", "662891", 30.0, False),  # candle wick crackle: the stage's candle and lantern
    "drag": ("drag", "560349", 0.5, True),            # hand and wood sliding: a prop pushed along its track
    "step": ("step", "732813", 0.18, True),           # soft wood floor hit: the paper puppet's footfall
    "climb": ("climb", "344196", 0.3, True),          # ladder: one rung
    "fall": ("fall", "701104", 0.6, True),            # light whoosh
    "land": ("land", "625305", 0.35, True),           # paper impact
    "slide": ("slide", "464302", 0.7, True),          # paper slide: down a steep shadow
    "thorns": ("thorns", "489968", None, True),       # tearing paper: caught on the thorns
    "candle": ("candle", "242867", None, True),       # blowing out a candle: time is up
    "star": ("star", "770899", 1.5, True),            # twinkling chime: the bonus star
    "door": ("door", "338986", 3.6, True),            # music box melody: through the door
    "click": ("click", "878238", 0.2, True),          # wooden UI click
    "unlock": ("unlock", "415477", 2.5, True),        # harp run: a new stage set opens
}
# candidates that are not the category's kind of sound stay out of its median
EXCLUDE = {"620399", "865677", "832399", "466900", "464099", "434145", "872848", "174493", "174494", "437548", "396894",
           "702171", "199350"}
AMB_DB = -10.0          # the ambience bed under the effects' typical level
# game mix on top of the category medians: the footfall and the slide are small sounds, heard over the bed
MIX = {"step": 6.0, "slide": 10.0, "climb": -4.0, "ambience": 2.0, "door": -2.0, "unlock": 12.0}
PEAK_MAX = 10 ** (-1.0 / 20)


def decode(path, ch):
    raw = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path), "-ac", str(ch), "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, "<f4").astype(np.float64).reshape(-1, ch)


def env(x):
    m = x.mean(axis=1)
    return np.sqrt(np.convolve(m * m, np.ones(441) / 441, "same"))


def active_rms(x):
    e = env(x)
    act = e > e.max() * 0.1
    return float(np.sqrt((x[act] ** 2).mean()))


def fade(x, fin, fout):
    n_in, n_out = int(fin * SR), int(fout * SR)
    if n_in:
        x[:n_in] *= np.linspace(0, 1, n_in)[:, None]
    if n_out:
        x[-n_out:] *= np.linspace(1, 0, n_out)[:, None]
    return x


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    A = json.loads((src / "analysis.json").read_text(encoding="utf-8"))
    X = src / "analysis_extra.json"
    if X.exists():
        for cat, cs in json.loads(X.read_text(encoding="utf-8")).items():
            have = {c["id"] for c in A.get(cat, [])}
            A.setdefault(cat, []).extend(c for c in cs if c["id"] not in have)
    credits = ["Shadow Puppeteer sounds: cut and levelled by tools/make_sounds.py from these recordings, all Creative Commons 0",
               "(https://creativecommons.org/publicdomain/zero/1.0/), checked on each sound's Freesound page.", ""]
    report = {}
    for name, (cat, sid, cut, mono) in PICK.items():
        c = next(c for c in A[cat] if c["id"] == sid)
        ch = 1 if mono else 2
        x = decode(src / c["file"], ch)
        if name == "ambience":
            a = int(10 * SR)
            n = int(cut * SR)
            xf = int(2.0 * SR)
            seg = x[a:a + n + xf].copy()
            w = np.linspace(0, 1, xf)[:, None]
            loop = seg[:n].copy()
            loop[:xf] = seg[:xf] * w + seg[n:n + xf] * (1 - w)       # the tail runs into the head: a seamless loop
            x = loop
        else:
            e = env(x)
            i = int(e.argmax())
            # the loudest event's onset: back from the peak to where it rose past 10% of it
            j = i
            while j > 0 and e[j] > e[i] * 0.1:
                j -= 1
            start = max(0, j - int(0.005 * SR))
            if cut:
                x = x[start:start + int(cut * SR)].copy()
            else:
                x = x[start:].copy()
                e2 = env(x)
                tail = np.where(e2 > e2.max() * 0.01)[0]
                x = x[: tail[-1] + int(0.05 * SR)].copy()
            x = fade(x, 0.003, min(0.04, len(x) / SR * 0.25))
        target_db = float(np.median([d["rms_active_db"] for d in A[cat] if d["id"] not in EXCLUDE])) + (AMB_DB if name == "ambience" else 0) + MIX.get(name, 0.0)
        g = 10 ** (target_db / 20) / max(active_rms(x), 1e-9)
        g = min(g, PEAK_MAX / max(np.abs(x).max(), 1e-9))
        x = np.clip(x * g, -1, 1)
        pcm = (x * 32767).astype("<i2")
        f = out / (name + ".wav")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", str(ch), "-i", "-", str(f)],
                       input=pcm.tobytes(), check=True)
        got = 20 * np.log10(active_rms(x))
        report[name] = {"id": sid, "dur": round(len(x) / SR, 2), "rms_active_db": round(got, 1), "target_db": round(target_db, 1),
                        "peak_db": round(20 * np.log10(np.abs(x).max()), 1)}
        credits.append(f"{name}.wav: \"{c['title']}\" by {c['user']}, {c['page']}")
        print(name, report[name])
    (out / "CREDITS.txt").write_text("\n".join(credits) + "\n", encoding="utf-8")
    (src / "chosen.json").write_text(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
