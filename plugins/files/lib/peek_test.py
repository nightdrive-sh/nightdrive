"""peek.py on sounds (#3416): each kind the preview plays is marked audio with its length, a cover is drawn once and a
sound without one is remembered as such (an empty file), and a video gets its length beside its frame. Made with ffmpeg
in a throwaway folder and XDG_CACHE_HOME."""
import os, shutil, subprocess, sys, tempfile, unittest
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


if __name__ == "__main__":
    unittest.main()
