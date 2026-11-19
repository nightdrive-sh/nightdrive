#!/usr/bin/env python3
"""claude-notify's answers from Companion (#3137): `python3 config/hypr/scripts/claude_notify_test.py`. The hook leaves
a request's whole input for Companion, takes Companion's Allow for it (an edit too, which its notification can't show)
only by the request's id, and never for one too long to leave whole. Hyprland, the notification and Quickshell are
stubbed: nothing shows and no window moves."""

import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.environ.get("CLAUDE_NOTIFY", os.path.join(HERE, "claude-notify"))
ADDR = "0xtest"
SID = "0b6c4a3e-1d2f-4e5a-9b8c-7d6e5f4a3b2c"
EDIT = {"file_path": "/tmp/x/notes.md", "old_string": "a", "new_string": "a\nb", "replace_all": False}

STUBS = {
    # the session's window is this test's process (the hook's parent); another window has the keyboard, unless CN_ACTIVE
    "hyprctl": """#!/bin/bash
case "$*" in
  "-j clients") printf '[{"pid": %s, "address": "%s", "title": "✳ test"}]' "$CN_PID" "$CN_ADDR" ;;
  "-j activewindow") printf '{"address": "%s"}' "${CN_ACTIVE:-0xother}" ;;
esac""",
    # prints its id at once, then waits as -w does for an action that never comes
    "notify-send": "#!/bin/bash\n: > \"$CN_NOTIFIED\"\necho 7\nexec sleep 600",
    # answers barShown with CN_BAR (the sessions bar there to see), else as if Quickshell weren't running
    "qs": "#!/bin/bash\n[[ $* == *barShown* && -n ${CN_BAR:-} ]] && { echo true; exit 0; }\nexit 1",
    "gdbus": "#!/bin/bash\nexit 0",
}


