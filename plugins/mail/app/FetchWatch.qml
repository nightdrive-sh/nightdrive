import QtQuick
import Quickshell
import Quickshell.Io

// Whether mail is being fetched (mbsync and notmuch new: the timer's round, push's inbox fetch or `nightmail sync`),
// for the sidebar's spinner. Every fetch holds nightmail's fetch lock (bin/nightmail, fetch()), so the lock is the
// truth: check() asks whether it is held, and if so a waiter takes it once the fetch lets go, which is the end even
// when the fetch is killed (the kernel drops a dead process's lock). fetch() calls check() over IPC as it starts
// (`nightmail fetching`), and Mail once as it opens, so nothing polls.
QtObject {
    id: root
    readonly property string lock: Quickshell.env("XDG_RUNTIME_DIR") + "/nightdrive/mail-fetch.lock"
    readonly property int heldCode: 75      // flock -n's exit when the lock is held (-E), apart from its own errors
    property bool fetching: false
    signal ended()      // the fetch has let go: its mail is indexed

    function check() {
        if (!fetching && !probe.running) probe.running = true
    }

    readonly property Process probe: Process {
        command: ["flock", "-n", "-E", String(root.heldCode), root.lock, "true"]
        onExited: code => {
            if (code !== root.heldCode) return
            root.fetching = true
            root.waiter.running = true
        }
    }
    // It holds the lock only while `true` runs, so a fetch that starts right after isn't held up
    readonly property Process waiter: Process {
        command: ["flock", root.lock, "true"]
        onExited: { root.fetching = false; root.ended() }
    }
}
