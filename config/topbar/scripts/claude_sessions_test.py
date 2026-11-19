#!/usr/bin/env python3
"""claude-sessions finds the transcript being written now (#3134), and a background session in the window showing it
(#3200): `python3 config/topbar/scripts/claude_sessions_test.py`.

A long conversation Claude Code carried on in new transcripts (each old one ends with a continued-in record, while the
session's record keeps the first id): the sessions bar's last line and Companion's view (config/companion/lib
transcript.py) must come from the newest, and follow it as it grows. claude-sessions runs for real against a made-up
config dir, with hyprctl and pgrep stubbed to name one stand-in process (a sleep) as the session's window.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "claude-sessions")
sys.path.insert(0, os.path.join(HERE, "..", "..", "companion", "lib"))
import transcript  # noqa: E402

FIRST = "11111111-1111-4111-8111-111111111111"
SECOND = "22222222-2222-4222-8222-222222222222"
THIRD = "33333333-3333-4333-8333-333333333333"


def line(**kw):
    return json.dumps(kw, separators=(",", ":"), ensure_ascii=False)


def user(text, sid):
    return line(type="user", sessionId=sid, message={"role": "user", "content": text})


def said(text, sid):
    return line(type="assistant", sessionId=sid, message={"role": "assistant", "content": [{"type": "text", "text": text}]})


def tool(name, inp, sid):
    return line(type="assistant", sessionId=sid,
                message={"role": "assistant", "content": [{"type": "tool_use", "id": "t", "name": name, "input": inp}]})


def result(text, sid):
    return line(type="user", sessionId=sid,
                message={"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t", "content": text}]})


def chatter(sid, turns, tag):
    """A long conversation with the records a real one has between its messages."""
    out = [line(type="custom-title", customTitle="Project Manager", sessionId=sid),
           line(type="permission-mode", permissionMode="auto", sessionId=sid)]
    for i in range(turns):
        out += [user(f"{tag} question {i}", sid),
                line(type="attachment", sessionId=sid, attachment={"type": "queued_command", "prompt": "3118, 3119"}),
                line(type="queue-operation", operation="enqueue", sessionId=sid),
                tool("Skill", {"skill": "pm"}, sid),
                user('<cross-session-message from="worker">done</cross-session-message>', sid),
                tool("CronCreate", {"cron": "*/30 * * * *", "prompt": "check"}, sid),
                # a big tool result, as a long note read whole
                result("x" * 81000, sid),
                line(type="last-prompt", lastPrompt=f"{tag} question {i}", sessionId=sid),
                said(f"{tag} answer {i}", sid)]
    return out


class Continued(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.home = os.path.join(self.tmp, "home")
        self.conf = os.path.join(self.home, ".claude")
        self.dir = os.path.join(self.tmp, "pm")
        self.folder = os.path.join(self.conf, "projects", "-pm")
        for d in (self.dir, self.folder, os.path.join(self.conf, "sessions")):
            os.makedirs(d)
        self.proc = subprocess.Popen(["sleep", "60"], cwd=self.dir, env={**os.environ, "CLAUDE_CONFIG_DIR": self.conf})
        self.addCleanup(self.proc.wait)
        self.addCleanup(self.proc.kill)
        # The session's record names the first transcript, as Claude Code's did
        with open(os.path.join(self.conf, "sessions", f"{self.proc.pid}.json"), "w") as f:
            json.dump({"pid": self.proc.pid, "sessionId": FIRST, "name": "Project Manager", "status": "idle"}, f)
        stubs = os.path.join(self.tmp, "bin")
        os.makedirs(stubs)
        clients = os.path.join(self.tmp, "clients.json")
        with open(clients, "w") as f:
            json.dump([{"address": "0xa1", "pid": self.proc.pid}], f)
        for name, body in (("hyprctl", f'cat "{clients}"'), ("pgrep", f"echo {self.proc.pid}")):
            path = os.path.join(stubs, name)
            with open(path, "w") as f:
                f.write(f"#!/bin/sh\n{body}\n")
            os.chmod(path, 0o755)
        self.env = {**os.environ, "HOME": self.home, "PATH": f"{stubs}:{os.environ['PATH']}"}
        self.env.pop("CLAUDE_CONFIG_DIR", None)

    def write(self, sid, lines):
        path = os.path.join(self.folder, sid + ".jsonl")
        with open(path, "a") as f:
            f.write("\n".join(lines) + "\n")
        return path

    def sessions(self):
        out = subprocess.run([SCRIPT], env=self.env, capture_output=True, text=True, timeout=60, check=True).stdout
        found = json.loads(out)
        self.assertEqual(len(found), 1, out)
        return found[0]

    def test_the_newest_transcript_and_its_growth(self):
        self.write(FIRST, chatter(FIRST, 12, "early") +
                   [line(type="continued-in", sessionId=FIRST, continuedInSessionId=SECOND)])
        self.write(SECOND, chatter(SECOND, 12, "middle") +
                   [line(type="continued-in", sessionId=SECOND, continuedInSessionId=THIRD)])
        newest = self.write(THIRD, chatter(THIRD, 12, "late"))

        found = self.sessions()
        self.assertEqual(found["transcript"], newest)
        self.assertEqual(found["last"], "late answer 11")
        shown = transcript.recent(found["transcript"], found["dir"], found["started"])
        self.assertEqual(shown[-1], {"role": "assistant", "kind": "text", "text": "late answer 11"})

        # A new message shows once it is written (the cache goes by the file's size and time)
        self.write(THIRD, [said("the very latest", THIRD)])
        shown = transcript.recent(found["transcript"], found["dir"], found["started"])
        self.assertEqual(shown[-1]["text"], "the very latest")
        self.assertEqual(self.sessions()["last"], "the very latest")

    def test_a_continuation_that_is_missing_or_loops(self):
        first = self.write(FIRST, chatter(FIRST, 2, "only") +
                           [line(type="continued-in", sessionId=FIRST, continuedInSessionId=SECOND)])
        self.assertEqual(self.sessions()["transcript"], first)   # SECOND isn't there: stay on what is
        self.write(SECOND, [said("second", SECOND),
                            line(type="continued-in", sessionId=SECOND, continuedInSessionId=FIRST)])
        self.assertIn(self.sessions()["transcript"], (first, os.path.join(self.folder, SECOND + ".jsonl")))

    def test_continued_in_quoted_in_a_message_is_not_followed(self):
        first = self.write(FIRST, [said('{"type":"continued-in","continuedInSessionId":"' + SECOND + '"}', FIRST)])
        self.write(SECOND, [said("elsewhere", SECOND)])
        self.assertEqual(self.sessions()["transcript"], first)


class Background(unittest.TestCase):
    """A background session of Claude Code's daemon (`claude --bg`, a project manager), shown in a window by `claude
    agents` (#3200): the window's claude has no record, the session's process runs under no window. Listed by the window
    with the session's name, PID (its sessions' opener), folder and transcript, as a `claude -n` session is; the sessions
    bar's robot and group, pm-space and Companion's tile go by them."""

    NAME = "Test Project Manager"

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.home = os.path.join(self.tmp, "home")
        self.conf = os.path.join(self.home, ".claude")
        self.pm_dir = os.path.join(self.tmp, "pm")
        self.folder = os.path.join(self.conf, "projects", "-pm")
        for d in (self.pm_dir, self.folder, os.path.join(self.conf, "sessions")):
            os.makedirs(d)
        # The window's `claude agents`, started in another folder, and the daemon's session, under no window
        self.agents = self.spawn(self.tmp, {})
        self.bg = self.spawn(self.pm_dir, {"NIGHTDRIVE_OPENER_PID": "0"})
        with open(os.path.join(self.folder, FIRST + ".jsonl"), "w") as f:
            f.write(said("the manager's answer", FIRST) + "\n")
        self.record(self.bg.pid, FIRST, self.NAME, kind="bg", cwd=self.pm_dir, procStart=self.start(self.bg.pid))
        stubs = os.path.join(self.tmp, "bin")
        os.makedirs(stubs)
        self.clients = os.path.join(self.tmp, "clients.json")
        self.title("◑ " + self.NAME)
        for name, body in (("hyprctl", f'cat "{self.clients}"'), ("pgrep", f"echo {self.agents.pid}")):
            path = os.path.join(stubs, name)
            with open(path, "w") as f:
                f.write(f"#!/bin/sh\n{body}\n")
            os.chmod(path, 0o755)
        self.env = {**os.environ, "HOME": self.home, "PATH": f"{stubs}:{os.environ['PATH']}"}
        self.env.pop("CLAUDE_CONFIG_DIR", None)

    def spawn(self, cwd, env):
        proc = subprocess.Popen(["sleep", "60"], cwd=cwd, env={**os.environ, "CLAUDE_CONFIG_DIR": self.conf, **env})
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        return proc

    @staticmethod
    def start(pid):
        with open(f"/proc/{pid}/stat") as f:
            return f.read().rsplit(") ", 1)[1].split()[19]

    def record(self, pid, sid, name, **kw):
        with open(os.path.join(self.conf, "sessions", f"{pid}.json"), "w") as f:
            json.dump({"pid": pid, "sessionId": sid, "name": name, "status": "idle", **kw}, f)

    def title(self, title):
        with open(self.clients, "w") as f:
            json.dump([{"address": "0xa1", "pid": self.agents.pid, "title": title}], f)

    def sessions(self):
        out = subprocess.run([SCRIPT], env=self.env, capture_output=True, text=True, timeout=60, check=True).stdout
        found = json.loads(out)
        self.assertEqual(len(found), 1, out)
        return found[0]

    def test_the_window_is_the_session(self):
        found = self.sessions()
        self.assertEqual((found["address"], found["name"], found["pid"], found["dir"], found["status"]),
                         ("0xa1", self.NAME, self.bg.pid, self.pm_dir, "idle"))
        self.assertEqual(found["transcript"], os.path.join(self.folder, FIRST + ".jsonl"))
        self.assertEqual(found["last"], "the manager's answer")
        # Waiting for you: ✳ before the name, as any session's title
        self.title("✳ " + self.NAME)
        self.assertEqual(self.sessions()["pid"], self.bg.pid)

    def test_only_a_live_background_session_of_that_name(self):
        # The list of sessions, attached to none: the window as before, nameless
        self.title("✳ Claude Code")
        self.assertEqual((self.sessions()["name"], self.sessions()["pid"]), ("", self.agents.pid))
        # A session of that name that isn't a background one: its own window shows it, not this
        self.title("◑ " + self.NAME)
        self.record(self.bg.pid, FIRST, self.NAME, cwd=self.pm_dir)
        self.assertEqual(self.sessions()["name"], "")
        # Its process gone, or its PID now another's (another start time)
        self.record(self.bg.pid, FIRST, self.NAME, kind="bg", cwd=self.pm_dir, procStart="1")
        self.assertEqual(self.sessions()["name"], "")
        self.record(99999999, FIRST, self.NAME, kind="bg", cwd=self.pm_dir)
        os.remove(os.path.join(self.conf, "sessions", f"{self.bg.pid}.json"))
        self.assertEqual(self.sessions()["name"], "")

    def test_the_window_own_record_wins(self):
        # A claude with a record of its own (a `claude -n` session) is that session, whatever its title says
        self.record(self.agents.pid, SECOND, "Another", cwd=self.tmp)
        self.assertEqual((self.sessions()["name"], self.sessions()["pid"]), ("Another", self.agents.pid))


if __name__ == "__main__":
    unittest.main()
