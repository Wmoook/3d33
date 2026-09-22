"""Procedural audio generator for EX Odyssey (SFX + ambient music beds).

Run:  python assets/audio/gen_audio.py
Writes 16-bit WAVs into assets/audio/sfx/ and assets/audio/music/.
Everything is synthesized (no samples): additive/FM voices, filtered noise, and a
synthetic convolution reverb. Music beds are seamless loops (tail crossfaded into head).
"""
import os
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
ROOT = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(1337)


# ---------------------------------------------------------------- helpers
def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def env_adsr(n, a, d, s, r, sustain_level=0.7):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(n - a - d - r, 0)
    e = np.concatenate([
        np.linspace(0, 1, a, endpoint=False) ** 1.5 if a else np.zeros(0),
        np.linspace(1, sustain_level, d, endpoint=False) if d else np.zeros(0),
        np.full(s_n, sustain_level),
        np.linspace(sustain_level, 0, r) ** 2 if r else np.zeros(0),
    ])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def env_exp(n, decay, attack=0.002):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-t / decay)


def noise(n):
    return rng.standard_normal(n)


def pink(n):
    w = np.fft.rfft(noise(n))
    f = np.arange(len(w)) + 1.0
    w /= np.sqrt(f)
    x = np.fft.irfft(w, n)
    return x / (np.max(np.abs(x)) + 1e-9)


def brown(n):
    x = np.cumsum(noise(n))
    x = signal.sosfilt(signal.butter(1, 20, 'hp', fs=SR, output='sos'), x)
    return x / (np.max(np.abs(x)) + 1e-9)


def lp(x, fc, order=2):
    return signal.sosfilt(signal.butter(order, min(fc, SR * 0.45), 'lp', fs=SR, output='sos'), x)


def hp(x, fc, order=2):
    return signal.sosfilt(signal.butter(order, fc, 'hp', fs=SR, output='sos'), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, min(hi, SR * 0.45)], 'bp', fs=SR, output='sos'), x)


def sweep_lp(x, f0, f1, curve=1.0):
    """Time-varying one-pole lowpass (cheap filter sweep)."""
    n = len(x)
    fc = f0 + (f1 - f0) * (np.linspace(0, 1, n) ** curve)
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.empty(n)
    z = 0.0
    for i in range(n):
        z = (1 - a[i]) * x[i] + a[i] * z
        y[i] = z
    return y


def osc_saw(freq, t, detune_cents=(0,), phase_rand=True):
    out = np.zeros_like(t)
    for c in detune_cents:
        f = freq * 2 ** (c / 1200)
        ph = rng.random() if phase_rand else 0
        out += 2 * ((f * t + ph) % 1.0) - 1
    return out / len(detune_cents)


def sine(freq, t, ph=0.0):
    return np.sin(2 * np.pi * freq * t + ph)


def make_ir(dur, decay, bright=6000, predelay=0.01, stereo=True):
    n = int(dur * SR)
    t = np.arange(n) / SR
    chans = []
    for _ in range(2 if stereo else 1):
        ir = noise(n) * np.exp(-t / decay)
        ir = lp(ir, bright)
        ir[: int(predelay * SR)] = 0
        chans.append(ir / np.sqrt(np.sum(ir ** 2)))
    return chans


def reverb(x, dur=2.5, decay=0.8, mix=0.3, bright=6000):
    """x: mono or (n,2). Returns stereo (n + tail, 2)."""
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    irs = make_ir(dur, decay, bright)
    n = x.shape[0] + len(irs[0]) - 1
    out = np.zeros((n, 2))
    for c in range(2):
        wet = signal.fftconvolve(x[:, c], irs[c])
        out[:, c] = wet * mix
        out[: x.shape[0], c] += x[:, c] * (1 - mix * 0.5)
    return out


