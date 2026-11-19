import QtQuick
import Quickshell
import qs

// Inbox's menu, from the top bar's mailbox (#3215): the newest messages, each with its title, sender, time and an unread
// mark; a click opens Inbox on that message (`inbox show ID`, which also turns a window that is already open to it), and
// Open Inbox at the bottom the whole window. The list is `nightdrive inbox list --json` as it is, newest first like the
// window's: nothing is worked out here. The sessions bar's mailbox still opens the window straight away.
Column {
    id: m
    width: parent ? parent.width : 360
    spacing: 8
    signal close()
    readonly property int preferredWidth: 360   // room for a title beside the time

    readonly property int shown: 6              // how many of the newest; the rest are in the window
    // The core's command by its path, as ./status uses it: ~/.local/bin may not be in Quickshell's PATH
    readonly property string cli: Qt.resolvedUrl("../../config/inbox/cli.py").toString().replace(/^file:\/\//, "")
    readonly property string app: Qt.resolvedUrl("bin/inbox").toString().replace(/^file:\/\//, "")
    property var messages: []
    property int unread: 0
    property bool loaded: false
    property bool failed: false

    // Today's by the clock, yesterday's as such, older ones by the date: the window's list shows the rest
    function when(iso) {
        const d = new Date(iso), now = new Date()
        const day = x => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
        const days = Math.round((day(now) - day(d)) / 86400000)
        if (days === 0) return Qt.formatTime(d, "HH:mm")
        if (days === 1) return "yesterday"
        return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy")
    }
    function open(args) { Quickshell.execDetached([m.app].concat(args)); m.close() }

    Component.onCompleted: list.running = true
    Timer { interval: 5000; repeat: true; running: true; onTriggered: list.running = true }

    Sh {
        id: list
        command: ["python3", m.cli, "list", "--json", "--limit", String(m.shown)]
        onResult: text => {
            try {
                const j = JSON.parse(text)
                m.messages = j.messages || []; m.unread = j.unread || 0; m.failed = false
            } catch (e) { m.failed = true }
            m.loaded = true
        }
    }

    MenuHeader {
        width: parent.width
        title: "Inbox"
        subtitle: m.unread ? m.unread + " unread" : ""
    }

    MenuNote {
        visible: text !== ""        // an empty one still takes the column's spacing
        variant: m.failed ? "danger" : "dim"
        text: !m.loaded || m.messages.length ? "" : m.failed ? "Couldn't read the messages (nightdrive inbox list)."
            : "No messages. Sessions leave theirs here for when you have time."
    }

    Column {
        width: parent.width
        spacing: 2
        visible: m.messages.length > 0
        Repeater {
            model: m.messages
            // A MenuRow for its click, hover and keys, with two lines of its own in place of the label: the title,
            // and under it who left it
            delegate: MenuRow {
                id: row
                required property var modelData
                readonly property bool isUnread: !modelData.read
                width: m.width
                height: 46
                onClicked: m.open(["show", modelData.id])

                // Its own two lines in place of MenuRow's label, with the unread mark (small) and the time level with
                // the title rather than MenuRow's icon and detail in the middle of the row
                Text {
                    id: title
                    anchors { left: parent.left; leftMargin: row.pad + 26; right: time.left; rightMargin: 10
                              top: parent.top; topMargin: 6 }
                    text: row.modelData.title
                    elide: Text.ElideRight
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 13; weight: row.isUnread ? Font.DemiBold : Font.Normal }
                }
                Text {
                    anchors { left: title.left; right: title.right; top: title.bottom; topMargin: 1 }
                    text: (row.modelData.sender || {}).short || ""
                    elide: Text.ElideRight
                    color: Theme.dim
                    font { family: Theme.font; pixelSize: 11 }
                }
                Text {
                    anchors { left: parent.left; leftMargin: row.pad + 3; baseline: title.baseline; baselineOffset: 2 }   // the glyph sits high on the baseline
                    text: Icons.g(row.isUnread ? "mail" : "mail-open")
                    color: row.isUnread ? Theme.primary : Theme.dim
                    font { family: Icons.family; pixelSize: 13 }
                }
                Text {
                    id: time
                    anchors { right: parent.right; rightMargin: row.pad; baseline: title.baseline }
                    text: m.when(row.modelData.at)
                    color: Theme.dim
                    font { family: Theme.font; pixelSize: 11 }
                }
            }
        }
    }

    MenuButton {
        gap: 10
        icon: "inbox"
        label: "Open Inbox"
        onClicked: m.open([])
    }
}
