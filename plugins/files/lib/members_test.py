#!/usr/bin/env python3
"""Looking into an archive without unpacking it: `python3 plugins/files/lib/members_test.py`. The listing of a zip and
of each tar is what unpacking would make (folders a tar leaves out put in, unsafe paths and links out counted, not
listed) and comes from the cache the second time; a member taken out for the preview is read-only and goes with its
slot; and members picked unpack alone, each under its own name, by unpack.py's rules: an archive made to harm writes
nothing outside the folder, no link points out, nothing is written over."""

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
import fsops, members, pack  # noqa: E402
from fsops import Refused  # noqa: E402


def evil_tar(path, items, mode="w"):
    """A tar of (name, kind, data or link target) as an attacker would write it."""
    with tarfile.open(path, mode) as tf:
        for name, what, data in items:
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


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.env = {k: os.environ.get(k) for k in ("XDG_CACHE_HOME", "XDG_RUNTIME_DIR")}
        os.environ["XDG_CACHE_HOME"] = str(self.root / "cache")
        os.environ["XDG_RUNTIME_DIR"] = str(self.root / "run")
        (self.root / "run").mkdir()
        self.src, self.out = self.root / "src", self.root / "out"
        self.src.mkdir()
        self.out.mkdir()
        fsops._stop = False

    def tearDown(self):
        for k, v in self.env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def tree(self):
        (self.src / "docs" / "deep").mkdir(parents=True)
        (self.src / "docs" / "a.txt").write_text("alpha")
        (self.src / "docs" / "deep" / "b.txt").write_text("beta")
        (self.src / "docs" / ".hidden").write_text("h")
        os.symlink("a.txt", self.src / "docs" / "link")
        (self.src / "note.md").write_text("# hi")

    def packed(self, fmt):
        self.tree()
        return pack.compress([self.src / "docs", self.src / "note.md"], self.root, "arc", fmt)["made"][0]

    def names(self, lst):
        return {e["name"]: e for e in lst["entries"]}


class Listing(Base):
    def test_every_format_lists_the_same(self):
        for fmt in pack.FORMATS:
            with self.subTest(fmt=fmt):
                for p in self.src.iterdir():
                    p.unlink() if p.is_file() or p.is_symlink() else __import__("shutil").rmtree(p)
                lst = members.listing(self.packed(fmt))
                n = self.names(lst)
                self.assertEqual(set(n), {"docs", "docs/a.txt", "docs/deep", "docs/deep/b.txt", "docs/.hidden",
                                          "docs/link", "note.md"})
                self.assertTrue(n["docs/deep"]["dir"])
                self.assertEqual(n["docs/a.txt"]["size"], 5)
                self.assertEqual(n["docs/link"]["link"], "a.txt")
                self.assertEqual(lst["skipped"], 0)

    def test_implied_folders_and_unsafe_paths(self):
        arc = self.root / "evil.tar"
        evil_tar(arc, [("../out.txt", "file", b"x"), ("/etc/passwd", "file", b"x"), ("C:/win.txt", "file", b"x"),
                       ("a/../../up.txt", "file", b"x"), ("only/deep/file.txt", "file", b"ok"),
                       ("hard", "hard", "only/deep/file.txt"), ("same.txt", "file", b"1"), ("same.txt", "file", b"2")])
        lst = members.listing(arc)
        self.assertEqual(set(self.names(lst)), {"only", "only/deep", "only/deep/file.txt", "same.txt"})
        self.assertEqual(lst["skipped"], 6)        # four paths out, the hard link, the second same.txt

    def test_cache_the_second_time_and_a_changed_archive_read_again(self):
        arc = self.packed("tar.gz")
        self.assertFalse(members.listing(arc)["cached"])
        self.assertTrue(members.listing(arc)["cached"])
        os.utime(arc, (1, 1))
        self.assertFalse(members.listing(arc)["cached"])

    def test_progress_while_a_tar_is_read(self):
        arc = self.root / "big.tar.gz"
        with tarfile.open(arc, "w:gz") as tf:
            for i in range(3000):
                info = tarfile.TarInfo(f"f{i}.bin"); data = os.urandom(512); info.size = len(data)
                tf.addfile(info, io.BytesIO(data))
        seen = []
        members.TICK, tick = 0, members.TICK
        try:
            members.listing(arc, lambda done, total, name: seen.append((done, total)))
        finally:
            members.TICK = tick
        self.assertTrue(seen)
        self.assertTrue(all(0 <= d <= t for d, t in seen))

    def test_not_an_archive_and_a_damaged_one(self):
        (self.root / "x.txt").write_text("x")
        with self.assertRaises(Refused):
            members.listing(self.root / "x.txt")
        (self.root / "bad.zip").write_bytes(b"PK not really")
        with self.assertRaises(Refused):
            members.listing(self.root / "bad.zip")
        (self.root / "bad.tar.gz").write_bytes(b"\x1f\x8b" + os.urandom(200))
        with self.assertRaises(Refused):
            members.listing(self.root / "bad.tar.gz")


