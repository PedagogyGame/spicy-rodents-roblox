"""Make the game's audio upload candidates OFFLINE (numpy + scipy + ffmpeg), and their manifest.

  python3 -I tools/audio/make_candidates.py [--out assets/audio/candidates] [--preview build/audio]

Roblox has no runtime synthesis (HANDOFF §3 rule 6), and every other sound in the game is from Roblox's licensed
library or Roblox's own; these are the few with nothing fitting there (docs/AUDIO_BUDGET.md "Uploads"). Each is
synthesised here from a fixed seed, so a rerun gives the same file: mono, 44.1 kHz, peak-normalised, faded in and
out, encoded as Ogg Vorbis. No recording or third-party audio is used, so there is no licence to track: the files
are the game's own (CC0-equivalent; made for Spicy Rodent). --preview also writes each as a WAV and a spectrogram
PNG for review. The lead listens, approves, uploads (tools/audio/publish.py) and records the ids.

Slots (the names Shared/Audio/Uploads uses):
  dog_bark      the yard dogs' "woof woof" (owner D16 #36: a custom bark): two short voiced barks, a friendly
                medium dog's, a quick rise and fall in pitch through a dog's open-mouth formants, a breath at the
                start of each; no growl
  bowling_roll  a ball rumbling down a lane, about 2.6 s: low filtered noise with the wooden lane's resonance,
                the ball's turn heard as a slow pulse, a little surface grit, getting further and duller, fading
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys

import numpy as np
from scipy import signal

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SR = 44100


def sos_band(lo, hi, order=2):
    return signal.butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")


def sos_low(f, order=4):
    return signal.butter(order, f, btype="lowpass", fs=SR, output="sos")


def sos_high(f, order=2):
    return signal.butter(order, f, btype="highpass", fs=SR, output="sos")


def resonator(x, f, q):
    """One formant: a peaking band of centre f and quality q."""
    b, a = signal.iirpeak(f, q, fs=SR)
    return signal.lfilter(b, a, x)


def fade(x, t_in, t_out):
    n_in, n_out = int(t_in * SR), int(t_out * SR)
    env = np.ones_like(x)
    if n_in > 0:
        env[:n_in] = np.linspace(0, 1, n_in) ** 2
    if n_out > 0:
        env[-n_out:] = np.linspace(1, 0, n_out) ** 2
    return x * env


def normalise(x, peak_db):
    peak = np.max(np.abs(x))
    return x * (10 ** (peak_db / 20) / peak) if peak > 0 else x


def woof(rng, dur, f_start, f_peak, f_end, level):
    """One bark: a voiced tone whose pitch jumps up and falls away, through open-mouth formants, with a breathy
    onset. Harmonics are summed directly (band-limited) so nothing aliases."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    # pitch: up fast over the first 20 %, then down (a bark's arc), a touch of jitter
    rise = np.clip(u / 0.2, 0, 1)
    fall = np.clip((u - 0.2) / 0.8, 0, 1)
    f0 = np.where(u < 0.2, f_start + (f_peak - f_start) * np.sin(rise * np.pi / 2),
                  f_peak + (f_end - f_peak) * fall ** 0.7)
    f0 = f0 * (1 + 0.012 * signal.sosfilt(sos_low(30), rng.standard_normal(n)) * 8)
    phase = 2 * np.pi * np.cumsum(f0) / SR
    src = np.zeros(n)
    for k in range(1, 40):
        alive = (k * f0) < 9000
        src += alive * np.sin(k * phase) / k ** 1.1
    # a little roughness on the attack only (a real bark's rasp), none after: friendly, not a growl
    rasp = 1 + 0.25 * np.exp(-t / 0.03) * np.sin(2 * np.pi * 70 * t)
    src *= rasp
    # open-mouth formants (a medium dog's "wuh"): around 650, 1250, 2600 Hz
    voiced = 1.0 * resonator(src, 650, 3.0) + 0.6 * resonator(src, 1250, 4.0) + 0.25 * resonator(src, 2600, 5.0)
    breath = signal.sosfilt(sos_band(900, 5000), rng.standard_normal(n)) * 0.35 * np.exp(-t / 0.025)
    x = voiced + breath
    env = (1 - np.exp(-t / 0.006)) * np.exp(-np.clip(t - 0.04, 0, None) / (dur * 0.3))
    return fade(x * env, 0, 0.03) * level  # (the tail closed, so no bark ends in a click)


def dog_bark(rng):
    total = np.zeros(int(0.78 * SR))
    for at, args in ((0.02, (0.20, 380, 560, 300, 1.0)), (0.36, (0.22, 360, 520, 280, 0.85))):
        w = woof(rng, *args)
        i = int(at * SR)
        total[i:i + len(w)] += w
    total = signal.sosfilt(sos_high(120), total)
    total = signal.sosfilt(sos_low(7000), total)
    return normalise(fade(total, 0.002, 0.05), -1.0)


