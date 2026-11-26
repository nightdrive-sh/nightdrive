import QtQuick
import Quickshell.Io

// One command at a time with its stdin, its answer to a callback: run(argv, stdin, done(code, stdout, stderr)). The
// window's reads, saves and pickers go through it, each a Run of its own so one never waits for another.
Item {
    id: root
    readonly property bool busy: proc.running || starting
    property bool starting: false
    property var done: null
    property string input: ""

    function run(argv, stdin, then) {
        starting = true
        done = then
        input = stdin || ""
        proc.command = argv
        proc.stdinEnabled = stdin !== undefined && stdin !== null
        proc.running = true
    }

    Process {
        id: proc
        onStarted: {
            root.starting = false
            if (stdinEnabled) { write(root.input); stdinEnabled = false }   // the end of stdin ends the read
        }
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            root.starting = false
            const then = root.done
            root.done = null
            if (then) then(code, out.text, err.text.trim().split("\n").pop() || "")
        }
    }
}
