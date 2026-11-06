#!/usr/bin/env python3
"""Generates Sus-o-meter's sound effects (SPEC.md §12) into assets/sfx/.

Every sound is synthesized from scratch here (no samples), so the files are
original work released under CC0. Standard library only; deterministic.

Usage: python3 tool/gen_sfx.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def note(name):
    """Frequency of a note like 'C5' or 'F#4'."""
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4,
             "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix_into(buf, samples, at_seconds, gain=1.0):
    start = int(at_seconds * RATE)
    need = start + len(samples)
    if need > len(buf):
        buf.extend([0.0] * (need - len(buf)))
    for i, s in enumerate(samples):
        buf[start + i] += s * gain


def adsr(n, attack=0.01, decay=0.05, sustain=0.7, release=0.1):
    a, d, r = int(attack * RATE), int(decay * RATE), int(release * RATE)
    env = []
    for i in range(n):
        if i < a:
            v = i / max(1, a)
        elif i < a + d:
            v = 1 - (1 - sustain) * (i - a) / max(1, d)
        elif i > n - r:
            v = sustain * max(0.0, (n - i) / max(1, r))
        else:
            v = sustain
        env.append(v)
    return env


def tone(freq, seconds, harmonics=(1.0,), env=None, vibrato=0.0, bend=0.0):
    """Additive tone. `bend` glides the pitch by that many semitones."""
    n = int(seconds * RATE)
    env = env or adsr(n)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = freq * 2 ** (bend * (i / n) / 12)
        if vibrato:
            f *= 1 + vibrato * math.sin(2 * math.pi * 5.5 * t)
        phase += 2 * math.pi * f / RATE
        s = sum(a * math.sin((k + 1) * phase) for k, a in enumerate(harmonics))
        out.append(s * env[i])
    return out


def bell(freq, seconds):
    n = int(seconds * RATE)
    partials = [(1.0, 1.0), (2.0, 0.5), (2.76, 0.35), (5.4, 0.2), (8.9, 0.1)]
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for ratio, amp in partials:
            s += amp * math.exp(-t * (3 + ratio)) * math.sin(2 * math.pi * freq * ratio * t)
        out.append(s * min(1.0, i / 40))
    return out


def noise_burst(seconds, decay, rng, tone_hz=0.0):
    n = int(seconds * RATE)
    out, prev = [], 0.0
    for i in range(n):
        t = i / RATE
        white = rng.uniform(-1, 1)
        prev = 0.6 * prev + 0.4 * white  # gentle low-pass
        s = prev
        if tone_hz:
            s = 0.7 * s + 0.3 * math.sin(2 * math.pi * tone_hz * t)
        out.append(s * math.exp(-t * decay))
    return out


def normalize(buf, peak=0.85):
    m = max(1e-9, max(abs(x) for x in buf))
    return [x * peak / m for x in buf]


def fade(buf, seconds=0.02):
    n = int(seconds * RATE)
    for i in range(min(n, len(buf))):
        buf[i] *= i / n
        buf[-1 - i] *= i / n
    return buf


def write(name, buf):
    buf = fade(normalize(buf))
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in buf))
    print(f"{path}: {len(buf) / RATE:.2f}s")


def jingle():
    """Short bright arpeggio for the start of a turn."""
    buf = silence(1.3)
    bright = (1.0, 0.45, 0.25, 0.12)
    for i, n in enumerate(["C5", "E5", "G5", "C6"]):
        mix_into(buf, tone(note(n), 0.22, bright, adsr(int(0.22 * RATE), 0.005, 0.05, 0.6, 0.08)), i * 0.13)
    for n in ["C5", "E5", "G5", "C6"]:
        mix_into(buf, tone(note(n), 0.6, bright, adsr(int(0.6 * RATE), 0.01, 0.1, 0.5, 0.4)), 0.55, 0.6)
    return buf


def drumroll(rng):
    """3 s snare roll that swells into a crash, under the 3-2-1 countdown."""
    buf = silence(3.4)
    t, step = 0.0, 1 / 18
    while t < 2.95:
        gain = 0.35 + 0.65 * (t / 2.95) ** 1.5
        mix_into(buf, noise_burst(0.07, 38, rng, tone_hz=190), t, gain)
        t += step * rng.uniform(0.9, 1.1)
    mix_into(buf, noise_burst(0.45, 6, rng), 2.98, 1.3)
    mix_into(buf, tone(70, 0.35, (1.0, 0.3), adsr(int(0.35 * RATE), 0.002, 0.08, 0.3, 0.25)), 2.98, 1.0)
    return buf


def ding_ding():
    """Two bright dings for Legit."""
    buf = silence(1.4)
    mix_into(buf, bell(1318.5, 0.9), 0.0)
    mix_into(buf, bell(1318.5, 1.1), 0.22)
    return buf


def wah_wah():
    """Sad-trombone 'wah wah wah waaah' for Hmm…"""
    buf = silence(2.4)
    brass = (1.0, 0.7, 0.5, 0.35, 0.2, 0.12)
    notes = [("G4", 0.38, 0.0), ("F#4", 0.38, 0.0), ("F4", 0.38, 0.0), ("E4", 1.1, -0.6)]
    t = 0.0
    for name, dur, bend in notes:
        env = adsr(int(dur * RATE), 0.04, 0.08, 0.75, 0.12)
        mix_into(buf, tone(note(name), dur, brass, env, vibrato=0.012 if dur > 1 else 0.0, bend=bend), t)
        t += dur + 0.04
    return buf


def buzzer():
    """Harsh game-show buzzer for Sus!"""
    n = int(0.95 * RATE)
    env = adsr(n, 0.005, 0.02, 0.9, 0.08)
    buf = []
    for i in range(n):
        t = i / RATE
        sq1 = 1.0 if math.sin(2 * math.pi * 146 * t) >= 0 else -1.0
        sq2 = 1.0 if math.sin(2 * math.pi * 152 * t) >= 0 else -1.0
        buf.append((sq1 + sq2) * 0.5 * env[i])
    return buf


def applause(rng):
    """A crowd clapping for the award reveal."""
    seconds = 2.8
    buf = silence(seconds)
    claps = 420
    for _ in range(claps):
        t = rng.uniform(0, seconds - 0.1)
        swell = math.sin(math.pi * t / seconds) ** 0.6
        mix_into(buf, noise_burst(0.03, 120, rng, tone_hz=rng.uniform(900, 1800)), t, swell * rng.uniform(0.3, 1.0))
    return buf


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(7)
    write("jingle", jingle())
    write("drumroll", drumroll(rng))
    write("ding_ding", ding_ding())
    write("wah_wah", wah_wah())
    write("buzzer", buzzer())
    write("applause", applause(rng))


if __name__ == "__main__":
    main()
