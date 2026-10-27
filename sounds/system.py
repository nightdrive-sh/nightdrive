"""The desktop's own sounds (system/*.wav): volume, screenshot, charger, battery, error, devices, lock, logout and
shutdown. Picked by ear from a few takes each (#1670), in the family of the notification sounds: soft sines with a
trace of the octave, E major, a small room. generate.py writes them; this file only says how each is made.
"""
import math, random

import generate
from generate import SR, mix, reverb, slide

E4, Gs4, E5, Gs5, B5 = 329.63, 415.305, 659.26, 830.61, 987.77


def note(freq, dur, kind="sine", start=0.0, attack=0.004, decay=0.12, amp=1.0):
    """generate.note() made at 0 and shifted: its own buffer can come out a sample short with a fractional start."""
    return [0.0] * int(start * SR) + generate.note(freq, dur, kind, 0.0, attack, decay, amp)


def click(centre, dur, decay, start=0.0, amp=1.0, q=3.0, seed=1):
    """A soft mechanical click: a burst of noise through a narrow band-pass."""
    rnd = random.Random(seed)
    f = 2 * math.sin(math.pi * centre / SR)
    low = band = 0.0
    buf = [0.0] * int(start * SR)
    for i in range(int(dur * SR)):
        low += f * band
        band += f * (rnd.uniform(-1, 1) * math.exp(-i / SR / decay) - low - band / q)
        buf.append(band * amp)
    return buf


def shutter(gap=0.105, slow=1.3):
    """A camera's two curtains, gap apart: each a bright and a low click together, over a low E4 then G#4.
    slow stretches every decay, so it rings a little longer than a phone's."""
    return reverb(mix(click(2400, .05 * slow, .005 * slow), click(650, .07 * slow, .014 * slow, amp=.8, seed=5),
                      click(1900, .05 * slow, .007 * slow, start=gap, seed=2),
                      click(550, .07 * slow, .012 * slow, start=gap, amp=.6, seed=6),
                      note(E4, .12 * slow, attack=.002, decay=.03 * slow, amp=.7),
                      note(Gs4, .14 * slow, start=gap, attack=.002, decay=.03 * slow, amp=.7)), wet=.12, tail=.15)


def horizon_close(T=1.3, pad_decay=.3, step=.09, cutoff=1400):
    """The startup sound (keys/startup, Horizon) turned to a goodbye: its Fmaj9 pad struck and let go at once, its
    sparkle falling (C7 A6 G6 E6 C6) instead of rising, its sub dropping, in the same hall."""
    n = int(T * SR)
    rnd = random.Random(7)
    pad = [0.0] * n
    for f in (87.31, 130.81, 220.0, 329.63, 392.0):
        for i, v in enumerate(generate.supersaw(f, n, rnd)):
            pad[i] += v / 5
    pad = generate.svf_lowpass(pad, cutoff)
    out = [v * min(i / (.01 * SR), 1) * math.exp(-i / SR / pad_decay) for i, v in enumerate(pad)]
    ph = 0.0
    for i in range(n):
        t = i / SR
        ph += 2 * math.pi * 80 * 0.5 ** min(t / .4, 1.0) / SR
        out[i] += .7 * math.sin(ph) * min(t / .005, 1) * math.exp(-t / .35)
    for k, f in enumerate((2093.0, 1760.0, 1567.98, 1318.51, 1046.5)):
        s0 = int(step * k * SR)
        for i in range(min(int(.4 * SR), n - s0)):
            out[s0 + i] += math.sin(2 * math.pi * f * i / SR) * math.exp(-i / SR / .1) * .25
    out = generate.hall(out, rt60=2.2, tail=1.2)
    # No DC; the silence at the end trimmed (50 dB under the peak)
    out = [v - w for v, w in zip(out, generate.onepole(out, 20))]
    peak = max(abs(v) for v in out)
    last = max(i for i, v in enumerate(out) if abs(v) > peak * 10 ** (-50 / 20))
    return out[: last + int(.05 * SR)]


# Name → (sound, peak dBFS). The volume tick plays on every step of a held key, so it is the shortest and quietest;
# battery-low has to be noticed, so it is the loudest.
SYSTEM = {
    "volume": (lambda: reverb(note(B5, .05, "detune", decay=.015), wet=.12, tail=.12), -26),
    "screenshot": (shutter, -20),
    "charger": (lambda: reverb(mix(note(E5, .3, "detune", 0, decay=.08), note(B5, .45, "detune", .09, decay=.14)),
                               wet=.25), -18),
    "battery-low": (lambda: reverb(mix(note(B5, .2, start=0, decay=.05), note(Gs5, .2, start=.08, decay=.05),
                                       note(B5, .2, start=.3, decay=.05), note(E5, .45, start=.38, decay=.12))), -15),
    "error": (lambda: reverb(mix(note(E4, .12, "tri", 0, decay=.04), note(E4, .18, "tri", .1, decay=.05)), wet=.12), -18),
    "device-in": (lambda: reverb(slide(E5, B5, .25, .07, .05), wet=.2), -18),
    "device-out": (lambda: reverb(slide(B5, E5, .25, .07, .05), wet=.2), -18),
    "lock": (lambda: reverb(mix(click(1100, .04, .006), click(700, .06, .01, start=.08, seed=4)), wet=.12, tail=.15), -18),
    "logout": (horizon_close, -18),
    "shutdown": (lambda: horizon_close(T=2.4, pad_decay=.8, step=.14), -16),
}
