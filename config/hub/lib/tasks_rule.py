"""Tasks' rule for the Hub (apps.py): the vdir in ~/.local/share/nightdrive/tasks, a folder per list and an .ics file
per task (plugins/tasks/lib/store.py).

A task edited on two devices is merged field by field from the version both last agreed on (Tasks' merge.py,
#3397): a value that lost goes in the task's notes. When it can't be (no agreed version: a first sync, a new Hub; a
file that isn't a task) both are kept (#3395): the Hub's stays in the task's place, and this computer's becomes a task
of its own beside it, with a UID of its own and the computer's name after its title ("Buy milk (laptop)"), so both
show in the window and the person picks. A task deleted on another device goes to Tasks' own trash (30 days), as a
deletion in the window does.
"""
import sys
import uuid
from pathlib import Path

import apps

# The Tasks plugin's library, from the repo this file is in (config/hub/lib -> plugins/tasks/lib): the same code that
# writes the files reads them here, so a copy is a task Tasks reads as its own. resolve(): ~/.config/hub is a link.
TASKS_LIB = Path(__file__).resolve().parents[3] / "plugins/tasks/lib"
sys.path.insert(0, str(TASKS_LIB))
import ics  # noqa: E402
import merge as task_merge  # noqa: E402
import store  # noqa: E402


class TasksRule(apps.Rule):
    name = "tasks"

    def root(self):
        return str(store.DATA)

    def accept(self, path):
        # A list's folder and a file in it (task.ics, displayname, color): what a vdir holds. Anything deeper or at the
        # top is no list's, so not Tasks' to send.
        return path.count("/") == 1

    def keeps_base(self, path):
        return path.endswith(".ics")

    def merge(self, path, base, mine, theirs):
        if not self.keeps_base(path):
            return None
        m = task_merge.merge(base, mine, theirs, apps.host())
        return m.text.encode("utf-8") if m else None

    def keep_both(self, path, data):
        if not path.endswith(".ics"):
            # A list's name renamed on two devices: the Hub's name stays, this one waits in the state folder
            return super().keep_both(path, data)
        folder = path.rsplit("/", 1)[0]
        try:
            task = ics.Task(data.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            return super().keep_both(path, data)
        # A new UID altogether: Tasks finds a task by its UID or the start of it (the short id `tasks list` shows),
        # so a copy whose UID began as the original's would make that short id ambiguous
        task.set("UID", str(uuid.uuid4()))
        full = store.path_for({"path": Path(self.root()) / folder}, task)
        task.set("SUMMARY", "%s (%s)" % (task.get("SUMMARY"), apps.host()))
        task.touch()
        store.write(full, str(task))
        return "%s/%s" % (folder, full.name)

    def put_away(self, path):
        if not path.endswith(".ics"):
            return super().put_away(path)
        # store.trash keeps the list/file layout under Tasks' trash and clears trash older than 30 days
        store.trash(Path(self.full(path)))
        self.tidy(path)
