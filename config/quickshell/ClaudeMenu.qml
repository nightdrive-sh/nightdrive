import QtQuick
import Quickshell
import qs.kit
import Quickshell.Io

// Claude: the Claude Code sessions on this desktop (Claude.qml) and a new one, then the plan's usage: 5-hour session,
// week and per-model week (topbar/scripts/claude-usage, Claude Code's own sign-in). Each account's in a column of its
// own (ClaudeAccountColumn.qml: its sessions, New session on it, its usage), side by side when there are more than one
// (claude-accounts; #3035), the menu as wide as they need. Claude writes' settings (⌘⇧C) live in the launcher
// (ClaudeWriteLevels.qml): the button at the bottom opens them.
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 10

    property var usage: []            // claude-usage --all: [{ account, plan, windows: [{ key, percent, resetsAt, model }], fetchedAt, error }]
    property bool loaded: false
    signal close()

    // A column per account; before the accounts are read (or with one), one column of every session
    readonly property var accounts: Claude.accounts.length > 1 ? Claude.accounts : [{ name: "", default: true }]
    readonly property bool several: accounts.length > 1
    readonly property int columnWidth: 290
    readonly property int columnGap: 48   // a line down its middle, with room on both sides
    readonly property int maxColumns: 3   // the menu's width stops at three: more accounts share it, narrower
    readonly property int preferredWidth: several
        ? Math.min(accounts.length, maxColumns) * columnWidth + (Math.min(accounts.length, maxColumns) - 1) * columnGap + 26
        : 320

    function refresh() { proc.running = true }
    Component.onCompleted: { refresh(); Claude.refreshAccounts() }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: m.refresh() }

    Sh {
        id: proc
        command: [Quickshell.env("HOME") + "/.config/topbar/scripts/claude-usage", "--all"]
        onResult: text => {
            let v = []
            try { v = JSON.parse(text) || [] } catch (e) {}
            if (JSON.stringify(v) !== JSON.stringify(m.usage)) m.usage = v   // every 5 s: no rebuild when nothing changed
            m.loaded = true
        }
    }
    // An account's usage, by its name; the one column of every session gets the default's (the first)
    function usageOf(account) {
        return account.name ? m.usage.find(u => u.account === account.name) || null : m.usage[0] || null
    }

    // The plan in the header with one account; with more, each column names its own
    MenuHeader { width: parent.width; title: "Claude"; subtitle: !m.several && m.usage.length === 1 && m.usage[0].plan ? m.usage[0].plan : "" }

    // The columns, a line down the middle of each gap between them (drawn over the Row: in it, it would take a place)
    Item {
        width: parent.width
        height: row.height
        Row {
            id: row
            width: parent.width
            spacing: m.columnGap
            // The tallest sessions part, so every column's usage starts at the same height
            readonly property real tallest: {
                let h = 0
                for (let i = 0; i < columns.count; i++) { const c = columns.itemAt(i); if (c) h = Math.max(h, c.topHeight) }
                return h
            }
            Repeater {
                id: columns
                model: m.accounts
                delegate: ClaudeAccountColumn {
                    required property var modelData
                    width: (m.width - (m.accounts.length - 1) * m.columnGap) / m.accounts.length
                    account: modelData
                    usage: m.usageOf(modelData)
                    loaded: m.loaded
                    titled: m.several
                    barToggle: !m.several
                    alignTo: parent.tallest
                    onClose: m.close()
                }
            }
        }
        Repeater {
            model: m.accounts.length - 1
            delegate: Rectangle {
                required property int index
                x: Math.round((index + 1) * (row.width + m.columnGap) / m.accounts.length - m.columnGap / 2)
                width: 1
                height: row.height
                color: Theme.border
                opacity: 0.6   // faint: it divides, it isn't a frame
            }
        }
    }
    // With columns the switch is the menu's, under them
    ClaudeBarToggle { visible: m.several }

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
