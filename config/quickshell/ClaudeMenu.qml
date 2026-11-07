import QtQuick
import Quickshell
import qs.kit
import Quickshell.Io

// Claude: the Claude Code sessions on this desktop (Claude.qml: a click goes to its window; the ones that finished while
// you were elsewhere first) and a new one, then the plan's usage: 5-hour session, week and per-model week
// (topbar/scripts/claude-usage, Claude Code's own sign-in). Claude writes' settings (⌘⇧C) live in the launcher
// (ClaudeWriteLevels.qml): the button at the bottom opens them.
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 10

    property var usage: null          // { plan, windows: [{ key, percent, resetsAt, model }], fetchedAt }
    property bool loaded: false
    signal close()

    function refresh() { proc.running = true }
    Component.onCompleted: refresh()
    Timer { interval: 5000; repeat: true; running: true; onTriggered: m.refresh() }

    Sh {
        id: proc
        command: [Quickshell.env("HOME") + "/.config/topbar/scripts/claude-usage"]
        onResult: text => {
            try { m.usage = JSON.parse(text) } catch (e) { m.usage = null }
            m.loaded = true
        }
    }

    function label(w) {
        if (w.key === "session") return "5-hour session"
        if (w.key === "weekly") return "Weekly"
        return "Weekly · " + (w.model || "model")
    }
    // "resets in 1h 28m" (under 24 h) or "resets Wed 01:00"
    function resets(iso) {
        const t = new Date(iso)
        if (isNaN(t)) return ""
        const d = Math.round((t - new Date()) / 1000)
        if (d <= 0) return "resetting now"
        if (d < 86400) {
            const h = Math.floor(d / 3600), mi = Math.floor(d % 3600 / 60)
            return "resets in " + (h > 0 ? h + "h " : "") + mi + "m"
        }
        return "resets " + Regional.dayName(t.getDay(), true) + " " + Regional.format(t, "time")   // the region's time: 1:00 AM in the US
    }

    MenuHeader { width: parent.width; title: "Claude"; subtitle: m.usage && m.usage.plan ? m.usage.plan : "" }

    MenuSection { title: "Sessions" }
    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: Claude.sessions
            delegate: MenuRow {
                required property var modelData
                width: parent.width
                icon: modelData.wants ? "bell-dot" : modelData.state === "working" ? "loader" : "terminal"
                iconColor: modelData.wants ? Theme.accent : "transparent"
                active: modelData.wants
                label: modelData.topic || modelData.project
                detail: modelData.state === "working" ? "working" : modelData.wants ? "done" : modelData.project
                busy: modelData.state === "working"
                onClicked: { Claude.focus(modelData); m.close() }
            }
        }
    }
    MenuButton {
        icon: "plus"
        label: "New session"
        onClicked: { Claude.newSession(); m.close() }
    }
    // The sessions bar at the bottom of the screen (SessionsBar.qml): laid out like Display's Night light row
    Item {
        id: barRow
        width: parent.width
        height: 30
        property bool navSelected: false
        readonly property bool navEnabled: true
        function navActivate() { Claude.setBar(!Claude.barOn) }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: barRow.navActivate() }
        Text {
            id: barIcon
            x: 10
            width: 20
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: Icons.g("panel-bottom")
            color: Theme.dim
            font { family: Icons.family; pixelSize: 16 }
        }
        Text {
            anchors { left: barIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: "Sessions bar"
            color: Theme.text
            font { family: Theme.font; pixelSize: 13 }
        }
        Toggle {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            checked: Claude.barOn
            navSelected: barRow.navSelected
            onToggled: barRow.navActivate()
        }
    }

    MenuSection { apart: true; title: "Usage" }

    MenuNote {
        visible: m.loaded && (!m.usage || !m.usage.windows || m.usage.windows.length === 0 || !!m.usage.error)
        text: m.usage && m.usage.error ? m.usage.error : "No usage data. Sign in to Claude Code (run claude) first."
    }

    Repeater {
        model: m.usage && m.usage.windows ? m.usage.windows : []
        delegate: Column {
            required property var modelData
            width: m.width
            spacing: 5
            Item {
                width: parent.width; height: 18
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: m.label(modelData)
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 13 }
                }
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: modelData.percent + "%"
                    color: modelData.percent > 95 ? Theme.danger : (modelData.percent > 90 ? Theme.warning : Theme.text)
                    font { family: Theme.font; pixelSize: 13; bold: true }
                }
            }
            Rectangle {
                width: parent.width; height: 6; radius: 3
                color: Theme.border
                Rectangle {
                    width: parent.width * Math.min(1, modelData.percent / 100)
                    height: parent.height; radius: 3
                    color: modelData.percent > 95 ? Theme.danger : (modelData.percent > 90 ? Theme.warning : Theme.accent)
                }
            }
            MenuNote { text: m.resets(modelData.resetsAt) }
        }
    }

    MenuButton {
        gap: 10   // no divider above it: the room sets it apart
        icon: "external-link"
        label: "Open usage page"
        onClicked: { Quickshell.execDetached(["xdg-open", "https://claude.ai/settings/usage"]); m.close() }
    }
    MenuButton {
        icon: "settings"
        label: "Claude writes settings…"
        onClicked: { Quickshell.execDetached(["qs", "ipc", "call", "launcher", "openLevel", "claudewrite"]); m.close() }
    }
}
