#!/usr/bin/env python3
"""The tools that move the focus wait for the user to stop typing (#1986): `python3 config/mcp/typing_wait_test.py`.
They wait for a pause of about a second, for at most QUIET_WAIT s, and only then refuse, with words that have Claude
call again rather than ask the user to type; their timeout leaves room for the wait, and a cancel (Esc in Claude Code)
stops the wait, so nothing opens after it. hyprctl's key age is a stand-in."""

import sys
import threading
import time
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True

import confirm  # noqa: E402
import registry  # noqa: E402
import run  # noqa: E402
from run import ToolError  # noqa: E402

FOCUS_TOOLS = ("windows_focus", "apps_open", "open_address", "files_open")


def windows():
    loader = SourceFileLoader("windows_typing_test", str(HERE.parent / "hypr/scripts/windows"))
    module = module_from_spec(spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    return module


class Waits(unittest.TestCase):
    def setUp(self):
        self.w = windows()
        self.w.POLL = 0.01

    def test_the_cards_second(self):
        """A key a whole second ago (age 1) is still typing; 2 is the pause"""
        self.assertEqual(self.w.QUIET, 1)
        self.assertGreaterEqual(self.w.QUIET_WAIT, 30)

    def test_runs_once_the_typing_pauses(self):
        ages = iter([0, 0, 1, 0, 1, 2])
        with mock.patch.object(self.w, "key_age", side_effect=lambda: next(ages)) as age:
            self.w.not_typing()
        self.assertEqual(age.call_count, 6)

    def test_no_key_age_doesnt_wait(self):
        with mock.patch.object(self.w, "key_age", return_value=None):
            self.w.not_typing()

    def test_refuses_only_after_the_wait_and_says_to_call_again(self):
        self.w.QUIET_WAIT = 0.1
        start = time.monotonic()
        with mock.patch.object(self.w, "key_age", return_value=0), mock.patch.object(self.w, "die") as die:
            die.side_effect = SystemExit
            with self.assertRaises(SystemExit):
                self.w.not_typing()
        self.assertGreaterEqual(time.monotonic() - start, 0.1)
        said = die.call_args[0][0]
        self.assertIn("call this tool again", said)
        self.assertIn("don't ask the user", said)


class Tools(unittest.TestCase):
    def setUp(self):
        self.tools = {t.name: t for t in registry.read_file(HERE / "tools/apps-files.json", HERE, None)[0]}

    def test_every_focus_tool_waits_has_time_for_it_and_stops_on_cancel(self):
        w = windows()
        for name in FOCUS_TOOLS:
            spec = self.tools[name].spec
            self.assertIn("--unless-typing", spec["command"], name)
            self.assertTrue(spec.get("stops_on_cancel"), name)
            # the wait, then up to WAIT s for the new window, and some to spare
            self.assertGreater(run.timeout_of(self.tools[name]), w.QUIET_WAIT + w.WAIT + 5, name)

    def test_stops_on_cancel_is_checked(self):
        spec = dict(self.tools["windows_focus"].spec, stops_on_cancel="yes")
        self.assertIn("stops_on_cancel", registry.problem(spec, None) or "")

    def test_one_event_for_the_card_and_the_commands(self):
        self.assertIs(confirm.CANCELLED, run.CANCELLED)


class Cancel(unittest.TestCase):
    def tearDown(self):
        run.CANCELLED.clear()

    def execute(self, stops):
        tool = SimpleNamespace(dir=HERE, name="t", spec={"stops_on_cancel": stops})
        threading.Timer(0.3, run.CANCELLED.set).start()
        start = time.monotonic()
        try:
            return run.execute(tool, [sys.executable, "-c", "import time; time.sleep(1.5); print('done')"], None, 10)
        finally:
            self.elapsed = time.monotonic() - start

    def test_a_cancel_stops_a_waiting_tool(self):
        with self.assertRaises(ToolError) as said:
            self.execute(True)
        self.assertIn("cancelled", str(said.exception))
        self.assertLess(self.elapsed, 1.2)

    def test_other_tools_run_to_their_end(self):
        out, _, status = self.execute(False)
        self.assertEqual((out, status), ("done\n", 0))


if __name__ == "__main__":
    unittest.main()
