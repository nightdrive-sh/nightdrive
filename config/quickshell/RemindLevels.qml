import QtQuick
import Quickshell

// The launcher's Tools › Remind (Dashboard #3118): a quick reminder, a banner in N minutes (RemindToast.qml). Pick the minutes (or
// type them: 25, 90m, 1h30m, or a time of day: 22:45, 22.45), then type the message and Enter. The waiting ones are listed under the choices; Enter twice
// (or ⌘⌫ twice) on one cancels it. hypr/scripts/remind does the work (a systemd timer, kept over a logout in a state
// file); this reads its list. Launcher.qml asks it like its other level files (levels, titles, parents, items,
// activate, footer, entered, deleteSelected).
Item {
    id: r
    property var launcher: null

    readonly property string cmdPath: Quickshell.env("HOME") + "/.config/hypr/scripts/remind"
    readonly property var presets: [5, 10, 15, 30, 60]
    readonly property int maxMinutes: 7 * 24 * 60   // as the script's MAX_MINUTES
    property var pending: []                        // [{ id, at_unix, minutes_left, message }], soonest first
    // The time picked on the way to Remind › Message: { min } (from now, when Enter is pressed) or { hm: "22:45", at }
    property var pick: ({ min: 0 })

    readonly property var levels: ["remind", "remindmsg"]
    readonly property var inputs: ["remindmsg"]     // a text field: ⌘⇧V pastes into it (ClipPicker)
    readonly property var titles: ({ remind: "Tools › Remind", remindmsg: "Remind › " + pickLabel() })
    readonly property var parents: ({ remind: "tools", remindmsg: "remind" })
    // Tools' row (LauncherMenus.qml), with how many wait
    readonly property var toolRow: ({ kind: "nav", name: "Remind", glyph: "alarm-clock", target: "remind",
                                      summary: pending.length ? pending.length + " waiting" : undefined,
                                      extra: "reminder timer alarm notify notification later minutes muistutus" })

    function clock(ms) { return Qt.formatTime(new Date(ms), "HH:mm") }
    function span(m) {
        if (m < 60) return m + " min"
        const h = Math.floor(m / 60), rest = m % 60
        return h + " h" + (rest ? " " + rest + " min" : "")
    }
    function pickAt() { return pick.hm ? pick.at : Date.now() + pick.min * 60000 }
    function pickLabel() { return pick.hm ? "At " + pick.hm : "In " + span(pick.min) }
    // A time of day as the script reads it (remind's clock_time): 22:45 or 22.45 → { hm, at } of its next such moment
    // (tomorrow's once today's has passed); null when not
    function clockTime(text) {
        const m = text.trim().match(/^([01]?\d|2[0-3])[:.]([0-5]\d)$/)
        if (!m) return null
        const d = new Date(); d.setHours(parseInt(m[1]), parseInt(m[2]), 0, 0)
        if (d.getTime() <= Date.now()) d.setDate(d.getDate() + 1)
        return { hm: Qt.formatTime(d, "HH:mm"), at: d.getTime() }
    }
    // The minutes as the script reads them (remind's parse_minutes): 15, 90m, 2h, 1h30m; 0 when not
    function parse(text) {
        const t = text.replace(/\s+/g, "").toLowerCase()
        let n = 0
        if (/^\d+$/.test(t)) n = parseInt(t)
        else {
            const m = t.match(/^(?:(\d+)h)?(?:(\d+)m(?:in)?)?$/)
            if (!m || !(m[1] || m[2])) return 0
            n = parseInt(m[1] || "0") * 60 + parseInt(m[2] || "0")
        }
        return n >= 1 && n <= maxMinutes ? n : 0
    }

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (level === "remindmsg") return "Enter: remind at " + clock(pickAt()) + "  ·  Esc: other time"
        if (cur.kind === "reminder") return "Enter twice or Cmd+Backspace twice: cancel"
        if (level === "remind") return "Enter: then the message  ·  or type the minutes or a time: 25, 1h30m, 22:45"
        return ""
    }
    function opened() { listProc.running = true }
    function entered(level) { if (level === "remind") listProc.running = true }
    function shiftActivate(it) {}

    function items(level, q) {
        if (level === "remindmsg") {
            const msg = launcher.query.trim()   // as typed: q is lower-cased
            return [{ kind: "remindadd", name: msg !== "" ? msg : "Type the message, or Enter for “Reminder”", glyph: "alarm-clock-plus",
                      dimmed: msg === "", summary: "at " + clock(pickAt()) }]
        }
        if (level !== "remind") return []
        const now = Date.now()
        let rows
        if (q !== "") {   // typed minutes or a time of day: one row for them, else a hint
            const c = clockTime(q), n = c ? 0 : parse(q)
            rows = c ? [{ kind: "remindin", hm: c.hm, at: c.at, name: "At " + c.hm, glyph: "alarm-clock",
                          summary: "in " + span(Math.max(1, Math.round((c.at - now) / 60000))) }]
                 : n ? [{ kind: "remindin", min: n, name: "In " + span(n), glyph: "timer", summary: "at " + clock(now + n * 60000) }]
                 : launcher.hint("Minutes up to a week (25, 90m, 1h30m) or a time of day (22:45)")
        } else {
            rows = [{ kind: "header", name: "Remind in" }].concat(presets.map(m => ({
                kind: "remindin", min: m, name: span(m), glyph: "timer", summary: "at " + clock(now + m * 60000) })))
        }
        if (!pending.length) return q !== "" ? rows : rows.concat([{ kind: "note", name: "A banner then, with a sound, until you dismiss it. It waits over a logout or a restart." }])
        return rows.concat([{ kind: "header", name: "Waiting" }], pending.map(p => ({
            kind: "reminder", id: p.id, name: p.message, glyph: "alarm-clock", armKey: "remind:" + p.id,
            summary: "at " + clock(p.at_unix * 1000) + " · in " + span(Math.max(1, p.minutes_left)) })))
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "remindin") { pick = it.hm ? { hm: it.hm, at: it.at } : { min: it.min }; l.go("remindmsg"); return true }
        if (it.kind === "remindadd") {
            l.open = false
            // Through bash for its error message on stdout (Sh reads only that)
            addProc.command = ["bash", "-c", 'exec "$0" "$@" 2>&1', cmdPath, "add", pick.hm || String(pick.min), "--json", "--"]
                .concat(l.query.trim() !== "" ? [l.query.trim()] : [])
            addProc.running = true
            return true
        }
        if (it.kind === "reminder") { cancel(it); return true }
        return false
    }
    // ⌘⌫ (IPC deleteSelected) or Delete on a waiting one with nothing typed: the same as Enter on it
    function deleteSelected() {
        const l = launcher
        if (l.level !== "remind" || l.query !== "") return false
        const it = l.results[l.selIndex]
        if (!it || it.kind !== "reminder") { l.shakeNow(); return true }
        cancel(it)
        return true
    }
    function cancel(it) {
        if (!arm(it.armKey)) return
        pending = pending.filter(p => p.id !== it.id)   // gone at once; the list is read again after
        launcher.keepSelection()
        cancelProc.command = [cmdPath, "cancel", it.id]
        cancelProc.running = true
    }
    function arm(key) {
        if (launcher.armed !== key) { launcher.armed = key; disarmTimer.restart(); return false }
        launcher.armed = ""
        return true
    }
    Timer { id: disarmTimer; interval: 4000; onTriggered: if (r.launcher) r.launcher.armed = "" }

    Sh {
        id: listProc
        command: [r.cmdPath, "list", "--json"]
        onResult: text => { try { r.pending = JSON.parse(text).reminders || [] } catch (e) { r.pending = [] } }
    }
    // The timer didn't start (no systemd user session): said in a notification, as the launcher is closed by then
    Sh {
        id: addProc
        onResult: text => {
            try { JSON.parse(text); listProc.running = true }
            catch (e) { Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Remind", "Reminder not set", text.trim() || "remind failed"]) }
        }
    }
    Sh { id: cancelProc; onResult: listProc.running = true }
}
