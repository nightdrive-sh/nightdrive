#!/usr/bin/env python3
"""A stand-in for voxtype and voxtype-onnx in transcribe_test.py: `-q [-c CONFIG] --engine E [--model M --language L]
transcribe FILE` prints what the real one does around the text (its progress lines and a warning), and as the text
the piece's length and what it was asked, so a test can see which piece went where. FAKE_VOXTYPE_LOG gets each call's
arguments; FAKE_VOXTYPE_FAIL makes it fail, FAKE_VOXTYPE_SLEEP slow (seconds a piece), and a piece shorter than a
second is "silence" (no text)."""

import os
import sys
import time
import wave

args = sys.argv[1:]
if os.environ.get("FAKE_VOXTYPE_LOG"):
    with open(os.environ["FAKE_VOXTYPE_LOG"], "a") as log:
        # A -c config's model goes in the log too: Recorder picks Parakeet's model there (voxtype.parakeet_config)
        conf = open(args[args.index("-c") + 1]).read() if "-c" in args else ""
        model = [ln.split("=")[1].strip(' "') for ln in conf.splitlines() if ln.startswith("model =")]
        line = [os.path.basename(sys.argv[0])] + args + [f"config-model={m}" for m in model]
        log.write(" ".join(line) + "\n")
if os.environ.get("FAKE_VOXTYPE_FAIL"):
    print("error: the model is broken", file=sys.stderr)
    sys.exit(1)
time.sleep(float(os.environ.get("FAKE_VOXTYPE_SLEEP", "0")))

path = args[args.index("transcribe") + 1]
with wave.open(path) as w:
    rate, frames = w.getframerate(), w.getnframes()
engine = args[args.index("--engine") + 1]
language = args[args.index("--language") + 1] if "--language" in args else "-"
print(f'Loading audio file: "{path}"')
print(f"Audio format: {rate} Hz, 1 channel(s), Int")
print(f"Processing {frames} samples ({frames / rate:.2f}s)...")
print("\x1b[33m WARN\x1b[0m GPU device discovery failed")
print()
if frames >= rate:
    print(f"{engine} {language} {rate} {round(frames / rate)}s")
