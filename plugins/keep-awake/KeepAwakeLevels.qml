import QtQuick
import Quickshell
import qs

// Keep Awake's part of the launcher (plugin-parts lists it while the plugin is on): Tools › Keep Awake, the same as its
// top bar menu (KeepAwakeMenu.qml): the switch, and how long. bin/keep-awake does the work; this reads its status.
// Launcher.qml asks it like its own level files (levels, titles, parents, items, activate, footer, entered).
Item {
    id: k
    property var launcher: null               // Launcher.qml sets it once the file is loaded

    readonly property string cmdPath: Qt.resolvedUrl("bin/keep-awake").toString().replace(/^file:\/\//, "")
    readonly property var choices: [{ min: 0, label: "Until turned off" }, { min: 60, label: "1 hour" },
                                    { min: 120, label: "2 hours" }, { min: 240, label: "4 hours" },
                                    { min: 480, label: "8 hours" }]
    property bool on: false
    property int until: 0                     // epoch seconds; 0 = until turned off
    property int minutes: 0                   // the choice it was turned on with

    function clock(ms) { return Qt.formatTime(new Date(ms), "HH:mm") }
    readonly property string state: !on ? "off" : until ? "until " + clock(until * 1000) : "on"

    // A row in Tools (Launcher.qml's statics.tools), found by the root search too
    readonly property var toolItems: [{ kind: "nav", name: "Keep Awake", glyph: "coffee", target: "keepawake", summary: state,
                                        extra: "caffeine amphetamine prevent sleep screensaver lock idle awake" }]
    readonly property var levels: ["keepawake"]
    readonly property var titles: ({ keepawake: "Tools › Keep Awake" })
    readonly property var parents: ({ keepawake: "tools" })

    function footer(level, query) { return "Enter: keep awake for that long" }
    function opened() { status.running = true }
    function entered(level) { status.running = true }
    function shiftActivate(it) {}

    function items(level, q) {
        if (level !== "keepawake") return []
        const now = Date.now()
        return [{ kind: "awakeswitch", name: "Keep Awake", glyph: "coffee", switchOn: on,
                  summary: on && until ? "until " + clock(until * 1000) : undefined },
                { kind: "header", name: "How long" }]
            .concat(choices.map(c => {
                const cur = on && minutes === c.min
                return { kind: "awake", min: c.min, name: c.label, glyph: c.min ? "timer" : "infinity",
                         summary: c.min ? "until " + clock(cur ? until * 1000 : now + c.min * 60000) : undefined,
                         trailGlyph: cur ? "check" : undefined }
            }))
            .concat([{ kind: "note", name: "While on: no screensaver or lock, and the lid doesn't put it to sleep." }])
    }

    function activate(it) {
        if (it.kind === "awakeswitch") { launcher.keepSelection(); run([on ? "off" : "on"]); return true }
        if (it.kind === "awake") { launcher.keepSelection(); run(["on", String(it.min)]); return true }
        return false
    }
    function run(args) { cmd.command = [cmdPath].concat(args); cmd.running = true }

    Sh {
        id: status
        command: [k.cmdPath, "status"]
        onResult: text => {
            try { const j = JSON.parse(text); k.on = j.on; k.until = j.until; k.minutes = j.minutes } catch (e) { k.on = false }
        }
    }
    Sh { id: cmd; onResult: status.running = true }
}