def bowling_roll(rng):
    dur = 2.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    # the rumble: brown noise, low-passed, with the lane's boom (two wooden resonances)
    brown = np.cumsum(rng.standard_normal(n))
    brown = signal.sosfilt(sos_high(25, 2), brown)
    rumble = signal.sosfilt(sos_low(260), brown)
    rumble = rumble / np.max(np.abs(rumble))
    boom = resonator(rumble, 85, 4.0) * 0.8 + resonator(rumble, 140, 6.0) * 0.5
    # the ball's turn: a slow pulse, about 4.5 turns a second (a 16 lb ball at bowling speed), easing as it goes
    rev = 4.6 - 0.6 * u
    pulse = 1 + 0.22 * np.sin(2 * np.pi * np.cumsum(rev) / SR)
    # surface grit: a quiet band of hiss, duller and fainter as the ball goes away
    grit = signal.sosfilt(sos_band(700, 2600), rng.standard_normal(n)) * 0.05 * (1 - 0.7 * u)
    x = (rumble * 0.7 + boom) * pulse + grit
    # further away: duller (a sliding low-pass, done in short blocks) and quieter
    out = np.zeros(n)
    block = 2048
    zi = None
    for i in range(0, n, block):
        cut = 900 - 600 * min(1.0, (i / n))
        sos = sos_low(cut, 2)
        if zi is None:
            zi = signal.sosfilt_zi(sos) * 0
        seg, zi = signal.sosfilt(sos, x[i:i + block], zi=zi)
        out[i:i + block] = seg
    out *= (1 - 0.45 * u)
    out = signal.sosfilt(sos_high(35), out)
    return normalise(fade(out, 0.06, 0.45), -3.0)


SLOTS = [
    {
        "slot": "dog_bark", "cues": ["Dogs.Bark"], "make": dog_bark, "seed": 3601,
        "displayName": "SR yard dog bark",
        "description": "Spicy Rodent: a friendly medium dog's woof woof (synthesised offline, tools/audio).",
        "how": "synthesised offline (tools/audio/make_candidates.py dog_bark, seed 3601): two voiced barks, "
               "harmonics through three formants, a breathy onset, pitch arc 380->560->300 Hz",
    },
    {
        "slot": "bowling_roll", "cues": ["roll"], "make": bowling_roll, "seed": 5002,
        "displayName": "SR bowling ball roll",
        "description": "Spicy Rodent: a bowling ball rumbling down a wooden lane (synthesised offline, tools/audio).",
        "how": "synthesised offline (tools/audio/make_candidates.py bowling_roll, seed 5002): brown noise "
               "low-passed with two wooden resonances (85, 140 Hz), a 4-4.6 Hz rotation pulse, faint grit, a "
               "closing low-pass and fade as it goes away",
    },
]


def write_wav(path, x):
    from scipy.io import wavfile
    wavfile.write(path, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))


def encode_ogg(wav, ogg):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", wav, "-ac", "1", "-ar", str(SR),
                        "-c:a", "libvorbis", "-q:a", "5", "-map_metadata", "-1", "-fflags", "+bitexact",
                        "-flags:a", "+bitexact", ogg], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"ffmpeg failed for {wav}: {r.stderr}")


def spectrogram(path, x, title):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, (a, b) = plt.subplots(2, 1, figsize=(8, 5), sharex=True)
    t = np.arange(len(x)) / SR
    a.plot(t, x, lw=0.4)
    a.set_title(title)
    f, tt, s = signal.spectrogram(x, SR, nperseg=1024, noverlap=768)
    b.pcolormesh(tt, f, 10 * np.log10(s + 1e-12), shading="auto", vmin=-110, vmax=-30)
    b.set_ylim(0, 6000)
    b.set_xlabel("s")
    fig.tight_layout()
    fig.savefig(path, dpi=80)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "audio", "candidates"))
    ap.add_argument("--preview", default=None, help="also write WAVs and spectrograms here (e.g. build/audio)")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    tmp = os.path.join(ROOT, "build", "audio", "tmp")
    os.makedirs(tmp, exist_ok=True)
    manifest_path = os.path.join(out, "manifest.json")
    old = {}
    if os.path.exists(manifest_path):
        with open(manifest_path) as fh:
            old = {c["slot"]: c for c in json.load(fh).get("candidates", [])}
    rows = []
    for s in SLOTS:
        x = s["make"](np.random.default_rng(s["seed"]))
        wav = os.path.join(tmp, f"{s['slot']}.wav")
        write_wav(wav, x)
        ogg = os.path.join(out, f"{s['slot']}.ogg")
        encode_ogg(wav, ogg)
        if a.preview:
            os.makedirs(a.preview, exist_ok=True)
            write_wav(os.path.join(a.preview, f"{s['slot']}.wav"), x)
            spectrogram(os.path.join(a.preview, f"{s['slot']}.png"), x, s["slot"])
        with open(ogg, "rb") as fh:
            sha = hashlib.sha256(fh.read()).hexdigest()[:16]
        prev = old.get(s["slot"], {})
        rows.append({
            "slot": s["slot"],
            "cues": s["cues"],
            "file": os.path.relpath(ogg, ROOT),
            "seconds": round(len(x) / SR, 2),
            "channels": 1,
            "sampleRate": SR,
            "peakDb": round(20 * np.log10(np.max(np.abs(x))), 1),
            "how": s["how"],
            "licence": "the game's own: synthesised offline from code in this repository, no recording or "
                       "third-party audio (CC0-equivalent)",
            "displayName": s["displayName"],
            "description": s["description"],
            "sha": sha,
            # kept from the last run: what the lead recorded after uploading (tools/audio/publish.py --record)
            "assetId": prev.get("assetId") if prev.get("sha") == sha else None,
            "moderation": prev.get("moderation") if prev.get("sha") == sha else None,
            "approved": prev.get("approved", False) if prev.get("sha") == sha else False,
        })
        print(f"  {s['slot']}: {rows[-1]['seconds']} s, {os.path.getsize(ogg)} bytes, sha {sha}")
    doc = {
        "$schema": "audio/candidates v1",
        "src": "tools/audio/make_candidates.py (made offline); tools/audio/publish.py (the lead's upload record)",
        "uploadsPlanned": len(rows),
        "candidates": rows,
    }
    with open(manifest_path, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    print(f"wrote {os.path.relpath(manifest_path, ROOT)}")


if __name__ == "__main__":
    main()
