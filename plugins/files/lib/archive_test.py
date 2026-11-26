#!/usr/bin/env python3
"""Files' archives, made and unpacked: `python3 plugins/files/lib/archive_test.py`. What is packed comes back the same in
each format; nothing is written over (" (2)"); one thing at an archive's top lands as itself, several in a folder of
the archive's name; and an archive made to harm (paths with "..", absolute ones, links out of the folder, a file written
through a link, hard links) writes nothing outside the folder it unpacks into. A stopped one leaves nothing behind."""

import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fsops, pack, unpack  # noqa: E402


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.src = self.root / "src"
        self.out = self.root / "out"
        self.src.mkdir()
        self.out.mkdir()
        fsops._stop = False

    def tearDown(self):
        fsops._stop = False
        self.tmp.cleanup()

    def tree(self):
        (self.src / "docs" / "deep").mkdir(parents=True)
        (self.src / "docs" / "a.txt").write_text("alpha")
        (self.src / "docs" / "deep" / "b.bin").write_bytes(os.urandom(3 * 1024 * 1024))
        (self.src / "docs" / "empty").mkdir()
        os.symlink("a.txt", self.src / "docs" / "link")
        (self.src / "note.md").write_text("# hi")

    def listing(self, d):
        """Every path under d with what it is and holds, for comparing two trees."""
        out = {}
        for p in sorted(d.rglob("*")):
            rel = str(p.relative_to(d))
            out[rel] = ("link", os.readlink(p)) if p.is_symlink() else ("dir",) if p.is_dir() else ("file", p.read_bytes())
        return out

    def no_hidden_left(self, d):
        self.assertEqual([p.name for p in d.iterdir() if p.name.startswith(".")], [])


class RoundTrip(Base):
    def test_every_format_comes_back_the_same(self):
        self.tree()
        for fmt in pack.FORMATS:
            with self.subTest(fmt=fmt):
                made = pack.compress([self.src / "docs"], self.out, "docs", fmt)["made"][0]
                self.assertTrue(made.endswith(pack.FORMATS[fmt]))
                dest = self.root / ("x-" + fmt)
                dest.mkdir()
                got = unpack.extract(made, dest)
                self.assertEqual(got["skipped"], [])
                self.assertEqual(got["made"], [str(dest / "docs")])
                self.assertEqual(self.listing(dest / "docs"), self.listing(self.src / "docs"))
                self.no_hidden_left(self.out)
                self.no_hidden_left(dest)

    def test_several_at_the_top_land_in_a_folder_of_the_archive_name(self):
        self.tree()
        made = pack.compress([self.src / "docs", self.src / "note.md"], self.out, "src", "tar.gz")["made"][0]
        got = unpack.extract(made)
        self.assertEqual(got["made"], [str(self.out / "src")])
        self.assertEqual(sorted(os.listdir(self.out / "src")), ["docs", "note.md"])
        self.assertEqual(oct((self.out / "src").stat().st_mode & 0o700), oct(0o700))

    def test_one_file_lands_as_itself(self):
        self.tree()
        made = pack.compress([self.src / "note.md"], self.out, "note", "zip")["made"][0]
        self.assertEqual(unpack.extract(made)["made"], [str(self.out / "note.md")])

    def test_same_names_from_different_folders_both_go_in(self):
        (self.src / "one").mkdir(); (self.src / "two").mkdir()
        (self.src / "one" / "r.txt").write_text("1"); (self.src / "two" / "r.txt").write_text("2")
        made = pack.compress([self.src / "one" / "r.txt", self.src / "two" / "r.txt"], self.out, "r", "zip")["made"][0]
        self.assertEqual(sorted(zipfile.ZipFile(made).namelist()), ["r (2).txt", "r.txt"])


