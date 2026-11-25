"""peek.py on sounds (#3416): each kind the preview plays is marked audio with its length, a cover is drawn once and a
sound without one is remembered as such (an empty file), and a video gets its length beside its frame. Made with ffmpeg
in a throwaway folder and XDG_CACHE_HOME. And a PDF peeked by several at once (the pane and the big preview, #3614):
each gets its first page, drawn once."""
import json, os, shutil, subprocess, sys, tempfile, time, unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import peek

HAVE = all(shutil.which(t) for t in ("ffmpeg", "ffprobe"))


def ff(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True, capture_output=True)


@unittest.skipUnless(HAVE, "needs ffmpeg and ffprobe")
class Sounds(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        os.environ["XDG_CACHE_HOME"] = str(self.tmp / "cache")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def tone(self, name, seconds=2, extra=()):
        p = self.tmp / name
        ff("-f", "lavfi", "-i", f"sine=duration={seconds}", *extra, str(p))
        return p

    def test_each_kind_is_audio_with_its_length(self):
        for name, extra in (("a.mp3", ()), ("a.ogg", ()), ("a.flac", ()), ("a.wav", ()),
                            ("a.m4a", ("-c:a", "aac")), ("a.opus", ("-c:a", "libopus"))):
            with self.subTest(name):
                d = peek.peek(self.tone(name, 2, extra))
                self.assertIs(d.get("audio"), True)
                self.assertAlmostEqual(d["duration"], 2, delta=0.1)
                self.assertNotIn("text", d)

    def test_no_cover_is_remembered(self):
        p = self.tone("plain.mp3")
        self.assertIsNone(peek.peek(p)["picture"])
        marks = list((self.tmp / "cache/nightdrive/files/peek").iterdir())
        self.assertEqual([m.stat().st_size for m in marks], [0])
        self.assertIsNone(peek.peek(p)["picture"])

    def test_cover_is_drawn(self):
        src, pic = self.tone("src.mp3"), self.tmp / "pic.png"
        ff("-f", "lavfi", "-i", "testsrc=size=64x64:duration=1", "-frames:v", "1", str(pic))
        p = self.tmp / "covered.mp3"
        ff("-i", str(src), "-i", str(pic), "-map", "0", "-map", "1", "-c", "copy", "-id3v2_version", "3",
           "-disposition:v", "attached_pic", str(p))
        d = peek.peek(p)
        self.assertTrue(d["picture"] and Path(d["picture"]).stat().st_size > 0)

    def test_video_has_its_length(self):
        p = self.tmp / "v.mp4"
        ff("-f", "lavfi", "-i", "testsrc=size=64x64:duration=2", "-pix_fmt", "yuv420p", str(p))
        d = peek.peek(p)
        self.assertNotIn("audio", d)
        self.assertAlmostEqual(d["duration"], 2, delta=0.1)


# One page with a line of text, enough for pdftoppm
PDF = b"""%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Contents 4 0 R
  /Resources << /Font << /F1 5 0 R >> >> >> endobj
4 0 obj << /Length 40 >> stream
BT /F1 24 Tf 40 150 Td (A page) Tj ET
endstream endobj
5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
trailer << /Root 1 0 R >>
%%EOF
"""
CLI = str(Path(__file__).resolve().parent / "cli.py")


@unittest.skipUnless(shutil.which("pdftoppm"), "needs pdftoppm (poppler-utils)")
class PdfAtOnce(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        os.environ["XDG_CACHE_HOME"] = str(self.tmp / "cache")
        self.cache = self.tmp / "cache/nightdrive/files/peek"

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_each_peek_at_once_gets_the_page(self):
        # A shared part file once made the later of two peeks find it gone and say there was no picture
        for n in range(4):
            pdf = self.tmp / f"new{n}.pdf"
            pdf.write_bytes(PDF)
            runs = [subprocess.Popen([sys.executable, "-I", CLI, "peek", str(pdf), "--long"], stdout=subprocess.PIPE,
                                     env=os.environ) for _ in range(3)]
            outs = [json.loads(r.communicate(timeout=30)[0]) for r in runs]
            with self.subTest(n):
                self.assertTrue(all(o["picture"] for o in outs), outs)
                self.assertEqual(len({o["picture"] for o in outs}), 1)
        self.assertEqual(sorted(p.suffix for p in self.cache.iterdir()), [".png"] * 4)

    def test_an_old_part_is_swept(self):
        self.cache.mkdir(parents=True)
        old, young = self.cache / "x.1.part.png", self.cache / "x.2.part.png"
        old.touch(); young.touch()
        os.utime(old, (time.time() - 3600,) * 2)
        pdf = self.tmp / "a.pdf"
        pdf.write_bytes(PDF)
        self.assertTrue(peek.peek(pdf)["picture"])
        self.assertFalse(old.exists())
        self.assertTrue(young.exists())


if __name__ == "__main__":
    unittest.main()
