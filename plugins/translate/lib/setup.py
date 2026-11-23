"""Installing and removing engines: the venv the offline ones run in, their models, translate-shell's package.

A model is downloaded into the engine's folder, checked against the sha256 its entry gives (a file that doesn't match
is deleted and the install stops), and for Opus-MT converted from the university's Marian file to CTranslate2's
8-bit format: a quarter of the size, and what ct2_worker.py reads. Everything is under ~/.local/share/nightdrive/
translate, so removing an engine is removing its folder.
"""
import hashlib
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

import config
from config import Problem

PACKAGES = ["ctranslate2", "sentencepiece"]     # the offline engines' Python packages, in the venv
CHUNK = 1 << 20


def say(text):
    print(text, file=sys.stderr, flush=True)


def installed(name, spec):
    kind = spec["type"]
    if kind == "ct2":
        return bool(spec.get("pairs")) and all((config.model_dir(name) / pair / "model.bin").exists()
                                               for pair in spec["pairs"])
    if kind == "nllb":
        return (config.model_dir(name) / "model.bin").exists()
    if kind == "trans":
        return shutil.which("trans") is not None
    if kind == "claude":
        return shutil.which("claude") is not None or (config.HOME / ".local/bin/claude").exists()
    return True          # the user's own command: theirs to have


def venv():
    """The venv with the offline engines' packages, made on first use (uv when there, else Python's own venv)."""
    python = config.VENV / "bin" / "python"
    probe = [str(python), "-c", "import ctranslate2, sentencepiece"]
    if python.exists() and subprocess.run(probe, capture_output=True).returncode == 0:
        return python
    say("Setting up the translation library (CTranslate2)…")
    config.DATA_DIR.mkdir(parents=True, exist_ok=True)
    if shutil.which("uv"):
        steps = [["uv", "venv", "--quiet", "--allow-existing", str(config.VENV)],
                 ["uv", "pip", "install", "--quiet", "--python", str(python)] + PACKAGES]
    else:
        steps = [[sys.executable, "-m", "venv", str(config.VENV)],
                 [str(python), "-m", "pip", "install", "--quiet"] + PACKAGES]
    for step in steps:
        if subprocess.run(step).returncode != 0:
            raise Problem("Couldn't set up the translation library: " + " ".join(step[:3]) + " failed")
    return python


def download(url, dest, sha256):
    """url → dest, with a progress line; the file is kept only when its sha256 is the expected one."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    digest = hashlib.sha256()
    request = urllib.request.Request(url, headers={"User-Agent": "nightdrive-translate"})
    try:
        with urllib.request.urlopen(request, timeout=60) as reply, open(part, "wb") as out:
            total, got = int(reply.headers.get("Content-Length") or 0), 0
            while chunk := reply.read(CHUNK):
                out.write(chunk)
                digest.update(chunk)
                got += len(chunk)
                if sys.stderr.isatty():
                    of = f" of {total >> 20} MB" if total else ""
                    print(f"\r  {dest.name}: {got >> 20}{of} MB", end="", file=sys.stderr, flush=True)
        if sys.stderr.isatty():
            print(file=sys.stderr)
    except OSError as error:
        part.unlink(missing_ok=True)
        raise Problem(f"Downloading {url} failed: {error}")
    if digest.hexdigest() != sha256:
        part.unlink(missing_ok=True)
        raise Problem(f"{dest.name} isn't the file expected (its checksum differs): nothing was installed")
    part.replace(dest)


def install_opus(name, spec, python):
    converter = python.with_name("ct2-opus-mt-converter")
    for pair, source in spec["pairs"].items():
        target = config.model_dir(name) / pair
        if (target / "model.bin").exists():
            continue
        say(f"{spec['name']} {pair}: downloading…")
        work = config.model_dir(name) / f".{pair}.work"
        shutil.rmtree(work, ignore_errors=True)
        archive = work / "model.zip"
        try:
            download(source["url"], archive, source["sha256"])
            with zipfile.ZipFile(archive) as bundle:
                # Only the model, its vocabulary and tokenizers: the archive's scripts are never run or kept. Names
                # are flattened, so nothing in it can land outside the work folder
                for member in bundle.infolist():
                    base = Path(member.filename).name
                    if base.endswith((".npz", ".yml", ".spm")):
                        with bundle.open(member) as src, open(work / base, "wb") as out:
                            shutil.copyfileobj(src, out)
            archive.unlink()
            say(f"{spec['name']} {pair}: converting…")
            built = work / "ct2"
            done = subprocess.run([str(converter), "--model_dir", str(work), "--output_dir", str(built),
                                   "--quantization", "int8"], capture_output=True, text=True)
            if done.returncode != 0:
                raise Problem(f"Converting {pair} failed: " + (done.stderr.strip().splitlines() or ["?"])[-1])
            for tokenizer in ("source.spm", "target.spm"):
                shutil.move(str(work / tokenizer), str(built / tokenizer))
            shutil.rmtree(target, ignore_errors=True)
            built.replace(target)
        finally:
            shutil.rmtree(work, ignore_errors=True)


def install_nllb(name, spec):
    folder = config.model_dir(name)
    # model.bin last: it is what marks the engine installed
    try:
        for filename, sha256 in sorted(spec["files"].items(), key=lambda item: item[0] == "model.bin"):
            if not (folder / filename).exists():
                say(f"{spec['name']}: downloading {filename}…")
                download(spec["base"] + filename, folder / filename, sha256)
    finally:
        if folder.is_dir() and not any(folder.iterdir()):
            folder.rmdir()           # nothing arrived: no empty folder left behind


def install(name):
    name, spec = config.engine(name)
    kind = spec["type"]
    if kind in ("ct2", "nllb"):
        python = venv()
        if kind == "ct2":
            install_opus(name, spec, python)
        else:
            install_nllb(name, spec)
    elif kind == "trans":
        if not shutil.which("trans"):
            packages = spec.get("packages", ["translate-shell"])
            say("Installing " + " ".join(packages) + " (asks for your password)…")
            if subprocess.run(["sudo", "dnf", "install", "-y"] + packages).returncode != 0:
                raise Problem("Installing " + " ".join(packages) + " failed")
    elif not installed(name, spec):
        raise Problem(f"{spec.get('name', name)} needs Claude Code: https://claude.com/claude-code")
    say(f"{spec.get('name', name)} is installed.")
    return name, spec


def remove(name):
    name, spec = config.engine(name)
    if spec["type"] not in ("ct2", "nllb"):
        raise Problem(f"{spec.get('name', name)} has no files of its own to remove")
    shutil.rmtree(config.model_dir(name), ignore_errors=True)
    # The venv goes with the last model that used it
    if not any(installed(n, s) for n, s in config.engines().items() if s["type"] in ("ct2", "nllb")):
        shutil.rmtree(config.VENV, ignore_errors=True)
    say(f"{spec.get('name', name)} removed.")
