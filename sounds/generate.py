#!/usr/bin/python3 -I
"""Makes the notification sounds (regular/*.wav, urgent/*.wav), agent-warn's (agent/*.wav), Mail's (mail/*.wav) and
the login screen's sounds (keys/*.wav) from scratch: no samples, so no licences to track.

  python3 sounds/generate.py      rewrites the .wav files next to this script

Soft sine/synth tones with a little room. Regular ones peak at -18 dBFS (noticed, not startling), urgent at -12 dBFS.
hypr/scripts/sounds picks and plays them.
"""
import math, os, random, struct, wave

SR = 48000
HERE = os.path.dirname(os.path.abspath(__file__))


def note(freq, dur, kind="sine", start=0.0, attack=0.004, decay=0.12, amp=1.0, glide=None):
    """One tone: a short attack (no click) and an exponential decay. glide: pitch ratio reached after 60 ms."""
    buf = [0.0] * int((start + dur) * SR)
    phase = mphase = 0.0
    for i in range(int(dur * SR)):
        t = i / SR
        f = freq if glide is None else freq * (glide ** min(t / 0.06, 1.0))
        env = min(t / attack, 1.0) * math.exp(-t / decay)
        if kind == "sine":        # with a trace of the octave, a bit rounder than a pure sine
            s = math.sin(phase) + 0.12 * math.sin(2 * phase)
        elif kind == "tri":       # band-limited triangle: retro, but not harsh
            s = sum(((-1) ** k) * math.sin((2 * k + 1) * phase) / (2 * k + 1) ** 2 for k in range(4))
        elif kind == "detune":    # two sines 0.6 % apart: a slow synth shimmer
            s = 0.5 * (math.sin(phase) + math.sin(mphase))
            mphase += 2 * math.pi * f * 1.006 / SR
        phase += 2 * math.pi * f / SR
        buf[int(start * SR) + i] = s * env * amp
    return buf


def mix(*bufs):
    out = [0.0] * max(len(b) for b in bufs)
    for b in bufs:
        for i, v in enumerate(b):
            out[i] += v
    return out


def reverb(buf, wet=0.18, tail=0.35):
    """A small room: four parallel comb filters."""
    n = len(buf) + int(tail * SR)
    x = buf + [0.0] * (n - len(buf))
    out = x[:]
    for d_ms, g in ((29.7, 0.55), (37.1, 0.5), (41.1, 0.45), (43.7, 0.4)):
        d = int(d_ms / 1000 * SR)
        c = [0.0] * n
        for i in range(n):
            c[i] = x[i] + (g * c[i - d] if i >= d else 0.0)
        for i in range(n):
            out[i] += wet * 0.25 * c[i]
    return out


def write(path, buf, peak_db):
    fade = int(0.03 * SR)
    for i in range(fade):
        buf[-1 - i] *= i / fade
    g = 10 ** (peak_db / 20) / (max(abs(v) for v in buf) or 1.0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(v * g * 32767)) for v in buf))


E5, Fs5, G5, A5, B5, D6, E6, A6 = 659.26, 739.99, 783.99, 880.0, 987.77, 1174.7, 1318.5, 1760.0

REGULAR = {
    "plip": lambda: reverb(mix(note(E5, .22, start=0, decay=.06), note(B5, .3, start=.07, decay=.08))),
    "drop": lambda: reverb(note(A5, .3, decay=.07, glide=1.5), wet=.25),
    "tick": lambda: reverb(note(E6, .2, "detune", decay=.05), wet=.2),
    "retro": lambda: reverb(mix(note(A5, .15, "tri", 0, decay=.04), note(D6, .25, "tri", .06, decay=.07))),
    "glass": lambda: reverb(mix(note(A6, .25, start=0, decay=.06), note(E6, .35, start=.05, decay=.09, amp=.7)), wet=.35, tail=.5),
}
URGENT = {
    "double-plip": lambda: reverb(mix(note(B5, .2, start=0, decay=.05), note(E6, .2, start=.07, decay=.05),
                                      note(B5, .2, start=.2, decay=.05), note(E6, .3, start=.27, decay=.08))),
    "plip-fall": lambda: reverb(mix(note(E5, .22, start=0, decay=.06), note(B5, .22, start=.08, decay=.06),
                                    note(G5, .4, start=.16, decay=.12))),
    "synth-fall": lambda: reverb(mix(note(B5, .35, "detune", 0, decay=.12), note(E5, .55, "detune", .15, decay=.18)), wet=.25),
    "arpeggio": lambda: reverb(mix(note(E5, .15, "tri", 0, decay=.05), note(G5, .15, "tri", .07, decay=.05),
                                   note(B5, .15, "tri", .14, decay=.05), note(Fs5, .4, "tri", .21, decay=.12))),
    "pulse": lambda: reverb(mix(*[note(B5, .18, "detune", .14 * k, decay=.05) for k in range(3)])),
}

