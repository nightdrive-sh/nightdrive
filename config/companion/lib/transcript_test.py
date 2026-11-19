"""What a session's own view shows from its transcript (transcript.py recent): your prompts, also one given while it
worked (#3147), Claude's texts and its tool calls, in the order they came, each call named to read and marked when it
failed, was denied or is still at work (#3218). The records are shaped as Claude Code
writes them (a mid-turn prompt is an attachment of type queued_command, not a user's message).

    python3 config/companion/lib/transcript_test.py
"""
import json
import os
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import transcript  # noqa: E402


def user(text):
    return {"type": "user", "message": {"role": "user", "content": text}}


def claude(*items):
    return {"type": "assistant", "message": {"role": "assistant", "content": list(items)}}


def queued(prompt, origin="human", mode="prompt"):
    return {"type": "attachment", "isSidechain": False,
            "attachment": {"type": "queued_command", "prompt": prompt, "commandMode": mode,
                           "origin": {"kind": origin}, "humanTurn": True}}


class RecentTest(unittest.TestCase):
    def recent(self, *entries):
        fd, path = tempfile.mkstemp(suffix=".jsonl")
        self.addCleanup(os.remove, path)
        with os.fdopen(fd, "w") as f:
            f.write("cut by the seek\n")         # the first line read is left out, as a tail's would be
            for e in entries:
                f.write(json.dumps(e) + "\n")
        return [(e["role"], e["kind"], e["text"]) for e in transcript.recent(path, "/nowhere", time.time())]

    def test_a_prompt_given_mid_turn_shows_where_it_was_read_in(self):
        tool = {"type": "tool_use", "name": "Bash", "input": {"command": "make"}}
        self.assertEqual(self.recent(
            user("Build it"),
            claude(tool),
            {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "content": "ok"}]}},
            queued("Also run the tests"),
            claude({"type": "text", "text": "Running them too."}),
        ), [
            ("user", "text", "Build it"),
            ("assistant", "tool", "Bash: make"),
            ("user", "text", "Also run the tests"),
            ("assistant", "text", "Running them too."),
        ])

    def test_one_with_an_image_shows_its_words(self):
        prompt = [{"type": "text", "text": "[Image #4] the lights are black"},
                  {"type": "image", "source": {"type": "base64", "data": "AAAA"}}]
        self.assertEqual(self.recent(queued(prompt)), [("user", "text", "[Image #4] the lights are black")])

    def test_not_another_sessions_message_nor_a_task_notice(self):
        self.assertEqual(self.recent(
            queued('<cross-session-message from="x">hi</cross-session-message>', origin="peer"),
            queued("<task-notification>done</task-notification>", origin="task-notification",
                   mode="task-notification"),
            {"type": "attachment", "attachment": {"type": "date", "date": "2026-11-19"}},
        ), [])



def call(cid, name, **inp):
    return claude({"type": "tool_use", "id": cid, "name": name, "input": inp})


def result(cid, content="ok", error=None):
    item = {"type": "tool_result", "tool_use_id": cid, "content": content}
    if error is not None:
        item["is_error"] = error
    return {"type": "user", "message": {"role": "user", "content": [item]}}


class StepsTest(unittest.TestCase):
    """A step's name to read, and its outcome from its result (#3218)."""
    def steps(self, *entries):
        fd, path = tempfile.mkstemp(suffix=".jsonl")
        self.addCleanup(os.remove, path)
        with os.fdopen(fd, "w") as f:
            f.write("cut by the seek\n")
            for e in entries:
                f.write(json.dumps(e) + "\n")
        return [(e["text"], e.get("status")) for e in transcript.recent(path, "/nowhere", time.time())
                if e["kind"] == "tool"]

    def test_mcp_tools_read_as_their_app_and_what_they_do(self):
        self.assertEqual(self.steps(
            call("a", "mcp__claude_ai_Dashboard__log_add", title="Done"), result("a"),
            call("b", "mcp__nightdrive__inbox_update", id=3), result("b"),
            call("c", "mcp__easel__chart"), result("c"),
        ), [("Dashboard: log add", None), ("Inbox: update", None), ("Easel: chart", None)])

    def test_a_command_without_its_cd(self):
        self.assertEqual(self.steps(
            call("a", "Bash", command="cd ~/Projects/deck && cargo test"), result("a"),
            call("b", "Bash", command='cd "/tmp/a b"; ls'), result("b"),
            call("c", "Bash", command="make && cd out"), result("c"),
        ), [("Bash: cargo test", None), ("Bash: ls", None), ("Bash: make && cd out", None)])

    def test_skill_and_message_say_which(self):
        self.assertEqual(self.steps(
            call("a", "Skill", skill="run"), result("a"),
            call("b", "SendMessage", to="Nightdrive Project Manager", message="hi"), result("b"),
        ), [("Skill: run", None), ("SendMessage: Nightdrive Project Manager", None)])

    def test_a_failed_step_a_denied_one_and_one_still_at_work(self):
        self.assertEqual(self.steps(
            call("a", "Bash", command="cargo test"), result("a", "Exit code 101\nfailures: 2", True),
            call("b", "Bash", command="rm -rf target"),
            result("b", "The user doesn't want to proceed with this tool use. The tool use was rejected", True),
            call("c", "Edit", file_path="src/a.rs"),
            result("c", [{"type": "text", "text": "Permission for this command was denied by a built-in Claude Code "
                                                  "safety check, not by the user."}], True),
            call("d", "Read", file_path="src/b.rs"), result("d", "fn main", False),
            call("e", "Bash", command="cargo build"),
        ), [("Bash: cargo test", "error"), ("Bash: rm -rf target", "denied"), ("Edit: src/a.rs", "denied"),
            ("Read: src/b.rs", None), ("Bash: cargo build", "running")])


if __name__ == "__main__":
    unittest.main()
