import QtQuick
import Quickshell
import Quickshell.Io

// Each display's own settings, as hypr/scripts/display has them: resolutions and the saved one (json), the scales that
// keep text sharp as the size they look like (list), the refresh rates at its resolution (rates). Read again when the
// screens change (Screens: a reload, a display plugged in), and set with the same commands as Settings › Display. A new
// resolution asks to be kept (--keep: Nightdrive's card, back in 20 s unless kept), as one can leave a screen unreadable.
Item {
    id: root
    property var info: ({})          // output -> { resolution, refresh, scale, resolutions, savedMode, scales: [{ value, size }], rates: { chosen, hz } }
    property string error: ""
    signal applied()                 // a change ran: the arrangement may have moved (display fits it)

    readonly property string cmd: Quickshell.env("HOME") + "/.config/hypr/scripts/display"
    function of(id) { return info[id] || null }
    function refresh() { if (!reader.running) reader.running = true }

    function setScale(id, v) { run([cmd, "scale", id, String(v)]) }
    function setMode(id, m) { run(m === "auto" ? [cmd, "mode", id, "auto"] : [cmd, "mode", id, m, "--keep"]) }
    function setRate(id, hz) { run([cmd, "rate", id, String(hz)]) }
    // A resolution's --keep waits for the card's answer, so the window doesn't wait for it: it reads again once the
    // new mode is on trial (a moment), and again on every change of the screens after
    function run(argv) {
        error = ""
        if (argv.indexOf("--keep") >= 0) { Quickshell.execDetached(argv); later.restart(); return }
        setter.command = argv
        setter.running = true
    }
    Timer { id: later; interval: 1500; onTriggered: { root.refresh(); root.applied() } }

    Process {
        id: setter
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") root.error = text.trim() }
        onRunningChanged: if (!running) { root.refresh(); root.applied() }
    }

    // json, list and rates in one go, as three sections
    Process {
        id: reader
        command: ["bash", "-c", '"$0" json; echo "@@"; "$0" list; echo "@@"; "$0" rates', root.cmd]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("@@\n")
                if (parts.length < 3) return
                const out = {}
                try {
                    for (const d of JSON.parse(parts[0]))
                        out[d.name] = { resolution: d.resolution, refresh: d.refresh, scale: d.scale, savedMode: d.saved_mode,
                                        resolutions: d.resolutions.slice().sort((a, b) => {
                                            const [aw, ah] = a.split("x").map(Number), [bw, bh] = b.split("x").map(Number)
                                            return bw * bh - aw * ah || bw - aw }),
                                        scales: [], rates: { chosen: "auto", hz: [] } }
                } catch (e) { return }
                for (const f of parts[1].split("\n").map(l => l.split("\t")).filter(f => f.length >= 3 && out[f[0]]))
                    out[f[0]].scales = f.slice(3).map(o => { const [v, size] = o.split(":"); return { value: parseFloat(v), size: size.replace("×", " × ") } })
                for (const f of parts[2].split("\n").map(l => l.split("\t")).filter(f => f.length >= 3 && out[f[0]]))
                    out[f[0]].rates = { chosen: f[2] === "auto" ? "auto" : parseFloat(f[2]), hz: f.slice(3).map(parseFloat) }
                root.info = out
            }
        }
    }
    Component.onCompleted: refresh()
}