class NothingOverwritten(Base):
    def test_archive_name_taken_gets_a_number(self):
        (self.src / "f.txt").write_text("x")
        (self.out / "f.zip").write_text("mine")
        made = pack.compress([self.src / "f.txt"], self.out, "f.zip", "zip")["made"][0]
        self.assertEqual(Path(made).name, "f (2).zip")
        self.assertEqual((self.out / "f.zip").read_text(), "mine")
        made = pack.compress([self.src / "f.txt"], self.out, "f", "tar.gz")["made"][0]
        self.assertEqual(Path(made).name, "f.tar.gz")
        made = pack.compress([self.src / "f.txt"], self.out, "f", "tar.gz")["made"][0]
        self.assertEqual(Path(made).name, "f (2).tar.gz")

    def test_unpacked_name_taken_gets_a_number(self):
        self.tree()
        made = pack.compress([self.src / "docs"], self.out, "docs", "zip")["made"][0]
        (self.out / "docs").mkdir()
        (self.out / "docs" / "a.txt").write_text("mine")
        got = unpack.extract(made)
        self.assertEqual(got["made"], [str(self.out / "docs (2)")])
        self.assertEqual((self.out / "docs" / "a.txt").read_text(), "mine")
        self.assertEqual(os.listdir(self.out / "docs"), ["a.txt"])


def evil_tar(path, members):
    """A tar of (name, kind, data or link target) as an attacker would write it."""
    with tarfile.open(path, "w") as tf:
        for name, what, data in members:
            info = tarfile.TarInfo(name)
            if what == "file":
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))
            elif what == "dir":
                info.type = tarfile.DIRTYPE
                tf.addfile(info)
            else:
                info.type = tarfile.SYMTYPE if what == "sym" else tarfile.LNKTYPE
                info.linkname = data
                tf.addfile(info)


class Unsafe(Base):
    def setUp(self):
        super().setUp()
        self.dest = self.root / "nest" / "dest"      # ".." from here lands in nest, still inside the test's folder
        self.dest.mkdir(parents=True)

    def outside(self):
        """Every file under the test's folder that isn't in dest or the archives' own folder."""
        return [str(p) for p in self.root.rglob("*")
                if not p.is_dir() and self.dest not in p.parents and self.src not in p.parents]

    def test_dotdot_absolute_and_drive_paths_stay_out(self):
        target = self.root / "abs.txt"
        arc = self.src / "bad.tar"
        evil_tar(arc, [("../escape.txt", "file", b"x"), ("ok/../../escape2.txt", "file", b"x"),
                       (str(target), "file", b"x"), ("C:/win.txt", "file", b"x"), ("ok/fine.txt", "file", b"y")])
        got = unpack.extract(arc, self.dest)
        self.assertEqual(self.outside(), [])
        self.assertEqual(len(got["skipped"]), 4)
        self.assertEqual((self.dest / "ok" / "fine.txt").read_bytes(), b"y")

    def test_zip_dotdot_absolute_and_backslash_paths_stay_out(self):
        arc = self.src / "bad.zip"
        with zipfile.ZipFile(arc, "w") as zf:
            for name in ("../escape.txt", "/abs.txt", "..\\back.txt", "ok\\fine.txt"):
                zf.writestr(zipfile.ZipInfo(name), b"x")
        got = unpack.extract(arc, self.dest)
        self.assertEqual(self.outside(), [])
        self.assertEqual(len(got["skipped"]), 3)
        self.assertTrue((self.dest / "ok" / "fine.txt").is_file())

    def test_links_out_are_left_out_and_inside_ones_kept(self):
        arc = self.src / "links.tar"
        evil_tar(arc, [("d/a.txt", "file", b"a"), ("d/in", "sym", "a.txt"), ("d/up", "sym", "../d/a.txt"),
                       ("d/out", "sym", "../../x"), ("d/abs", "sym", "/etc/passwd"), ("d/hard", "hard", "/etc/passwd")])
        got = unpack.extract(arc, self.dest)
        d = self.dest / "d"
        self.assertEqual(sorted(os.listdir(d)), ["a.txt", "in", "up"])
        self.assertEqual(sorted(got["skipped"]), ["d/abs", "d/hard", "d/out"])

    def test_no_file_written_through_a_link(self):
        """A link to a folder outside, then a file "through" it: the classic way out of a naive unpacker."""
        victim = self.root / "victim"
        victim.mkdir()
        arc = self.src / "through.tar"
        evil_tar(arc, [("top/esc", "sym", str(victim)), ("top/esc/pwned.txt", "file", b"x"),
                       ("top/rel", "sym", "../../../victim"), ("top/rel/pwned2.txt", "file", b"x"),
                       ("top/ok.txt", "file", b"ok")])
        unpack.extract(arc, self.dest)
        self.assertEqual(os.listdir(victim), [])
        self.assertEqual(self.outside(), [])

    def test_file_then_dir_of_same_name_and_duplicates(self):
        arc = self.src / "dup.tar"
        evil_tar(arc, [("a/x", "file", b"first"), ("a/x", "file", b"second"), ("a/x/y", "file", b"z")])
        got = unpack.extract(arc, self.dest)
        self.assertEqual((self.dest / "a" / "x").read_bytes(), b"first")
        self.assertEqual(sorted(got["skipped"]), ["a/x", "a/x/y"])

    def test_setuid_dropped(self):
        arc = self.src / "suid.tar"
        with tarfile.open(arc, "w") as tf:
            info = tarfile.TarInfo("run"); info.size = 1; info.mode = 0o4755
            tf.addfile(info, io.BytesIO(b"x"))
        unpack.extract(arc, self.dest)
        self.assertEqual((self.dest / "run").stat().st_mode & 0o7777, 0o755)

    def test_nothing_safe_is_refused_and_leaves_nothing(self):
        arc = self.src / "all-bad.tar"
        evil_tar(arc, [("../a", "file", b"x")])
        with self.assertRaises(fsops.Refused):
            unpack.extract(arc, self.dest)
        self.assertEqual(os.listdir(self.dest), [])

    def test_not_an_archive(self):
        bad = self.src / "fake.zip"
        bad.write_text("not a zip")
        with self.assertRaises(fsops.Refused):
            unpack.extract(bad, self.dest)
        self.assertEqual(os.listdir(self.dest), [])


