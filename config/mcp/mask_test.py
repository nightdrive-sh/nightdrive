#!/usr/bin/env python3
"""mask.py's tests: `python3 config/mcp/mask_test.py`. The samples are in mask_samples.json, what gets hidden and what
must stay (order and phone numbers, dates, prices, plain links); the rest is how a tool's answer is masked."""

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import mask  # noqa: E402

SAMPLES = json.loads((HERE / "mask_samples.json").read_text())


class Samples(unittest.TestCase):
    def test_masked(self):
        for text, want in SAMPLES["masked"]:
            with self.subTest(text=text):
                self.assertEqual(mask.mask(text), want)

    def test_kept(self):
        for text in SAMPLES["kept"]:
            with self.subTest(text=text):
                self.assertEqual(mask.mask(text), text)

    def test_together(self):
        """A mail with several at once, and what isn't secret around them."""
        text = ("Hi! Order 12345678 is on its way (29.10.2026).\n"
                "Your verification code is 482913.\n"
                "Card 4242 4242 4242 4242, exp 12/27, CVV 123. Call 040 123 4567.\n"
                "Reset: https://example.com/reset?token=Zx81kQp0aLm29sVb\n")
        self.assertEqual(mask.mask(text),
                         "Hi! Order 12345678 is on its way (29.10.2026).\n"
                         "Your verification code is [code hidden].\n"
                         "Card •••• 4242, exp [expiry hidden], CVV [CVV hidden]. Call 040 123 4567.\n"
                         "Reset: [login link hidden]\n")

    def test_not_text(self):
        for value in ("", None, 42):
            self.assertEqual(mask.mask(value), value)

    def test_private_use_text(self):
        """Text that has the marks' own characters can't make one: they come through as they were."""
        text = "\U000f0000 4242 4242 4242 4242"
        self.assertEqual(mask.mask(text), "\U000f0000 •••• 4242")


class Invisible(unittest.TestCase):
    """visible() takes out what the confirmation card spells out, from the same definition (invisible.py, #1932)."""

    def unseen(self):
        """Every character invisible.py counts as unseen wherever it stands, with the card's own set beside it."""
        import confirm
        for n in range(0x110000):
            c = chr(n)
            if 0xD800 <= n < 0xE000 or not mask.invisible.always(c):
                continue
            yield c, confirm.visible("4" + c + "8")

    def test_card_and_mask_agree(self):
        """A code with any of them inside is a code, and the card shows each one: neither has a set of its own."""
        unseen = list(self.unseen())
        self.assertGreater(len(unseen), 4000)   # the tags alone are 4096
        for c, card in unseen:
            with self.subTest(c=f"U+{ord(c):04X}"):
                self.assertEqual(card, f"4⟨U+{ord(c):04X}⟩8")
                self.assertEqual(mask.mask(f"Your code is 48{c}2913"),
                                 "Your code is 48\n[code hidden]" if c in mask.LINE_BREAKS else
                                 "Your code is [code hidden]")

    def test_line_breaks(self):
        """A line break of another kind is a line feed, so lines don't run together; a CRLF stays."""
        self.assertEqual(mask.visible("one two three\r\nfour\rfive\x0csix\x85seven"),
                         "one\ntwo\nthree\r\nfour\nfive\nsix\nseven")

    def test_emoji_read_as_before(self):
        """Emoji, keycaps and the joiners words need come through as they did before #1932."""
        same = ["❤️ Kiitos!", "\U0001f468‍❤️‍\U0001f468", "☺︎", "\U0001f1eb\U0001f1ee",
                "\U0001f3f3️‍\U0001f308", "\U0001f44d\U0001f3fd", "\U0001f9d1‍\U0001f4bb", "#️⃣ *️⃣",
                "‼️ ™️ ©️", "می‌خواهم", "क्‍ष", "한국어 ㄱ", "Hei\n\tmaailma\r\nrivi"]
        for text in same:
            with self.subTest(text=ascii(text)):
                self.assertEqual(mask.visible(text), text)
        self.assertEqual(mask.visible("Room 1️⃣2️⃣, 3️⃣"), "Room 12, 3")   # a keycap is its digit
        # A subdivision flag's tags are tag letters, gone as before: the black flag stays
        self.assertEqual(mask.visible("\U0001f3f4\U000e0067\U000e0062\U000e0073\U000e0063\U000e0074\U000e007f"),
                         "\U0001f3f4")

    def test_joiner_runs(self):
        """A joiner stays only between characters outside ASCII, judged around the whole run of them: what was
        taken out can't leave one between two digits."""
        self.assertEqual(mask.visible("48‍‍‍29ㅤ‍ㅤ13"), "482913")
        self.assertEqual(mask.visible("ä‍‍ö"), "ä‍‍ö")


