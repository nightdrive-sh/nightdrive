#!/usr/bin/env python3
"""Save on Ask Claude's result cards (#2245): `python3 config/hypr/scripts/ask-claude.d/save_test.py`. A download is
copied into Downloads under a free name (never over a file), 0644, with where it came from in its xattrs; anything
but one of the conversation's own downloads is refused."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "save.py"
CONV = "0123abcd-0000-4000-8000-00000000beef"


def xattrs_work(folder):
    probe = Path(folder) / ".probe"
    probe.write_bytes(b"")
    try:
        os.setxattr(probe, "user.test", b"1")
        return True
    except OSError:
        return False
    finally:
        probe.unlink()


class Save(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.tmp)]))
        self.state = self.tmp / "state"
        self.files = self.state / "nightdrive/ask" / CONV / "files"
        self.files.mkdir(parents=True)
        self.down = self.tmp / "Downloads"

    def download(self, name, data=b"OggS sound", origin=None):
        path = self.files / name
        path.write_bytes(data)
        path.chmod(0o600)
        if origin:
            try:
                os.setxattr(path, "user.xdg.origin.url", origin.encode())
            except OSError:
                pass
        return path

    def save(self, *args, conv=CONV):
        env = {"HOME": str(self.tmp), "XDG_STATE_HOME": str(self.state), "PATH": os.environ["PATH"]}
        return subprocess.run([str(SCRIPT), "--into", str(self.down), conv, *args], env=env,
                              capture_output=True, text=True, timeout=10)

    def test_copies_into_downloads(self):
        self.download("engine.ogg", b"OggS 1")
        r = self.save("engine.ogg")
        self.assertEqual(r.returncode, 0, r.stderr)
        out = json.loads(r.stdout)
        self.assertEqual(out["name"], "engine.ogg")
        saved = Path(out["path"])
        self.assertEqual(saved, self.down / "engine.ogg")
        self.assertEqual(saved.read_bytes(), b"OggS 1")
        self.assertEqual(saved.stat().st_mode & 0o777, 0o644)
        self.assertTrue((self.files / "engine.ogg").exists())   # a copy: the card still has its file

    def test_never_overwrites(self):
        self.download("engine.ogg", b"new")
        self.down.mkdir()
        (self.down / "engine.ogg").write_bytes(b"mine")
        (self.down / "engine (2).ogg").write_bytes(b"mine too")
        names = [json.loads(self.save("engine.ogg").stdout)["name"] for _ in range(2)]
        self.assertEqual(names, ["engine (3).ogg", "engine (4).ogg"])
        self.assertEqual((self.down / "engine.ogg").read_bytes(), b"mine")
        self.assertEqual((self.down / "engine (2).ogg").read_bytes(), b"mine too")
        self.assertEqual((self.down / "engine (4).ogg").read_bytes(), b"new")

    def test_numbering_keeps_the_extension(self):
        self.download("photo.v2.jpg")
        self.download("README")
        self.save("photo.v2.jpg"), self.save("README")
        self.assertEqual(json.loads(self.save("photo.v2.jpg").stdout)["name"], "photo.v2 (2).jpg")
        self.assertEqual(json.loads(self.save("README").stdout)["name"], "README (2)")

    def test_a_link_in_downloads_is_not_followed(self):
        self.download("engine.ogg", b"new")
        self.down.mkdir()
        target = self.tmp / "elsewhere"
        target.write_bytes(b"keep")
        (self.down / "engine.ogg").symlink_to(target)
        self.assertEqual(json.loads(self.save("engine.ogg").stdout)["name"], "engine (2).ogg")
        self.assertEqual(target.read_bytes(), b"keep")

    def test_source_goes_with_it(self):
        if not xattrs_work(self.tmp):
            self.skipTest("no user xattrs on this file system")
        self.download("engine.ogg", origin="https://cdn.example.org/engine.ogg")
        cards = {"version": 1, "cards": [{"n": 1, "type": "sound", "file": "engine.ogg",
                                          "url": "https://freesound.example/s/1/"}]}
        (self.files.parent / "results.json").write_text(json.dumps(cards))
        saved = json.loads(self.save("engine.ogg").stdout)["path"]
        self.assertEqual(os.getxattr(saved, "user.xdg.origin.url"), b"https://cdn.example.org/engine.ogg")
        self.assertEqual(os.getxattr(saved, "user.xdg.referrer.url"), b"https://freesound.example/s/1/")

    def test_refuses_what_isnt_a_download(self):
        self.download("engine.ogg")
        self.download("half.ogg.part")
        (self.files / "link.ogg").symlink_to(self.files / "engine.ogg")
        secret = self.tmp / "secret"
        secret.write_text("x")
        for name in ("../../../../secret", "link.ogg", "half.ogg.part", ".hidden", "missing.ogg", ""):
            with self.subTest(name=name):
                r = self.save(name)
                self.assertEqual(r.returncode, 1, r.stdout)
        self.assertEqual(self.save("engine.ogg", conv="../" + CONV).returncode, 1)
        self.assertFalse(self.down.exists() and any(p.name != "engine.ogg" for p in self.down.iterdir()))


if __name__ == "__main__":
    unittest.main()