C5, E5b, G5b, C6 = 523.25, 659.25, 783.99, 1046.5
G6 = 1567.98
# hypr/scripts/agent-warn: a coding agent is about to open the launcher or a menu, which takes the keyboard. A rising
# chord unlike the notification sounds ("hands off the keyboard"), a countdown tick, and "now". Name → (sound, peak dBFS)
AGENT = {
    "attention": (lambda: reverb(mix(*[note(f, .5, start=.11 * k, decay=.18) for k, f in enumerate((C5, E5b, G5b, C6))])), -14),
    "tick": (lambda: note(E6, .12, decay=.03), -20),
    "go": (lambda: reverb(mix(note(C6, .3, start=0, decay=.08), note(G6, .3, start=.07, decay=.1))), -16),
}


def swoosh(f0, ratio, dur, q=1.4, decay=.5, shape=2.0, seed=3):
    """Air: noise through a band-pass whose centre glides f0 -> f0*ratio, swelling and fading over dur."""
    rnd = random.Random(seed)
    out, low, band = [], 0.0, 0.0
    for i in range(int(dur * SR)):
        t = i / SR
        f = 2 * math.sin(math.pi * min(f0 * ratio ** (t / dur), 9000) / SR)
        low += f * band
        band += f * (rnd.uniform(-1, 1) - low - band / q)
        out.append(band * math.sin(math.pi * t / dur) ** shape * math.exp(-t / decay))
    return out


# plugins/mail: a message has gone (Mail plays it after sending, in the background). A soft, deep swoosh rising away.
# Name → (sound, peak dBFS)
MAIL = {
    "sent": (lambda: reverb(swoosh(350, 6, .6), wet=.12, tail=.07), -18),
}


def beep(freq, dur, harmonics=12):
    """A PC-speaker beep: a band-limited square (odd harmonics) held at full level and cut off with a 3 ms release."""
    n = int(dur * SR)
    return [sum(math.sin(2 * math.pi * freq * (2 * k + 1) * i / SR) / (2 * k + 1) for k in range(harmonics))
            * min(i / (0.002 * SR), 1.0) * min((n - i) / (0.003 * SR), 1.0) for i in range(n)]


# The login screen's startup sound, "Horizon": a sub drop, a wide Fmaj9 supersaw pad and a sparkle of sines over it, in a
# hall. Plain Python, so it takes a while (~half a minute).
def supersaw(freq, n, rnd, voices=7, spread=0.018):
    """Detuned saws (PolyBLEP, so they don't alias) stacked: the big synthwave pad."""
    out = [0.0] * n
    for k in range(voices):
        dt = freq * (1 + spread * (k - (voices - 1) / 2) / ((voices - 1) / 2)) / SR
        p = rnd.random()
        for i in range(n):
            p += dt
            if p >= 1.0:
                p -= 1.0
            v = 2 * p - 1
            if p < dt:
                x = p / dt
                v -= x + x - x * x - 1
            elif p > 1 - dt:
                x = (p - 1) / dt
                v -= x * x + x + x + 1
            out[i] += v / voices
    return out


def svf_lowpass(x, cutoff, q=0.7):
    """A state-variable low-pass."""
    f, damp = 2 * math.sin(math.pi * cutoff / SR), 1 / q
    low = band = 0.0
    out = []
    for v in x:
        low += f * band
        band += f * (v - low - damp * band)
        out.append(low)
    return out


def onepole(x, cutoff):
    a = math.exp(-2 * math.pi * cutoff / SR)
    y, out = 0.0, []
    for v in x:
        y = (1 - a) * v + a * y
        out.append(y)
    return out


