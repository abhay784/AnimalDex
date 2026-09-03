#!/usr/bin/env python3
"""Generate AnimalDex's sound effects as original 8-bit-style WAVs.

The nostalgic handheld sound is a *synthesis technique*, not a set of files:
square waves at low duty cycles, triangle waves for bass, pitch sweeps, fast
arpeggios, and hard amplitude envelopes — all at a low sample rate with coarse
quantization. Producing them here means the app ships assets it owns outright
rather than anyone else's copyrighted audio.

Every cue is a named slot in Design/SoundBank.swift, so replacing any of these
with recorded or commissioned audio is a file swap with no code change.

    python3 tools/make_sfx.py
"""
from __future__ import annotations

import pathlib
import struct
import wave

import numpy as np

SR = 22_050          # period-appropriate and small
BITS = 8             # quantize hard; the crunch is the point
OUT = pathlib.Path(__file__).resolve().parent.parent / "AnimalDex" / "Resources" / "Audio"

A4 = 440.0
def note(semitones_from_a4: float) -> float:
    return A4 * (2 ** (semitones_from_a4 / 12))

# Scale degrees used across the cues (relative to A4).
C5, D5, E5, G5, A5, C6, E6, G6 = 3, 5, 7, 10, 12, 15, 19, 22


def square(freq: np.ndarray | float, n: int, duty: float = 0.5) -> np.ndarray:
    t = np.arange(n) / SR
    phase = np.cumsum(np.full(n, freq) / SR) if np.isscalar(freq) else np.cumsum(freq / SR)
    return np.where((phase % 1.0) < duty, 1.0, -1.0)


def triangle(freq: float, n: int) -> np.ndarray:
    phase = (np.arange(n) * freq / SR) % 1.0
    return 4 * np.abs(phase - 0.5) - 1


def noise(n: int) -> np.ndarray:
    # Sample-and-hold noise, like a period noise channel.
    rng = np.random.default_rng(7)
    raw = rng.uniform(-1, 1, size=n // 12 + 1)
    return np.repeat(raw, 12)[:n]


def env(n: int, attack: float = 0.01, decay: float = 0.9) -> np.ndarray:
    a = max(1, int(n * attack))
    d = n - a
    return np.concatenate([np.linspace(0, 1, a), np.linspace(1, 0, d) ** decay])


def tone(semi: float, ms: int, duty: float = 0.5, vol: float = 0.6,
         sweep: float | None = None) -> np.ndarray:
    n = int(SR * ms / 1000)
    f0 = note(semi)
    freq = np.linspace(f0, note(semi + sweep), n) if sweep is not None else f0
    return square(freq, n, duty) * env(n) * vol


def silence(ms: int) -> np.ndarray:
    return np.zeros(int(SR * ms / 1000))


def seq(*parts: np.ndarray) -> np.ndarray:
    return np.concatenate(parts) if parts else np.zeros(0)


def mix(*layers: np.ndarray) -> np.ndarray:
    n = max(len(x) for x in layers)
    out = np.zeros(n)
    for x in layers:
        out[: len(x)] += x
    return out


def write(name: str, samples: np.ndarray) -> None:
    peak = np.max(np.abs(samples)) or 1.0
    norm = np.clip(samples / peak * 0.85, -1, 1)
    # Quantize to 8-bit unsigned, which is where the grit comes from.
    data = ((norm * 0.5 + 0.5) * 255).astype(np.uint8)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  {name+'.wav':<24} {len(data)/SR:>5.2f}s  {path.stat().st_size/1024:>5.1f} KB")


CUES = {
    # UI
    "select":     lambda: tone(C5, 40, duty=0.25, vol=0.5),
    "back":       lambda: tone(C5, 55, duty=0.25, sweep=-5),
    "error":      lambda: seq(tone(-2, 70, duty=0.5), tone(-7, 110, duty=0.5)),

    # Device chrome
    "orb_spin":   lambda: seq(*[tone(C5 + i, 34, duty=0.125, vol=0.4) for i in (0, 4, 7, 12)]),
    "dex_open":   lambda: mix(
                      seq(tone(C5, 60, duty=0.125), tone(G5, 60, duty=0.125), tone(C6, 130, duty=0.25)),
                      seq(silence(20), noise(int(SR * 0.05)) * env(int(SR * 0.05)) * 0.18)),
    "dex_close":  lambda: seq(tone(C6, 55, duty=0.25), tone(G5, 55, duty=0.25), tone(C5, 110, duty=0.125)),

    # Scanner
    "detect":     lambda: seq(tone(G5, 45, duty=0.125, vol=0.55), tone(C6, 90, duty=0.125, vol=0.55)),
    "throw":      lambda: mix(tone(C6, 180, duty=0.25, sweep=-14),
                              noise(int(SR * 0.18)) * env(int(SR * 0.18), decay=1.6) * 0.22),
    "shake":      lambda: mix(tone(A5, 90, duty=0.5, vol=0.45, sweep=2),
                              noise(int(SR * 0.09)) * env(int(SR * 0.09)) * 0.15),
    "escape":     lambda: seq(tone(G5, 90, duty=0.25, sweep=-4), tone(C5, 160, duty=0.25, sweep=-7)),

    # Resolution
    "caught":     lambda: seq(tone(C5, 70, duty=0.25), tone(E5, 70, duty=0.25),
                              tone(G5, 70, duty=0.25), tone(C6, 200, duty=0.25)),
    "registered": lambda: mix(
                      seq(tone(G5, 60, duty=0.125), tone(C6, 60, duty=0.125), tone(E6, 220, duty=0.125)),
                      seq(silence(60), triangle(note(C5 - 12), int(SR * 0.22)) * env(int(SR * 0.22)) * 0.4)),
    "duplicate":  lambda: seq(tone(E5, 55, duty=0.25), tone(E5, 90, duty=0.25)),

    # Rarity fanfares, escalating in length and register
    "fanfare_uncommon": lambda: seq(tone(C5, 70, duty=0.25), tone(G5, 180, duty=0.25)),
    "fanfare_rare":     lambda: seq(tone(C5, 65, duty=0.25), tone(E5, 65, duty=0.25),
                                    tone(G5, 65, duty=0.25), tone(C6, 240, duty=0.25)),
    "fanfare_epic":     lambda: seq(tone(C5, 60, duty=0.125), tone(E5, 60, duty=0.125),
                                    tone(G5, 60, duty=0.125), tone(C6, 60, duty=0.125),
                                    tone(E6, 60, duty=0.125), tone(G6, 300, duty=0.125)),
    "fanfare_legendary": lambda: mix(
                            seq(tone(C5, 55, duty=0.125), tone(G5, 55, duty=0.125),
                                tone(C6, 55, duty=0.125), tone(E6, 55, duty=0.125),
                                tone(G6, 55, duty=0.125), tone(G6 + 5, 420, duty=0.125)),
                            seq(silence(120), triangle(note(C5 - 24), int(SR * 0.5)) * env(int(SR * 0.5)) * 0.45),
                            seq(silence(240), noise(int(SR * 0.3)) * env(int(SR * 0.3), decay=2.2) * 0.12)),
}


def main() -> int:
    print(f"generating {len(CUES)} cues -> {OUT.name}/")
    for name, make in CUES.items():
        write(name, make())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
