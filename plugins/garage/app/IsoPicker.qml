import QtQuick
import Quickshell
import Quickshell.Io

// Choose an ISO in a file dialog (zenity, as Mail's attachments), from ~/Downloads where one usually is, or from the
// one there is. pick(start, path => …): nothing comes back if the dialog is cancelled.
QtObject {
    id: root
    property var done: null
    function pick(start, then) {
        done = then
        const from = start ? start : Quickshell.env("HOME") + "/Downloads/"
        dialog.command = ["zenity", "--file-selection", "--title=Choose an ISO", "--filename=" + from,
                          "--file-filter=ISO images | *.iso *.ISO", "--file-filter=All files | *"]
        dialog.running = true
    }
    property Process dialog: Process {
        stdout: StdioCollector {
            onStreamFinished: { const p = text.trim(); if (p && root.done) root.done(p) }
        }
    }
}
