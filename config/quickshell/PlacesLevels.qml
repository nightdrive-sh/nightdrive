import QtQuick
import Quickshell

// The launcher's Settings › Places (Dashboard #3281, part 6 of #3275): names for Wi-Fi networks (work = "Feature"),
// which Remind and Schedule can wait for arriving at or leaving. Places lists them; "This network (SSID) is…" puts the
// Wi-Fi now in a place, an old one or one named there; a place's own level lists its networks, each forgotten with Enter
// twice, and removes the place. hypr/scripts/places does the work (`--json`, its file ~/.config/nightdrive/places.json);
// this keeps no copy of its rules. RemindLevels and ScheduleLevels read `places` here for their arrive and leave rows
// (eventRows, eventLabel), so the list is read when one of the three is entered, not at every launcher open.
// Launcher.qml asks it like its other level files (levels, titles, parents, items, activate, footer, entered,
// deleteSelected).
Item {
    id: r
    property var launcher: null

    readonly property string cmdPath: Quickshell.env("HOME") + "/.config/hypr/scripts/places"
    property var places: []         // places list --json: [{ name, wifi: [SSIDs], here }]
    property var wifi: []           // the SSIDs now (usually one)
    property bool loaded: false     // read once: until then "…" rather than "no places"
    property string current: ""     // the place open in its own level

    readonly property var levels: ["places", "place", "placehere"]
    readonly property var inputs: ["placehere", "place"]   // text fields: ⌘⇧V pastes into them (ClipPicker)
    readonly property var titles: ({ places: "Settings › Places", place: "Places › " + current, placehere: "Places › " + ssid() + " is…" })
    readonly property var parents: ({ places: "settings", place: "places", placehere: "places" })

    function ssid() { return wifi.length ? wifi[0] : "" }
    function find(name) { return places.find(p => p.name.toLowerCase() === name.toLowerCase()) || null }
    function nets(p) { return p.wifi.length ? p.wifi.join(", ") : "no networks" }
    function refresh() { listProc.running = true }

    // For RemindLevels and ScheduleLevels: what an event is called on a row, and the rows of every place
    function eventLabel(when, place) {
        return when === "wake" ? "On wake" : when === "login" ? "At login"
             : when === "arrive" ? "On arriving: " + place : when === "leave" ? "On leaving: " + place : ""
    }
    // The same in a sentence's middle: "on arriving at work"
    function eventPhrase(when, place) {
        return when === "arrive" ? "on arriving at " + place : when === "leave" ? "on leaving " + place
             : eventLabel(when, place).toLowerCase()
    }
    // One arrive and one leave row a place, made by make(when, place, name, glyph) as the caller's row kind
    function eventRows(make) {
        const out = []
        places.forEach(p => {
            out.push(make("arrive " + p.name, eventLabel("arrive", p.name), "map-pin-check"))
            out.push(make("leave " + p.name, eventLabel("leave", p.name), "map-pin-x"))
        })
        return out
    }
    // A typed event (wake, login, arrive work, leave work): { when, name, glyph } with the place's name as saved; null when not
    function typedEvent(text) {
        const t = text.trim().toLowerCase().replace(/\s+/g, " ")
        if (t === "wake") return { when: "wake", name: "On wake", glyph: "sunrise" }
        if (t === "login") return { when: "login", name: "At login", glyph: "log-in" }
        const m = t.match(/^(arrive|leave) (.+)$/)
        const p = m ? find(m[2]) : null
        return p ? { when: m[1] + " " + p.name, name: eventLabel(m[1], p.name), glyph: m[1] === "arrive" ? "map-pin-check" : "map-pin-x" } : null
    }

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "placeforget") return "Enter twice or Cmd+Backspace twice: take " + cur.ssid + " off " + current
        if (cur.kind === "placeremove") return "Enter twice: remove " + current
        if (cur.kind === "placeopen") return "Enter: its networks  ·  Cmd+Backspace twice: remove it"
        if (cur.kind === "nav") return "Enter: put " + cur.ssid + " in a place, an old one or a new one"
        if (cur.kind === "placeadd") return "Enter: add " + cur.ssid + " to " + cur.place
        if (level === "placehere") return "Type a new place’s name, or pick one"
        if (level === "place") return "Type another network’s name to add it"
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level !== "place") refresh()
    }
    function shiftActivate(it) {}

    function items(level, q) {
        if (level === "placehere") return hereRows(launcher.query.trim())   // as typed: q is lower-cased
        if (level === "place") return placeRows(launcher.query.trim())
        if (level !== "places") return []
        const s = ssid(), inIt = s ? places.filter(p => p.wifi.indexOf(s) >= 0).map(p => p.name) : []
        const rows = [{ kind: "header", name: "This network" }].concat(
            !s ? [{ kind: "note", name: loaded ? "Not on Wi-Fi now: a place is a Wi-Fi network you name" : "…" }]
               : [{ kind: "nav", name: s + " is…", glyph: "map-pin-plus", target: "placehere", ssid: s,
                    summary: inIt.length ? inIt.join(", ") : "not a place" }])
        if (!places.length) return rows.concat(loaded ? [
            { kind: "note", name: "Name your networks: work, home. Then Remind and Schedule" },
            { kind: "note", name: "can wait for arriving at one or leaving it." }] : [])
        return rows.concat([{ kind: "header", name: "Places" }], places.map(p => ({
            kind: "placeopen", place: p.name, name: p.name, glyph: p.here ? "map-pin-check" : "map-pin", armKey: "place:" + p.name,
            summary: nets(p) + (p.here ? " · here" : "") })))
    }
    // This network is…: a new place by the typed name, then the places it isn't in yet
    function hereRows(typed) {
        const s = ssid()
        if (!s) return launcher.hint("Not on Wi-Fi now")
        const old = typed !== "" ? find(typed) : null
        const rows = typed !== "" && !old ? [{ kind: "placeadd", place: typed, ssid: s, name: "New place “" + typed + "”", glyph: "map-pin-plus" }] : []
        const others = places.filter(p => p.wifi.indexOf(s) < 0 && (typed === "" || p.name.toLowerCase().indexOf(typed.toLowerCase()) >= 0))
        return rows.concat(others.map(p => ({ kind: "placeadd", place: p.name, ssid: s, name: p.name, glyph: "map-pin",
                                              summary: "with " + nets(p) })),
                           !rows.length && !others.length ? launcher.hint(typed === "" ? "Type a name for it: work, home" : s + " is in " + typed + " already") : [])
    }
    // One place: its networks, the Wi-Fi now to add, and Remove; typed, only the network to add (SSIDs match exactly)
    function placeRows(typed) {
        const p = find(current)
        if (!p) return launcher.hint("…")
        if (typed !== "") return p.wifi.indexOf(typed) >= 0 ? launcher.hint(p.name + " has " + typed + " already")
                               : [{ kind: "placeadd", place: p.name, ssid: typed, name: "Add “" + typed + "”", glyph: "wifi" }]
        const s = ssid()
        return [{ kind: "header", name: "Networks" }].concat(
            p.wifi.map(w => ({ kind: "placeforget", ssid: w, name: w, glyph: "wifi", armKey: "placenet:" + w,
                               summary: w === s ? "now" : undefined })),
            s && p.wifi.indexOf(s) < 0 ? [{ kind: "placeadd", place: p.name, ssid: s, name: "Add " + s, glyph: "wifi", summary: "the Wi-Fi now" }] : [],
            [{ kind: "placeremove", name: "Remove " + p.name, glyph: "trash-2", armKey: "placerm:" + p.name }])
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "placeopen") { current = it.place; l.go("place"); return true }
        if (it.kind === "placeadd") {
            run(["add", it.place, it.ssid])
            if (l.level === "placehere") l.go("places", true)
            else l.go("place", true)   // the typed network cleared
            return true
        }
        if (it.kind === "placeforget") { if (arm(it.armKey)) run(["forget", current, it.ssid]); return true }
        if (it.kind === "placeremove") {
            if (!arm(it.armKey)) return true
            run(["remove", current])
            l.go("places", true)
            return true
        }
        return false
    }
    // ⌘⌫ (IPC deleteSelected) or Delete with nothing typed: a place in Places, a network in a place's level
    function deleteSelected() {
        const l = launcher
        if ((l.level !== "places" && l.level !== "place") || l.query !== "") return false
        const it = l.results[l.selIndex]
        if (it && it.kind === "placeopen") { if (arm(it.armKey)) run(["remove", it.place]); return true }
        if (it && it.kind === "placeforget") { activate(it); return true }
        l.shakeNow()
        return true
    }
    function arm(key) {
        if (launcher.armed !== key) { launcher.armed = key; disarmTimer.restart(); return false }
        launcher.armed = ""
        return true
    }
    Timer { id: disarmTimer; interval: 4000; onTriggered: if (r.launcher) r.launcher.armed = "" }

    // A change, then the list read again. Through bash for its error on stdout (Sh reads only that): said in a
    // notification, as the row it came from may be gone by then
    function run(args) {
        changeProc.command = ["bash", "-c", 'exec "$0" "$@" 2>&1', cmdPath].concat(args, ["--json"])
        changeProc.running = true
    }
    Sh {
        id: changeProc
        onResult: text => {
            try { JSON.parse(text) }
            catch (e) { Quickshell.execDetached(["notify-send", "-a", "Places", "Places", text.trim() || "places failed"]) }
            r.refresh()
        }
    }
    Sh {
        id: listProc
        command: [r.cmdPath, "list", "--json"]
        onResult: text => {
            try { const d = JSON.parse(text); r.places = d.places || []; r.wifi = d.wifi || [] }
            catch (e) { r.places = []; r.wifi = [] }
            r.loaded = true
        }
    }
}
