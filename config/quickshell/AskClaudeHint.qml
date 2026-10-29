import QtQuick
import Quickshell
import Quickshell.Io

// The launcher's footer hint that ⌘⌥Enter sends what was typed to Claude Code (askClaude in Launcher.qml's IpcHandler):
// in the background with only Nightdrive's tools, the answer a notification (hypr/scripts/ask-claude, which opens a
// terminal instead when the MCP server is off), and ⌘⌃Enter in a terminal (hypr/scripts/terminal-or-claude).
// Few know the key, so it shows when the search looks like a request rather than a name: nothing found, three words or
// more ("Soita jazzia Deckistä"), or two words that none of the hits has in its name. A one-word search with hits (an
// app, a fuzzy "fierfox") stays as it was. Only when Claude Code is installed, at the path terminal-or-claude runs.
Item {
    id: h
    property var launcher: null

    readonly property string text: "Cmd+Alt+Enter: Ask Claude  ·  Cmd+Ctrl+Enter: in terminal"
    readonly property string claudeBin: Quickshell.env("HOME") + "/.local/bin/claude"
    property bool installed: false

    // Checked at start and on each opening: installing Claude Code (Welcome) shouldn't need a restart
    Process {
        id: check
        command: ["test", "-x", h.claudeBin]
        onExited: code => h.installed = code === 0
    }
    Component.onCompleted: check.running = true
    Connections {
        target: h.launcher
        function onOpenChanged() { if (h.launcher.open && !check.running) check.running = true }
    }

    function shows(level, query, results) {
        if (!installed || (level !== "root" && level !== "apps")) return false
        const words = launcher.fold(query).split(/\s+/).filter(w => w !== "")
        if (words.length === 0) return false
        // Rows after the hits whatever was typed (Deck's Search Spotify) aren't hits
        const hits = results.filter(r => !r.tail)
        if (hits.length === 0 || words.length >= 3) return true
        // "olohuone kattovalo" finds Kattovalo by its name: no hint; two words found only in search words or fuzzily: a hint
        return words.length === 2 && !hits.some(r => words.some(w => launcher.fold(r.name || "").includes(w)))
    }
}