@unittest.skipUnless(shutil.which("jq"), "needs jq")
class CompanionAnswer(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        bin_ = os.path.join(self.tmp, "bin")
        os.mkdir(bin_)
        for name, text in STUBS.items():
            path = os.path.join(bin_, name)
            with open(path, "w") as f:
                f.write(text + "\n")
            os.chmod(path, 0o755)
        self.state = os.path.join(self.tmp, "run", "nightdrive", "claude-notify")
        self.env = {"PATH": f"{bin_}:/usr/bin:/bin", "HOME": self.tmp, "XDG_RUNTIME_DIR": os.path.join(self.tmp, "run"),
                    "CN_PID": str(os.getpid()), "CN_ADDR": ADDR, "LANG": "C.UTF-8",
                    "CLAUDE_CONFIG_DIR": os.path.join(self.tmp, "claude"),
                    "CN_NOTIFIED": os.path.join(self.tmp, "notified")}
        self.proc = None

    def tearDown(self):
        if self.proc and self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def record(self, status, waiting_for="", at=None):
        """Claude Code's record of the session (<config dir>/sessions/<pid>.json), as it writes it: compact JSON."""
        d = os.path.join(self.env["CLAUDE_CONFIG_DIR"], "sessions")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "4242.json.tmp"), "w") as f:
            json.dump({"pid": 4242, "sessionId": SID, "status": status, "waitingFor": waiting_for,
                       "statusUpdatedAt": at or int(time.time() * 1000)}, f, separators=(",", ":"))
        os.replace(os.path.join(d, "4242.json.tmp"), os.path.join(d, "4242.json"))

    def start(self, tool, tool_input):
        event = {"hook_event_name": "PermissionRequest", "cwd": "/home/me/proj", "session_id": SID, "tool_name": tool,
                 "tool_input": tool_input}
        self.proc = subprocess.Popen([HOOK], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=self.env)
        self.proc.stdin.write(json.dumps(event))
        self.proc.stdin.close()

    def ask(self, tool, tool_input):
        """Starts the hook on a permission request; returns what it left for Companion: (perm, input or None)."""
        self.start(tool, tool_input)
        perm = os.path.join(self.state, f"{ADDR}.perm")
        for _ in range(100):
            if os.path.exists(perm) and os.path.getsize(perm):
                break
            time.sleep(0.05)
        with open(perm) as f:
            p = json.load(f)
        try:
            with open(os.path.join(self.state, f"{ADDR}.input")) as f:
                inp = json.load(f)
        except FileNotFoundError:
            inp = None
        return p, inp

    def answer(self, line):
        """Writes Companion's answer as sessions.answer does, and waits until the hook has read it or ended."""
        ans = os.path.join(self.state, f"{ADDR}.answer")
        with open(ans + ".tmp", "w") as f:
            f.write(line + "\n")
        os.replace(ans + ".tmp", ans)
        for _ in range(40):
            if not os.path.exists(ans) or self.proc.poll() is not None:
                return
            time.sleep(0.05)

    def decision(self, timeout=3):
        out, _ = self.proc.communicate(timeout=timeout)
        return json.loads(out)["hookSpecificOutput"]["decision"] if out.strip() else None

    def test_an_edit_is_left_whole_and_allowed_from_companion(self):
        p, inp = self.ask("Edit", EDIT)
        self.assertEqual((p["tool"], p["allow"], p["whole"]), ("Edit", False, True))   # the notification: no Allow
        self.assertEqual(inp, {"request": p["request"], "input": EDIT})
        self.answer(f"allow {p['request']}")
        self.assertEqual(self.decision(), {"behavior": "allow"})
        self.assertFalse(os.path.exists(os.path.join(self.state, f"{ADDR}.input")))    # gone with the request

    def test_an_answer_for_another_request_is_ignored(self):
        p, _ = self.ask("mcp__dash__note_edit", {"id": "98", "edits": [{"old": "a", "new": "b"}]})
        self.answer("allow someother")
        self.assertIsNone(self.proc.poll())                                            # still waits
        self.answer(f"deny {p['request']}")
        self.assertEqual(self.decision(), {"behavior": "deny", "message": "Denied from Companion"})

    def test_a_command_outside_the_sandbox(self):
        p, inp = self.ask("Bash", {"command": "ls", "dangerouslyDisableSandbox": True})
        self.assertEqual((p["allow"], p["whole"]), (False, True))
        self.assertTrue(inp["input"]["dangerouslyDisableSandbox"])
        self.answer(f"allow {p['request']}")
        self.assertEqual(self.decision(), {"behavior": "allow"})

    def test_too_long_to_leave_whole_gets_no_allow(self):
        p, inp = self.ask("Write", {"file_path": "/tmp/x/big", "content": "x" * 200_001})
        self.assertEqual((p["allow"], p["whole"], inp), (False, False, None))
        self.answer(f"allow {p['request']}")
        self.assertIsNone(self.proc.poll())                                            # refused: still waits
        self.proc.send_signal(signal.SIGTERM)
        self.assertIsNone(self.decision())                                             # left to the terminal


    # #3146: Companion types into a session by bringing its window up, and away from the computer it stays the active
    # one. A request then still reaches Companion (no notification: you may be in that window), and ends when the
    # session's record says it was answered elsewhere, so Companion never offers Allow for one that's gone.
    def test_the_active_window_still_leaves_the_request_for_companion(self):
        self.env["CN_ACTIVE"] = ADDR
        self.record("waiting", "permission prompt")
        p, inp = self.ask("Edit", EDIT)
        self.assertEqual(inp, {"request": p["request"], "input": EDIT})
        time.sleep(1.2)
        self.assertIsNone(self.proc.poll())                                            # waits, though active
        self.assertFalse(os.path.exists(self.env["CN_NOTIFIED"]))                      # no notification
        self.answer(f"allow {p['request']}")
        self.assertEqual(self.decision(), {"behavior": "allow"})

    def test_answered_in_the_terminal_the_request_goes(self):
        self.env["CN_ACTIVE"] = ADDR
        self.record("waiting", "permission prompt")
        self.ask("Edit", EDIT)
        time.sleep(0.6)
        self.record("busy")                                                            # the terminal's Yes
        self.assertIsNone(self.decision())                                             # left to the terminal
        self.assertEqual(os.listdir(self.state), [])                                   # Companion has nothing

    def test_a_newer_request_ends_the_one_before(self):
        self.record("waiting", "permission prompt")
        self.ask("Write", {"file_path": "/tmp/x/a", "content": "a"})
        time.sleep(0.6)
        self.record("waiting", "permission prompt", int(time.time() * 1000) + 5)      # the next one's prompt
        self.assertIsNone(self.decision())

    def test_an_older_waiting_stamp_is_not_this_request(self):
        self.record("waiting", "permission prompt", int(time.time() * 1000) - 60_000)  # the request before this one
        p, _ = self.ask("Edit", EDIT)
        self.record("waiting", "permission prompt")                                    # this one's
        time.sleep(0.6)
        self.assertIsNone(self.proc.poll())
        self.answer(f"deny {p['request']}")
        self.assertEqual(self.decision(), {"behavior": "deny", "message": "Denied from Companion"})

    # #3126: while the sessions bar is there to see, a question pops up nothing (its chip asks) but still reaches
    # Companion; a permission request keeps its notification
    def test_a_question_while_the_bar_shows_is_quiet_but_reaches_companion(self):
        self.env["CN_BAR"] = "1"
        self.record("waiting", "question")
        q = {"questions": [{"question": "Commit?", "options": [{"label": "Yes"}, {"label": "No"}]}]}
        self.start("AskUserQuestion", q)
        ask = os.path.join(self.state, f"{ADDR}.ask")                                 # Companion's copy of it
        for _ in range(100):
            if os.path.exists(ask) and os.path.getsize(ask):
                break
            time.sleep(0.05)
        with open(ask) as f:
            self.assertEqual(json.load(f)["questions"][0]["question"], "Commit?")
        time.sleep(0.6)
        self.assertIsNone(self.proc.poll())                                            # waits for an answer
        self.assertFalse(os.path.exists(self.env["CN_NOTIFIED"]))                      # no notification

    def test_a_permission_request_while_the_bar_shows_still_notifies(self):
        self.env["CN_BAR"] = "1"
        self.record("waiting", "permission prompt")
        self.ask("Edit", EDIT)
        for _ in range(40):
            if os.path.exists(self.env["CN_NOTIFIED"]):
                break
            time.sleep(0.05)
        self.assertTrue(os.path.exists(self.env["CN_NOTIFIED"]))

    def test_without_a_record_the_active_window_answers_in_the_terminal(self):
        self.env["CN_ACTIVE"] = ADDR
        self.start("Edit", EDIT)
        self.assertIsNone(self.decision())                                             # as before #3146
        self.assertFalse(os.path.exists(os.path.join(self.state, f"{ADDR}.perm")))


if __name__ == "__main__":
    unittest.main()
