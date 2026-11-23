"""detect.py: the language guess, on words and sentences it must get right."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import detect  # noqa: E402


class Detect(unittest.TestCase):
    def test_finnish_words(self):
        for word in "kolinaa sisu talo koira nopeasti kiitos huomenta tietokone metsä ystävä lähettää kauppa".split():
            self.assertEqual(detect.detect(word, "fi", "en"), "fi", word)

    def test_english_words_by_letters(self):
        # No dictionary needed for these: the trigrams alone tell
        for word in "rattling quickly thanks invoice computer forest friend country window".split():
            self.assertEqual(detect.detect(word, "fi", "en"), "en", word)

    def test_sentences(self):
        self.assertEqual(detect.detect("Kuulin kellarista outoa kolinaa.", "fi", "en"), "fi")
        self.assertEqual(detect.detect("Could you send the invoice next week?", "en", "fi"), "en")
        self.assertEqual(detect.detect("see you tomorrow", "fi", "en"), "en")
        self.assertEqual(detect.detect("nähdään huomenna", "fi", "en"), "fi")

    def test_other_pairs_and_nothing_to_go_on(self):
        self.assertIsNone(detect.detect("god morgon", "sv", "en"))
        self.assertIsNone(detect.detect("123 !?", "fi", "en"))

    @unittest.skipUnless(detect.ENGLISH_DIC.exists(), "needs hunspell-en-US's dictionary")
    def test_english_words_the_dictionary_settles(self):
        for word in "milk lake banana noise moon".split():
            self.assertEqual(detect.detect(word, "fi", "en"), "en", word)


if __name__ == "__main__":
    unittest.main()
