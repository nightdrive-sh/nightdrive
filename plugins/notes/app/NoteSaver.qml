import QtQuick
import Quickshell.Io

// Writes the editor's text to its note through `notes write` (lib/notes.py), one save at a time. The text goes on stdin,
// so nothing in it can be read as an option, and with --expect the MD5 of the text the editor started from: a save in
// Apostrophe or Claude's append meanwhile is reported as a conflict (exit status 3), never written over unasked.
// A save asked for while one runs waits for it and then writes the latest text: saving often stays one write at a time.
Item {
    id: root
    required property string command        // the plugin's bin/notes
    // From save() until the write has answered: set at once, not when the process has started, so a window quitting
    // right after a save waits for it (shell.qml) rather than leaving notes.py an empty stdin
    property bool writing: false
    readonly property bool busy: writing || pending !== null

    // id: the note's; text: the whole note; base: what the editor started from (null: write over whatever is there)
    signal saved(string id, string text, var note)
    signal conflict(string id, string text)
    signal failed(string id, string message)
    signal setAside(string id, var note)      // keepAside's new note

    property var pending: null               // the save asked for while one was running: the latest only
    function save(id, text, base) {
        const job = { id: id, text: text, expect: base === null ? null : Qt.md5(base) }
        if (writing) { pending = job; return }
        start(job)
    }

    // Text that can't go into its note (changed elsewhere, and the window is closing): a new note of its own, so nothing
    // written is lost. notes create names it after the title and puts the title on top.
    function keepAside(id, title, text) {
        const job = { id: id, text: text, aside: title + " (not saved)" }
        if (writing) { pending = job; return }
        start(job)
    }

    function start(job) {
        writing = true
        proc.job = job
        // --md5: notes.py writes only this text, whole; a stdin cut short is refused, not written
        proc.command = job.aside ? [command, "create", "--json", job.aside]
            : [command, "write", "--json", "--md5", Qt.md5(job.text)]
                .concat(job.expect === null ? [] : ["--expect", job.expect], [job.id])
        proc.stdinEnabled = true
        proc.running = true
    }

    Process {
        id: proc
        property var job: null
        onStarted: { write(job.text); stdinEnabled = false }   // the end of stdin ends the read
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            const job = proc.job
            let note = null
            if (code === 0) try { note = JSON.parse(out.text) } catch (e) {}
            if (note && job.aside) root.setAside(job.id, note)
            else if (note) root.saved(job.id, job.text, note)
            else if (code === 3) root.conflict(job.id, job.text)
            // notes.py's own words, the last line: the rest is a traceback, if anything
            else root.failed(job.id, err.text.trim().split("\n").pop() || "The note wasn't saved: notes log says why.")
            const next = root.pending
            root.pending = null
            root.writing = false
            if (next) {
                // The waiting save started from what this one wrote, if this one wrote: its check is against that
                if (note && !job.aside && next.id === job.id && next.expect) next.expect = note.md5
                root.start(next)
            }
        }
    }
}
