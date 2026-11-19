#!/usr/bin/env python3
"""schedule's messages to Claude (#3150): `python3 config/hypr/scripts/schedule_claude_test.py`. A line is a command
when its first word is a program or nightdrive, else a message, and --run / --claude say it instead; --to finds one
session by id or name and refuses a name that fits several; a message's run goes to the running session's window (not
while it waits for an answer), resumes a closed one, or opens a new session. Sessions, windows, typing and terminals
are stubbed: nothing here opens a window or types."""

import importlib.machinery
import importlib.util
import json
import os
import shlex
import stat
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("schedule", os.path.join(HERE, "schedule"))
schedule = importlib.util.module_from_spec(importlib.util.spec_from_loader("schedule", loader))
loader.exec_module(schedule)
claude = schedule.claude

PM = "Nightdrive Project Manager"
ID_OLD, ID_NEW, ID_RUN = ("%08d-0000-0000-0000-000000000000" % n for n in (1, 2, 3))
SESSIONS = [
    {"id": ID_RUN, "name": "Cold Start Project Manager", "dir": "/p/cold", "account": "feature", "last": 300,
     "running": True, "address": "0xc0"},
    {"id": ID_NEW, "name": PM, "dir": "/p/pm", "account": "default", "last": 200, "running": False, "address": None},
    {"id": ID_OLD, "name": PM, "dir": "/p/pm", "account": "default", "last": 100, "running": False, "address": None},
]


def patch(test, target, name, stub):
    p = mock.patch.object(target, name, stub)
    p.start()
    test.addCleanup(p.stop)