def hall(x, rt60=2.8, wet=0.35, damp=5000, tail=2.0, pre=0.02):
    """A Schroeder hall: eight damped combs into four allpasses."""
    x = x + [0.0] * int(tail * SR)
    n = len(x)
    src = onepole([0.0] * int(pre * SR) + x, damp)[:n]
    acc = [0.0] * n
    for d_ms in (29.7, 37.1, 41.1, 43.7, 47.9, 53.3, 59.9, 67.1):
        d = round(d_ms / 1000 * SR)
        g = 10 ** (-3 * d / (rt60 * SR))
        y = [0.0] * n
        for i in range(n):
            y[i] = src[i] + (g * y[i - d] if i >= d else 0.0)
            acc[i] += y[i] / 8
    for d_ms, g in ((5.0, 0.7), (1.7, 0.7), (11.3, 0.6), (7.9, 0.6)):
        d = round(d_ms / 1000 * SR)
        y = [0.0] * n
        for i in range(n):
            y[i] = -g * acc[i] + (acc[i - d] + g * y[i - d] if i >= d else 0.0)
        acc = y
    return [(1 - wet) * a + wet * 3 * b for a, b in zip(x, acc)]


def horizon():
    T = 3.6
    n = int(T * SR)
    rnd = random.Random(7)
    # A sub drop, 80 → 40 Hz in 0.6 s
    sub, ph = [], 0.0
    for i in range(n):
        t = i / SR
        ph += 2 * math.pi * 80 * 0.5 ** min(t / 0.6, 1.0) / SR
        sub.append(math.sin(ph) * math.exp(-t / 0.9) * 0.8)
    # Fmaj9, swelling in (0.6 s), easing to 80 %, let go 1.4 s before the end
    notes = (87.31, 130.81, 220.0, 329.63, 392.0)                          # F2 C3 A3 E4 G4
    pad = [0.0] * n
    for f in notes:
        for i, v in enumerate(supersaw(f, n, rnd)):
            pad[i] += v / len(notes)
    pad = svf_lowpass(pad, 2000)
    hold = T - 1.4
    at_hold = 0.8 + 0.2 * math.exp(-(hold - 0.6) / 1.5)
    for i in range(n):
        t = i / SR
        e = t / 0.6 if t < 0.6 else 0.8 + 0.2 * math.exp(-(t - 0.6) / 1.5)
        pad[i] *= at_hold * math.exp(-(t - hold) / 0.35) if t > hold else e
    # The sparkle: C6 E6 G6 A6 C7 rising from 0.5 s, 0.14 s apart
    sparkle = [0.0] * n
    for k, f in enumerate((1046.5, 1318.51, 1567.98, 1760.0, 2093.0)):
        s0 = int((0.5 + 0.14 * k) * SR)
        for i in range(int(0.5 * SR)):
            sparkle[s0 + i] += math.sin(2 * math.pi * f * i / SR) * math.exp(-i / SR / 0.12) * 0.25
    out = hall([a + b + c for a, b, c in zip(sub, pad, sparkle)])
    # No DC; the silence at the end trimmed (54 dB under the peak: -70 dBFS once written at -16)
    out = [v - w for v, w in zip(out, onepole(out, 20))]
    peak = max(abs(v) for v in out)
    last = max(i for i, v in enumerate(out) if abs(v) > peak * 10 ** (-54 / 20))
    return out[: last + int(0.05 * SR)]


# config/greeter's LoginView: Horizon as the screen appears (its first sparkle with the logo's first letter), ringing on
# past the prompt; a PC's power-on beep when the
# password prompt is printed, and the same short beep for every key press. Name → (sound, peak dBFS); the beeps are
# padded with silence, as write() fades the last 30 ms
KEYS = {
    "startup": (horizon, -16),
    "key": (lambda: beep(1000, .03) + [0.0] * int(.05 * SR), -30),
    "prompt": (lambda: beep(1000, .16) + [0.0] * int(.1 * SR), -26),
}

if __name__ == "__main__":
    for kind, sounds, peak in (("regular", REGULAR, -18), ("urgent", URGENT, -12)):
        for name, make in sounds.items():
            write(os.path.join(HERE, kind, name + ".wav"), make(), peak)
            print(f"{kind}/{name}.wav")
    for name, (make, peak) in AGENT.items():
        write(os.path.join(HERE, "agent", name + ".wav"), make(), peak)
        print(f"agent/{name}.wav")
    for name, (make, peak) in MAIL.items():
        write(os.path.join(HERE, "mail", name + ".wav"), make(), peak)
        print(f"mail/{name}.wav")
    for name, (make, peak) in KEYS.items():
        write(os.path.join(HERE, "keys", name + ".wav"), make(), peak)
        print(f"keys/{name}.wav")
