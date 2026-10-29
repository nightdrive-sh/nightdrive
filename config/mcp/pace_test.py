#!/usr/bin/env python3
"""How much Claude can do, and how big (#1882): `python3 config/mcp/pace_test.py`. An area's 21st change in a minute
asks on the card; a call refused on the card isn't shown again at once; a text argument has a limit, and so do all of
them together; a command's output is read a chunk at a time and kept to a limit, however much it prints; notes takes
no more text on stdin than its limit; one helper keeps the change notifications, and only ROWS_MAX buttons at once.
The card, the tools' commands and notify-send are stand-ins."""

import io
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True

import notices  # noqa: E402
import pace  # noqa: E402
import registry  # noqa: E402
import run  # noqa: E402
import undo  # noqa: E402
from run import ToolError  # noqa: E402


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


def change(name="notes_create", area="notes", title="Create a note"):
    return SimpleNamespace(name=name, cls="change", area=area, spec={"title": title})


class Pacing(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.pace = pace.Pace(self.clock)

    def test_the_21st_change_in_a_minute_asks(self):
        tool = change()
        for _ in range(pace.PACE):
            self.assertFalse(self.pace.due(tool, "allow"))
            self.pace.ran(tool)
        self.assertTrue(self.pace.due(tool, "allow"))
        self.assertFalse(self.pace.due(change(area="tasks"), "allow"))   # another area's own count
        self.assertFalse(self.pace.due(SimpleNamespace(cls="read", area="notes"), "allow"))
        self.clock.now += pace.WINDOW
        self.assertFalse(self.pace.due(tool, "allow"))

    def test_the_card_says_why_and_the_title_comes_back(self):
        tool = change()
        for _ in range(pace.PACE):
            self.pace.ran(tool)
        with self.pace.noted(tool, True):
            self.assertEqual(tool.spec["title"], f"Create a note ({pace.PACE} changes here in a minute)")
        self.assertEqual(tool.spec["title"], "Create a note")
        untitled = SimpleNamespace(name="x", cls="change", area="a", spec={})
        with self.pace.noted(untitled, True):
            self.assertTrue(untitled.spec["title"].startswith("x ("))
        self.assertNotIn("title", untitled.spec)

    def test_a_refused_call_is_not_asked_again_at_once(self):
        tool, args = change(), {"title": "Buy", "text": "milk"}
        self.pace.check(tool, args)
        self.pace.refused(tool, args)
        with self.assertRaises(ToolError) as said:
            self.pace.check(tool, dict(reversed(list(args.items()))))   # the same call, its keys in another order
        self.assertIn("refused this same call", str(said.exception))
        self.pace.check(tool, {"title": "Buy", "text": "bread"})        # another call is asked
        self.clock.now += pace.REFUSED_FOR
        self.pace.check(tool, args)
        self.assertEqual(self.pace.refusals, {})


class Calls(unittest.TestCase):
    """Registry.call with its Access, card and command as stand-ins"""

    def setUp(self):
        self.reg = registry.Registry(core="/nonexistent", active="/nonexistent")
        self.reg.undo = None
        self.tool = registry.Tool({"name": "notes_create", "title": "Create a note", "class": "change", "area": "notes",
                                   "description": "x", "command": ["true"], "undo": ["true"],
                                   "inputSchema": {"type": "object", "properties": {"t": {"type": "string"}}}},
                                  HERE, "test")
        self.cards, self.answer, self.ran = [], True, 0
        self.reg.visible = lambda: {"notes_create": self.tool}
        self.reg.rules = SimpleNamespace(decide=lambda cls, area, right: "allow")
        self.reg.confirm = SimpleNamespace(ask=self.card)
        p = mock.patch.object(run, "run", side_effect=self.run_)
        p.start()
        self.addCleanup(p.stop)

    def card(self, tool, arguments):
        self.cards.append(tool.spec["title"])
        return self.answer

    def run_(self, tool, arguments):
        self.ran += 1
        return {"content": [{"type": "text", "text": "Done."}]}

    def test_a_flood_asks_and_a_refusal_holds(self):
        for i in range(pace.PACE):
            self.reg.call("notes_create", {"t": str(i)})
        self.assertEqual(self.cards, [])
        self.answer = False
        with self.assertRaises(ToolError):
            self.reg.call("notes_create", {"t": "again"})
        self.assertEqual(self.cards, [f"Create a note ({pace.PACE} changes here in a minute)"])
        with self.assertRaises(ToolError) as said:
            self.reg.call("notes_create", {"t": "again"})
        self.assertIn("refused this same call", str(said.exception))
        self.assertEqual(len(self.cards), 1)
        self.assertEqual(self.ran, pace.PACE)
        self.assertEqual(self.tool.spec["title"], "Create a note")
        self.answer = True
        self.reg.call("notes_create", {"t": "allowed"})
        self.assertEqual(self.ran, pace.PACE + 1)


class Sizes(unittest.TestCase):
    TOOL = SimpleNamespace(name="t", spec={"inputSchema": {"type": "object", "properties": {
        "text": {"type": "string"}, "short": {"type": "string", "maxLength": 10},
        "many": {"type": "array", "items": {"type": "string"}}}}})

    def test_text_has_a_limit(self):
        run.check(self.TOOL, {"text": "x" * run.STRING_MAX})
        for args in ({"text": "x" * (run.STRING_MAX + 1)}, {"short": "x" * 11}, {"many": ["x" * (run.STRING_MAX + 1)]}):
            with self.assertRaises(ToolError):
                run.check(self.TOOL, args)

    def test_all_together_too(self):
        with self.assertRaises(ToolError) as said:
            run.check(self.TOOL, {"many": ["x" * 90_000] * 12})
        self.assertIn("together", str(said.exception))
        with self.assertRaises(ToolError):
            run.check(self.TOOL, {"other": "x" * (run.ARGUMENTS_MAX + 1)})   # one the schema doesn't name

    def test_the_schema_shows_it(self):
        schema = self.TOOL.spec["inputSchema"]
        shown = run.limited(schema)
        self.assertEqual(shown["properties"]["text"]["maxLength"], run.STRING_MAX)
        self.assertEqual(shown["properties"]["short"]["maxLength"], 10)
        self.assertEqual(shown["properties"]["many"]["items"]["maxLength"], run.STRING_MAX)
        self.assertNotIn("maxLength", schema["properties"]["text"])   # the spec as its file has it

    def test_every_listed_tool_shows_a_limit(self):
        for tool in registry.Registry(active="/nonexistent").load()[0].values():
            for name, prop in tool.listing()["inputSchema"].get("properties", {}).items():
                if prop.get("type") == "string":
                    self.assertIn("maxLength", prop, f"{tool.name}.{name}")


class Output(unittest.TestCase):
    WHERE = SimpleNamespace(dir=HERE, name="t")

    def python(self, code, stdin=None, timeout=20):
        return run.execute(self.WHERE, [sys.executable, "-c", code], stdin, timeout)

    def test_kept_to_a_limit_and_the_command_finishes(self):
        with mock.patch.object(run, "READ_MAX", 1000), mock.patch.object(run, "ERR_MAX", 100):
            out, err, status = self.python(
                "import sys\nfor i in range(2000): sys.stdout.write('x' * 1000); sys.stderr.write(f'{i:04}\\n')\n"
                "print('end', file=sys.stderr)")
        self.assertEqual(status, 0)
        self.assertEqual(len(out), 1000)
        self.assertLessEqual(len(err), 100)
        self.assertTrue(err.endswith("1999\nend\n"))

    def test_endless_output_is_stopped_by_the_timeout(self):
        with mock.patch.object(run, "READ_MAX", 1000):
            with self.assertRaises(ToolError) as said:
                self.python("import sys\nwhile True: sys.stdout.write('x' * 65536)", timeout=1)
        self.assertIn("didn't finish", str(said.exception))

    def test_stdin_that_isnt_read_doesnt_hang(self):
        out, _, status = self.python("print('hi')", stdin="x" * 5_000_000)
        self.assertEqual((out, status), ("hi\n", 0))

    def test_stdin_and_text_as_before(self):
        out, _, status = self.python("import sys; print(sys.stdin.read().upper())", stdin="äö ok")
        self.assertEqual((out, status), ("ÄÖ OK\n", 0))
        out, _, _ = self.python("import sys; sys.stdout.buffer.write(b'bad \\xff byte')")
        self.assertEqual(out, "bad � byte")


class Notes(unittest.TestCase):
    def test_stdin_has_a_limit(self):
        sys.path.insert(0, str(REPO / "plugins/notes/lib"))
        try:
            import notes
        except ImportError as e:
            self.skipTest(f"notes: {e}")
        with mock.patch.object(notes, "TEXT_MAX", 10), mock.patch.object(sys, "stdin", io.StringIO("x" * 11)):
            with self.assertRaises(notes.NoteError):
                notes.stdin_text()
        with mock.patch.object(notes, "TEXT_MAX", 10), mock.patch.object(sys, "stdin", io.StringIO("x" * 10)):
            self.assertEqual(notes.stdin_text(), "x" * 10)


class FakeUndo:
    """undo's notice (a row that waits until it is let go) and retire"""

    def __init__(self):
        self.started, self.retired, self.go = [], [], {}

    def notice(self, entry_id, action):
        self.started.append((entry_id, action))
        self.go.setdefault(entry_id, threading.Event()).wait(10)

    def retire(self, entry_id):
        self.retired.append(entry_id)
        self.go.setdefault(entry_id, threading.Event()).set()


class Helper(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.sock, self.lock = self.dir / "s.sock", self.dir / "s.lock"
        self.undo, self.stop = FakeUndo(), threading.Event()

    def start(self, idle=30):
        t = threading.Thread(target=notices.serve, args=(self.undo, self.sock, self.lock, idle, self.stop),
                             daemon=True)
        t.start()
        end = time.monotonic() + 5
        while not self.sock.exists() and time.monotonic() < end:
            time.sleep(0.02)
        self.addCleanup(self.stop.set)
        return t

    def test_one_helper_keeps_the_rows_and_retires_the_oldest(self):
        self.start()
        for i in (1, 2, 3):
            self.assertTrue(notices.send(i, "undo", self.sock))
        end = time.monotonic() + 5
        while len(self.undo.started) < 3 and time.monotonic() < end:
            time.sleep(0.02)
        self.assertEqual(self.undo.started, [(1, "undo"), (2, "undo"), (3, "undo")])
        self.assertEqual(self.undo.retired, [])   # ROWS_MAX is 20
        self.assertEqual(os.stat(self.sock).st_mode & 0o077, 0)

    def test_past_rows_max(self):
        rows = notices.Rows(self.undo, rows_max=2)
        for i in (1, 2, 3, 4):
            rows.add(i, "undo")
        self.assertEqual(self.undo.retired, [1, 2])
        self.assertEqual(list(rows.live()), [3, 4])
        for e in self.undo.go.values():
            e.set()

    def test_hostile_requests(self):
        for line in (b"", b"1", b"x undo", b"1 rm", b"1 undo extra", b"-1 undo", b"\xff\xfe", b"1 undo; rm -rf ~"):
            self.assertIsNone(notices.request(line), line)
        self.assertEqual(notices.request(b"12 redo\n"), (12, "redo"))
        self.start()
        import socket
        with socket.socket(socket.AF_UNIX) as s:
            s.connect(str(self.sock))
            s.sendall(b"1 rm\n")
            self.assertEqual(s.recv(16), b"no\n")
        self.assertEqual(self.undo.started, [])

    def test_a_second_helper_leaves_it_to_the_first(self):
        self.start()
        t = threading.Thread(target=notices.serve, args=(self.undo, self.dir / "other.sock", self.lock, 30))
        t.start()
        t.join(3)
        self.assertFalse(t.is_alive())
        self.assertFalse((self.dir / "other.sock").exists())

    def test_it_ends_when_idle(self):
        t = self.start(idle=0.3)
        self.assertTrue(notices.send(1, "undo", self.sock))
        self.undo.go.setdefault(1, threading.Event()).set()
        t.join(5)
        self.assertFalse(t.is_alive())
        self.assertFalse(self.sock.exists())
        self.assertFalse(notices.send(2, "undo", self.sock))

    def test_show_without_a_runtime_folder_falls_back(self):
        with mock.patch.object(notices, "RUNTIME", self.dir / "none"), \
                mock.patch.object(notices, "SOCKET", self.dir / "none/s.sock"), \
                mock.patch.object(notices.subprocess, "Popen") as popen:
            notices.show(7, "undo")
        self.assertEqual(popen.call_args[0][0][-3:], ["notice", "7", "undo"])


class Retire(unittest.TestCase):
    def test_retire_ends_the_wait_and_keeps_a_row(self):
        proc = mock.Mock()
        undo.WAITING[5] = proc
        rows = []
        with mock.patch.object(undo.changes, "get", return_value={"id": 5, "notice": "Made a note", "state": "done"}), \
                mock.patch.object(undo, "notify", side_effect=lambda *a, **k: rows.append((a, k))):
            undo.retire(5)
        proc.terminate.assert_called_once()
        self.assertNotIn(5, undo.WAITING)
        (entry_id, summary, body), more = rows[0]
        self.assertEqual((entry_id, summary), (5, "Made a note"))
        self.assertIn("ask Claude to undo", body)
        self.assertEqual(more, {})   # no button


if __name__ == "__main__":
    unittest.main()