class Kind(unittest.TestCase):
    """Commands and messages, against a PATH of this test's own: make and ndpm are programs, nothing else is."""
    def setUp(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        for prog in ("make", "ndpm"):
            path = os.path.join(d.name, prog)
            with open(path, "w") as f:
                f.write("#!/bin/sh\n")
            os.chmod(path, stat.S_IRWXU)
        self.dir = d.name
        patch(self, claude, "search_path", lambda: d.name)

    def test_a_program_or_nightdrive_is_a_command(self):
        for words in (["make && notify-send done"], ["make", "all"], ["ndpm"], ["nightdrive update"],
                      ["FOO=1 make"], [os.path.join(self.dir, "make") + " -j4"]):
            self.assertEqual(claude.kind(words), "run", words)

    def test_anything_else_is_a_message(self):
        for words in (["aloita aamun tehtävät"], ["aloita", "aamun", "tehtävät"], ["don't forget the CI"],
                      ["./nowhere"], ["Check", "the", "build"]):
            self.assertEqual(claude.kind(words), "claude", words)

    def test_a_message_keeps_its_words(self):
        self.assertEqual(claude.message(["don't", " forget ", "", "it"]), "don't forget it")


class ParseAdd(unittest.TestCase):
    def test_which_one(self):
        a = schedule.parse_add(["wake", "--to", PM, "aloita", "--run"])
        self.assertEqual((a.when, a.to, a.command), ("wake", PM, ["aloita", "--run"]))
        a = schedule.parse_add(["--claude", "14:45", "--to=pm", "make"])
        self.assertEqual((a.claude, a.to, a.command), (True, "pm", ["make"]))
        self.assertTrue(schedule.parse_add(["--run", "15", "x"]).run)

    def test_refused(self):
        self.assertIsNone(schedule.parse_add(["15", "--to"]))
        self.assertIsNone(schedule.parse_add(["15", "--to", " ", "x"]))
        self.assertIsNone(schedule.parse_add(["--run", "--claude", "15", "x"]))
        self.assertIsNone(schedule.parse_add(["--run", "--to", PM, "15", "x"]))


class Target(unittest.TestCase):
    def test_by_name_any_case_or_part(self):
        self.assertEqual(claude.target("nightdrive project manager", SESSIONS), PM)
        self.assertEqual(claude.target("Nightdrive Project", SESSIONS), PM)

    def test_by_id(self):
        self.assertEqual(claude.target(ID_OLD, SESSIONS), ID_OLD)
        with self.assertRaises(ValueError):
            claude.target("%08d-0000-0000-0000-000000000000" % 9, SESSIONS)

    def test_none_or_several(self):
        with self.assertRaisesRegex(ValueError, "No session named"):
            claude.target("Mail", SESSIONS)
        with self.assertRaisesRegex(ValueError, "Cold Start Project Manager, Nightdrive Project Manager"):
            claude.target("project manager", SESSIONS)

    def test_pick_running_else_newest(self):
        self.assertEqual(claude.pick(PM, SESSIONS)["id"], ID_NEW)
        running = [dict(SESSIONS[2], running=True, address="0xa"), *SESSIONS[:2]]
        self.assertEqual(claude.pick(PM, running)["id"], ID_OLD)
        self.assertEqual(claude.pick(ID_OLD, SESSIONS)["id"], ID_OLD)
        self.assertIsNone(claude.pick("Mail", SESSIONS))


class Rows(unittest.TestCase):
    """Added, listed and fired as schedule does, its timers, notifications and run stubbed."""
    def setUp(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        self.notes, self.ran = [], []
        self.output = "Sent to Nightdrive Project Manager, in its window\n"
        for name, stub in [("STATE", os.path.join(d.name, "schedule.json")),
                           ("arm", lambda r: (True, "")),
                           ("disarm", lambda rid: None),
                           ("screen_locked", lambda: False),
                           ("notify", lambda rid, summary, body="", pinned=False: self.notes.append((summary, body))),
                           ("run_command", lambda rid, line: (self.ran.append(line), (0, self.output))[1])]:
            patch(self, schedule, name, stub)
        patch(self, claude, "sessions", lambda: SESSIONS)
        patch(self, claude, "is_command", lambda word: word == "make")

    def add(self, when, *words, **opts):
        schedule.cmd_add(types.SimpleNamespace(json=True, when=when, command=list(words), **opts))
        with open(schedule.STATE) as f:
            return json.load(f)["commands"][-1]

    def test_a_message_and_where_it_goes(self):
        r = self.add("wake", "aloita aamun tehtävät", to="nightdrive project manager")
        self.assertEqual((r["kind"], r["to"], r["command"]), ("claude", PM, "aloita aamun tehtävät"))
        self.assertEqual(schedule.public(r)["kind"], "claude")
        schedule.cmd_fire(types.SimpleNamespace(id=r["id"], now=True))
        argv = shlex.split(self.ran[0])
        self.assertEqual(argv[1:], ["send", "--to", PM, "--", "aloita aamun tehtävät"])
        self.assertEqual(self.notes, [(f"Ask Claude → {PM}: aloita aamun tehtävät", "On waking"),
                                      (f"Done: Ask Claude → {PM}: aloita aamun tehtävät", self.output.strip())])

    def test_read_by_its_first_word_or_as_told(self):
        self.assertEqual(self.add("15", "make", "all").get("kind", "run"), "run")
        self.assertEqual(self.add("15", "tarkista CI").get("kind"), "claude")
        self.assertEqual(self.add("15", "make", claude=True)["kind"], "claude")
        self.assertEqual(self.add("15", "check", "it", run=True).get("kind", "run"), "run")

    def test_an_unknown_session_adds_nothing(self):
        with self.assertRaises(SystemExit):
            self.add("15", "hi", to="Mail")
        self.assertFalse(os.path.exists(schedule.STATE))


class Deliver(unittest.TestCase):
    """deliver(): where a message goes, with sessions, status, typing and launching stubbed."""
    def setUp(self):
        self.sessions = list(SESSIONS)
        self.launched, self.typed, self.warned = [], [], []
        self.statuses = []
        patch(self, claude, "sessions", lambda: self.sessions)
        patch(self, claude, "launch", lambda argv: (self.launched.append(argv), (0, ""))[1])
        patch(self, claude, "status", lambda addr: self.statuses.pop(0) if len(self.statuses) > 1 else self.statuses[0])
        patch(self, claude, "WAIT_MINUTES", 0)
        patch(self, claude.subprocess, "run", lambda argv, **kw: (self.warned.append(argv[1:]),
                                                                  subprocess.CompletedProcess(argv, 0))[1])
        fake = types.ModuleType("control")
        fake.type_text = lambda addr, text, submit: self.typed.append((addr, text, submit))
        patch(self, sys, "modules", {**sys.modules, "control": fake})

    def running_pm(self):
        self.sessions = [dict(SESSIONS[1], running=True, address="0xpm"), SESSIONS[2]]

    def test_into_the_running_session_after_a_warning(self):
        self.running_pm()
        self.statuses = ["idle"]
        code, said = claude.deliver(PM, "aloita")
        self.assertEqual((code, self.typed, self.launched), (0, [("0xpm", "aloita", True)], []))
        self.assertEqual(self.warned, [[f"{PM}'s window"]])
        self.assertIn("Sent to", said)

    def test_not_while_it_waits_for_an_answer(self):
        self.running_pm()
        self.statuses = ["waiting"]
        code, said = claude.deliver(PM, "aloita")
        self.assertEqual((code, self.typed), (1, []))
        self.assertIn("waiting for your answer", said)
        self.statuses = ["idle", "waiting"]   # a question came during the countdown
        self.assertEqual(claude.deliver(PM, "aloita")[0], 1)
        self.assertEqual(self.typed, [])

    def test_a_closed_one_is_resumed_with_it(self):
        code, _ = claude.deliver(PM, "aloita")
        argv = self.launched[0]
        self.assertEqual(code, 0)
        self.assertEqual(argv[argv.index("--resume") + 1], ID_NEW)
        self.assertEqual((argv[argv.index("--dir") + 1], argv[argv.index("--account") + 1]), ("/p/pm", "default"))
        self.assertIn("--background", argv)
        self.assertEqual(argv[-2:], ["--", "aloita"])

    def test_otherwise_a_new_session(self):
        self.sessions = []
        claude.deliver(PM, "aloita")                  # its name's sessions are gone: a new one of that name
        claude.deliver(None, "tarkista CI ja kerro") # no --to: named for the message
        (a, b) = self.launched
        self.assertEqual(a[1:2] + a[a.index("--name") + 1:], ["ask", PM, "--", "aloita"])
        self.assertEqual(b[b.index("--name") + 1], "Scheduled: tarkista CI ja kerro")
        self.assertIn("--background", b)



class SendByHand(unittest.TestCase):
    """`schedule send --to PART`: a part of a name finds its session, as an add does; several names stop it."""
    def setUp(self):
        self.sent = []
        patch(self, claude, "sessions", lambda: SESSIONS)
        patch(self, claude, "deliver", lambda key, text, found=None: (self.sent.append((key, text)), (0, "ok"))[1])

    def send(self, *argv):
        with self.assertRaises(SystemExit) as end:
            schedule.cmd_send(list(argv))
        return end.exception.code

    def test_a_part_of_a_name(self):
        self.assertEqual(self.send("--to", "nightdrive project", "--", "hei"), 0)
        self.assertEqual(self.send("--to", "Mail", "hei", "taas"), 0)   # none: a new session of that name
        self.assertEqual(self.sent, [(PM, "hei"), ("Mail", "hei taas")])

    def test_several_names_stop_it(self):
        self.assertEqual(self.send("--to", "project manager", "hei"), 2)
        self.assertEqual(self.sent, [])


if __name__ == "__main__":
    unittest.main(verbosity=1, argv=sys.argv[:1])
