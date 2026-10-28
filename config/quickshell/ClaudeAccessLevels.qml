import QtQuick
import Quickshell
import Quickshell.Io

// The launcher's Settings › Claude › Access: what Claude Code may use of this desktop through Nightdrive's MCP server
// (config/mcp, plan: Dashboard #1761). At the top the server itself, on or off (`nightdrive mcp install|remove`); then
// the level, Strict, Normal or Open, which sets every row; then a row per area, each Off, Reads or Reads and changes,
// and the actions with consequences (sending, devices, installing), which always ask on screen as well. An app's area
// shows only while the app is installed. An area that is off isn't there for Claude at all.
// config/mcp/access.py owns ~/.config/nightdrive/claude-access.json: this only runs `nightdrive mcp access …`, and
// reads back what applies (`nightdrive mcp access`). Welcome to Nightdrive asks for the level once (config/welcome).
Item {
    id: w
    property var launcher: null

    readonly property string nd: Quickshell.env("HOME") + "/.local/bin/nightdrive"
    readonly property var levels: ["claudeaccess", "claudeaccessarea"]
    readonly property var titles: ({ claudeaccess: "Settings › Claude › Access",
                                     claudeaccessarea: "Access › " + (names[area] || area) })
    readonly property var parents: ({ claudeaccess: "settings", claudeaccessarea: "claudeaccess" })

    readonly property var presets: [
        ["strict", "Strict", "shield", "Only Nightdrive's docs and status: Claude tells you how things work"],
        ["normal", "Normal", "shield-half", "Reads, and makes changes you can undo; nothing with consequences"],
        ["open", "Open", "shield-check", "Also sends, installs and works devices, each time asking you on screen"]]
    readonly property var values: [
        ["off", "Off", "eye-off", "Claude doesn't see it at all"],
        ["read", "Reads", "eye", "Searches and reads, changes nothing"],
        ["change", "Reads and changes", "pencil", "Each change comes with a notification that undoes it"]]
    readonly property var glyphs: ({ nightdrive: "book-open", mail: "mail", contacts: "contact", calendar: "calendar",
                                     tasks: "list-checks", notes: "notebook-pen", deck: "disc-3", ferry: "smartphone",
                                     "home-assistant": "house", notifications: "bell-ring", appearance: "palette",
                                     "sound-display": "volume-2", "apps-files": "folder", software: "package" })

    // access.py's summary: { chosen, level, act, areas: {id: value}, names, apps, changed, actChanged, problem? }
    property var now: null
    readonly property var names: now ? now.names : ({})
    property string area: ""                 // the row Access › Area is about
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
    function valueName(id) { const v = values.find(v => v[0] === id); return v ? v[1] : id }
    readonly property bool serverOn: !!(server && server.server)

    // The rows of the areas: an app's only while it is installed, plugins' own areas (not in names) by their id
    function areaRows() {
        if (!now) return []
        return Object.keys(now.areas)
            .filter(a => now.apps.indexOf(a) < 0 || Plugins.has(a))
            .map(a => ({ kind: "caarea", value: a, name: names[a] || a.charAt(0).toUpperCase() + a.slice(1).replace(/-/g, " "),
                         glyph: glyphs[a] || "puzzle", summary: valueName(now.areas[a]),
                         sub: now.changed.indexOf(a) >= 0 ? "Your own, not the level's" : undefined }))
    }

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "caserver" || cur.kind === "caact") return "Enter: on/off"
        if (cur.kind === "capreset") return now && (now.changed.length || now.actChanged) ? "Enter: use it (your own rows go back to it)" : "Enter: use it"
        if (cur.kind === "caarea") return "Enter: choose"
        if (cur.kind === "cavalue") return "Enter: choose"
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level === "claudeaccess") { reread(); statusProc.running = true }
        if (level === "claudeaccessarea" && now) Qt.callLater(() => launcher.selectWhere(r => r.value === now.areas[area]))
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
            const changed = now.changed.length + (now.actChanged ? 1 : 0)
            const presetRows = presets.map(p => ({ kind: "capreset", value: p[0], name: p[1], sub: p[3],
                glyph: p[0] === now.level ? "check" : p[2],
                summary: p[0] !== now.level ? (p[0] === "normal" ? "default" : undefined)
                       : changed ? "current, " + changed + " of your own" : "current" }))
            const act = { kind: "caact", name: "Actions with consequences", glyph: "zap", switchOn: now.act,
                          sub: "Sending, devices, installing: in the areas that read and change, each one asks you on screen" }
            return top.concat([{ kind: "header", name: "Level" }], presetRows, [{ kind: "header", name: "Areas" }], areaRows(), [act],
                              now.problem ? [{ kind: "note", name: now.problem }] : [])
        }
        if (level === "claudeaccessarea") {
            if (!now) return l.hint("Loading…")
            const cur = now.areas[area]
            return values.map(v => ({ kind: "cavalue", value: v[0], name: v[1], sub: v[3], glyph: v[0] === cur ? "check" : v[2],
                                      summary: v[0] === cur ? "current" : undefined }))
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
        if (it.kind === "caact") {
            l.keepSelection()
            now = Object.assign({}, now, { act: !now.act })
            set(["act", now.act ? "on" : "off"])
            return true
        }
        if (it.kind === "caarea") {
            area = it.value
            l.go("claudeaccessarea")
            return true
        }
        if (it.kind === "cavalue") {
            const areas = Object.assign({}, now.areas); areas[area] = it.value
            now = Object.assign({}, now, { areas: areas })
            set(["area", area, it.value])
            l.back()   // to the area's row
            return true
        }
        return false
    }
}
