import QtQuick
import Quickshell

// The launcher's Tools › Schedule (Dashboard #3152, part 5 of #3121): a command, or a message to Claude, run once later.
// Pick when (minutes, a time of day, wake or login; or type it: 25, 1h30m, 14:45), then type what and Enter. How the
// line is read shows on its row before Enter (Run or Ask Claude), and the row under it is the other reading. The
// waiting ones are listed under the choices: Enter twice (or ⌘⌫ twice) cancels one, Ctrl+Enter runs it now (a missed
// one, say). hypr/scripts/schedule does the work and the reading: this asks it (`add --dry-run --json`, `list --json`)
// rather than keeping a second copy of its rules here. Launcher.qml asks it like its other level files (levels,
// titles, parents, items, activate, footer, entered, deleteSelected, ctrlActivate).
Item {
    id: r
    property var launcher: null

    readonly property string cmdPath: Quickshell.env("HOME") + "/.config/hypr/scripts/schedule"
    readonly property var presets: [15, 30, 60]
    property var pending: []        // schedule list --json's commands: by time, then wake and login
    // When, as picked on the way to Schedule › What: { when: "15" | "14:45" | "wake" | "login", label }
    property var pick: ({ when: "15", label: "In 15 min" })
    // The script's reading of what is typed: { level, query, row } with row its --dry-run --json answer ({error} or a
    // row: when, clock, minutes_left, kind, command). A row is shown only for the query it was asked about.
    property var reading: ({ level: "", query: "", row: null })

    readonly property var levels: ["schedule", "schedulewhat"]
    readonly property var inputs: ["schedulewhat"]  // a text field: ⌘⇧V pastes into it (ClipPicker)
    readonly property var titles: ({ schedule: "Tools › Schedule", schedulewhat: "Schedule › " + pick.label })
    readonly property var parents: ({ schedule: "tools", schedulewhat: "schedule" })
    // Tools' row (LauncherMenus.qml), with how many wait
    readonly property var toolRow: ({ kind: "nav", name: "Schedule", glyph: "calendar-clock", target: "schedule",
                                      summary: pending.length ? pending.length + " waiting" : undefined,
                                      extra: "later run command timer at wake login ask claude message ajasta" })

    function clock(ms) { return Qt.formatTime(new Date(ms), "HH:mm") }
    function span(m) {
        if (m < 60) return m + " min"
        const h = Math.floor(m / 60), rest = m % 60
        return h + " h" + (rest ? " " + rest + " min" : "")
    }
    function whenLabel(row) {
        return row.when === "wake" ? "On wake" : row.when === "login" ? "At login" : "At " + row.clock
    }
    // What a kind is called on its row: the same words as the script's list (Run, Ask Claude)
    function kindName(k) { return k === "claude" ? "Ask Claude" : "Run" }
    function kindGlyph(k) { return k === "claude" ? "bot" : "terminal" }
    function fresh(level, q) { return reading.level === level && reading.query === q ? reading.row : null }

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "scheduled") return "Enter twice or Cmd+Backspace twice: cancel  ·  Ctrl+Enter: run now"
        if (level === "schedulewhat") return cur.kind === "scheduleadd" ? "Enter: " + kindName(cur.as) + " " + pick.label.toLowerCase()
                                             + "  ·  ↑↓: Run or Ask Claude  ·  Esc: other time" : "Esc: other time"
        if (level === "schedule") return "Enter: then what to run  ·  or type the minutes or a time: 25, 1h30m, 14:45"
        return ""
    }
    function opened() { listProc.running = true }
    function entered(level) {
        if (level === "schedule") listProc.running = true
        check()
    }
    function shiftActivate(it) {}

    function items(level, q) {
        if (level === "schedulewhat") return whatRows(launcher.query.trim())   // as typed: q is lower-cased
        if (level !== "schedule") return []
        const now = Date.now()
        let rows
        if (q !== "") {   // typed: the script says what time that is, or why not
            const row = fresh(level, launcher.query.trim())
            rows = !row ? launcher.hint("…")
                 : row.error ? launcher.hint("Minutes up to a week (25, 90m, 1h30m), a time of day (14:45), wake or login")
                 : [{ kind: "schedulewhen", when: launcher.query.trim(), name: whenLabel(row),
                      glyph: row.clock ? "calendar-clock" : row.when === "wake" ? "sunrise" : "log-in",
                      summary: row.clock ? "in " + span(Math.max(1, row.minutes_left)) : undefined }]
        } else {
            rows = [{ kind: "header", name: "Run" }].concat(presets.map(m => ({
                kind: "schedulewhen", when: String(m), name: "In " + span(m), glyph: "timer", summary: "at " + clock(now + m * 60000) })),
                [{ kind: "schedulewhen", when: "wake", name: "On wake", glyph: "sunrise", summary: "the first unlock after sleep" },
                 { kind: "schedulewhen", when: "login", name: "At login", glyph: "log-in", summary: "the next login" }])
        }
        // Two notes, not one: a note row is a single line and would be cut off at the launcher's width
        if (!pending.length) return q !== "" ? rows : rows.concat([
            { kind: "note", name: "A command runs as typed; other text goes to Claude as a message." },
            { kind: "note", name: "A notification then says what ran and how it went." }])
        return rows.concat([{ kind: "header", name: "Waiting" }], pending.map(waitingRow))
    }
    function whatRows(line) {
        if (line === "") return [{ kind: "hint", name: "Type a command, or a message to Claude" }]
        const row = fresh("schedulewhat", line)
        if (row && row.error) return launcher.hint(row.error)
        const read = row ? row.kind : ""   // "" until the script has read it: Enter then lets it decide
        const first = { kind: "scheduleadd", as: read, name: line, glyph: kindGlyph(read),
                        summary: read ? kindName(read) : "…" }
        if (!read) return [first]
        const other = read === "claude" ? "run" : "claude"
        return [first, { kind: "scheduleadd", as: other, name: line, glyph: kindGlyph(other), dimmed: true,
                         summary: kindName(other) + " instead" }]
    }
    function waitingRow(p) {
        const when = p.when === "wake" ? "on wake" : p.when === "login" ? "at login"
                   : p.state === "missed" ? "missed " + p.clock + " · Ctrl+Enter: run"
                   : p.state === "unlock" ? "waits for the unlock"
                   : p.state === "due" ? "running"
                   : "at " + p.clock + " · in " + span(Math.max(1, p.minutes_left))
        return { kind: "scheduled", id: p.id, name: p.command, glyph: kindGlyph(p.kind), armKey: "schedule:" + p.id,
                 summary: (p.kind === "claude" ? "Ask Claude" + (p.to ? " → " + p.to : "") + " · " : "") + when
                          + (p.by === "claude" ? " · by Claude" : "") }   // added by a session (schedule_add, #3151)
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "schedulewhen") {
            pick = { when: it.when, label: it.name }
            l.go("schedulewhat")
            return true
        }
        if (it.kind === "scheduleadd") {
            l.open = false
            // Through bash for its error message on stdout (Sh reads only that). A reading picked on its row is said
            // with --run or --claude; before the script has read it, it decides itself.
            addProc.command = ["bash", "-c", 'exec "$0" "$@" 2>&1', cmdPath, "add", "--json"]
                .concat(it.as ? ["--" + it.as] : [], [pick.when, "--", it.name])
            addProc.running = true
            return true
        }
        if (it.kind === "scheduled") { cancel(it); return true }
        return false
    }
    // Ctrl+Enter on a waiting one: it runs now, whatever it waits for (its notification says how it went)
    function ctrlActivate(it) {
        if (!it || it.kind !== "scheduled") return false
        launcher.open = false
        runProc.command = [cmdPath, "run", it.id]
        runProc.running = true
        return true
    }
    // ⌘⌫ (IPC deleteSelected) or Delete on a waiting one with nothing typed: the same as Enter on it
    function deleteSelected() {
        const l = launcher
        if (l.level !== "schedule" || l.query !== "") return false
        const it = l.results[l.selIndex]
        if (!it || it.kind !== "scheduled") { l.shakeNow(); return true }
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

    // The reading follows the typing, a moment after it stops: one python start per pause, not per key
    function check() { checkTimer.restart() }
    Timer { id: checkTimer; interval: 150; onTriggered: r.ask() }
    Connections {
        target: r.launcher
        function onQueryChanged() { if (r.levels.indexOf(r.launcher.level) >= 0) r.check() }
    }
    function ask() {
        const l = launcher
        if (!l || levels.indexOf(l.level) < 0) return
        const q = l.query.trim()
        if (q === "" || fresh(l.level, q)) return
        if (checkProc.running) { checkTimer.restart(); return }   // one at a time: asked again once it is done
        checkProc.asked = { level: l.level, query: q }
        checkProc.command = [cmdPath, "add", "--dry-run", "--json"].concat(l.level === "schedule" ? [q, "--"] : [pick.when, "--", q])
        checkProc.running = true
    }
    Sh {
        id: checkProc
        property var asked: ({})
        onResult: text => {
            let row
            try { row = JSON.parse(text) } catch (e) { row = { error: text.trim() || "schedule failed" } }
            r.reading = { level: asked.level, query: asked.query, row: row }
        }
    }
    Sh {
        id: listProc
        command: [r.cmdPath, "list", "--json"]
        onResult: text => { try { r.pending = JSON.parse(text).commands || [] } catch (e) { r.pending = [] } }
    }
    // Not added (no systemd user session, a line that doesn't parse): said in a notification, as the launcher is closed
    Sh {
        id: addProc
        onResult: text => {
            try { JSON.parse(text); listProc.running = true }
            catch (e) { Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Schedule", "Not scheduled", text.trim() || "schedule failed"]) }
        }
    }
    Sh { id: cancelProc; onResult: listProc.running = true }
    Sh { id: runProc; onResult: listProc.running = true }
}
