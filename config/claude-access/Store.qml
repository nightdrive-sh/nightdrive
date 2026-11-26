import QtQuick
import Quickshell
import Quickshell.Io

// What applies, and the writes: `nightdrive mcp access` (config/mcp/access.py owns claude-access.json) gives the level
// and every area's rights with their tools and own choices; a choice runs `nightdrive mcp access set AREA RIGHT VALUE`,
// `option AREA ID on|off` (a list's `add|remove ITEM`) or `level L`, one at a time and in order, and then reads back
// what applies (a value put back to the level's follows the level).
// The file is watched too: the launcher, a terminal or Welcome may change it while the window is open.
QtObject {
    id: store
    // this checkout's nightdrive, as the window is this checkout's (a worktree's window writes with its own access.py)
    readonly property string nd: Quickshell.shellDir + "/../../bin/nightdrive"
    property var now: null              // access.py's summary: { level, levels, own, areas: [...], problem?, chosen }
    property bool failed: false
    readonly property var areas: now ? now.areas : []

    function area(id) { return areas.find(a => a.id === id) || null }

    property Process reader: Process {
        property bool again: false      // asked while running: a write may have landed after this read began
        command: [store.nd, "mcp", "access"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { store.now = JSON.parse(text); store.failed = false } catch (e) { store.failed = store.now === null }
            }
        }
        onRunningChanged: if (!running && again) { again = false; running = true }
    }
    function refresh() { if (reader.running) reader.again = true; else reader.running = true }

    property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.config/nightdrive/claude-access.json"
        watchChanges: true; printErrors: false
        onFileChanged: store.refresh()
    }

    // Claude Code's own permissions that let it past these limits (Bash allowed wholesale, bypassPermissions: #1837),
    // from `nightdrive mcp status`, read again when Claude Code's settings change
    property var warnings: []
    property Process status: Process {
        command: [store.nd, "mcp", "status", "--json", "--quick"]
        stdout: StdioCollector {
            onStreamFinished: { try { store.warnings = JSON.parse(text).warnings || [] } catch (e) { store.warnings = [] } }
        }
    }
    property FileView claudeSettings: FileView {
        path: Quickshell.env("HOME") + "/.claude/settings.json"
        watchChanges: true; printErrors: false
        onFileChanged: store.status.running = true
    }

    // One write at a time: a second choice while the first runs isn't lost, nor done out of order
    property var queue: []
    property Process writer: Process {
        onRunningChanged: if (!running) { if (store.queue.length) store.next(); else store.refresh() }
    }
    function run(args) { queue = queue.concat([args]); if (!writer.running) next() }
    function next() {
        writer.command = [nd, "mcp", "access"].concat(queue[0])
        queue = queue.slice(1)
        writer.running = true
    }

    // The choice shows at once; what applies is read back after the write
    function set(areaId, right, value) {
        const copy = JSON.parse(JSON.stringify(now))
        const a = copy.areas.find(x => x.id === areaId)
        if (a && a.rights[right]) { a.rights[right].value = value; now = copy }
        run(["set", areaId, right, value])
    }
    // One of an area's own choices (areas.py's options: Home Assistant's locks), on or off
    function setOption(areaId, option, on) {
        const copy = JSON.parse(JSON.stringify(now))
        const a = copy.areas.find(x => x.id === areaId)
        const o = a && (a.options || []).find(x => x.id === option)
        if (o) { o.value = on; now = copy }
        run(["option", areaId, option, on ? "on" : "off"])
    }
    // An item of a list choice (a window class on the apps Claude sees without asking), put on or taken off
    function setListItem(areaId, option, item, add) {
        const copy = JSON.parse(JSON.stringify(now))
        const a = copy.areas.find(x => x.id === areaId)
        const o = a && (a.options || []).find(x => x.id === option)
        if (o) {
            o.value = o.value.filter(v => v.toLowerCase() !== item.toLowerCase()).concat(add ? [item] : [])
            now = copy
        }
        run(["option", areaId, option, add ? "add" : "remove", item])
    }
    function setLevel(level) {
        now = Object.assign({}, now, { level: level })
        run(["level", level])
    }

    Component.onCompleted: { refresh(); status.running = true }
}
