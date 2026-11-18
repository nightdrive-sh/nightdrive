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
EDIT = {"file_path": "/tmp/x/notes.md", "old_string": "a", "new_string": "a\nb", "replace_all": False}

STUBS = {
    # the session's window is this test's process (the hook's parent); another window has the keyboard
    "hyprctl": """#!/bin/bash
case "$*" in
  "-j clients") printf '[{"pid": %s, "address": "%s", "title": "✳ test"}]' "$CN_PID" "$CN_ADDR" ;;
  "-j activewindow") echo '{"address": "0xother"}' ;;
esac""",
    # prints its id at once, then waits as -w does for an action that never comes
    "notify-send": "#!/bin/bash\necho 7\nexec sleep 600",
    "qs": "#!/bin/bash\nexit 1",
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
                    "CN_PID": str(os.getpid()), "CN_ADDR": ADDR, "LANG": "C.UTF-8"}
        self.proc = None

    def tearDown(self):
        if self.proc and self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def ask(self, tool, tool_input):
        """Starts the hook on a permission request; returns what it left for Companion: (perm, input or None)."""
        event = {"hook_event_name": "PermissionRequest", "cwd": "/home/me/proj", "tool_name": tool, "tool_input": tool_input}
        self.proc = subprocess.Popen([HOOK], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=self.env)
        self.proc.stdin.write(json.dumps(event))
        self.proc.stdin.close()
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


if __name__ == "__main__":
    unittest.main()
