"""Make the game's audio upload candidates OFFLINE (numpy + scipy + ffmpeg), and their manifest.

  python3 -I tools/audio/make_candidates.py [--out assets/audio/candidates] [--preview build/audio]

Roblox has no runtime synthesis (HANDOFF §3 rule 6), and every other sound in the game is from Roblox's licensed
library or Roblox's own; these are the few with nothing fitting there (docs/AUDIO_BUDGET.md "Uploads"). Each is
synthesised here from a fixed seed, so a rerun gives the same file: mono, 44.1 kHz, loudness-normalised (ITU-R
BS.1770 integrated loudness, TARGET_LUFS) under a true-peak ceiling (TRUE_PEAK_DB), faded in and out, encoded as Ogg
Vorbis. No recording or third-party audio is used, so there is no licence to track: the files are the game's own
(CC0-equivalent; made for Spicy Rodent). --preview also writes each as a WAV and a spectrogram PNG for review. The
lead listens, approves, uploads (tools/audio/publish.py) and records the ids.

Slots (the names Shared/Audio/Uploads uses):
  dog_bark      the yard dogs' "woof woof" (owner D16 #36: a custom bark): two barks of a friendly medium dog, each
                a glottal pulse train (jitter, shimmer, a moment of period doubling for the bark's rasp) with
                breath noise, through a dog's time-varying vocal-tract formants (the mouth opening on "wuh" and
                closing on "f"), a noisy burst on the onset, the pitch jumping up then dropping; no growl
  dog_bark_v2   a second take of the bark (owner D33: "an improved dog bark"), a candidate to take over dog_bark's
                id: each bark a chest push and a noisy burst, a "w"/"r" glide opening into "uh", a pressed,
                irregular pulse train (period doubling, breath on every pulse) through five moving formants, a
                quick decay closing on a soft "f"; a touch of yard (a few short reflections, no reverb tail)
  bowling_roll  a ball rumbling down a wooden lane, 2.6 s: low noise through the lane's and the ball's resonances,
                the ball's turn as a lumpy once-a-turn pulse, rolling grit and irregular lane-board ticks (so it is
                heard on a phone speaker, not only as sub-bass), going away: a slight pitch drop, duller and
                quieter, a smooth fade
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys

import numpy as np
from scipy import signal
from scipy.ndimage import minimum_filter1d, uniform_filter1d

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SR = 44100
TARGET_LUFS = -15.0  # short effects sit at about -16 to -14 LUFS integrated
TRUE_PEAK_DB = -1.5  # before encoding; Vorbis can add a few tenths, and the files must stay at or under -1 dBTP


def sos_band(lo, hi, order=2, fs=SR):
    return signal.butter(order, [lo, hi], btype="bandpass", fs=fs, output="sos")


def sos_low(f, order=4, fs=SR):
    return signal.butter(order, f, btype="lowpass", fs=fs, output="sos")


def sos_high(f, order=2, fs=SR):
    return signal.butter(order, f, btype="highpass", fs=fs, output="sos")


def resonator(x, f, q, fs=SR):
    """A peaking band of centre f and quality q."""
    b, a = signal.iirpeak(f, q, fs=fs)
    return signal.lfilter(b, a, x)


def fade(x, t_in, t_out):
    """Raised-cosine fades: no corner at either end, so nothing clicks."""
    n_in, n_out = int(t_in * SR), int(t_out * SR)
    env = np.ones_like(x)
    if n_in > 0:
        env[:n_in] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n_in))
    if n_out > 0:
        env[-n_out:] = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n_out))
    return x * env


# ---- loudness (ITU-R BS.1770-4: K-weighting, 400 ms blocks at 75 % overlap, absolute and relative gates) ----

def _k_weighting(fs):
    # the standard's two stages, as RBJ biquads at any rate (the constants are the 48 kHz filters' fitted values)
    g, q, fc = 3.99984385397, 0.7071752369554193, 1681.9744509555319
    a_ = 10 ** (g / 40)
    w0 = 2 * np.pi * fc / fs
    al = np.sin(w0) / (2 * q)
    c = np.cos(w0)
    shelf = [a_ * ((a_ + 1) + (a_ - 1) * c + 2 * np.sqrt(a_) * al), -2 * a_ * ((a_ - 1) + (a_ + 1) * c),
             a_ * ((a_ + 1) + (a_ - 1) * c - 2 * np.sqrt(a_) * al),
             (a_ + 1) - (a_ - 1) * c + 2 * np.sqrt(a_) * al, 2 * ((a_ - 1) - (a_ + 1) * c),
             (a_ + 1) - (a_ - 1) * c - 2 * np.sqrt(a_) * al]
    q, fc = 0.5003270373253953, 38.13547087613982
    w0 = 2 * np.pi * fc / fs
    al = np.sin(w0) / (2 * q)
    c = np.cos(w0)
    high = [(1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al]
    sos = np.array([shelf, high])
    sos[:, :3] /= sos[:, 3:4]
    sos[:, 3:] /= sos[:, 3:4]
    return sos


def integrated_lufs(x):
    y = signal.sosfilt(_k_weighting(SR), x)
    block, step = int(0.4 * SR), int(0.1 * SR)
    z = np.array([np.mean(y[i:i + block] ** 2) for i in range(0, len(y) - block + 1, step)])
    if len(z) == 0:  # shorter than one block: the whole thing as one
        z = np.array([np.mean(y ** 2)])
    lk = -0.691 + 10 * np.log10(z + 1e-20)
    z = z[lk > -70]
    if len(z) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(z)) - 10
    z = z[-0.691 + 10 * np.log10(z) > rel]
    return float(-0.691 + 10 * np.log10(np.mean(z)))


def true_peak_db(x):
    """Peak of the 4x oversampled signal (BS.1770's true peak)."""
    return float(20 * np.log10(np.max(np.abs(signal.resample_poly(x, 4, 1))) + 1e-20))


def _limit(x, ceiling_db):
    """Pull the few peaks above the ceiling down with a smooth 3 ms gain dip (the averaged minimum never exceeds
    what each sample needs, so it never lets a peak through and never clips)."""
    ceiling = 10 ** (ceiling_db / 20)
    over = np.abs(signal.resample_poly(x, 4, 1))[: 4 * len(x)].reshape(-1, 4).max(axis=1)
    need = np.minimum(1.0, ceiling / np.maximum(over, 1e-12))
    w = int(0.003 * SR) | 1
    g = uniform_filter1d(minimum_filter1d(need, size=2 * w + 1, mode="nearest"), size=w, mode="nearest")
    return x * g


def loudness_normalise(x, lufs=TARGET_LUFS, ceiling_db=TRUE_PEAK_DB):
    """Gain to the integrated loudness asked for; any peak that would pass the true-peak ceiling is limited, then
    the loudness is re-aimed (a few rounds settle it)."""
    for _ in range(8):
        x = x * 10 ** ((lufs - integrated_lufs(x)) / 20)
        if true_peak_db(x) <= ceiling_db:
            break
        x = _limit(x, ceiling_db - 0.3)
    return x * min(1.0, 10 ** ((ceiling_db - true_peak_db(x)) / 20))


# ---- the dog's bark ----

def formant_cascade(x, fs, tracks, block=64):
    """x through a cascade of two-pole resonators (unity gain at 0 Hz, as in a Klatt synthesiser) whose centre and
    bandwidth follow per-sample tracks [(f, bw), ...]; the coefficients move every block, the state carries over."""
    out = np.empty_like(x)
    zi = np.zeros((len(tracks), 2))
    for i in range(0, len(x), block):
        sos = []
        for f, bw in tracks:
            r = np.exp(-np.pi * bw[i] / fs)
            c = 2 * r * np.cos(2 * np.pi * f[i] / fs)
            sos.append([1 - c + r * r, 0.0, 0.0, 1.0, -c, r * r])
        out[i:i + block], zi = signal.sosfilt(np.array(sos), x[i:i + block], zi=zi)
    return out


def glottal_train(rng, fs, n, f0_at, amp_at, closing_at, jitter, shimmer, rough):
    """The voice source: a Rosenberg pulse per period (rising cosine over the opening, falling over the closing,
    shut for the rest), its derivative taken (the lips' radiation). Each period's length wanders by `jitter` and
    each pulse's height by `shimmer`; where rough(u) > 0, alternate periods are longer and weaker (period doubling,
    the rasp in a bark). Returns the flow derivative and the flow (which gates the breath noise)."""
    flow = np.zeros(n + 1)
    t, k = 0, 0
    while t < n:
        u = t / n
        r = rough(u)
        alt = 1 if k % 2 == 0 else -1
        period = fs / f0_at(u) * (1 + jitter * rng.standard_normal()) * (1 + 0.06 * r * alt)
        period = max(period, fs / 1200)
        a = amp_at(u) * max(0.2, 1 + shimmer * rng.standard_normal()) * (1 - 0.35 * r * (alt < 0))
        n_open = int(period * 0.55)
        n_close = max(2, int(period * closing_at(u)))
        rise = 0.5 - 0.5 * np.cos(np.pi * np.arange(n_open) / n_open)
        fall = np.cos(0.5 * np.pi * np.arange(n_close) / n_close)
        pulse = a * np.concatenate([rise, fall])
        end = min(n, t + len(pulse))
        flow[t:end] += pulse[: end - t]
        t += int(round(period))
        k += 1
    return np.diff(flow) * fs / 1000, flow[:n]


def woof(rng, dur, f0s, level, fs):
    """One bark at rate fs. f0s = (start, peak, end) Hz: up in the first fifth, then down."""
    n = int(dur * fs)
    t = np.arange(n) / fs
    u = t / dur
    f_start, f_peak, f_end = f0s

    def f0_at(v):
        if v < 0.2:
            return f_start + (f_peak - f_start) * np.sin(v / 0.2 * np.pi / 2)
        return f_peak + (f_end - f_peak) * ((v - 0.2) / 0.8) ** 0.8

    def amp_at(v):
        return min(1.0, v / 0.03) * (1 - 0.55 * v) * (1 - max(0.0, (v - 0.75) / 0.25) ** 1.5)

    def closing_at(v):  # a short closing phase is a hard, bright pulse; it softens as the bark ends
        return 0.12 + 0.18 * v

    def rough(v):  # period doubling from 15 % to 50 % of the bark
        return float(np.clip(1 - abs(v - 0.32) / 0.18, 0, 1))

    dflow, flow = glottal_train(rng, fs, n, f0_at, amp_at, closing_at, jitter=0.03, shimmer=0.12, rough=rough)
    dflow /= np.max(np.abs(dflow)) + 1e-12
    flow /= np.max(flow) + 1e-12
    # breath: noise gated by the flow (pulse-synchronous) over a steady turbulence, strongest at the start and as
    # the mouth closes: a bark is a noisy, harsh voice (little harmonic-to-noise), never a clean tone
    breath = signal.sosfilt(sos_high(500, 2, fs), rng.standard_normal(n))
    breath *= (0.35 + 0.65 * flow) * (0.55 + 0.4 * np.exp(-t / 0.02) + 0.5 * np.clip((u - 0.7) / 0.3, 0, 1))
    env_amp = np.array([amp_at(v) for v in u[:: 64]]).repeat(64)[:n]
    breath *= np.maximum(env_amp, 0.15 * (u > 0.7) * (1 - u))
    # the mouth: "w" (rounded) opening to "uh", closing to "f" (a medium dog: formants about 1 kHz apart). The
    # first three in cascade carry the voice; the upper ones in parallel carry the breath's hiss and the rasp's top
    shape = np.clip(u / 0.15, 0, 1) * (1 - np.clip((u - 0.6) / 0.4, 0, 1))
    tracks = [
        (420 + 300 * shape, 110 + 60 * shape),
        (950 + 450 * shape, 150 + 60 * shape),
        (2350 + 250 * shape, 280 + np.zeros(n)),
    ]
    voiced = formant_cascade(dflow + 0.9 * breath, fs, tracks)
    voiced /= np.max(np.abs(voiced)) + 1e-12
    upper = 0.3 * dflow + breath
    upper = resonator(upper, 3600, 4.0, fs) + 0.7 * resonator(upper, 4800, 4.0, fs) + 0.4 * signal.sosfilt(
        sos_band(5500, 9000, 2, fs), upper)
    upper *= np.maximum(env_amp, 0.0)
    upper /= np.max(np.abs(upper)) + 1e-12
    # the onset: a short noisy burst, the air let go
    burst = signal.sosfilt(sos_band(1000, 7000, 2, fs), rng.standard_normal(n)) * np.exp(-t / 0.009)
    burst *= 1 - np.exp(-t / 0.0007)
    x = voiced + 0.3 * upper + 0.7 * burst / (np.max(np.abs(burst)) + 1e-12)
    return x * level


def dog_bark(rng):
    os_ = 2  # synthesised at 88.2 kHz and brought down, so the sharp pulses do not alias
    fs = SR * os_
    total = np.zeros(int(0.62 * fs))
    for at, dur, f0s, level in ((0.004, 0.21, (400, 590, 320), 1.0), (0.33, 0.25, (380, 550, 290), 0.85)):
        w = woof(rng, dur, f0s, level, fs)
        i = int(at * fs)
        total[i:i + len(w)] += w[: len(total) - i]
    x = signal.resample_poly(total, 1, os_)
    x = signal.sosfilt(sos_high(140, 4), x)
    x = signal.sosfilt(sos_low(9000, 4), x)
    return loudness_normalise(fade(x, 0.002, 0.02))


# ---- the dog's bark, second take (owner D33: "an improved dog bark") ----

def _track(u, points):
    """A smooth contour through (u, value) breakpoints (monotone cubic, so it never overshoots between them)."""
    from scipy.interpolate import PchipInterpolator
    us, vs = zip(*points)
    return PchipInterpolator(us, vs)(np.clip(u, 0, 1))


def glottal_train_v2(rng, fs, f0, amp, close_q, jitter, shimmer, sub, chaos):
    """The voice source, period by period, from per-sample tracks (each read at the period's start): a Rosenberg
    pulse (0.55 of the period opening, `close_q` of it closing; a short closing is a pressed, bright voice), its
    derivative taken (the lips' radiation). Each period's length wanders by `jitter` and its height by `shimmer`,
    both raised by `chaos` (the irregular patch at a bark's onset); where `sub` > 0 every other period is longer
    and weaker (period doubling: the subharmonic roughness of a bark, not a growl). Returns (flow', flow)."""
    n = len(f0)
    flow = np.zeros(n + 1)
    t, k = 0, 0
    while t < n:
        s, c = sub[t], chaos[t]
        alt = 1 if k % 2 == 0 else -1
        period = fs / f0[t] * (1 + (jitter + 0.08 * c) * rng.standard_normal()) * (1 + 0.07 * s * alt)
        period = max(period, fs / 1400)
        a = amp[t] * max(0.15, 1 + (shimmer + 0.2 * c) * rng.standard_normal()) * (1 - 0.45 * s * (alt < 0))
        n_open = int(period * 0.55)
        n_close = max(2, int(period * close_q[t]))
        rise = 0.5 - 0.5 * np.cos(np.pi * np.arange(n_open) / n_open)
        fall = np.cos(0.5 * np.pi * np.arange(n_close) / n_close)
        pulse = a * np.concatenate([rise, fall])
        end = min(n, t + len(pulse))
        flow[t:end] += pulse[: end - t]
        t += int(round(period))
        k += 1
    return np.diff(flow) * fs / 1000, flow[:n]


def woof_v2(rng, fs, dur, f0_pts, level, open_by=1.0):
    """One bark of a friendly medium dog at rate fs: a breath of `dur` seconds; f0_pts the pitch contour as (u, Hz)
    breakpoints over the bark (u = 0..1); `open_by` how wide the mouth opens (1 = the first bark).

    In order: a chest push (a low thump under the onset) and a noisy burst as the air is let go; a "w"/"r" glide
    (formants low, F3 dipped) opening fast into "uh"; the voiced body, a harsh pulse train (jitter, shimmer, an
    irregular patch at the onset, then period doubling) with breath riding on each pulse, through five formants
    of a ~14 cm vocal tract (dispersion about 1.1 kHz) that open and then close; a quick decay as the mouth
    closes ("f": the formants fall, a little labial hiss)."""
    n = int(dur * fs)
    t = np.arange(n) / fs
    u = t / dur
    # pitch: the breakpoints with a slow wander (a live voice never holds a line)
    wander = signal.sosfiltfilt(sos_low(18, 2, fs), rng.standard_normal(n))
    wander /= np.max(np.abs(wander)) + 1e-12
    f0 = _track(u, f0_pts) * (1 + 0.025 * wander)
    # loudness of the breath, in dB: up in ~3 ms, at its loudest by ~20 ms, held, then falling ~30 dB as the mouth
    # closes; the hard onset (chest-driven) is the loudest moment
    env_db = _track(u, [(0, -40), (0.012, -4), (0.05, 0), (0.3, -2.5), (0.55, -7), (0.8, -16), (1, -42)])
    amp = 10 ** (env_db / 20)
    close_q = _track(u, [(0, 0.06), (0.3, 0.09), (0.7, 0.16), (1, 0.28)])  # pressed and bright, softening
    sub = _track(u, [(0, 0), (0.14, 0), (0.24, 0.7), (0.45, 0.6), (0.58, 0), (1, 0)])
    chaos = _track(u, [(0, 1), (0.06, 0.8), (0.13, 0), (1, 0)])
    dflow, flow = glottal_train_v2(rng, fs, f0, amp, close_q, 0.025, 0.1, sub, chaos)
    dflow /= np.max(np.abs(dflow)) + 1e-12
    flow /= np.max(flow) + 1e-12
    # breath: turbulence riding on each pulse (pulse-synchronous) over a steady part, stronger at the onset and as
    # the mouth closes; it is what makes a bark harsh rather than a sung tone
    breath = signal.sosfilt(sos_high(400, 2, fs), rng.standard_normal(n))
    breath *= (0.3 + 0.7 * flow) * amp * _track(u, [(0, 1.6), (0.1, 0.9), (0.6, 0.9), (1, 1.5)])
    # the mouth: (u, Hz) per formant. "w"/"r" at the onset (lips rounded, F3 dipped), open "uh", closing on "f"
    o = open_by
    f1 = _track(u, [(0, 360), (0.07, 560 + 80 * o), (0.2, 700 + 140 * o), (0.5, 680 + 100 * o), (0.82, 520),
                    (1, 380)])
    f2 = _track(u, [(0, 820), (0.07, 1200), (0.2, 1450 + 200 * o), (0.5, 1450 + 120 * o), (0.82, 1150),
                    (1, 900)])
    f3 = _track(u, [(0, 1900), (0.1, 2450), (0.25, 2750), (0.7, 2700), (1, 2450)])
    f4 = _track(u, [(0, 3500), (0.2, 3900), (1, 3700)])
    f5 = _track(u, [(0, 4600), (0.2, 4900), (1, 4700)])
    bw1 = _track(u, [(0, 90), (0.2, 130), (0.8, 110), (1, 90)])  # an open mouth radiates more: wider
    tracks = [(f1, bw1)] + [(f, np.full(n, bw)) for f, bw in ((f2, 120.0), (f3, 160.0), (f4, 220.0), (f5, 320.0))]
    voiced = formant_cascade(dflow + 0.55 * breath / (np.max(np.abs(breath)) + 1e-12), fs, tracks)
    # an open mouth radiates the upper harmonics strongly: about +6 dB above ~2 kHz (a gentle shelf)
    voiced = voiced + signal.sosfilt(sos_high(2000, 1, fs), voiced)
    voiced /= np.max(np.abs(voiced)) + 1e-12
    # the hiss above the voice (breath through the upper formants, in parallel)
    hiss = breath * (0.5 + 0.5 * flow)
    hiss = resonator(hiss, 3900, 3.0, fs) + 0.7 * resonator(hiss, 5200, 3.0, fs) + 0.3 * signal.sosfilt(
        sos_band(6000, 10000, 2, fs), hiss)
    hiss /= np.max(np.abs(hiss)) + 1e-12
    # the onset: the air let go (a noisy burst, coloured by the still-rounded mouth) over a chest push
    burst = signal.sosfilt(sos_band(700, 6500, 2, fs), rng.standard_normal(n))
    burst = resonator(burst, 1100, 2.0, fs) + 0.8 * resonator(burst, 2600, 2.5, fs)
    burst *= (1 - np.exp(-t / 0.0006)) * np.exp(-t / 0.007)
    burst /= np.max(np.abs(burst)) + 1e-12
    chest = np.sin(2 * np.pi * 150 * t) * (1 - np.exp(-t / 0.002)) * np.exp(-t / 0.018)
    # the mouth closing: a soft labial "f" as the lips meet the teeth
    close = signal.sosfilt(sos_band(1500, 6000, 2, fs), rng.standard_normal(n))
    close *= np.exp(-((u - 0.93) / 0.04) ** 2)
    close /= np.max(np.abs(close)) + 1e-12
    x = voiced + 0.28 * hiss + 0.5 * burst + 0.35 * chest + 0.03 * close
    return x * level


def yard(x, rng, fs):
    """A touch of the yard (no reverb tail): the ground's reflection, a fence and the house wall a few metres off,
    each duller and quieter than the bark, then ~60 ms of faint scatter dying away."""
    ir = np.zeros(int(0.09 * fs))
    ir[0] = 1.0
    for ms, db_, cut in ((2.3, -10, 6000), (9.5, -16, 4500), (21.0, -19, 3500), (33.0, -25, 3000)):
        tap = np.zeros_like(ir)
        tap[int(ms / 1000 * fs)] = 10 ** (db_ / 20)
        ir += signal.sosfilt(sos_low(cut, 2, fs), tap)
    k = np.arange(len(ir)) / fs
    scatter = signal.sosfilt(sos_band(300, 4000, 2, fs), rng.standard_normal(len(ir)))
    scatter *= np.exp(-k / 0.014) * (k > 0.012)
    ir += scatter * np.sqrt(10 ** (-22 / 10) / np.sum(scatter ** 2))  # its energy 22 dB under the direct sound
    return signal.fftconvolve(x, ir)[: len(x)]


def dog_bark_v2(rng):
    os_ = 2  # synthesised at 88.2 kHz and brought down, so the sharp pulses do not alias
    fs = SR * os_
    total = np.zeros(int(0.68 * fs))
    barks = (  # at (s), breath (s), pitch breakpoints (u, Hz), level, mouth
        (0.003, 0.2, [(0, 520), (0.1, 640), (0.45, 520), (1, 360)], 1.0, 1.0),
        (0.37, 0.23, [(0, 480), (0.13, 600), (0.5, 470), (1, 320)], 0.88, 0.85),
    )
    for at, dur, f0_pts, level, open_by in barks:
        w = woof_v2(rng, fs, dur, f0_pts, level, open_by)
        i = int(at * fs)
        total[i:i + len(w)] += w[: len(total) - i]
    total = yard(total, rng, fs)
    x = signal.resample_poly(total, 1, os_)
    x = signal.sosfilt(sos_high(90, 4), x)
    x = signal.sosfilt(sos_low(11000, 4), x)
    return loudness_normalise(fade(x, 0.001, 0.03))


# ---- the bowling ball ----

def bowling_roll(rng):
    dur = 2.6
    n = int(dur * SR)
    m = n + SR // 10  # a little more body, read slower below
    t = np.arange(m) / SR
    u = np.clip(t / dur, 0, 1)
    # the ball's turn: about 5 turns a second (a club bowler's rev rate), a lumpy once-a-turn pulse (the finger
    # holes and the weight block), easing as it goes
    rev = 5.2 - 0.7 * u
    ph = 2 * np.pi * np.cumsum(rev) / SR
    turn = 1 + 0.2 * np.sin(ph) + 0.09 * np.sin(2 * ph + 1.3) + 0.05 * np.sin(3 * ph + 0.4)
    # the rumble: noise through the lane's and the ball's resonances (wooden boards on a hollow bed, a dense ball)
    pink = signal.sosfilt(sos_low(400, 1), rng.standard_normal(m))
    pink = signal.sosfilt(sos_high(45, 2), pink)
    modes = ((72, 5, 0.9), (108, 7, 1.0), (165, 8, 0.75), (240, 9, 0.55), (330, 10, 0.4), (470, 12, 0.28),
             (690, 14, 0.16))
    body = sum(g * resonator(pink, f, q) for f, q, g in modes)
    body = body / np.max(np.abs(body))
    # rolling grit: a dense rain of tiny contacts (the lane's grain and dust), band-limited
    rain = np.zeros(m)
    hits = np.cumsum(rng.exponential(1 / 260, int(dur * 400)))
    hits = (hits[hits < m / SR] * SR).astype(int)
    rain[hits] = rng.exponential(1.0, len(hits))
    grain = signal.sosfilt(sos_band(500, 3800, 2), rain + 0.35 * rng.standard_normal(m))
    grain = resonator(grain, 900, 2.0) + 0.6 * resonator(grain, 1700, 3.0) + 0.3 * grain
    grain = grain / np.max(np.abs(grain))
    # lane-board ticks: irregular, about 8 a second; each a short wooden click with a little knock under it
    ticks = np.zeros(m)
    gaps = rng.uniform(0.07, 0.18, int(dur * 15))
    tick_t = np.cumsum(gaps)
    tick_t = tick_t[tick_t < dur - 0.3]
    k = np.arange(int(0.012 * SR)) / SR
    for at in tick_t:
        f = rng.uniform(1300, 2300)
        click = np.sin(2 * np.pi * f * k) * np.exp(-k / 0.003) + 0.8 * np.sin(2 * np.pi * 210 * k) * np.exp(
            -k / 0.006)
        i = int(at * SR)
        ticks[i:i + len(k)] += rng.uniform(0.4, 1.0) * click[: m - i]
    ticks = ticks / (np.max(np.abs(ticks)) + 1e-12)
    x = body * turn + 0.32 * grain * (0.85 + 0.3 * (turn - 1)) + 0.5 * ticks
    # going away: read slightly slower as it goes (every resonance drops about 3 %, doppler-ish), duller, quieter
    rate = 1 - 0.03 * np.linspace(0, 1, n)
    pos = np.cumsum(rate) - rate[0]
    x = np.interp(pos, np.arange(m), x)
    out = np.zeros(n)
    block = 1024
    zi = None
    for i in range(0, n, block):
        cut = 5200 * (1400 / 5200) ** min(1.0, i / n)  # a sliding low-pass, 5.2 kHz to 1.4 kHz
        sos = sos_low(cut, 2)
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        seg, zi = signal.sosfilt(sos, x[i:i + block], zi=zi)
        out[i:i + block] = seg
    out *= 10 ** (-9 * np.linspace(0, 1, n) / 20)  # 9 dB quieter by the pins
    out = signal.sosfilt(sos_high(40, 4), out)
    return loudness_normalise(fade(out, 0.03, 0.7))


SLOTS = [
    {
        "slot": "dog_bark", "cues": ["Dogs.Bark"], "make": dog_bark, "seed": 3601,
        "displayName": "SR yard dog bark",
        "description": "Spicy Rodent: a friendly medium dog's woof woof (synthesised offline, tools/audio).",
        "how": "synthesised offline (tools/audio/make_candidates.py dog_bark, seed 3601): two barks, each a glottal "
               "pulse train (3 % jitter, 12 % shimmer, a moment of period doubling) with pulse-synchronous breath "
               "through three time-varying formants (the mouth opening on 'wuh', closing on 'f') and two upper "
               "ones for the hiss, a noise burst on each onset, pitch 400->590->320 and 380->550->290 Hz; loudness-normalised",
    },
    {
        # a second take of the bark (owner D33): once uploaded it takes over dog_bark's id (tools/audio/publish.py
        # --record dog_bark=<assetId> records the id onto this take and points the game's slot at this file)
        "slot": "dog_bark_v2", "replaces": "dog_bark", "cues": ["Dogs.Bark"], "make": dog_bark_v2, "seed": 3602,
        "displayName": "SR yard dog bark 2",
        "description": "Spicy Rodent: a friendly medium dog's woof woof, second take (synthesised offline, "
                       "tools/audio).",
        "how": "synthesised offline (tools/audio/make_candidates.py dog_bark_v2, seed 3602): two barks (0.20 and "
               "0.23 s of breath, 0.37 s apart), each a chest push and a noisy burst at the onset, a 'w'/'r' glide "
               "(low formants, F3 dipped) opening into 'uh', a pressed pulse train (2.5 % jitter, 10 % shimmer, an "
               "irregular onset, then period doubling) with pulse-synchronous breath through five moving formants "
               "(F1 360->840->380, F2 820->1650->900 Hz), pitch 520->640->360 and 480->600->320 Hz, a quick decay "
               "closing on a soft 'f'; a touch of yard (ground, fence and wall reflections, 60 ms of faint "
               "scatter, no reverb tail); loudness-normalised",
    },
    {
        "slot": "bowling_roll", "cues": ["roll"], "make": bowling_roll, "seed": 5002,
        "displayName": "SR bowling ball roll",
        "description": "Spicy Rodent: a bowling ball rumbling down a wooden lane (synthesised offline, tools/audio).",
        "how": "synthesised offline (tools/audio/make_candidates.py bowling_roll, seed 5002): noise through seven "
               "lane and ball resonances (72-690 Hz), a lumpy 5.2->4.5 Hz once-a-turn pulse, rolling grit "
               "(a rain of tiny contacts, 0.5-3.8 kHz) and irregular lane-board ticks, going away: a 3 % "
               "doppler-ish pitch drop, a closing low-pass, 9 dB quieter, a 0.7 s fade; loudness-normalised",
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


def decode_ogg(ogg):
    """The encoded file as the game will play it (float, mono, 44.1 kHz)."""
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", ogg, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                       capture_output=True)
    if r.returncode != 0:
        sys.exit(f"ffmpeg cannot decode {ogg}")
    return np.frombuffer(r.stdout, dtype=np.float32).astype(np.float64)


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
        y = decode_ogg(ogg)  # measured as encoded: what will be uploaded
        lufs, tp = integrated_lufs(y), true_peak_db(y)
        if tp > -1.0 or abs(lufs - TARGET_LUFS) > 0.5:
            sys.exit(f"{s['slot']}: encoded at {lufs:.1f} LUFS, {tp:.2f} dBTP (want {TARGET_LUFS} LUFS, <= -1 dBTP)")
        prev = old.get(s["slot"], {})
        rows.append({
            "slot": s["slot"],
            **({"replaces": s["replaces"]} if s.get("replaces") else {}),
            "cues": s["cues"],
            "file": os.path.relpath(ogg, ROOT),
            "seconds": round(len(x) / SR, 2),
            "channels": 1,
            "sampleRate": SR,
            "peakDb": round(20 * np.log10(np.max(np.abs(y))), 1),
            "truePeakDb": round(tp, 1),
            "loudnessLufs": round(lufs, 1),
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
        print(f"  {s['slot']}: {rows[-1]['seconds']} s, {os.path.getsize(ogg)} bytes, {lufs:.1f} LUFS, "
              f"{tp:.1f} dBTP, sha {sha}")
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
