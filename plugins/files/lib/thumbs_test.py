"""thumbs.py: the freedesktop cache's names, a picture drawn once and used again, a changed file drawn again, a file
that can't be drawn marked as failed, and the other kinds left out. Runs in a throwaway XDG_CACHE_HOME."""
import hashlib, io, json, os, shutil, sys, tempfile, unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import thumbs

try:
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf
except (ImportError, ValueError):
    GdkPixbuf = None


def picture(path, w, h):
    pb = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, w, h)
    pb.fill(0x3366ccff)
    pb.savev(str(path), "png", [], [])


class Names(unittest.TestCase):
    def test_key_is_md5_of_uri(self):
        with tempfile.TemporaryDirectory() as d:
            os.environ["XDG_CACHE_HOME"] = d
            u, out, fail = thumbs.names("/tmp/a b.png", "large")
            self.assertEqual(u, "file:///tmp/a%20b.png")
            self.assertEqual(out, Path(d) / "thumbnails/large" / (hashlib.md5(u.encode()).hexdigest() + ".png"))
            self.assertEqual(fail.parent, Path(d) / "thumbnails/fail/nightdrive-files")

    def test_kinds(self):
        self.assertEqual(thumbs.kind("a.JPG"), "image")
        self.assertEqual(thumbs.kind("a.pdf"), "pdf")
        self.assertEqual(thumbs.kind("a.mkv"), "video")
        self.assertIsNone(thumbs.kind("a.txt"))


@unittest.skipUnless(GdkPixbuf, "needs GdkPixbuf (python3-gobject, gdk-pixbuf2)")
class Draw(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        os.environ["XDG_CACHE_HOME"] = os.path.join(self.dir, "cache")
        self.src = Path(self.dir) / "photo.png"
        picture(self.src, 800, 400)

    def tearDown(self):
        shutil.rmtree(self.dir)

    def run_main(self, *paths):
        buf = io.StringIO()
        with redirect_stdout(buf):
            thumbs.main(["thumbs.py", "large", *map(str, paths)])
        return [json.loads(line) for line in buf.getvalue().splitlines()]

    def test_draws_at_size_with_uri_and_mtime(self):
        out = thumbs.draw(self.src, "large")
        pb = GdkPixbuf.Pixbuf.new_from_file(str(out))
        self.assertEqual((pb.get_width(), pb.get_height()), (256, 128))
        self.assertEqual(pb.get_option("tEXt::Thumb::URI"), thumbs.uri(self.src))
        self.assertEqual(pb.get_option("tEXt::Thumb::MTime"), str(int(self.src.stat().st_mtime)))
        self.assertEqual(oct(out.stat().st_mode & 0o777), "0o600")

    def test_small_picture_not_enlarged(self):
        small = Path(self.dir) / "icon.png"
        picture(small, 40, 20)
        pb = GdkPixbuf.Pixbuf.new_from_file(str(thumbs.draw(small, "large")))
        self.assertEqual((pb.get_width(), pb.get_height()), (40, 20))

    def test_cached_used_again_and_changed_drawn_again(self):
        out = thumbs.draw(self.src, "large")
        first = out.stat().st_mtime_ns
        self.assertEqual(thumbs.draw(self.src, "large"), out)
        self.assertEqual(out.stat().st_mtime_ns, first)
        picture(self.src, 400, 400)
        os.utime(self.src, (1_000_000_000, 1_000_000_000))
        thumbs.draw(self.src, "large")
        pb = GdkPixbuf.Pixbuf.new_from_file(str(out))
        self.assertEqual(pb.get_option("tEXt::Thumb::MTime"), "1000000000")
        self.assertEqual(pb.get_width(), 256)

    def test_broken_marked_failed_and_left(self):
        bad = Path(self.dir) / "broken.jpg"
        bad.write_bytes(b"not a picture")
        self.assertIsNone(thumbs.draw(bad, "large"))
        _, out, fail = thumbs.names(bad, "large")
        self.assertFalse(out.exists())
        self.assertTrue(fail.exists())
        self.assertIsNone(thumbs.draw(bad, "large"))

    def test_main_prints_drawn_and_skips_others(self):
        text = Path(self.dir) / "notes.txt"
        text.write_text("hi")
        rows = self.run_main(self.src, text, Path(self.dir) / "gone.png")
        self.assertEqual([r["path"] for r in rows], [str(self.src)])
        self.assertTrue(Path(rows[0]["thumb"]).exists())
        # A second run finds it in the cache
        self.assertEqual(self.run_main(self.src), rows)


@unittest.skipUnless(GdkPixbuf and shutil.which("pdftoppm"), "needs pdftoppm (poppler-utils)")
class Pdf(unittest.TestCase):
    def test_first_page(self):
        with tempfile.TemporaryDirectory() as d:
            os.environ["XDG_CACHE_HOME"] = d
            pdf = Path(d) / "doc.pdf"
            # The smallest PDF with one empty A4 page
            objs = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>"]
            body, offsets = b"%PDF-1.4\n", []
            for i, o in enumerate(objs, 1):
                offsets.append(len(body))
                body += f"{i} 0 obj\n{o}\nendobj\n".encode()
            xref = len(body)
            body += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
            body += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
            body += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
            pdf.write_bytes(body)
            pb = GdkPixbuf.Pixbuf.new_from_file(str(thumbs.draw(pdf, "large")))
            self.assertEqual(pb.get_height(), 256)
            self.assertLess(pb.get_width(), 256)


if __name__ == "__main__":
    unittest.main()
