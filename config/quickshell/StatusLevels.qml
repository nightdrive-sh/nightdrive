import QtQuick
import Quickshell
import qs.kit

// The launcher's System › Status: the top bar's SystemMenu and ClaudeMenu as launcher rows (topbar/scripts/sysinfo menu
// and claude-usage). Launcher.qml asks it like its other Levels files (levels, titles, parents, items, activate, footer,
// entered), and for liveText: the values change every two seconds, so they are bound in their rows instead of
// rebuilding the list. Read only while the level is open. Split from SystemLevels.qml (#1937).
Item {
    id: s
    property var launcher: null

    readonly property var levels: ["status"]
    readonly property var titles: ({ status: "System › Status" })
    readonly property var parents: ({ status: "system" })
    readonly property string level: launcher ? launcher.level : ""
    readonly property bool shown: launcher !== null && launcher.open && levels.indexOf(level) >= 0

    function row(r) { return { item: r, text: r.kind === "header" || r.kind === "hint" ? "" : r.name, extra: r.extra || "" } }
    function sel() { if (launcher) launcher.keepSelection() }   // a refresh rebuilds the rows: keep the selected one

    function footer(level, query) { return "" }
    function opened() {}
    function entered(level) {
        if (level === "status") { sysProc.running = true; claudeProc.running = true }
    }
    function shiftActivate(item) {}
    function items(level, q) {
        if (level === "status") return { all: statusRows().map(row) }
        return []
    }
    function activate(it) { return false }
    function liveText(key) { return statusLive(key) }

    // ================= Status (topbar/scripts/sysinfo menu and claude-usage; as in SystemMenu and ClaudeMenu) =================
    // The rows only change when their shape does (how many temperatures, processes, usage windows); the values, and the
    // processes' names, are live (liveText), so the list doesn't jump every two seconds
    property var sysData: null       // { cpu, cores, freq, load, memUsed, memTotal, swapUsed, swapTotal, temps: [{ label, c }], top: [{ name, cpu, rss }] }
    property var usage: []           // claude-usage --all: [{ account, plan, windows: [{ key, percent, resetsAt, model }], error }]
    property bool usageLoaded: false
    property string statusShape: ""
    property var statusSnap: ({ d: null, u: [] })   // the data the rows were built from (statusRows reads only this)
    function updateShape() {
        const d = sysData, u = usage
        const shape = JSON.stringify([d ? d.temps.map(t => t.label) : null, d ? d.top.length : 0,
                                      u.map(a => [a.account, a.plan || "", a.error || "", (a.windows || []).map(w => w.key + w.model)]), usageLoaded])
        if (shape !== statusShape) { sel(); statusShape = shape; statusSnap = { d: d, u: u } }
    }
    function gb(b) { return (b / 1073741824).toFixed(1) }
    function mb(b) { return b >= 1073741824 ? gb(b) + " GB" : Math.round(b / 1048576) + " MB" }
    function usageLabel(w) { return w.key === "session" ? "5-hour session" : w.key === "weekly" ? "Weekly" : "Weekly · " + (w.model || "model") }
    function resets(iso) {           // "resets in 1h 28m" (under 24 h) or "resets Wed 01:00"
        const t = new Date(Math.round(new Date(iso) / 60000) * 60000)   // the API's time jitters: 21:59:59.9 is 22:00
        if (isNaN(t)) return ""
        const d = Math.round((t - new Date()) / 1000)
        if (d <= 0) return "resetting now"
        if (d < 86400) { const h = Math.floor(d / 3600), mi = Math.floor(d % 3600 / 60); return "resets in " + (h > 0 ? h + "h " : "") + mi + "m" }
        return "resets " + Regional.dayName(t.getDay(), true) + " " + Regional.format(t, "time")   // the region's time: 1:00 AM in the US
    }
    function runsOut(iso) {          // "runs out in 5h" or "runs out Tue", as in ClaudeUsage.qml (claude-forecast)
        const t = new Date(iso)
        if (!iso || isNaN(t)) return ""
        const d = Math.round((t - new Date()) / 1000)
        return "runs out " + (d < 86400 ? "in " + Math.max(1, Math.round(d / 3600)) + "h" : Regional.dayName(t.getDay(), true))
    }
    function statusLive(key) {
        const d = sysData
        const [k, i] = key.split(":")
        if (k === "cpu") return d ? d.cpu + "%  ·  load " + d.load.join("  ") : ""
        if (k === "mem") return d ? gb(d.memUsed) + " / " + gb(d.memTotal) + " GB" + (d.swapUsed > 0 ? "  ·  swap " + mb(d.swapUsed) : "") : ""
        if (k === "temp") return d && d.temps[i] ? d.temps[i].c + " °C" : ""
        if (k === "procname") return d && d.top[i] ? d.top[i].name : ""
        if (k === "proc") return d && d.top[i] ? d.top[i].cpu.toFixed(1) + "%  ·  " + mb(d.top[i].rss) : ""
        if (k === "usage") {   // usage:ACCOUNT_INDEX:WINDOW_INDEX
            const a = usage[i], w = a && a.windows ? a.windows[key.split(":")[2]] : null
            return w ? [w.percent + "%", resets(w.resetsAt), runsOut(w.runsOut)].filter(t => t).join("  ·  ") : ""
        }
        return undefined   // not one of ours: Launcher.qml asks the next file
    }
    function statusRows() {
        const d = statusSnap.d, u = statusSnap.u   // not sysData / usage: they change every two seconds
        const r = [{ kind: "header", name: "System" }]
        if (!d) r.push({ kind: "hint", name: "Loading…" })
        else {
            r.push({ kind: "stat", name: "CPU", glyph: "cpu", live: "cpu", extra: "processor load" },
                   { kind: "stat", name: "Memory", glyph: "memory-stick", live: "mem", extra: "ram swap" })
            if (d.temps.length > 0) r.push({ kind: "header", name: "Temperatures" })
            d.temps.forEach((t, i) => r.push({ kind: "stat", name: t.label, glyph: "thermometer", live: "temp:" + i, extra: "temperature" }))
            if (d.top.length > 0) r.push({ kind: "header", name: "Top processes (CPU, 1 core = 100 %)" })
            d.top.forEach((p, i) => r.push({ kind: "stat", name: p.name, liveName: "procname:" + i, glyph: "activity", live: "proc:" + i, extra: "process" }))
        }
        // Each Claude Code account's (claude-accounts), named after it when there are more than one, as the Claude menu
        if (usageLoaded && u.length === 0) r.push({ kind: "header", name: "Claude usage" })
        u.forEach((a, ai) => {
            r.push({ kind: "header", name: "Claude usage" + (u.length > 1 ? " · " + a.account : "") + (a.plan ? " · " + a.plan : "") })
            if (usageLoaded && (!a.windows || a.windows.length === 0 || a.error))
                r.push({ kind: "hint", name: a.error ? a.error : "No usage data. Sign in to Claude Code (run claude) first." })
            if (a.windows) a.windows.forEach((w, i) => r.push({ kind: "stat", name: usageLabel(w), glyph: "gauge", live: "usage:" + ai + ":" + i,
                                                               extra: "claude usage limit " + a.account }))
        })
        if (usageLoaded && u.length === 0) r.push({ kind: "hint", name: "No usage data. Sign in to Claude Code (run claude) first." })
        r.push({ kind: "header", name: "More" },
               { kind: "action", name: "Open Claude usage page", glyph: "external-link", cmd: ["xdg-open", "https://claude.ai/settings/usage"], extra: "claude" })
        return r
    }
    Timer { interval: 2000; repeat: true; running: s.shown && s.level === "status"; onTriggered: sysProc.running = true }
    Timer { interval: 5000; repeat: true; running: s.shown && s.level === "status"; onTriggered: claudeProc.running = true }
    Sh {
        id: sysProc
        command: ["bash", "-c", "~/.config/topbar/scripts/sysinfo menu"]
        onResult: text => { try { s.sysData = JSON.parse(text); s.updateShape() } catch (e) {} }
    }
    Sh {
        id: claudeProc
        command: [Quickshell.env("HOME") + "/.config/topbar/scripts/claude-usage", "--all"]
        onResult: text => {
            try { s.usage = JSON.parse(text) || [] } catch (e) { s.usage = [] }
            s.usageLoaded = true
            s.updateShape()
        }
    }
}
