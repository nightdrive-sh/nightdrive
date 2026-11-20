"""Inbox files for <audio>/<video> (media.py): byte ranges as iOS asks for them, and Ogg converted to AAC once.

    python3 config/companion/lib/media_test.py
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import media  # noqa: E402


class Range(unittest.TestCase):
    def test_ranges(self):
        r = media.byte_range
        self.assertIsNone(r(None, 100))
        self.assertIsNone(r("", 100))
        self.assertEqual(r("bytes=0-1", 100), (0, 1))            # iOS's first probe
        self.assertEqual(r("bytes=10-", 100), (10, 99))          # open-ended
        self.assertEqual(r("bytes=90-500", 100), (90, 99))       # past the end: cut to it
        self.assertEqual(r("bytes=-30", 100), (70, 99))          # the last 30
        self.assertEqual(r("bytes=-500", 100), (0, 99))
        self.assertIsNone(r("bytes=0-1,5-9", 100))               # several: the whole file
        self.assertIsNone(r("items=0-1", 100))
        for bad in ("bytes=100-", "bytes=5-2", "bytes=-0"):
            with self.assertRaises(ValueError):
                r(bad, 100)


def encoders():
    if not shutil.which("ffmpeg"):
        return ""
    return subprocess.run(["ffmpeg", "-v", "error", "-encoders"], capture_output=True, text=True).stdout


ENC = encoders()


@unittest.skipUnless(" aac " in ENC and " libvorbis " in ENC, "needs ffmpeg with aac and libvorbis")
class Convert(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        self.cache = media.CACHE
        media.CACHE = os.path.join(self.dir, "cache")
        self.addCleanup(setattr, media, "CACHE", self.cache)

    def test_ogg_once(self):
        src = os.path.join(self.dir, "note.ogg")
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i", "sine=d=1", "-c:a", "libvorbis",
                        src], check=True)
        out = media.as_m4a(src, "audio/ogg")
        with open(out, "rb") as f:
            self.assertEqual(f.read(12)[4:8], b"ftyp")              # an MP4 container
        self.assertEqual(media.as_m4a(src, "audio/ogg"), out)        # from the cache the second time
        self.assertEqual(os.listdir(media.CACHE), [os.path.basename(out)])

    def test_not_audio(self):
        with self.assertRaises(media.MediaError):
            media.as_m4a(__file__, "video/webm")


if __name__ == "__main__":
    unittest.main()