class Answers(unittest.TestCase):
    def thread(self):
        return {"id": "thread:0000000000000005", "subject": "Your code 482913",
                "messages": [{"id": "CAF123456@mail.gmail.com", "subject": "Your code 482913",
                              "text": "Your verification code is 482913.", "tags": ["inbox"]},
                             {"id": "abc", "text": "Order 12345678", "tags": []}]}

    def test_paths(self):
        data = mask.apply(self.thread(), ["subject", "messages.subject", "messages.text"])
        self.assertEqual(data["subject"], "Your code [code hidden]")
        self.assertEqual(data["messages"][0]["text"], "Your verification code is [code hidden].")
        self.assertEqual(data["messages"][0]["id"], "CAF123456@mail.gmail.com")   # ids stay: other tools take them
        self.assertEqual(data["id"], "thread:0000000000000005")
        self.assertEqual(data["messages"][1]["text"], "Order 12345678")

    def test_list_of_texts(self):
        data = mask.apply({"notes": [{"lines": ["PIN 4821", "milk"]}]}, ["notes.lines"])
        self.assertEqual(data["notes"][0]["lines"], ["PIN [code hidden]", "milk"])

    def test_missing_paths(self):
        self.assertEqual(mask.apply({"a": 1, "b": [1, "x"]}, ["c.d", "a.b", "b.c"]), {"a": 1, "b": [1, "x"]})

    def test_secret_whole(self):
        """Ferry marks a text that is a code or a password itself: "hunter2" says nothing to find it by."""
        data = mask.apply({"items": [{"kind": "text", "text": "hunter2", "secret": True},
                                     {"kind": "text", "text": "milk"}, {"kind": "file", "name": "a.pdf"}]},
                          ["items.text"])
        self.assertEqual([i.get("text") for i in data["items"]], [mask.SECRET, "milk", None])

    def test_answer_json(self):
        body = json.dumps(self.thread())
        out = mask.answer({"content": [{"type": "text", "text": body}], "structuredContent": json.loads(body)},
                          ["messages.text"])
        self.assertEqual(json.loads(out["content"][0]["text"]), out["structuredContent"])
        self.assertNotIn("482913.", out["content"][0]["text"])
        self.assertIn("Your code 482913", out["content"][0]["text"])   # not a path given

    def test_answer_text(self):
        """A cut answer isn't JSON any more: all of its text is masked."""
        out = mask.answer({"content": [{"type": "text", "text": '{"text": "PIN 4821 … (12 more characters'}]},
                          ["text"])
        self.assertEqual(out["content"][0]["text"], '{"text": "PIN [code hidden] … (12 more characters')


class Registry(unittest.TestCase):
    """The registry masks a tool's `mask` fields on their way to Claude, unless its area's `secrets` is on."""

    OUT = json.dumps({"id": "thread:01", "text": "Your verification code is 482913."})

    def call(self, area, options=None, command=None):
        import tempfile
        import registry
        with tempfile.TemporaryDirectory() as tmp:
            tool = {"name": "test_read", "description": "A test.", "class": "read", "area": area,
                    "inputSchema": {"type": "object", "properties": {}}, "mask": ["text"],
                    "command": command or ["python3", "-c", f"print({self.OUT!r})"]}
            (Path(tmp) / "tools.json").write_text(json.dumps({"tools": [tool]}))
            rules = {"version": 2, "level": "open", "areas": {}, "options": {area: options or {}}}
            (Path(tmp) / "access.json").write_text(json.dumps(rules))
            reg = registry.Registry(core=tmp, active=Path(tmp) / "none", access_file=Path(tmp) / "access.json",
                                    log=lambda text: None)
            return reg.call("test_read", {})["structuredContent"]

    def test_masked(self):
        self.assertEqual(self.call("mail"), {"id": "thread:01", "text": "Your verification code is [code hidden]."})

    def test_area_without_the_choice(self):
        self.assertEqual(self.call("contacts")["text"], "Your verification code is [code hidden].")

    def test_shown(self):
        self.assertEqual(self.call("mail", {"secrets": True})["text"], "Your verification code is 482913.")

    # A failing command's message is its stderr, or its stdout without one: what it quotes there is masked too (#1930)
    FAIL_ERR = ["python3", "-c", "import sys; sys.exit('cannot parse: Your verification code is 482913.')"]
    FAIL_OUT = ["python3", "-c", "print('Your verification code is 482913.'); raise SystemExit(2)"]

    def failure(self, command, options=None):
        from run import ToolError
        with self.assertRaises(ToolError) as caught:
            self.call("mail", options, command)
        return str(caught.exception)

    def test_error_masked(self):
        for command in (self.FAIL_ERR, self.FAIL_OUT):
            with self.subTest(command=command[-1]):
                message = self.failure(command)
                self.assertIn("Your verification code is [code hidden].", message)
                self.assertNotIn("482913", message)
                self.assertTrue(message.startswith("test_read failed (python3 exited with "), message)

    def test_error_shown_with_secrets(self):
        self.assertIn("482913", self.failure(self.FAIL_ERR, {"secrets": True}))


class Declared(unittest.TestCase):
    """Fields that carry text someone else wrote are in their tool's `mask`: a draft's quote of a mail (#1861), the
    subject a sent mail answers with, a shared address book's free text."""
    WANT = {"mail": {"mail_draft": {"subject", "body"}, "mail_send": {"subject"},
                     "mail_thread": {"subject", "messages.subject", "messages.text"}},
            "contacts": {"contacts_find": {"people.org", "people.title"},
                         "contacts_card": {"note", "org", "title", "nickname"}}}

    def test_masks(self):
        for plugin, tools in self.WANT.items():
            spec = json.loads((HERE.parents[1] / "plugins" / plugin / "mcp.json").read_text())
            masks = {t["name"]: set(t.get("mask", [])) for t in spec["tools"]}
            for name, fields in tools.items():
                with self.subTest(tool=name):
                    self.assertLessEqual(fields, masks[name])


if __name__ == "__main__":
    unittest.main()
