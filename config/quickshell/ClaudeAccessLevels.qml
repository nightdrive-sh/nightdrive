import QtQuick
import Quickshell
import Quickshell.Io

// The launcher's Settings › Claude › Access: what Claude Code may use of this desktop through Nightdrive's MCP server
// (config/mcp, plan: Dashboard #1761). At the top the server itself, on or off (`nightdrive mcp install|remove`); then
// the level, Strict, Normal or Open, which sets every area; then a row that opens the Access window
// (config/claude-access, #1831), where each area's Read, Modify and Delete are Allow, Ask or No: a grid of choices is
// too much for the launcher's rows.
// config/mcp/access.py owns ~/.config/nightdrive/claude-access.json: this only runs `nightdrive mcp access …`, and
// reads back what applies (`nightdrive mcp access`). Welcome to Nightdrive asks once (config/welcome).
Item {
    id: w
    property var launcher: null

    readonly property string nd: Quickshell.env("HOME") + "/.local/bin/nightdrive"
    readonly property var levels: ["claudeaccess"]
    readonly property var titles: ({ claudeaccess: "Settings › Claude › Access" })
    readonly property var parents: ({ claudeaccess: "settings" })

    readonly property var presets: [
        ["strict", "Strict", "shield", "Only Nightdrive's docs and status: Claude tells you how things work"],
        ["normal", "Normal", "shield-half", "Reading mail, people, calendar, notes, notifications and the screen asks; deleting asks"],
        ["open", "Open", "shield-check", "Everything allowed; sending, devices and installing still ask on screen"]]

    // access.py's summary: { chosen, level, own, areas: [...], problem? }
    property var now: null
    // `nightdrive mcp status --json --quick`: { claude, server, allowed, … }; null until read
    property var server: null
    property bool serverBusy: false          // install or remove still running
    property string serverError: ""          // what it said when it didn't do it
    property var serverAsked: null           // after install (true) or remove (false): its last line, kept if nothing changed
    // The level's name on Settings' own row, read from the file itself: no command on every open of Settings
    property string fileLevel: ""
    FileView {
        path: Quickshell.env("HOME") + "/.config/nightdrive/claude-access.json"; watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { w.fileLevel = JSON.parse(text()).level || "" } catch (e) { w.fileLevel = "" } }
        onLoadFailed: w.fileLevel = ""
    }
    // Without a file the server uses Normal (access.py's UNCHOSEN)
    readonly property string summary: presetName(fileLevel || "normal")

    property bool failed: false              // `nightdrive mcp access` gave no summary
    Sh {
        id: accessProc
        property bool again: false           // asked while running: a write may have landed after this read began
        command: [w.nd, "mcp", "access"]
        onResult: text => {
            // the rows are rebuilt with the values read back: the selection stays on its row
            if (w.launcher && w.levels.indexOf(w.launcher.level) >= 0) w.launcher.keepSelection()
            try { w.now = JSON.parse(text); w.failed = false } catch (e) { w.failed = w.now === null }
        }
        // on the exit, not the output's end: before it, running = true does nothing
        onRunningChanged: if (!running && again) { again = false; running = true }
    }
    function reread() { if (accessProc.running) accessProc.again = true; else accessProc.running = true }
    Sh {
        id: statusProc
        command: [w.nd, "mcp", "status", "--json", "--quick"]
        onResult: text => {
            if (w.launcher && w.levels.indexOf(w.launcher.level) >= 0) w.launcher.keepSelection()
            try { w.server = JSON.parse(text) } catch (e) { w.server = {} }   // shown as without Claude Code
            // e.g. remove when the server was added by hand: it says so, and the switch stays as it was
            if (w.serverAsked) w.serverError = w.serverOn === w.serverAsked.on ? "" : w.serverAsked.said
            w.serverAsked = null
            w.serverBusy = false
        }
    }
    Sh {
        id: serverProc
        property bool on: false
        script: '"$HOME/.local/bin/nightdrive" mcp ' + (on ? "install" : "remove") + " --yes"
        onResult: text => {
            w.serverAsked = { on: serverProc.on, said: text.trim().split("\n").pop() || "It didn't change" }
            statusProc.running = true
        }
    }
    // A change shows at once, and what applies is read back after it (a row set to the level's value follows it again)
    // One write at a time, in order: a second press while the first runs isn't lost
    property var queue: []
    Sh {
        id: setProc
        onRunningChanged: if (!running) { if (w.queue.length) w.next(); else w.reread() }
    }
    function set(args) { queue = queue.concat([args]); if (!setProc.running) next() }
    function next() {
        setProc.command = [nd, "mcp", "access"].concat(queue[0])
        queue = queue.slice(1)
        setProc.running = true
    }

    function presetName(id) { const p = presets.find(p => p[0] === id); return p ? p[1] : id }
    readonly property bool serverOn: !!(server && server.server)

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "caserver") return "Enter: on/off"
        if (cur.kind === "capreset") return now && now.own ? "Enter: use it (your own choices go back to it)" : "Enter: use it"
        if (cur.kind === "cawindow") return "Enter: open"
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level === "claudeaccess") { reread(); statusProc.running = true }
    }

    function items(level, q) {
        const l = launcher
        if (level === "claudeaccess") {
            if (failed) return l.hint("Access can't be read: see `nightdrive mcp access` in a terminal")
            if (!now || !server) return l.hint("Loading…")
            const top = !server.claude
                ? [{ kind: "note", name: "Claude Code isn't installed. These apply once it is, and Nightdrive's tools are on" }]
                : [{ kind: "caserver", name: "Nightdrive's tools in Claude Code", glyph: "sparkles", switchOn: serverOn, switchBusy: serverBusy,
                     sub: serverBusy ? (serverOn ? "Turning off…" : "Turning on…")
                        : serverOn ? "Claude Code can use your desktop as allowed below" : "Off: Claude Code doesn't see your desktop" }]
                  .concat(serverError ? [{ kind: "note", name: serverError }] : [])
                  // Claude Code's own permissions that let it past these limits (#1837)
                  .concat((server.warnings || []).map(t => ({ kind: "note", name: t })))
            const changed = now.own
            const presetRows = presets.map(p => ({ kind: "capreset", value: p[0], name: p[1], sub: p[3],
                glyph: p[0] === now.level ? "check" : p[2],
                summary: p[0] !== now.level ? (p[0] === "normal" ? "default" : undefined)
                       : changed ? "current, " + changed + " of your own" : "current" }))
            const open = { kind: "cawindow", name: "Areas: what Claude may read, modify and delete…", glyph: "app-window",
                           sub: "Each area Allow, Ask or No, in plain words, in a window of its own" }
            const only = { kind: "note", name: "These cover only Nightdrive's tools: what Claude Code may do with its own (commands, files) is set in Claude Code" }
            return top.concat([{ kind: "header", name: "Level" }], presetRows, [{ kind: "header", name: "Areas" }], [open],
                              now.problem ? [{ kind: "note", name: now.problem }] : [], [only])
        }
        return []
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "caserver") {
            if (serverBusy) { l.shakeNow(); return true }
            l.keepSelection()
            serverBusy = true; serverError = ""
            // The switch is the user's yes: install shows its change and asks only in a terminal
            serverProc.on = !serverOn
            serverProc.running = true
            return true
        }
        if (it.kind === "capreset") {
            l.keepSelection()
            now = Object.assign({}, now, { level: it.value })   // the check moves now; the rows follow when read back
            set(["level", it.value])
            return true
        }
        if (it.kind === "cawindow") {
            Quickshell.execDetached([nd, "mcp", "access", "open"])
            l.open = false
            return true
        }
        return false
    }
}
