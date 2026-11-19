import QtQuick
import Quickshell
import Quickshell.Io

// The sessions bar's Inbox button (#3179), at its right end: the mailbox (Inbox's own icons, plugins/inbox/icons), its
// flag raised and the count while Claude's sessions have left messages you haven't read; a click opens Inbox with only
// the sessions' messages (`inbox from claude`). Nothing pops up and nothing sounds: a message waits until you have time.
// The numbers come from `nightdrive inbox count --json` (config/inbox), every pollEvery ms while the bar shows: the
// core's command is there on every install, the window may not be (then there's no button: installed).
Rectangle {
    id: btn
    property bool running: false           // SessionsBar.visible: no polling while there's no bar
    readonly property int pollEvery: 5000  // as the top bar's Inbox module (plugins/inbox/module.jsonc)
    readonly property string home: Quickshell.env("HOME")
    // Its icons come with the plugin (nightdrive plugins installed lists them); without it, no window to open
    readonly property bool installed: icons.loaded
    readonly property int pad: 10
    readonly property int iconW: 19        // as the top bar's Inbox module (#3212)

    property int unread: 0                 // the sessions' unread messages, all of them

    visible: installed
    width: installed ? pad + iconW + (unread ? 6 + num.implicitWidth : 0) + pad : 0
    radius: 6
    color: area.containsMouse ? Theme.hover : "transparent"

    // Only to see whether the plugin's icons are there
    FileView { id: icons; path: btn.home + "/.local/state/nightdrive/plugins.d/icons/mailbox-flag-up.svg"; printErrors: false }

    Image {
        id: img
        anchors { left: parent.left; leftMargin: btn.pad; verticalCenter: parent.verticalCenter }
        width: btn.iconW; height: btn.iconW
        sourceSize { width: btn.iconW * 2; height: btn.iconW * 2 }
        source: TopBar.iconUrl(btn.unread ? "mailbox-flag-up" : "mailbox-flag-down", btn.unread ? Theme.accent : Theme.dim)
    }
    Text {
        id: num
        visible: btn.unread > 0
        anchors { left: img.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
        text: btn.unread
        color: Theme.text
        font { family: Theme.font; pixelSize: 12 }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Quickshell.execDetached([btn.home + "/.local/bin/inbox", "from", "claude"])
            poll.restart()
        }
    }

    Process {
        id: counter
        command: [btn.home + "/.local/bin/nightdrive", "inbox", "count", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text)
                    btn.unread = r.claude || 0
                } catch (e) { /* an older core without the sessions' count: no number */ }
            }
        }
    }
    Timer {
        id: poll
        interval: btn.pollEvery; repeat: true; triggeredOnStart: true
        running: btn.running && btn.installed
        onTriggered: if (!counter.running) counter.running = true
    }
}
