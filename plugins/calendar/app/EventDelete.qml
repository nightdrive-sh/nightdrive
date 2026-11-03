import QtQuick
import Quickshell.Io
import qs.kit
import "Dates.js" as Dates

// Deleting an event, asked first: the kit's yes-or-no panel with what goes, then `calendar delete --check`, which
// deletes it here and on the server only if the event is still the one asked about (its title and start, as the card
// showed them): a sync in between may have changed it. The panel stays while that runs, so a server's refusal is said
// on it; the window is told when it is gone (deleted), to reload and say so.
AppConfirm {
    id: root
    required property var app           // the window: command
    property var event: null
    property bool busy: false
    property string error: ""
    signal deleted(var result)          // calendar delete's JSON: deleted (the uid), title, start, synced
    signal closed()
    visible: false
    action: busy ? "Deleting…" : "Delete"
    question: event ? "Delete “" + event.title + "”?" : ""
    detail: error !== "" ? error
          : event ? Dates.span(event, Regional) + " · " + event.calendar_name + ". It goes from the server and your other devices too."
          : ""

    function ask(e) { event = e; error = ""; visible = true }
    function close() { if (!busy) { visible = false; closed() } }
    onAnswered: ok => {
        if (busy) return
        if (!ok) { close(); return }
        busy = true
        deleter.command = [app.command, "delete", "--json", "--check", event.calendar, event.uid]
        deleter.input = JSON.stringify({ title: event.title, start: event.start })
        deleter.running = true
    }

    Process {
        id: deleter
        property string input: ""
        stdinEnabled: true
        onStarted: { write(input); stdinEnabled = false }   // the end of stdin ends its read
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            root.busy = false
            stdinEnabled = true
            let result = null
            if (code === 0) try { result = JSON.parse(out.text) } catch (e) {}
            if (!result) {
                // write.py's own words, the last line: the server said no, or the event changed since the view read
                // it, whose words are written for Claude (calendar_events); here a fresh read is the window's own
                const said = err.text.trim().split("\n").pop()
                root.error = said.startsWith("Nothing deleted: the event is")
                           ? "It has changed since it was shown (a sync), so nothing was deleted. Open it again to see it as it is."
                           : said || "The event wasn't deleted: calendar log says why."
                if (said.startsWith("Nothing deleted")) root.app.reload()
                return
            }
            root.close()
            root.deleted(result)
        }
    }
}