class Preview(Base):
    def test_member_taken_out_read_only_and_cleaned(self):
        arc = self.packed("zip")
        d = members.peek_member(arc, "docs/a.txt", "w1")
        self.assertEqual(d["path"], f"{arc}/docs/a.txt")
        self.assertEqual(d["text"], "alpha")
        f = Path(d["file"])
        self.assertTrue(f.is_relative_to(self.root / "run"))
        self.assertEqual(f.stat().st_mode & 0o777, 0o400)
        self.assertEqual(members.member_file(arc, "docs/a.txt", "w1"), f)     # once, not again
        members.clean("w1")
        self.assertFalse(f.exists())

    def test_folder_and_link_are_not_taken_out(self):
        arc = self.packed("tar.xz")
        d = members.peek_member(arc, "docs", "w1")
        self.assertEqual((d["kind"], d["items"], d["hidden"]), ("Folder", 3, 1))
        self.assertEqual(members.peek_member(arc, "docs/link", "w1")["kind"], "Link")
        self.assertFalse((self.root / "run" / "nightdrive-files" / "w1").exists())

    def test_too_large_is_not_taken_out(self):
        arc = self.packed("tar")
        members.PREVIEW_MAX, big = 2, members.PREVIEW_MAX
        try:
            self.assertNotIn("file", members.peek_member(arc, "docs/a.txt", "w1"))
        finally:
            members.PREVIEW_MAX = big

    def test_slot_and_member_names_cannot_reach_out(self):
        arc = self.packed("zip")
        for slot in ("../x", "", "a/b", "A"):
            with self.assertRaises(Refused):
                members.peek_member(arc, "docs/a.txt", slot)
        with self.assertRaises(Refused):
            members.peek_member(arc, "../../etc/passwd", "w1")


class Extract(Base):
    def test_picked_land_under_their_own_names(self):
        for fmt in pack.FORMATS:
            with self.subTest(fmt=fmt):
                out = self.out / fmt
                out.mkdir()
                if not (self.root / f"arc.{fmt}").exists():
                    for p in list(self.src.iterdir()):
                        p.unlink() if p.is_file() or p.is_symlink() else __import__("shutil").rmtree(p)
                arc = self.packed(fmt)
                r = members.extract(arc, ["docs/deep", "docs/a.txt", "docs/link"], out)
                self.assertEqual(r["made"], [str(out / "deep"), str(out / "a.txt"), str(out / "link")])
                self.assertEqual((out / "deep" / "b.txt").read_text(), "beta")
                self.assertEqual((out / "a.txt").read_text(), "alpha")
                self.assertEqual(os.readlink(out / "link"), "a.txt")
                self.assertEqual([p.name for p in out.iterdir() if p.name.startswith(".")], [])

    def test_nothing_written_over_and_same_names_both_come(self):
        arc = self.root / "two.tar"
        evil_tar(arc, [("a/x/1.txt", "file", b"a"), ("b/x/2.txt", "file", b"b")])
        (self.out / "x").mkdir()
        r = members.extract(arc, ["a/x", "b/x"], self.out)
        self.assertEqual(r["made"], [str(self.out / "x (2)"), str(self.out / "x (3)")])
        self.assertEqual(sorted(p.name for p in (self.out / "x").iterdir()), [])
        self.assertEqual((self.out / "x (2)" / "1.txt").read_text(), "a")

    def test_links_out_left_out_and_nothing_through_a_link(self):
        arc = self.root / "links.tar"
        outside = self.root / "outside"
        outside.mkdir()
        evil_tar(arc, [("p/esc", "sym", "../../../outside"), ("p/abs", "sym", "/etc"), ("p/ok", "sym", "f.txt"),
                       ("p/f.txt", "file", b"f"), ("p/esc/pwn.txt", "file", b"pwn"), ("p/hard", "hard", "/etc/passwd")])
        r = members.extract(arc, ["p"], self.out)
        self.assertEqual(r["made"], [str(self.out / "p")])
        self.assertEqual(os.listdir(outside), [])
        self.assertFalse((self.out / "p" / "esc").is_symlink())
        self.assertFalse((self.out / "p" / "abs").exists())
        self.assertEqual(os.readlink(self.out / "p" / "ok"), "f.txt")
        self.assertFalse((self.out / "p" / "hard").exists())

    def test_a_link_out_of_what_was_picked_cannot_climb_out(self):
        arc = self.root / "climb.tar"
        evil_tar(arc, [("a/b/c/up", "sym", "../../x"), ("a/b/c/far", "sym", "../../../../../etc"),
                       ("a/b/c/side", "sym", "../c/f"), ("a/b/c/f", "file", b"f")])
        r = members.extract(arc, ["a/b/c"], self.out)
        self.assertEqual(sorted(os.listdir(self.out / "c")), ["f", "side"])
        self.assertEqual(sorted(r["skipped"]), ["a/b/c/far", "a/b/c/up"])

    def test_unsafe_or_missing_names_refused(self):
        arc = self.packed("zip")
        for bad in ("../x", "/etc/passwd", "docs/../note.md", "nope.txt", ""):
            with self.subTest(bad=bad), self.assertRaises(Refused):
                members.extract(arc, [bad], self.out)
        self.assertEqual(os.listdir(self.out), [])

    def test_stopped_leaves_nothing(self):
        arc = self.packed("tar.gz")
        members.listing(arc)
        fsops._stop = True
        r = members.extract(arc, ["docs"], self.out)
        fsops._stop = False
        self.assertTrue(r["stopped"])
        self.assertEqual(os.listdir(self.out), [])


class Cli(Base):
    def run_cli(self, *args):
        p = subprocess.run([sys.executable, "-I", str(HERE / "cli.py"), *args], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(p.stdout.strip().splitlines()[-1])

    def test_list_peek_extract_clean(self):
        arc = self.packed("tar.gz")
        self.assertIn("docs/a.txt", {e["name"] for e in self.run_cli("archive-list", arc)["entries"]})
        self.assertEqual(self.run_cli("member-peek", arc, "note.md", "--slot", "w9")["text"], "# hi")
        d = self.run_cli("extract-members", arc, "--into", str(self.out), "--", "note.md")
        self.assertEqual(d["undo"], ["trash", "--", str(self.out / "note.md")])
        self.run_cli("member-clean", "--slot", "w9")
        self.assertFalse((self.root / "run" / "nightdrive-files" / "w9").exists())


if __name__ == "__main__":
    unittest.main()
