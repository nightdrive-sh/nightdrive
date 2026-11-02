import QtQuick
import Quickshell

// The launcher's Settings › Tailscale: the Tailscale plugin's menu (plugins/tailscale/TailscaleMenu.qml) as launcher rows,
// so the launcher doesn't hand over to it. Launcher.qml asks it like its other Levels files (levels, titles, parents,
// items, activate, footer, entered). The machines are read only while the level is open. Split from SystemLevels.qml
// (#1937).
Item {
    id: s
    property var launcher: null

    readonly property var levels: ["tailscale"]
    readonly property var titles: ({ tailscale: "Settings › Tailscale" })
    readonly property var parents: ({ tailscale: "settings" })
    readonly property string level: launcher ? launcher.level : ""
    readonly property bool shown: launcher !== null && launcher.open && levels.indexOf(level) >= 0
    readonly property string copied: launcher ? launcher.rowCopy.copied : ""   // a row just copied says so (RowCopy)

    function row(r) { return { item: r, text: r.kind === "header" || r.kind === "hint" ? "" : r.name, extra: r.extra || "" } }
    function sel() { if (launcher) launcher.keepSelection() }   // a refresh rebuilds the rows: keep the selected one

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "tslogin" || (cur.key === "tailscale" && tsNeedsLogin && !tsRunning)) return "Enter: log in"
        if (cur.kind === "systoggle") return "Enter: on/off"
        if (cur.kind === "tsmachine") return "Enter: copy IP address  ·  Cmd+C: copy"
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level === "tailscale") { tsMessage = ""; tsProc.running = true }
    }
    function shiftActivate(item) {}

    function items(level, q) {
        if (level === "tailscale") return { all: tsRows().map(row) }
        return []
    }

    // Enter on a row. Returns true when the row was one of ours.
    function activate(it) {
        if (it.kind === "systoggle" && it.key === "tailscale") {
            sel()
            if (tsNeedsLogin && !tsRunning) tsLogin()   // tailscale up would only wait for the login
            else {
                tsMessage = ""
                tsToggle.script = tsRunning ? "tailscale down" : "tailscale up"
                tsToggle.running = true
            }
            return true
        }
        if (it.kind === "tslogin") { sel(); tsLogin(); return true }
        if (it.kind === "tsmachine") { launcher.rowCopy.copyText(it.ip); return true }
        return false
    }

    // ================= Tailscale (as in the Tailscale plugin's menu, plugins/tailscale/TailscaleMenu.qml) =================
    property bool tsRunning: LastState.tailscale
    onTsRunningChanged: LastState.tailscale = tsRunning
    property bool tsNeedsLogin: false
    property string selfIp: ""
    property string selfName: ""
    property var peers: []           // [{ host, ip, online, os }]
    property string tsMessage: ""
    function tsRows() {
        const r = [{ kind: "systoggle", key: "tailscale", name: "Tailscale", glyph: tsRunning ? "shield-check" : "shield-off", switchOn: tsRunning }]
        if (tsNeedsLogin && !tsRunning)
            r.push({ kind: "tslogin", name: "Log in", glyph: "log-in", summary: "opens the link in the browser" })
        if (tsMessage !== "") r.push({ kind: "hint", name: tsMessage })
        if (!tsRunning) return r
        if (selfIp !== "") r.push({ kind: "header", name: "This machine" },
                                  { kind: "tsmachine", name: selfName, ip: selfIp, copy: selfIp, glyph: "laptop-minimal-check", summary: copied === selfIp ? "copied" : selfIp })
        for (const online of [true, false]) {
            const list = peers.filter(p => p.online === online)
            if (list.length === 0) continue
            r.push({ kind: "header", name: online ? "Online" : "Offline" })
            for (const p of list)
                r.push({ kind: "tsmachine", name: p.host, ip: p.ip, copy: p.ip, dimmed: !online, extra: p.ip + " " + p.os,
                         glyph: /mac|ios/i.test(p.os) ? "laptop" : /android/i.test(p.os) ? "smartphone" : "server",
                         summary: copied === p.ip ? "copied" : p.ip })
        }
        r.push({ kind: "header", name: "More" })
        r.push({ kind: "action", name: "Admin console", glyph: "external-link", cmd: ["xdg-open", "https://login.tailscale.com/admin/machines"] })
        return r
    }
    Timer { interval: 3000; repeat: true; running: s.shown && s.level === "tailscale"; onTriggered: tsProc.running = true }
    Sh {
        id: tsProc
        command: ["tailscale", "status", "--json"]
        onResult: text => {
            let j
            try { j = JSON.parse(text) } catch (e) { s.sel(); s.tsRunning = false; s.peers = []; return }
            const arr = []
            for (const k in (j.Peer || {})) {
                const p = j.Peer[k]
                arr.push({ host: p.HostName, ip: (p.TailscaleIPs || [""])[0], online: !!p.Online, os: p.OS })
            }
            arr.sort((a, b) => (b.online - a.online) || a.host.localeCompare(b.host))
            const running = j.BackendState === "Running"
            const needsLogin = j.BackendState === "NeedsLogin"
            const ip = ((j.Self || {}).TailscaleIPs || [""])[0]
            if (running === s.tsRunning && needsLogin === s.tsNeedsLogin && ip === s.selfIp
                && JSON.stringify(arr) === JSON.stringify(s.peers)) return
            s.sel()
            s.tsRunning = running
            s.tsNeedsLogin = needsLogin
            if (running && s.tsMessage === s.tsWaiting) s.tsMessage = ""
            s.selfIp = ip
            s.selfName = (j.Self || {}).HostName || ""
            s.peers = arr
        }
    }
    // Logging in: the plugin's ./login starts it and opens the link in the browser; the rows follow tailscale status
    // until it's done
    readonly property string tsWaiting: "Finish logging in in the browser"
    function tsLogin() {
        const menu = TopBar.plugin.menus.tailscale || ""
        if (menu === "") { tsMessage = "Turn the Tailscale plugin on to log in here, or run tailscale up in a terminal"; return }
        tsMessage = ""
        tsToggle.script = "'" + menu.replace(/[^/]*$/, "login") + "'"
        tsToggle.loggingIn = true
        tsToggle.running = true
    }
    Sh {
        id: tsToggle
        property bool loggingIn: false
        onResult: text => {
            s.sel()
            if (tsToggle.loggingIn && tsToggle.exitCode === 0) s.tsMessage = s.tsWaiting
            tsToggle.loggingIn = false
            if (tsToggle.exitCode !== 0)
                s.tsMessage = /denied|operator/i.test(text) ? "Permission denied. Run once: sudo tailscale set --operator=$USER"
                                                            : text.trim().split("\n").pop()
            tsProc.running = true
        }
    }
}
