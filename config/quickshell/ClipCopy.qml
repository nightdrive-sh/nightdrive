import QtQuick
import Quickshell
import Quickshell.Io

// Copies text to the clipboard through wl-copy's stdin, never its arguments: a command line is readable by every user in
// /proc/PID/cmdline while it runs (#1947). copy(v, sensitive): a sensitive value (a password) skips the clipboard
// history (wl-copy --sensitive, which cliphist honours) and is cleared after 45 s unless something else was copied since.
// The script keeps the value in a shell variable; printf and [ are builtins, so it's in no other process's command line.
// One Process per copy, gone once wl-copy has it (or, when sensitive, once it has cleared).
Item {
    id: c

    function copy(v, sensitive) { clipper.createObject(c, { input: String(v), sensitive: sensitive === true }) }

    Component {
        id: clipper
        Process {
            property string input
            property bool sensitive
            running: true
            stdinEnabled: true
            command: sensitive
                ? ["bash", "-c", 'IFS= read -r -d "" p; printf %s "$p" | wl-copy --sensitive; sleep 45; [ "$(wl-paste -n 2>/dev/null)" = "$p" ] && wl-copy --clear']
                : ["wl-copy"]
            onStarted: { write(input); input = ""; stdinEnabled = false }   // the end of stdin ends the read
            onExited: destroy()
        }
    }
}
