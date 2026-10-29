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

    def call(self, area, options=None):
        import tempfile
        import registry
        with tempfile.TemporaryDirectory() as tmp:
            out = json.dumps({"id": "thread:01", "text": "Your verification code is 482913."})
            tool = {"name": "test_read", "description": "A test.", "class": "read", "area": area,
                    "inputSchema": {"type": "object", "properties": {}}, "mask": ["text"],
                    "command": ["python3", "-c", f"print({out!r})"]}
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


if __name__ == "__main__":
    unittest.main()
