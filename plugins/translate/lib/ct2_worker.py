"""The offline engines' translator: run by the venv's Python (lib/setup.py made it), never the system's.

Reads one JSON job on stdin, {"kind": "ct2" | "nllb", "dir", "text", "from", "to", "alternatives"}, and prints
{"translation", "alternatives"}. A process per translation is fast enough to translate while typing (the model is
mapped from disk: about 0.1 s for Opus-MT, 0.5 s for NLLB), so there is no server to keep alive.
"""
import json
import re
import sys

import ctranslate2
import sentencepiece

BEAM = 6             # the beam the Opus-MT models were tuned with (their decoder.yml), length-normalised
MAX_ALTERNATIVES = 4
# NLLB names languages by FLORES-200 codes; a code given in that form already passes as it is
FLORES = {"fi": "fin_Latn", "en": "eng_Latn", "sv": "swe_Latn", "de": "deu_Latn", "fr": "fra_Latn", "es": "spa_Latn",
          "it": "ita_Latn", "et": "est_Latn", "no": "nob_Latn", "da": "dan_Latn", "nl": "nld_Latn", "pl": "pol_Latn",
          "ru": "rus_Cyrl", "uk": "ukr_Cyrl", "ja": "jpn_Jpan", "zh": "zho_Hans", "pt": "por_Latn", "is": "isl_Latn",
          "hu": "hun_Latn", "cs": "ces_Latn", "tr": "tur_Latn", "el": "ell_Grek", "lv": "lvs_Latn", "lt": "lit_Latn"}


def segments(text):
    """The text a sentence at a time, each with what followed it: the models were trained on single sentences."""
    out = []
    for line in text.split("\n"):
        parts = re.split(r"(?<=[.!?…])\s+", line.strip()) if line.strip() else []
        for i, part in enumerate(parts):
            out.append((part, " " if i < len(parts) - 1 else "\n"))
        if not parts:
            out.append(("", "\n"))
    return out


def unique(items):
    seen, out = set(), []
    for item in items:
        key = item.strip().lower()
        if key and key not in seen:
            seen.add(key)
            out.append(item.strip())
    return out


def main():
    job = json.load(sys.stdin)
    folder = job["dir"]
    translator = ctranslate2.Translator(folder, device="cpu", compute_type="int8")
    if job["kind"] == "nllb":
        source = target = sentencepiece.SentencePieceProcessor(model_file=f"{folder}/sentencepiece.bpe.model")
        src = FLORES.get(job["from"], job["from"])
        tgt = FLORES.get(job["to"], job["to"])
        encode = lambda s: [src] + source.encode(s, out_type=str) + ["</s>"]
        prefix = [tgt]
    else:
        source = sentencepiece.SentencePieceProcessor(model_file=f"{folder}/source.spm")
        target = sentencepiece.SentencePieceProcessor(model_file=f"{folder}/target.spm")
        encode = lambda s: source.encode(s, out_type=str) + ["</s>"]
        prefix = None

    parts = segments(job["text"])
    real = [p for p, _ in parts if p]
    # Other wordings only for one short piece of text: for a paragraph they would be near-copies of it
    want = MAX_ALTERNATIVES if job.get("alternatives") and len(real) == 1 else 1
    results = translator.translate_batch(
        [encode(p) for p in real], target_prefix=[prefix] * len(real) if prefix else None,
        beam_size=max(BEAM, want), num_hypotheses=want, max_decoding_length=512, length_penalty=1,
    ) if real else []
    decode = lambda hyp: target.decode(hyp[1:] if prefix else hyp)

    done, pieces = iter(results), []
    alternatives = []
    for part, after in parts:
        if not part:
            pieces.append(after)
            continue
        hyps = unique(decode(h) for h in next(done).hypotheses)
        pieces.append((hyps[0] if hyps else "") + after)
        if want > 1:
            alternatives = hyps[1:]
    json.dump({"translation": "".join(pieces).strip(), "alternatives": alternatives}, sys.stdout, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
