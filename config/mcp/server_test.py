#!/usr/bin/env python3
"""server.py's cancellation (#1865): `python3 config/mcp/server_test.py`. Claude Code cancels a call (Esc, its own
timeout) while the confirmation card waits for the user: the card must close at once, not stay to be allowed for a
call no one waits for any more. The card is a stand-in (confirm.qs), the tools a provider of the test's own."""

import io
import json
import os
import sys
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import confirm  # noqa: E402
import server  # noqa: E402


class Card:
    """confirm.qs as Quickshell would answer: the card is shown and stays pending until closed."""

    def __init__(self):
        self.calls, self.lock = [], threading.Lock()

    def __call__(self, *args):
        with self.lock:
            self.calls.append(args)
        return "pending"

    def asked(self):
        with self.lock:
            return any(c[0] == "answer" for c in self.calls)

    def closed(self):
        with self.lock:
            return [c[1] for c in self.calls if c[0] == "close"]


class Tools:
    """A provider whose `act` waits on the card, as registry.call does for a tool that asks."""

    def __init__(self):
        self.ran = []

    def list(self):
        return []

    def call(self, name, arguments):
        self.ran.append(name)
        if name == "act" and not confirm.wait("card1", name, timeout=30):
            raise server.ToolError("denied")
        return {"content": [{"type": "text", "text": "done"}]}


class Cancel(unittest.TestCase):
    def setUp(self):
        self.card = Card()
        patcher = mock.patch.object(confirm, "qs", self.card)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.tools = Tools()
        read, write = os.pipe()
        self.stdin, self.pipe = os.fdopen(read, "r"), os.fdopen(write, "w")
        self.stdout = io.StringIO()
        srv = server.Server(self.tools)
        self.thread = threading.Thread(target=srv.serve, args=(self.stdin, self.stdout), daemon=True)
        with mock.patch.object(server, "log", lambda text: None):
            self.thread.start()
        self.addCleanup(self.stdin.close)

    def send(self, **message):
        self.pipe.write(json.dumps({"jsonrpc": "2.0", **message}) + "\n")
        self.pipe.flush()

    def until(self, test, timeout=5):
        end = time.monotonic() + timeout
        while not test():
            if time.monotonic() > end:
                self.fail("timed out")
            time.sleep(0.02)

    def responses(self):
        return [json.loads(line) for line in self.stdout.getvalue().splitlines()]

    def end(self):
        self.pipe.close()
        self.thread.join(5)
        self.assertFalse(self.thread.is_alive())

    def test_cancel_closes_the_card(self):
        self.send(id=1, method="tools/call", params={"name": "act", "arguments": {}})
        self.until(self.card.asked)
        self.send(method="notifications/cancelled", params={"requestId": 1, "reason": "user pressed Esc"})
        self.until(lambda: self.card.closed())
        self.assertEqual(self.card.closed(), ["card1"])
        self.send(id=2, method="ping", params={})
        self.until(lambda: self.responses())
        self.assertEqual([r["id"] for r in self.responses()], [2])   # none for the cancelled call
        self.end()

    def test_cancel_of_another_id_leaves_the_card(self):
        self.send(id=1, method="tools/call", params={"name": "act", "arguments": {}})
        self.until(self.card.asked)
        for rid in (2, "1", None, [1]):
            self.send(method="notifications/cancelled", params={"requestId": rid})
        self.send(method="notifications/cancelled", params="x")
        time.sleep(0.6)
        self.assertEqual(self.card.closed(), [])
        self.end()   # the client went away: that closes it
        self.assertEqual(self.card.closed(), ["card1"])

    def test_queued_call_cancelled_before_it_runs(self):
        self.send(id=1, method="tools/call", params={"name": "act", "arguments": {}})
        self.until(self.card.asked)
        self.send(id=2, method="tools/call", params={"name": "other", "arguments": {}})
        self.send(method="notifications/cancelled", params={"requestId": 2})
        self.send(method="notifications/cancelled", params={"requestId": 1})
        self.send(id=3, method="ping", params={})
        self.until(lambda: self.responses())
        self.assertEqual(self.tools.ran, ["act"])
        self.assertEqual([r["id"] for r in self.responses()], [3])
        self.end()

    def test_client_gone_asks_no_more(self):
        """A pipe's calls still run once it ends, but none waits on a card that no one can answer."""
        self.send(id=1, method="tools/call", params={"name": "act", "arguments": {}})
        self.until(self.card.asked)
        self.send(id=2, method="tools/call", params={"name": "other", "arguments": {}})
        self.send(id=3, method="tools/call", params={"name": "act", "arguments": {}})
        self.end()
        self.assertEqual(self.card.closed(), ["card1", "card1"])
        self.assertEqual(self.tools.ran, ["act", "other", "act"])
        self.assertEqual([r["id"] for r in self.responses()], [1, 2, 3])
        self.assertTrue(self.responses()[2]["result"]["isError"])

    def test_bad_lines_still_answered(self):
        self.pipe.write("not json\n")
        self.send(id=[1], method="ping", params={})
        self.send(id=4, method="ping", params={})
        self.end()
        self.assertEqual([r.get("id") for r in self.responses()], [None, None, 4])


if __name__ == "__main__":
    unittest.main()
