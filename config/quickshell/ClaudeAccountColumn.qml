import QtQuick
import qs.kit

// One Claude Code account in the Claude menu (ClaudeMenu.qml): its sessions (a click goes to the window; the ones that
// finished while you were elsewhere first), New session on it, and its usage (ClaudeUsage.qml). With one account the
// menu is this alone, as it always was; with more, a column each, side by side, under the account's name and plan.
// account is one of claude-accounts --json's ({ name, default, plan, … }); { name: "" } stands for "every session"
// while the accounts aren't read yet.
Column {
    id: col
    width: parent ? parent.width : 300
    spacing: 10

    property var account: ({ name: "", default: true })
    property var usage: null             // claude-usage's for this account
    property bool loaded: false
    property bool titled: false          // more than one account: its name and plan on top
    property bool barToggle: false       // the Sessions bar switch after New session (one account: where it always was)
    // Side by side, the usage sections start level: the menu gives the tallest column's sessions part (topHeight)
    property real alignTo: 0
    readonly property real topHeight: top.height
    signal close()

    // The account's sessions: a session on a config dir no account lists goes with the default's
    readonly property var sessions: !account.name ? Claude.sessions
        : Claude.sessions.filter(s => account.default ? (s.accountDefault || !Claude.accounts.some(a => a.name === s.account))
                                                      : s.account === account.name)

    // As tall as the tallest column's (alignTo), so the usage below starts level with the others' (a spacer item of
    // height 0 would be skipped by the Column, and its spacing with it)
    Item {
        width: parent.width
        height: Math.max(top.height, col.alignTo)
        Column {
            id: top
            width: parent.width
            spacing: col.spacing
            MenuSection {
                visible: col.titled
                title: col.account.name || ""
                subtitle: col.account.plan || ""
            }
            MenuSection { title: "Sessions" }
            MenuNote { visible: col.titled && col.sessions.length === 0; text: "No sessions" }
            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: col.sessions
                    delegate: MenuRow {
                        required property var modelData
                        width: parent.width
                        icon: modelData.wants ? "bell-dot" : modelData.state === "working" ? "loader" : "terminal"
                        iconColor: modelData.wants ? Theme.accent : "transparent"
                        active: modelData.wants
                        label: modelData.topic || modelData.project
                        detail: modelData.state === "working" ? "working" : modelData.wants ? "done" : modelData.project
                        busy: modelData.state === "working"
                        onClicked: { Claude.focus(modelData); col.close() }
                    }
                }
            }
            MenuButton {
                icon: "plus"
                label: "New session"
                onClicked: { Claude.newSession(col.account.default ? "" : col.account.name); col.close() }
            }
            ClaudeBarToggle { visible: col.barToggle }
        }
    }

    ClaudeUsage {
        width: col.width
        usage: col.usage
        loaded: col.loaded
    }
}
