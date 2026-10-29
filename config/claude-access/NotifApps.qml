import QtQuick
import Quickshell.Io

// The apps in the notification history, by the name their notifications carry: what Access › Notifications' list (the
// apps whose notifications Claude doesn't see, Dashboard #1789) offers to tick. Read when the panel opens (refresh), as
// `nightdrive notifications list --json` of this checkout, the whole history (50).
QtObject {
    id: apps
    required property string nd         // the window's nightdrive (Store.nd)
    property var names: []

    function refresh() { if (!reader.running) reader.running = true }

    property Process reader: Process {
        command: [apps.nd, "notifications", "list", "--json", "--limit", "50"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const seen = {}
                    apps.names = JSON.parse(text).notifications.map(n => n.app || "")
                        .filter(a => a && !seen[a.toLowerCase()] && (seen[a.toLowerCase()] = true))
                } catch (e) {
                    apps.names = []
                }
            }
        }
    }
}
