import QtQuick
import Quickshell
import qs.kit
import Quickshell.Io

// Claude: one Claude Code account's sessions on this desktop (Claude.qml: a click goes to its window; the ones that
// finished while you were elsewhere first) and a new one on it, then its plan's usage: 5-hour session, week and
// per-model week (topbar/scripts/claude-usage, Claude Code's own sign-in; ClaudeUsage.qml). The bar's claude icon
// opens it for the first account (the default, ~/.claude), claude2's for the second (Claude2Menu.qml: accountIndex 1;
// claude-accounts, #3038). Claude writes' settings (⌘⇧C) live in the launcher (ClaudeWriteLevels.qml): the button at
// the bottom opens them.
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 10

    property int accountIndex: 0      // its place in Claude.accounts
    property var usage: []            // claude-usage --all: [{ account, plan, windows: [{ key, percent, resetsAt, model }], fetchedAt, error }]
    property bool loaded: false
    signal close()

    // Its account; before the accounts are read, the default's stands for it
    readonly property var account: Claude.accounts[accountIndex] || { name: "", default: true }
    readonly property bool several: Claude.accounts.length > 1
    readonly property var sessions: Claude.sessions.filter(s => Claude.accountIndex(s) === m.accountIndex)
    // Its usage by name; the first (the default's) until the accounts are read
    readonly property var accountUsage: account.name ? usage.find(u => u.account === account.name) || null
                                                     : accountIndex === 0 ? usage[0] || null : null

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

    // The plan; with more than one account, which one this is first
    MenuHeader {
        width: parent.width
        title: "Claude"
        subtitle: [m.several ? m.account.name : "", m.accountUsage && m.accountUsage.plan || ""].filter(t => t).join(" · ")
    }

    MenuSection { title: "Sessions" }
    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: m.sessions
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
        onClicked: { Claude.newSession(m.account.default ? "" : m.account.name); m.close() }
    }
    ClaudeBarToggle {}

    ClaudeUsage {
        width: m.width
        usage: m.accountUsage
        loaded: m.loaded
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
