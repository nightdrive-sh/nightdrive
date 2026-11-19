"""What a session's own view shows from its transcript (transcript.py recent): your prompts, also one given while it
worked (#3147), Claude's texts and its tool calls, in the order they came. The records are shaped as Claude Code
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


if __name__ == "__main__":
    unittest.main()
