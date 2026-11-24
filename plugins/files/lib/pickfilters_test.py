#!/usr/bin/env python3
"""The file types of Files' Open and Save window (pickfilters.py): a MIME type becomes its globs from the MIME database
(image/* every image's, */* any file), the globs one regex that matches as fnmatch does but in any case, and the ending a
saved file takes (the app's own glob first, .jpg for image/jpeg, none for image/*). A small globs2 of the test's own
stands in for the system's."""
import fnmatch, os, re, sys, tempfile, unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pickfilters as pf  # noqa: E402

GLOBS2 = """# a comment
50:image/png:*.png
50:image/jpeg:*.jfif
50:image/jpeg:*.jpeg
50:image/jpeg:*.jpg
50:text/plain:*.txt
"""


class Filters(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.tmp, "mime"))
        Path(self.tmp, "mime", "globs2").write_text(GLOBS2)
        self.table = pf.load_globs([self.tmp, os.path.join(self.tmp, "none")])

    def expand(self, *rules):
        return pf.expand([{"name": "t", "rules": [list(r) for r in rules]}], self.table)[0]

    def test_mime_globs(self):
        self.assertEqual(self.table["image/jpeg"], ["*.jfif", "*.jpeg", "*.jpg"])
        self.assertEqual(self.expand((1, "image/*"))["globs"], ["*.png", "*.jfif", "*.jpeg", "*.jpg"])
        self.assertEqual(self.expand((1, "*/*"))["regex"], "")
        self.assertEqual(self.expand((0, "*.txt"), (1, "text/plain"))["globs"], ["*.txt"])

    def test_regex_matches_as_fnmatch_in_any_case(self):
        globs = ["*.png", "*.[jJ]pg", "file?.txt", "[!a]*.tar.gz", "a+b(1).md", "*.c++"]
        rx = re.compile(pf.regex(globs), re.I)
        for name in ["x.png", "PHOTO.PNG", "y.Jpg", "file1.txt", "file12.txt", "b.tar.gz", "a.tar.gz", "a+b(1).md",
                     "ab1.md", "x.c++", "x.png.bak", ".png"]:
            want = any(fnmatch.fnmatchcase(name.lower(), g.lower()) for g in globs)
            self.assertEqual(bool(rx.match(name)), want, name)

    def test_ending(self):
        self.assertEqual(self.expand((1, "image/jpeg"))["ending"], "jpg")
        self.assertEqual(self.expand((0, "*.jpeg"), (1, "image/jpeg"))["ending"], "jpeg")
        self.assertEqual(self.expand((1, "image/*"))["ending"], "")
        self.assertEqual(self.expand((0, "*"))["ending"], "")
        self.assertEqual(self.expand((0, "Makefile"))["ending"], "")

    def test_no_database_needed_for_globs(self):
        f = pf.expand([{"name": "t", "rules": [[0, "*.md"]]}])[0]
        self.assertEqual((f["globs"], f["ending"]), (["*.md"], "md"))


if __name__ == "__main__":
    unittest.main()