class Stop(Base):
    def test_stopped_pack_and_unpack_leave_nothing(self):
        self.tree()
        made = pack.compress([self.src / "docs"], self.out, "docs", "tar.gz")["made"][0]

        def stop(*_):
            fsops._stop = True
        self.assertEqual(pack.compress([self.src / "docs"], self.out, "again", "zip", stop)["made"], [])
        fsops._stop = False
        dest = self.root / "dest"; dest.mkdir()
        got = unpack.extract(made, dest, stop)
        self.assertTrue(got["stopped"])
        self.assertEqual(os.listdir(dest), [])
        self.assertEqual(sorted(os.listdir(self.out)), ["docs.tar.gz"])


class Cli(Base):
    def run_cli(self, *args):
        p = subprocess.run([sys.executable, "-I", str(HERE / "cli.py"), *args], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(p.stdout.strip().splitlines()[-1])

    def test_compress_and_extract_have_undo(self):
        self.tree()
        d = self.run_cli("compress", "--into", str(self.out), "--name", "docs", "--format", "zip", "--", str(self.src / "docs"))
        self.assertEqual(d["undo"][0], "trash")
        e = self.run_cli("extract", d["made"][0])
        self.assertEqual(e["made"], [str(self.out / "docs")])
        self.assertEqual(e["undo"], ["trash", "--", str(self.out / "docs")])

    def test_kind_and_stem(self):
        self.assertEqual(unpack.kind("a.ZIP"), "zip")
        self.assertEqual(unpack.kind("a.tar.xz"), "tar")
        self.assertEqual(unpack.kind("a.tgz"), "tar")
        self.assertIsNone(unpack.kind("a.gz"))
        self.assertEqual(unpack.stem("photos.tar.gz"), "photos")
        self.assertEqual(pack.with_ending("x", "tar.xz"), "x.tar.xz")
        self.assertEqual(pack.with_ending("x.zip", "zip"), "x.zip")


if __name__ == "__main__":
    unittest.main()