def pan(x, p):
    """p in [-1,1]; constant power."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], 1)


def normalize(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-9
    return x * (peak / m)


def fade(x, fin=0.003, fout=0.02):
    n = x.shape[0]
    a, b = int(fin * SR), int(fout * SR)
    e = np.ones(n)
    if a:
        e[:a] = np.linspace(0, 1, a)
    if b:
        e[-b:] *= np.linspace(1, 0, b)
    return x * (e[:, None] if x.ndim == 2 else e)


def write(path, x, peak=0.89):
    x = normalize(fade(x), peak)
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    wavfile.write(path, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    print("wrote", os.path.relpath(path, ROOT), f"{x.shape[0] / SR:.2f}s")


def bell(freq, dur, decay=0.6, partials=((1, 1), (2.76, 0.45), (5.4, 0.25), (8.93, 0.12)), bright=1.0):
    t = t_axis(dur)
    n = len(t)
    out = np.zeros(n)
    for ratio, amp in partials:
        d = decay / (1 + ratio * 0.35 * bright)
        out += amp * sine(freq * ratio, t, rng.random() * 6.28) * env_exp(n, d, 0.001)
    return out


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# ---------------------------------------------------------------- SFX
def sfx_jump():
    d = 0.32
    t = t_axis(d)
    n = len(t)
    # airy whoosh rising
    w = sweep_lp(noise(n), 500, 3200, 0.7) * env_adsr(n, 0.01, 0.08, 0.3, 0.2, 0.4)
    w = hp(w, 300)
    # soft tonal blip rising (pitch glide)
    f = 330 * 2 ** (np.linspace(0, 0.6, n))
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) * 0.35 * env_exp(n, 0.07, 0.004) + np.sin(2 * ph) * 0.08 * env_exp(n, 0.04)
    return reverb(w * 0.55 + tone, 0.8, 0.18, 0.15)


def sfx_land():
    d = 0.45
    t = t_axis(d)
    n = len(t)
    thump = sine(55 * np.exp(-t * 7), t) * env_exp(n, 0.09, 0.001)
    body = lp(noise(n), 400) * env_exp(n, 0.05, 0.001) * 1.6
    grit = bp(noise(n), 1500, 5000) * env_exp(n, 0.018, 0.0005) * 0.35
    return reverb(thump * 0.9 + body + grit, 0.9, 0.2, 0.12, 3000)


def sfx_coin():
    d = 1.3
    a = bell(midi(88), d, 0.9, ((1, 1), (2.0, 0.3), (3.01, 0.18), (4.2, 0.06)))
    b = np.pad(bell(midi(95), d - 0.07, 0.8, ((1, 1), (2.0, 0.25), (3.0, 0.1))), (int(0.07 * SR), 0))[: len(a)]
    sparkle = hp(noise(len(a)), 7000) * env_exp(len(a), 0.08) * 0.12
    x = np.stack([a * 0.7 + b * 0.45 + sparkle, a * 0.45 + b * 0.7 + sparkle], 1)
    return reverb(x, 1.6, 0.45, 0.28, 9000)


def sfx_blue_coin():
    d = 1.6
    parts = []
    for i, m in enumerate([84, 91, 96, 103]):
        s = bell(midi(m), d, 1.1, ((1, 1), (2.0, 0.2), (3.0, 0.1)))
        parts.append(np.pad(s, (int(i * 0.045 * SR), 0))[: int(d * SR)] * (0.9 - i * 0.12))
    x = sum(pan(p, (-0.5 + i / 3)) for i, p in enumerate(parts))
    shimmer = hp(noise(int(d * SR)), 9000) * env_exp(int(d * SR), 0.25) * 0.08
    x += np.stack([shimmer, shimmer], 1)
    return reverb(x, 2.2, 0.7, 0.35, 10000)


def sfx_key():
    d = 2.0
    n = int(d * SR)
    x = np.zeros((n, 2))
    notes = [72, 76, 79, 84, 88]
    for i, m in enumerate(notes):
        s = bell(midi(m), d, 1.0, ((1, 1), (2.0, 0.4), (3.0, 0.2), (4.0, 0.08)))
        s = np.pad(s, (int(i * 0.06 * SR), 0))[:n]
        x += pan(s * (0.8 - i * 0.07), -0.6 + i * 0.3)
    t = t_axis(d)
    swell = sweep_lp(noise(n), 800, 6000, 0.5) * env_adsr(n, 0.25, 0.3, 0.2, 1.2, 0.3) * 0.12
    pad = osc_saw(midi(60), t, (-8, 0, 7)) + osc_saw(midi(67), t, (-6, 5))
    pad = lp(pad, 1800) * env_adsr(n, 0.15, 0.4, 0.4, 1.3, 0.4) * 0.18
    x += np.stack([swell + pad, swell + pad], 1)
    return reverb(x, 2.5, 0.8, 0.35, 9000)


def sfx_key_expired():
    d = 1.2
    n = int(d * SR)
    x = np.zeros(n)
    for i, m in enumerate([84, 79, 76, 72]):
        s = bell(midi(m), d, 0.5, ((1, 1), (2.0, 0.3), (3.0, 0.1)))
        x += np.pad(s, (int(i * 0.08 * SR), 0))[:n] * (0.8 - i * 0.1)
    return reverb(lp(x, 5000), 1.8, 0.6, 0.3, 6000)


def sfx_portal():
    d = 1.1
    t = t_axis(d)
    n = len(t)
    nz = noise(n)
    # phaser-like swept band noise
    f = 300 * 2 ** (np.sin(np.linspace(0, np.pi, n)) * 4)
    y = np.zeros(n)
    z1 = z2 = 0.0
    for i in range(n):  # state-variable bandpass sweep
        fc = 2 * np.sin(np.pi * f[i] / SR)
        hp_ = nz[i] - z1 * 0.35 - z2
        z1 += fc * hp_
        z2 += fc * z1
        y[i] = z1
    y = y / (np.max(np.abs(y)) + 1e-9) * env_adsr(n, 0.12, 0.2, 0.6, 0.6, 0.6)
    fm = sine(midi(57) * (1 + 0.5 * np.linspace(1, 0, n)), t + 0.004 * sine(170, t)) * env_adsr(n, 0.05, 0.3, 0.3, 0.6, 0.3) * 0.35
    x = np.stack([y * (0.6 + 0.4 * np.sin(t * 9)), y * (0.6 + 0.4 * np.cos(t * 9))], 1) + np.stack([fm, fm], 1)
    return reverb(x, 1.8, 0.55, 0.35, 7000)


def sfx_death():
    d = 1.6
    t = t_axis(d)
    n = len(t)
    boom = sine(48 * np.exp(-t * 2), t) * env_exp(n, 0.35, 0.002)
    crack = lp(noise(n), 2500) * env_exp(n, 0.06, 0.0005) * 1.2
    f = 520 * 2 ** (-np.linspace(0, 2.2, n))
    ph = 2 * np.pi * np.cumsum(f) / SR
    wail = np.tanh(3 * (np.sin(ph) + 0.4 * np.sin(1.5 * ph))) * env_adsr(n, 0.02, 0.3, 0.3, 0.9, 0.4) * 0.25
    x = boom + crack + lp(wail, 3000)
    return reverb(x, 2.4, 0.8, 0.35, 4000)


def sfx_respawn():
    d = 1.5
    t = t_axis(d)
    n = len(t)
    swell = sweep_lp(noise(n), 200, 7000, 2.0) * (np.linspace(0, 1, n) ** 3) * 0.5
    swell[int(n * 0.55):] *= np.linspace(1, 0, n - int(n * 0.55)) ** 2
    ch = np.zeros(n)
    start = int(0.55 * d * SR)
    for i, m in enumerate([79, 83, 86, 91]):
        s = bell(midi(m), d, 0.7)[: n - start - int(i * 0.03 * SR)]
        ch[start + int(i * 0.03 * SR): start + int(i * 0.03 * SR) + len(s)] += s * 0.4
    return reverb(swell + ch, 2.0, 0.6, 0.3, 9000)


def sfx_crown():
    d = 3.0
    t = t_axis(d)
    n = len(t)
    x = np.zeros((n, 2))
    for i, m in enumerate([60, 64, 67, 72, 76, 79, 84]):
        v = (osc_saw(midi(m), t, (-9, 0, 8)) * 0.6 + sine(midi(m), t) * 0.4)
        v = lp(v, 2800) * env_adsr(n, 0.02 + i * 0.03, 0.4, 0.55, 1.6, 0.5)
        x += pan(v * 0.25, -0.7 + i * 0.23)
    x += np.stack([bell(midi(96), d, 1.5)] * 2, 1) * 0.3
    return reverb(x, 3.0, 1.1, 0.4, 8000)


def sfx_gravity():
    d = 0.5
    t = t_axis(d)
    n = len(t)
    f = 90 + 60 * np.sin(np.linspace(0, np.pi, n))
    ph = 2 * np.pi * np.cumsum(f) / SR
    wub = np.tanh(2 * np.sin(ph)) * env_adsr(n, 0.02, 0.1, 0.5, 0.3, 0.5)
    return reverb(lp(wub, 900) * 0.8, 1.0, 0.3, 0.2, 3000)


def sfx_ui_move():
    d = 0.18
    b = bell(midi(91), d, 0.05, ((1, 1), (2, 0.2)))
    return reverb(b * 0.5, 0.5, 0.15, 0.2, 9000)


def sfx_ui_select():
    d = 0.7
    a = bell(midi(84), d, 0.35, ((1, 1), (2, 0.3), (3, 0.1)))
    b = np.pad(bell(midi(91), d, 0.35, ((1, 1), (2, 0.3))), (int(0.05 * SR), 0))[: len(a)]
    return reverb(a * 0.5 + b * 0.5, 1.4, 0.5, 0.3, 9000)


def sfx_title_hit():
    d = 6.0
    t = t_axis(d)
    n = len(t)
    boom = sine(38 * np.exp(-t * 0.6) + 12, t) * env_exp(n, 1.6, 0.004)
    body = lp(brown(n), 300) * env_exp(n, 0.9, 0.002) * 0.9
    hit = lp(noise(n), 3500) * env_exp(n, 0.08, 0.0008) * 0.7
    chord = np.zeros(n)
    for m in [36, 43, 48, 55, 60, 63]:
        chord += osc_saw(midi(m), t, (-12, -4, 5, 11))
    chord = lp(chord, 1200) * env_adsr(n, 0.05, 1.5, 0.35, 3.8, 0.35) * 0.18
    shimmer = hp(noise(n), 6000) * env_adsr(n, 0.8, 1.0, 0.2, 3.5, 0.15) * 0.1
    x = boom + body + hit + chord + shimmer
    return reverb(x, 5.0, 1.8, 0.45, 5000)


def sfx_zone():
    d = 4.0
    t = t_axis(d)
    n = len(t)
    gong = np.zeros(n)
    for r, a in [(1, 1), (1.47, 0.5), (2.09, 0.35), (2.56, 0.25), (3.9, 0.12)]:
        gong += a * sine(midi(38) * r, t, rng.random() * 6) * env_exp(n, 2.2 / r, 0.01)
    swell = sweep_lp(noise(n), 300, 2500, 0.5) * env_adsr(n, 0.6, 0.8, 0.2, 2.0, 0.2) * 0.12
    return reverb(gong * 0.6 + swell, 4.0, 1.5, 0.4, 4000)


# ---------------------------------------------------------------- music beds
def loopify(x, xfade):
    """x has length L+xfade. Crossfade tail into head for a seamless loop of length L."""
    L = x.shape[0] - xfade
    head = x[:xfade].copy()
    tail = x[L:L + xfade]
    w = np.linspace(0, 1, xfade)[:, None] if x.ndim == 2 else np.linspace(0, 1, xfade)
    out = x[:L].copy()
    out[:xfade] = tail * np.sqrt(1 - w) + head * np.sqrt(w)
    return out


def write_loop(name, x, xfade_s=3.0, peak=0.7):
    x = loopify(x, int(xfade_s * SR))
    x = normalize(x, peak)
    path = os.path.join(ROOT, "music", name + ".wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    wavfile.write(path, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    print("wrote", os.path.relpath(path, ROOT), f"{x.shape[0] / SR:.1f}s loop")


def pad_voice(freqs, t, env, cutoff=1400, detune=(-11, -4, 3, 10), wobble=0.12):
    v = np.zeros_like(t)
    for f in freqs:
        v += osc_saw(f, t, detune) + 0.5 * sine(f * 0.5, t)
    # slow breathing filter via crossfading two lowpass versions
    lo = lp(v, cutoff * 0.5)
    hi = lp(v, cutoff)
    m = 0.5 + 0.5 * np.sin(2 * np.pi * wobble * t + rng.random() * 6)
    return (lo * (1 - m) + hi * m) * env


def chord_track(dur, chords, seg, cutoff, gain=0.1, detune=(-11, -4, 3, 10), wobble=0.1):
    """chords: list of midi-note lists, each held seg seconds with overlap."""
    n = int(dur * SR)
    out = np.zeros(n)
    t_full = t_axis(dur)
    for i, ch in enumerate(chords):
        start = int(i * seg * SR)
        length = int((seg + seg * 0.6) * SR)
        if start >= n:
            break
        length = min(length, n - start)
        t = t_full[:length]
        e = env_adsr(length, seg * 0.45, 0.1, seg * 0.6, seg * 0.6, 0.9)
        out[start:start + length] += pad_voice([midi(m) for m in ch], t, e, cutoff, detune, wobble)
    return out * gain


def drips(dur, rate, pitch_lo, pitch_hi, gain):
    n = int(dur * SR)
    out = np.zeros((n, 2))
    k = int(dur * rate)
    for _ in range(k):
        s = int(rng.random() * (n - SR))
        f = rng.uniform(pitch_lo, pitch_hi)
        ln = int(0.12 * SR)
        t = np.arange(ln) / SR
        fr = f * (1 + 1.2 * np.exp(-t * 60))
        d = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 35)
        out[s:s + ln] += pan(d * rng.uniform(0.4, 1.0), rng.uniform(-0.8, 0.8))
    return out * gain


def wind(dur, lo, hi, gain, gust=0.07):
    n = int(dur * SR)
    t = t_axis(dur)
    chans = []
    for c in range(2):
        w = pink(n)
        g = 0.55 + 0.45 * np.sin(2 * np.pi * gust * t + c * 1.3 + rng.random() * 6) * np.sin(2 * np.pi * gust * 0.37 * t + rng.random() * 6)
        w = bp(w, lo, hi) * g
        # whistle resonance
        chans.append(w)
    out = np.stack(chans, 1)
    return out / (np.max(np.abs(out)) + 1e-9) * gain


def crackle(dur, rate, gain):
    n = int(dur * SR)
    out = np.zeros((n, 2))
    k = int(dur * rate)
    for _ in range(k):
        s = int(rng.random() * (n - 2000))
        ln = int(rng.uniform(0.002, 0.02) * SR)
        c = noise(ln) * np.exp(-np.arange(ln) / (ln * 0.3))
        out[s:s + ln] += pan(c * rng.uniform(0.2, 1.0) ** 2, rng.uniform(-0.9, 0.9))
    out[:, 0] = bp(out[:, 0], 800, 9000)
    out[:, 1] = bp(out[:, 1], 800, 9000)
    roar = np.stack([lp(brown(n), 350), lp(brown(n), 350)], 1)
    return out * gain + roar * gain * 0.6


def crickets(dur, gain):
    n = int(dur * SR)
    out = np.zeros((n, 2))
    t = t_axis(dur)
    for k in range(3):
        f = rng.uniform(4200, 5200)
        chirp_rate = rng.uniform(2.5, 3.6)
        gate = (np.sin(2 * np.pi * chirp_rate * t + rng.random() * 6) > 0.6).astype(float)
        gate = lp(gate, 60)
        trill = (np.sin(2 * np.pi * 40 * t) > 0).astype(float)
        c = sine(f, t) * gate * lp(trill, 400) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * t + k * 2))
        out += pan(c, -0.7 + k * 0.7)
    return out * gain


def stereoize(x, width=0.012):
    d = int(width * SR)
    return np.stack([x, np.concatenate([np.zeros(d), x[:-d]])], 1)


def music_title(dur):
    t = t_axis(dur)
    n = len(t)
    # D minor epic: Dm - Bb - F - C - Dm - Gm - Bb - A
    chords = [[38, 50, 57, 62, 65], [34, 46, 53, 58, 62], [41, 53, 60, 65, 69], [36, 48, 55, 60, 64],
              [38, 50, 57, 62, 65], [43, 55, 58, 62, 67], [34, 46, 53, 58, 65], [33, 45, 52, 57, 61]]
    seg = dur / len(chords)
    pad = chord_track(dur, chords, seg, 1600, 0.09)
    sub = np.zeros(n)
    for i, ch in enumerate(chords):
        s0, s1 = int(i * seg * SR), int((i + 1) * seg * SR)
        sub[s0:s1] = sine(midi(ch[0] - 12), t[s0:s1]) * 0.25
    sub = lp(sub, 120)
    # slow bell melody
    mel = np.zeros(n)
    melody = [74, 72, 69, 67, 69, 70, 69, 65, 62, 64, 65, 69]
    step = dur / len(melody)
    for i, m in enumerate(melody):
        s = bell(midi(m), min(4.0, dur), 1.8, ((1, 1), (2, 0.25), (3, 0.12), (4.01, 0.04)))
        st = int(i * step * SR)
        e = min(n, st + len(s))
        mel[st:e] += s[: e - st] * 0.16
    air = wind(dur, 300, 2500, 0.05, 0.05)
    x = stereoize(pad + sub) + stereoize(mel, 0.02) + air
    return reverb(x, 5.0, 2.2, 0.45, 5000)[:n]


def music_surface(dur):
    t = t_axis(dur)
    n = len(t)
    # night: Am9-Fmaj7-Cadd9-Em7, soft and wide
    chords = [[45, 57, 64, 67, 71], [41, 53, 60, 64, 69], [48, 55, 62, 64, 67], [40, 52, 59, 62, 67]] * 2
    seg = dur / len(chords)
    pad = chord_track(dur, chords, seg, 1100, 0.07, wobble=0.07)
    mel = np.zeros(n)
    notes = [76, 79, 83, 81, 76, 74, 72, 71]
    for i, m in enumerate(notes):
        st = int((i * dur / len(notes) + rng.uniform(0, 1.5)) * SR)
        s = bell(midi(m), 3.5, 1.4, ((1, 1), (2, 0.15), (3, 0.05))) * 0.09
        e = min(n, st + len(s))
        mel[st:e] += s[: e - st]
    x = stereoize(pad) + stereoize(mel, 0.018) + wind(dur, 200, 1800, 0.12) + crickets(dur, 0.012)
    return reverb(x, 4.0, 1.6, 0.4, 5000)[:n]


def music_cave(dur):
    t = t_axis(dur)
    n = len(t)
    drone = (osc_saw(midi(31), t, (-7, 0, 6)) + 0.6 * osc_saw(midi(38), t, (-5, 4)))
    drone = lp(drone, 260) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.05 * t)) * 0.3
    rumble = lp(brown(n), 90) * 0.35
    chords = [[50, 57, 60], [48, 55, 58], [46, 53, 57], [48, 55, 62]]
    pad = chord_track(dur, chords, dur / 4, 700, 0.05, wobble=0.05)
    x = stereoize(drone + rumble + pad) + drips(dur, 0.5, 900, 2600, 0.25) + wind(dur, 80, 500, 0.06, 0.03)
    return reverb(x, 6.0, 2.6, 0.5, 3500)[:n]


def music_hell(dur):
    t = t_axis(dur)
    n = len(t)
    drone = osc_saw(midi(29), t, (-12, 0, 11)) + osc_saw(midi(35), t, (-9, 7))  # tritone
    drone = np.tanh(lp(drone, 420) * 1.5) * 0.3
    pulse = (0.6 + 0.4 * np.sin(2 * np.pi * 0.9 * t) ** 8)
    choir = chord_track(dur, [[53, 56, 59], [52, 55, 58], [53, 56, 61], [51, 54, 59]], dur / 4, 900, 0.07,
                        detune=(-18, -6, 6, 18), wobble=0.2)
    x = stereoize(drone * pulse + choir) + crackle(dur, 70, 0.35)
    return reverb(x, 4.5, 1.8, 0.4, 3000)[:n]


def music_corruption(dur):
    t = t_axis(dur)
    n = len(t)
    a = osc_saw(midi(34), t, (-25, 0, 23))
    b = osc_saw(midi(35), t, (-15, 14))
    drone = lp(a + b, 380) * 0.28 * (0.7 + 0.3 * np.sin(2 * np.pi * 0.13 * t))
    whisper = np.stack([bp(pink(n), 1800, 4200), bp(pink(n), 1800, 4200)], 1)
    whisper *= (0.5 + 0.5 * np.sin(2 * np.pi * np.array([0.21, 0.17]) * t[:, None])) ** 3 * 0.12
    glass = np.zeros(n)
    for i in range(7):
        st = int(rng.uniform(0, dur - 4) * SR)
        s = bell(midi(rng.choice([73, 74, 80, 86])), 4.0, 2.0, ((1, 1), (2.41, 0.4), (3.7, 0.2))) * 0.07
        glass[st:st + len(s)] += s
    x = stereoize(drone) + whisper + stereoize(glass, 0.03) + drips(dur, 0.25, 500, 1200, 0.12)
    return reverb(x, 5.5, 2.3, 0.5, 4000)[:n]


def music_ice(dur):
    t = t_axis(dur)
    n = len(t)
    chords = [[62, 69, 74, 76, 81], [60, 67, 72, 74, 79], [65, 72, 76, 79, 84], [64, 71, 74, 79, 83]]
    pad = chord_track(dur, chords, dur / 4, 3200, 0.05, detune=(-6, -2, 2, 6), wobble=0.15)
    shimmer = np.zeros((n, 2))
    for i in range(22):
        st = int(rng.uniform(0, dur - 3) * SR)
        m = rng.choice([86, 88, 91, 93, 95, 98, 100])
        s = bell(midi(m), 3.0, 1.2, ((1, 1), (2.0, 0.1), (3.0, 0.05))) * rng.uniform(0.03, 0.07)
        shimmer[st:st + len(s)] += pan(s, rng.uniform(-0.9, 0.9))
    x = stereoize(pad) + shimmer + wind(dur, 1200, 6000, 0.07, 0.09) + wind(dur, 150, 700, 0.07, 0.04)
    return reverb(x, 6.0, 2.8, 0.55, 9000)[:n]


def music_lake(dur):
    t = t_axis(dur)
    n = len(t)
    drone = osc_saw(midi(26), t, (-6, 0, 7)) + osc_saw(midi(33), t, (-4, 5))
    drone = lp(drone, 220) * 0.35 * (0.75 + 0.25 * np.sin(2 * np.pi * 0.07 * t))
    heart = np.zeros(n)
    beat = 60 / 42
    k = 0
    while k * beat < dur - 1:
        for off, amp in [(0, 1.0), (0.28, 0.7)]:
            st = int((k * beat + off) * SR)
            ln = int(0.5 * SR)
            tt = np.arange(ln) / SR
            h = np.sin(2 * np.pi * 42 * tt * (1 - tt * 0.5)) * np.exp(-tt * 9) * amp
            heart[st:st + ln] += h[: max(0, min(ln, n - st))]
        k += 1
    water = np.stack([lp(pink(n), 700), lp(pink(n), 700)], 1)
    water *= (0.5 + 0.5 * np.sin(2 * np.pi * np.array([0.23, 0.31]) * t[:, None])) * 0.12
    choir = chord_track(dur, [[50, 53, 57], [49, 53, 56], [50, 53, 58], [48, 52, 55]], dur / 4, 800, 0.05,
                        detune=(-14, -5, 5, 14))
    x = stereoize(drone + heart * 0.35 + choir) + water + drips(dur, 0.3, 400, 1000, 0.15)
    return reverb(x, 5.5, 2.4, 0.5, 3000)[:n]


def main():
    sfx = {
        "jump": sfx_jump, "land": sfx_land, "coin": sfx_coin, "blue_coin": sfx_blue_coin,
        "key": sfx_key, "key_expired": sfx_key_expired, "portal": sfx_portal, "death": sfx_death,
        "respawn": sfx_respawn, "crown": sfx_crown, "gravity": sfx_gravity, "ui_move": sfx_ui_move,
        "ui_select": sfx_ui_select, "title_hit": sfx_title_hit, "zone": sfx_zone,
    }
    for name, fn in sfx.items():
        write(os.path.join(ROOT, "sfx", name + ".wav"), fn())
    DUR, XF = 48.0, 4.0
    for name, fn in [("title", music_title), ("surface", music_surface), ("cave", music_cave),
                     ("hell", music_hell), ("corruption", music_corruption), ("ice", music_ice),
                     ("lake", music_lake)]:
        write_loop(name, fn(DUR + XF), XF)


# ---------------------------------------------------------------- Forgotten Veil (daytime) + piano
def birds(dur, rate, gain):
    """Synthesized birdsong: short FM chirps and trills, scattered in stereo."""
    n = int(dur * SR)
    out = np.zeros((n, 2))
    k = int(dur * rate)
    for _ in range(k):
        st = int(rng.uniform(0, dur - 1.5) * SR)
        kind = rng.integers(0, 3)
        notes = int(rng.integers(2, 7))
        base = rng.uniform(2600, 4800)
        p = rng.uniform(-0.9, 0.9)
        g = rng.uniform(0.3, 1.0)
        pos = st
        for j in range(notes):
            ln = int(rng.uniform(0.04, 0.12) * SR)
            t = np.arange(ln) / SR
            if kind == 0:     # rising chirp
                f = base * (1 + 0.5 * t / t[-1])
            elif kind == 1:   # falling whistle
                f = base * (1.3 - 0.4 * t / t[-1])
            else:             # warble
                f = base * (1 + 0.08 * np.sin(2 * np.pi * 38 * t))
            ph = 2 * np.pi * np.cumsum(f) / SR
            e = np.sin(np.pi * np.arange(ln) / ln) ** 2
            c = np.sin(ph) * e * g
            if pos + ln < n:
                out[pos:pos + ln] += pan(c, p)
            pos += ln + int(rng.uniform(0.02, 0.09) * SR)
    return out * gain


def leaves(dur, gain):
    n = int(dur * SR)
    t = t_axis(dur)
    chans = []
    for c in range(2):
        w = bp(pink(n), 900, 7000)
        gust = (0.35 + 0.65 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.06 * t + c + rng.random() * 6)) ** 3)
        rustle = 1.0 + 0.6 * lp(noise(n), 6) * 8
        chans.append(w * gust * np.clip(rustle, 0.2, 2.0))
    out = np.stack(chans, 1)
    return out / (np.max(np.abs(out)) + 1e-9) * gain


def harp_note(freq, dur, gain):
    return bell(freq, dur, 1.4, ((1, 1), (2.0, 0.35), (3.0, 0.12), (4.0, 0.05))) * gain


def music_day(dur):
    t = t_axis(dur)
    n = len(t)
    # C - Am - F - G, warm and open (major 7/9 colours)
    chords = [[48, 55, 64, 67, 71], [45, 52, 60, 64, 71], [41, 53, 60, 64, 69], [43, 50, 59, 62, 67]] * 2
    seg = dur / len(chords)
    pad = chord_track(dur, chords, seg, 1800, 0.06, detune=(-7, -2, 3, 8), wobble=0.08)
    mel = np.zeros(n)
    scale = [72, 74, 76, 79, 81, 84]
    tt = 1.5
    while tt < dur - 3:
        m = scale[int(rng.integers(0, len(scale)))]
        s = harp_note(midi(m), 3.0, 0.12)
        st = int(tt * SR)
        e = min(n, st + len(s))
        mel[st:e] += s[: e - st]
        tt += float(rng.choice([0.75, 1.0, 1.5, 2.25]))
    x = stereoize(pad) + stereoize(mel, 0.02) + birds(dur, 0.6, 0.05) + leaves(dur, 0.07)
    return reverb(x, 3.5, 1.3, 0.35, 7000)[:n]


def music_falls(dur):
    t = t_axis(dur)
    n = len(t)
    roar = np.stack([lp(pink(n), 1400) + 0.5 * lp(brown(n), 300), lp(pink(n), 1400) + 0.5 * lp(brown(n), 300)], 1)
    roar *= (0.85 + 0.15 * np.sin(2 * np.pi * np.array([0.11, 0.13]) * t[:, None]))
    roar = roar / (np.max(np.abs(roar)) + 1e-9) * 0.35
    spray = np.stack([hp(noise(n), 5000), hp(noise(n), 5000)], 1) * 0.02
    chords = [[50, 57, 62, 66], [47, 54, 62, 64], [43, 50, 59, 62], [45, 52, 61, 64]]
    pad = chord_track(dur, chords, dur / 4, 1500, 0.035, detune=(-6, -2, 2, 6), wobble=0.06)
    x = roar + spray + stereoize(pad) + birds(dur, 0.35, 0.035)
    return reverb(x, 2.5, 0.9, 0.2, 6000)[:n]


def music_temple(dur):
    t = t_axis(dur)
    n = len(t)
    drone = (sine(midi(38), t) + 0.6 * sine(midi(45), t) + 0.3 * sine(midi(50), t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * t)))
    drone = lp(drone, 500) * 0.12
    air = np.stack([bp(pink(n), 200, 1200), bp(pink(n), 200, 1200)], 1) * 0.05
    chime = np.zeros(n)
    for i in range(5):
        st = int(rng.uniform(1, dur - 5) * SR)
        s = bell(midi(float(rng.choice([69, 74, 76, 81]))), 5.0, 2.4, ((1, 1), (2.76, 0.3), (5.4, 0.1))) * 0.05
        chime[st:st + len(s)] += s[: max(0, min(len(s), n - st))]
    x = stereoize(drone) + air + drips(dur, 0.8, 1100, 3000, 0.22) + stereoize(chime, 0.03)
    return reverb(x, 6.5, 2.8, 0.55, 5000)[:n]


def music_veil_title(dur):
    t = t_axis(dur)
    n = len(t)
    # D - Bm - G - A - D - F#m - G - A: hopeful, warm
    chords = [[50, 57, 62, 66, 69], [47, 54, 62, 66, 71], [43, 50, 59, 62, 67], [45, 52, 61, 64, 69],
              [50, 57, 62, 66, 69], [42, 54, 61, 66, 69], [43, 55, 59, 62, 71], [45, 57, 61, 64, 69]]
    seg = dur / len(chords)
    pad = chord_track(dur, chords, seg, 1700, 0.075, detune=(-9, -3, 3, 9), wobble=0.07)
    arp = np.zeros(n)
    for i, ch in enumerate(chords):
        for j in range(8):
            m = ch[1:][j % 4] + 12
            st = int((i * seg + j * seg / 8) * SR)
            s = harp_note(midi(m), 2.5, 0.09 * (1.0 if j % 4 == 0 else 0.7))
            e = min(n, st + len(s))
            arp[st:e] += s[: e - st]
    mel = np.zeros(n)
    melody = [78, 76, 74, 76, 78, 81, 79, 78, 76, 74, 73, 74]
    step = dur / len(melody)
    for i, m in enumerate(melody):
        s = bell(midi(m), 4.0, 1.8, ((1, 1), (2, 0.2), (3, 0.08))) * 0.13
        st = int(i * step * SR)
        e = min(n, st + len(s))
        mel[st:e] += s[: e - st]
    x = stereoize(pad) + stereoize(arp, 0.015) + stereoize(mel, 0.02) + birds(dur, 0.25, 0.03) + leaves(dur, 0.035)
    return reverb(x, 4.5, 1.8, 0.4, 7000)[:n]


def piano_note(m, dur=3.2):
    """Soft grand-piano-ish tone: inharmonic partials, 3 slightly detuned strings, hammer thump."""
    f0 = midi(m)
    t = t_axis(dur)
    n = len(t)
    B = 0.0004 * (1.0 + max(0, m - 60) / 30.0)
    base_decay = float(np.interp(m, [21, 60, 108], [5.0, 2.6, 0.7]))
    bright = float(np.interp(m, [21, 60, 108], [0.6, 1.0, 1.4]))
    out = np.zeros(n)
    for k in range(1, 14):
        fk = f0 * k * np.sqrt(1 + B * k * k)
        if fk > SR * 0.45:
            break
        amp = (1.0 / k ** (1.35 / bright)) * (1.0 if k > 1 else 1.2)
        dec = base_decay / (1 + 0.45 * (k - 1))
        for cents in (-0.7, 0.0, 0.8):
            ff = fk * 2 ** (cents / 1200)
            out += amp * np.sin(2 * np.pi * ff * t + rng.random() * 6.28) * (np.exp(-t / dec) * 0.8 + 0.2 * np.exp(-t / (dec * 0.12)))
    out /= 3.0
    hammer = lp(noise(n), 1800 * bright) * env_exp(n, 0.008, 0.0005) * 0.25
    x = out * env_adsr(n, 0.003, 0.0, 1.0, 0.25, 1.0) + hammer
    return lp(x, 9000)


def gen_veil():
    DUR, XF = 48.0, 4.0
    for name, fn in [("veil_title", music_veil_title), ("day", music_day), ("falls", music_falls), ("temple", music_temple)]:
        write_loop(name, fn(DUR + XF), XF)
    # EE piano (block 77): note index n -> MIDI 48 + n (EE's C3 = note 0; range -27..60).
    # Sampled every 3 semitones; the game pitch-shifts to the exact note.
    for m in range(21, 109, 3):
        x = reverb(piano_note(m), 1.6, 0.5, 0.18, 8000)
        write(os.path.join(ROOT, "piano", "piano_%d.wav" % m), x, 0.8)


if __name__ == "__main__":
    import sys
    if "--veil" in sys.argv:
        gen_veil()   # only the Forgotten Veil set (keeps the Odyssey files byte-identical)
    else:
        main()
