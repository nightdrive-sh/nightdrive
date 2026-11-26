import QtQuick
import Quickshell

// The launcher's Home level: Home Assistant's pinned devices, then the rooms (HA areas); Enter on a room opens its devices
// (Home › Olohuone), grouped by kind. Devices without a room are grouped into their own rows (Scenes, Scripts, Automations,
// Other devices). Searching on Home finds rooms and devices at once.
// Enter turns a device on/off or runs a scene / script, and the launcher stays open; Shift+Enter pins it to the top bar's
// Home menu. A light that's on has a yellow icon; a dimmable one shows its brightness as a ring around it: ←/→ steps 10 %, a sideways drag sets it.
// Shown only when Home Assistant is set up and on (plugins/home-assistant; nightdrive plugins off hides it). Data: Home.qml.
// Launcher.qml asks it like its other Levels files (levels, titles, parents, items, activate, footer, entered).
Item {
    id: x
    property var launcher: null
    property string room: ""                 // Home › <room>: the room that is open

    readonly property var levels: ["home", "homeroom", "homeprefs"]
    readonly property var titles: ({ home: "Home", homeroom: "Home › " + room, homeprefs: "Apps › Home Assistant" })
    readonly property var parents: ({ homeroom: "home", homeprefs: "appsettings" })
    readonly property bool on: Home.configured && Plugins.has("home-assistant")
    // Settings › Apps › Home Assistant, in Launcher.qml's Settings › Apps while Home Assistant is set up
    readonly property var settingsItems: on ? [{ kind: "nav", name: "Home Assistant", glyph: "house", target: "homeprefs" }] : []
    readonly property var rootItems: on ? [{ kind: "nav", name: "Home", glyph: "house", target: "home", extra: "home assistant hass lights rooms" }] : []

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "haroom") return "Enter: open"
        if (cur.kind === "hakind") return "Enter: show / hide in Home  ·  pinned devices show anyway"
        if (cur.kind !== "haent") return ""
        const e = cur.ent
        const what = Home.canToggle(e) || e.domain === "climate" ? "on/off" : e.domain === "scene" ? "activate" : e.domain.indexOf("button") >= 0 ? "press" : "run now"
        return "Enter: " + what + (cur.slider !== undefined ? "  ·  ←/→: brightness" : "") + (level !== "root" ? "  ·  Shift+Enter: " + (e.fav ? "unpin from" : "pin to") + " the top bar" : "")
    }
    function opened() { Home.check() }
    function entered(level) { Home.refresh() }

    // ---- Rooms ----
    // Devices without an HA area go to a row of their own kind; these come after the real rooms, in this order
    readonly property var looseRooms: ["Scenes", "Scripts", "Automations", "Other devices"]
    function roomOf(e) { return e.area || ({ scene: "Scenes", script: "Scripts", automation: "Automations" })[e.domain] || "Other devices" }
    function rooms() {
        const names = []
        for (const e of Home.shown) { const r = roomOf(e); if (names.indexOf(r) < 0) names.push(r) }
        const loose = n => looseRooms.indexOf(n)
        return names.sort((a, b) => (loose(a) - loose(b)) || a.localeCompare(b))   // real rooms (-1) first, by name
    }
    // An icon from the room's name, in Finnish or English; a door when nothing matches
    readonly property var roomIcons: [
        [/keittiö|kitchen/i, "cooking-pot"], [/lasten|kids|nursery|child/i, "baby"], [/makuu|bedroom/i, "bed-double"],
        [/olohuone|living|lounge/i, "sofa"], [/kylpy|bath|sauna|wc|pesuhuone|toilet/i, "bath"],
        [/kodinhoito|khh|laundry|utility/i, "washing-machine"], [/työhuone|toimisto|office|study/i, "briefcase"],
        [/eteinen|aula|hall|entr/i, "door-open"], [/piha|puutarha|garden|yard|ulko|outdoor|parveke|terassi|balcony|patio/i, "trees"],
        [/autotalli|autokatos|garage|carport/i, "car"], [/ruokailu|dining/i, "utensils"], [/vaate|closet|wardrobe/i, "shirt"],
        [/varasto|storage|kellari|basement/i, "warehouse"],
        [/^Scenes$/, "sparkles"], [/^Scripts$/, "scroll-text"], [/^Automations$/, "zap"], [/^Other devices$/, "layers"]
    ]
    function roomIcon(name) { const m = roomIcons.find(t => t[0].test(name)); return m ? m[1] : "door-open" }
    function roomRow(name) {
        const list = Home.shown.filter(e => roomOf(e) === name)
        const on = list.filter(e => Home.canToggle(e) && Home.isOn(e)).length
        return { kind: "haroom", name: name, glyph: roomIcon(name),
                 summary: (on ? on + " on · " : "") + list.length + (list.length === 1 ? " device" : " devices") }
    }

    // ---- Devices ----
    function row(e, opts) {
        const o = opts || {}
        // In the root search the room goes in the name (the HOME tag takes the summary's place): "Olohuone › Katto"
        // A device that turns on/off gets a switch; "on" / "off" then drop from the text (80 %, open… stay)
        // (also in the root search, where the HOME tag sits left of it)
        const sw = Home.canToggle(e) && e.state !== "unavailable" && e.state !== "unknown"
        const slider = e.dimmable && sw ? Home.bright(e) : undefined
        const detail = slider !== undefined && /%$/.test(Home.detail(e)) ? "" : Home.detail(e)   // the ring shows the brightness
        return { kind: "haent", ent: e, name: o.from && e.area ? e.area + " › " + e.name : e.name, glyph: Home.icon(e), from: o.from,
                 summary: o.from ? undefined : [o.noArea ? "" : e.area, sw && (detail === "on" || detail === "off") ? "" : detail].filter(t => t).join(" · ") || undefined,
                 switchOn: sw ? Home.isOn(e) : undefined, slider: slider,
                 glyphColor: e.domain === "light" && Home.isOn(e) ? Theme.caution : undefined, badge: e.fav && !o.from ? "pin" : undefined, dimmed: e.state === "unavailable" }
    }
    function searchRow(e, from) {
        return { item: row(e, { from: from }), text: e.name,
                 extra: [e.area, Home.sectionNames[e.domain] || "", e.id, from ? "home" : ""].join(" ") }
    }
    // Every room and device for the root level's search ("olohuone" → the room and its lights), tagged HOME
    function rootRows() {
        if (!on) return []
        return rooms().map(n => ({ item: Object.assign(roomRow(n), { from: "Home", summary: undefined }), text: n, extra: "room home" }))
            .concat(Home.shown.map(e => searchRow(e, "Home")))
    }

    function items(level, q) {
        if (level === "homeprefs") {   // which kinds the launcher shows; the count is how many your Home Assistant has
            return Home.kinds.map(k => {
                const n = Home.states.filter(e => k[1].indexOf(e.domain) >= 0).length
                const on = k[1].some(d => Home.hidden.indexOf(d) < 0)
                return { kind: "hakind", name: k[0], domains: k[1], on: on, glyph: Home.kindIcon(k[1][0]), switchOn: on,
                         note: Home.loaded ? String(n) : undefined, dimmed: Home.loaded && n === 0 }
            })
        }
        if (!Home.loaded) return [{ kind: "hint", name: "Loading…" }]
        if (Home.error !== "" && Home.states.length === 0) return [{ kind: "hint", name: Home.error }]
        const out = Home.error !== "" ? [{ kind: "hint", name: Home.error }] : []
        if (level === "home") {
            if (q !== "")   // rooms and devices at once, no sections (a pinned device would show twice)
                return { all: rooms().map(n => ({ item: roomRow(n), text: n, extra: "room" })).concat(Home.shown.map(e => searchRow(e))) }
            out.push({ kind: "header", name: "Pinned" })
            if (Home.favorites.length) for (const e of Home.favorites) out.push(row(e))
            // Until something is pinned, say how: the footer only tells it on a device row, one level down
            else out.push({ kind: "note", name: "Shift+Enter on a device pins it here and to the top bar" })
            const names = rooms()
            if (names.length) out.push({ kind: "header", name: "Rooms" })
            for (const n of names) out.push(roomRow(n))
            if (out.length === 0) out.push({ kind: "hint", name: "No devices found" })
            return out
        }
        // homeroom: the room's devices, by kind (no headers when they're all one kind, e.g. Scenes)
        const list = Home.shown.filter(e => roomOf(e) === room)
        if (q !== "") return { all: list.map(e => ({ item: row(e, { noArea: true }), text: e.name, extra: (Home.sectionNames[e.domain] || "") + " " + e.id })) }
        const kinds = list.map(e => Home.sectionNames[e.domain] || e.domain).filter((k, i, a) => a.indexOf(k) === i)
        let sec = ""
        for (const e of list) {
            const name = Home.sectionNames[e.domain] || e.domain
            if (kinds.length > 1 && name !== sec) { out.push({ kind: "header", name: name }); sec = name }
            out.push(row(e, { noArea: true }))
        }
        if (list.length === 0) out.push({ kind: "hint", name: "No devices in " + room })
        return out
    }

    function activate(it) {
        if (it.kind === "hakind") { launcher.keepSelection(); Home.setHidden(it.domains, it.on); return true }
        if (it.kind === "haroom") { room = it.name; launcher.go("homeroom"); return true }
        if (it.kind !== "haent") return false
        launcher.keepSelection()
        Home.toggle(it.ent)
        return true
    }
    // The row's brightness ring (Launcher.qml calls these for rows with `slider`: ←/→ and a sideways drag)
    function slide(it, v) { if (it.kind !== "haent") return; launcher.keepSelection(); Home.setBright(it.ent, v) }
    function stepSlide(it, dir) { if (it.kind !== "haent") return; launcher.keepSelection(); Home.stepBright(it.ent, dir) }
    function shiftActivate(it) {
        if (it.kind !== "haent") return
        launcher.keepSelection()
        Home.setFav(it.ent, !it.ent.fav)
    }

    // New states rebuild the rows: keep the selected one where it is (a pin, a toggle, the 3 s refresh)
    Connections {
        target: Home
        function onChanging() { if (x.launcher && x.launcher.open && (x.levels.indexOf(x.launcher.level) >= 0 || x.launcher.level === "root")) x.launcher.keepSelection() }
    }
    Timer { interval: 3000; repeat: true; running: x.launcher !== null && x.launcher.open && x.levels.indexOf(x.launcher.level) >= 0; onTriggered: Home.refresh() }
}
