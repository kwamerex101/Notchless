#!/usr/bin/env python3
"""Generate Notchless's original click 'voices'.

Self-authored synthesis (CC0). Deterministic (seeded) so the set is
reproducible. Output: 48 kHz mono 16-bit WAV, ~35-60 ms each.

  pebble - deep damped-sine thump (mechanical detent body)
  twig   - crisp filtered-noise tick (dry, woody)
  drop   - liquid pitch-down blip
"""
import math
import os
import random
import struct
import wave

RATE = 48000
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Sounds")


def write_wav(name, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = 0.89 / peak  # headroom below full scale
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32767))
            for s in samples))
    print(f"wrote {path} ({len(samples) / RATE * 1000:.0f} ms)")


def env(i, n, attack=0.002, decay=6.0):
    """Fast attack, exponential decay envelope."""
    t = i / RATE
    a = min(1.0, t / attack)
    return a * math.exp(-decay * (i / n))


def pebble():
    n = int(0.055 * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        body = math.sin(2 * math.pi * 170 * t) * 0.9          # deep thump
        knock = math.sin(2 * math.pi * 950 * t) * math.exp(-t * 320) * 0.5  # contact transient
        out.append((body + knock) * env(i, n, decay=7.0))
    return out


def twig():
    rng = random.Random(7)
    n = int(0.035 * RATE)
    out, hp_prev_in, hp_prev_out = [], 0.0, 0.0
    for i in range(n):
        x = rng.uniform(-1, 1)
        # one-pole high-pass to keep it a dry tick, not a hiss burst
        hp = 0.92 * (hp_prev_out + x - hp_prev_in)
        hp_prev_in, hp_prev_out = x, hp
        out.append(hp * env(i, n, attack=0.0005, decay=11.0))
    return out


def drop():
    n = int(0.045 * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 900.0 * math.exp(-t * 42) + 260.0                 # 900 Hz -> ~260 Hz sweep
        phase += 2 * math.pi * f / RATE
        out.append(math.sin(phase) * env(i, n, decay=6.5))
    return out


if __name__ == "__main__":
    write_wav("pebble", pebble())
    write_wav("twig", twig())
    write_wav("drop", drop())
