pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The Claude Code sessions on this desktop, for the Claude menu and the bar's Claude icon. Which windows run Claude comes
// from topbar/scripts/claude-sessions (every few seconds); what each one is doing comes live from its window's title,
// which Claude Code sets: "✳ topic" when it waits for you, a spinner and the topic while it works.
// A session that finishes (or stops to ask) while you're in another window wants you: a dot in the bar and in the menu,
// gone once you go to its window.
Singleton {
    id: c

    property var found: []             // claude-sessions: [{ address, pid, dir, started }]
    property var wants: ({})           // address → true: finished while you were elsewhere
    property var lastState: ({})       // address → "working" | "waiting", to see the change

    // Hyprland's addresses with or without 0x
    function addr(a) { return String(a).replace(/^0x/, "") }
    readonly property string activeAddr: Hyprland.activeToplevel ? addr(Hyprland.activeToplevel.address) : ""

    // [{ address, dir, project, topic, state, started }] from the windows' titles. Kept apart from wants: the change
    // handler below writes wants, and a binding that read it would be re-evaluated from its own change (a binding loop).
    readonly property var seen: {
        const tops = Hyprland.toplevels.values
        const out = []
        for (const f of found) {
            const t = tops.find(t => addr(t.address) === addr(f.address))
            if (!t) continue
            const title = t.title || ""
            // ✳ = waiting; any other symbol before the topic = Claude's spinner
            const m = title.match(/^(\S)\s+(.*)$/)
            const state = !m || m[1] === "✳" || /[A-Za-z0-9\u00C0-\u024F]/.test(m[1]) ? "waiting" : "working"
            out.push({ address: addr(f.address), dir: f.dir, project: f.dir.replace(/\/+$/, "").split("/").pop() || "/",
                       topic: m && !/[A-Za-z0-9\u00C0-\u024F]/.test(m[1]) ? m[2] : title, state: state, started: f.started })
        }
        return out
    }
    // The same with wants, the ones that want you first, then the newest
    readonly property var sessions: seen.map(s => Object.assign({ wants: !!wants[s.address] }, s))
                                        .sort((a, b) => (b.wants - a.wants) || (b.started - a.started))
    readonly property int wanting: sessions.filter(s => s.wants).length

    // working → waiting while another window is focused: it wants you
    onSeenChanged: {
        const st = {}, w = Object.assign({}, wants)
        let changed = false
        for (const s of seen) {
            st[s.address] = s.state
            if (lastState[s.address] === "working" && s.state === "waiting" && s.address !== activeAddr && !w[s.address]) { w[s.address] = true; changed = true }
            if (s.state === "working" && w[s.address]) { delete w[s.address]; changed = true }   // you answered it elsewhere (ssh, the phone)
        }
        for (const a in w) if (!(a in st)) { delete w[a]; changed = true }   // closed
        lastState = st
        if (changed) wants = w
    }
    onActiveAddrChanged: if (wants[activeAddr]) { const w = Object.assign({}, wants); delete w[activeAddr]; wants = w }

    // Claude Code's Notification hook (hypr/scripts/claude-notify): it asked for you, from a window you're not in
    IpcHandler {
        target: "claude"
        function want(address: string): void {
            const a = c.addr(address)
            if (a === c.activeAddr || c.wants[a]) return
            const w = Object.assign({}, c.wants); w[a] = true; c.wants = w
        }
    }

    function focus(s) {
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:0x' + s.address + '" })'])
    }
    // A new session in ~/Projects, in the terminal chosen in Default apps (hypr/scripts/terminal-or-claude)
    function newSession() { Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/terminal-or-claude"]) }

    Sh {
        id: scan
        command: [Quickshell.env("HOME") + "/.config/topbar/scripts/claude-sessions"]
        onResult: text => {
            let v = []
            try { v = JSON.parse(text) || [] } catch (e) { return }
            if (JSON.stringify(v) !== JSON.stringify(c.found)) c.found = v
        }
    }
    // A new window or a closed one: look again at once; otherwise every few seconds (a claude started in an open terminal)
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "openwindow" || e.name === "closewindow") scan.running = true }
    }
    Timer { interval: 4000; repeat: true; running: true; triggeredOnStart: true; onTriggered: scan.running = true }
}
