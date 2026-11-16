import QtQuick
import qs.kit

// One Claude Code account's plan usage in the Claude menu (ClaudeMenu.qml): its section, then a meter for each window
// (5-hour session, week, per-model week) with when it resets. usage is one of
// topbar/scripts/claude-usage --all's: { account, plan, windows: [{ key, percent, resetsAt, model }], error }.
Column {
    id: u
    width: parent ? parent.width : 300
    spacing: 10

    property var usage: null
    property bool loaded: false

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
    readonly property var windows: usage && usage.windows ? usage.windows : []

    MenuSection { apart: true; title: "Usage" }

    MenuNote {
        visible: u.loaded && (u.windows.length === 0 || !!(u.usage && u.usage.error))
        text: u.usage && u.usage.error ? u.usage.error
            : "No usage data. Sign in to Claude Code (run claude) first."
    }

    Repeater {
        model: u.windows
        delegate: Column {
            required property var modelData
            width: u.width
            spacing: 5
            Item {
                width: parent.width; height: 18
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: u.label(modelData)
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
            MenuNote { text: u.resets(modelData.resetsAt) }
        }
    }
}
