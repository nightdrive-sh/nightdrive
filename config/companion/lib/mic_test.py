"""The app as the computer's microphone (mic.py): which app is ready, a start that waits for the app to listen and gives
up when it doesn't, a stop that brings back its words, and commands only on the newest stream. The "app" here is a
thread that answers as the page would; no server, no socket.

    python3 config/companion/lib/mic_test.py
"""
import os
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mic  # noqa: E402

IPAD = "ipad-0123456789"
PHONE = "phone-0123456789"


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


class MicTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.state = os.path.join(self.dir.name, "dictate-remote")
        self.clock = Clock()
        self.m = mic.Mic(threading.Condition(), state_file=self.state, clock=self.clock)

    def tearDown(self):
        self.dir.cleanup()

    def ready(self, device, name="iPad"):
        token = self.m.open(device)
        self.m.ready(device, name, True)
        return token

    def app(self, device, token, answer):
        """A page that takes its stream's commands and answers each with answer(command)."""
        def run():
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                with self.m.cond:
                    self.m.cond.wait_for(lambda: self.m.pending(device, token), timeout=0.1)
                    commands = self.m.take(device, token)
                for c in commands:
                    for kind, text in answer(c):
                        self.m.event(device, c["id"], kind, **{"error" if kind == "error" else "text": text})
        t = threading.Thread(target=run, daemon=True)
        t.start()
        return t

    def read_state(self):
        try:
            with open(self.state) as f:
                return f.read().strip()
        except FileNotFoundError:
            return None

    def test_none_ready(self):
        self.assertIsNone(self.m.available())
        with self.assertRaises(mic.MicError):
            self.m.start(wait=0.1)

    def test_ready_expires_and_ends_with_its_stream(self):
        token = self.ready(IPAD)
        self.assertEqual(self.m.available(), IPAD)
        self.clock.now += mic.READY_FOR + 1
        self.assertIsNone(self.m.available())
        self.m.ready(IPAD, "iPad", True)
        self.m.close(IPAD, token)
        self.assertIsNone(self.m.available())

    def test_the_most_recent_ready(self):
        self.ready(IPAD, "iPad")
        self.clock.now += 5
        self.ready(PHONE, "iPhone")
        self.assertEqual(self.m.available(), PHONE)
        self.m.ready(PHONE, "iPhone", False)     # its page went to the background
        self.assertEqual(self.m.available(), IPAD)

    def test_start_and_stop_bring_back_the_words(self):
        token = self.ready(IPAD)
        states = []

        def answer(c):
            if c["op"] == "start":
                return [("started", "")]
            states.append(self.read_state())
            return [("text", "Hei maailma")]
        self.app(IPAD, token, answer)
        got = self.m.start(wait=2)
        self.assertEqual(got["name"], "iPad")
        self.assertEqual(self.read_state(), "listening iPad")
        self.assertEqual(self.m.stop(got["id"], wait=2), "Hei maailma")
        self.assertEqual(states, ["transcribing iPad"])
        self.assertIsNone(self.read_state())
        self.assertIsNone(self.m.current)

    def test_a_silent_app_gives_up_and_is_aborted(self):
        token = self.ready(IPAD)
        with self.assertRaises(mic.MicError):
            self.m.start(wait=0.2)
        with self.m.cond:
            self.assertEqual([c["op"] for c in self.m.take(IPAD, token)], ["start", "abort"])
        self.assertIsNone(self.read_state())

    def test_an_error_before_listening_fails_the_start(self):
        token = self.ready(IPAD)
        self.app(IPAD, token, lambda c: [("error", "not-allowed")] if c["op"] == "start" else [])
        with self.assertRaisesRegex(mic.MicError, "not-allowed"):
            self.m.start(wait=2)

    def test_stop_while_start_waits(self):
        # The key let go before the app answered: dictate's stop has no id yet, and gets the words all the same
        token = self.ready(IPAD)
        out = {}
        starter = threading.Thread(target=lambda: out.setdefault("start", self.m.start(wait=2)))
        starter.start()
        time.sleep(0.1)
        self.app(IPAD, token, lambda c: [("started", "")] if c["op"] == "start" else [("text", "Hei")])
        self.assertEqual(self.m.stop(wait=2), "Hei")
        starter.join(3)
        self.assertIsNone(self.m.current)

    def test_commands_only_on_the_newest_stream(self):
        old = self.ready(IPAD)
        new = self.m.open(IPAD)          # iOS left the old connection open, silent; the page opened another
        with self.m.cond:
            self.m._send(IPAD, "start", 1)
            self.assertFalse(self.m.pending(IPAD, old))
            self.assertEqual(self.m.take(IPAD, old), [])
            self.assertEqual(self.m.take(IPAD, new), [{"op": "start", "id": 1}])
        self.m.close(IPAD, old)          # the old one closing doesn't take the new one's place
        self.assertEqual(self.m.available(), IPAD)

    def test_an_event_for_another_dictation_is_refused(self):
        self.ready(IPAD)
        with self.assertRaises(ValueError):
            self.m.event(IPAD, 7, "text", "late")

    def test_names_and_ids(self):
        self.assertEqual(mic.device_name("iPad"), "iPad")
        self.assertEqual(mic.device_name("<b>x</b>"), "bxb")
        self.assertEqual(mic.device_name(None), "the app")
        self.assertIsNone(mic.device_id("short"))
        self.assertIsNone(mic.device_id("../../etc/passwd-xx"))
        self.assertEqual(mic.device_id(IPAD), IPAD)

    def test_lid(self):
        path = os.path.join(self.dir.name, "lid")
        self.assertFalse(mic.lid_closed(path))
        with open(path, "w") as f:
            f.write("closed\n")
        self.assertTrue(mic.lid_closed(path))


if __name__ == "__main__":
    unittest.main()
