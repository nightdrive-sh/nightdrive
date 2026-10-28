import QtQuick
import Quickshell

// The launcher's Settings › Top bar (opacity, icon colors, highlight, the clock's date format, the N█ logo, which items it shows and
// in what order) and Screensaver (style, start after, screen off after). The values apply as they are chosen, so they
// can be tried one after another. Theme stays in Launcher.qml: Background's wallpapers are a grid of the launcher's own.
// The root search finds both pages' rows too (topbarItems, screensaverItems).
// Launcher.qml asks it like DefaultAppsLevels (levels, titles, parents, items, activate, footer, entered), and also
// moveSelected (Ctrl+Up/Down: Items' order).
Item {
    id: a
    property var launcher: null

    property int barOpacity: -1               // Top bar › Opacity: current value (hypr/scripts/bar-style), -1 = not read yet
    property string barIcons: ""              // Top bar › Icon colors: light | dark
    property int barIconOp: -1                // icon and text opacity
    property string barHl: ""                 // Top bar › Highlight: theme | white | black
    property string barDate: ""               // Top bar › Date format: auto | dmy | mdy | iso (topbar/scripts/clock style)
    // The clock's date styles, shown with today's date in each
    readonly property var dateStyles: [["auto", "As the system", ""], ["dmy", "Day first", "dd.MM."], ["mdy", "Month first", "MM/dd"],
                                       ["iso", "ISO", "MM-dd"]]
    property int idleSaver: -1                // Screensaver: minutes until the screensaver / screen off, 0 = never,
    property int idleOff: -1                  // -1 = not read yet (hypr/scripts/idle)
    property string idleStyle: ""             // which screensaver: random | saver | rain | clock
    readonly property var saverStyles: [["random", "Random", "shuffle"], ["saver", "Synthwave", "sunset"], ["rain", "Rain", "cloud-rain"], ["clock", "Clock", "clock"]]

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    readonly property var levels: ["topbar", "baropacity", "baricons", "barhl", "bardate", "baritems", "screensaver", "saverafter", "screenoff", "saverstyle"]
    readonly property var titles: ({ topbar: "Settings › Top bar", baropacity: "Top bar › Opacity", baricons: "Top bar › Icon colors", barhl: "Top bar › Highlight",
                                     bardate: "Top bar › Date format",
                                     baritems: "Top bar › Items", screensaver: "Settings › Screensaver", saverafter: "Screensaver › Start after",
                                     screenoff: "Screensaver › Screen off after", saverstyle: "Screensaver › Style" })
    readonly property var parents: ({ topbar: "settings", baropacity: "topbar", baricons: "topbar", barhl: "topbar", bardate: "topbar", baritems: "topbar",
                                      screensaver: "settings", saverafter: "screensaver", screenoff: "screensaver", saverstyle: "screensaver" })
    // Rows applied live: kind → [script, verb, property that holds the current value]
    readonly property var live: ({
        baropacity: ["bar-style", "opacity", "barOpacity"],
        baricons: ["bar-style", "icons", "barIcons"],
        bariconop: ["bar-style", "icon-opacity", "barIconOp"],
        barhl: ["bar-style", "highlight", "barHl"],
        idlesaver: ["idle", "saver", "idleSaver"],
        idleoff: ["idle", "off", "idleOff"],
        idlestyle: ["idle", "style", "idleStyle"]
    })

    function footer(level, query) { return level === "baritems" ? "Enter: show / hide  ·  Ctrl+Up+Down: reorder" : "" }
    function opened() {}
    function entered(level) {
        if (level === "topbar" || level === "baropacity" || level === "baricons" || level === "barhl" || level === "bardate") barProc.running = true
        if (level === "screensaver" || level === "saverafter" || level === "screenoff" || level === "saverstyle") idleProc.running = true
    }
    function shiftActivate(it) {}

    function minutes(m) { return m < 0 ? undefined : m === 0 ? "never" : m + " min" }
    // Screensaver: the two idle times with their current values, and a preview
    function screensaverItems() {
        return [
            { kind: "nav", name: "Style", glyph: "sparkles", target: "saverstyle", summary: (saverStyles.find(t => t[0] === idleStyle) || [])[1] },
            { kind: "nav", name: "Start after", glyph: "timer", target: "saverafter", summary: minutes(idleSaver) },
            { kind: "nav", name: "Screen off after", glyph: "monitor-off", target: "screenoff", summary: minutes(idleOff) },
            { kind: "action", name: "Preview", glyph: "monitor-play", cmd: ["bash", "-c", "sleep 0.4; \"$HOME/.config/screensaver/start\""] }
        ]
    }
    // Top bar: sub-items with their current values
    function topbarItems() {
        const logoOn = TopBar.hidden.indexOf("logo") < 0
        return [
            { kind: "nav", name: "Opacity", glyph: "panel-top", target: "baropacity", summary: barOpacity >= 0 ? barOpacity + "%" : undefined },
            { kind: "nav", name: "Icon colors", glyph: "contrast", target: "baricons",
              summary: barIcons !== "" ? (barIcons === "dark" ? "black" : "white") + " " + barIconOp + "%" : undefined },
            { kind: "nav", name: "Highlight", glyph: "highlighter", target: "barhl",
              summary: barHl === "theme" ? "theme color" : (barHl || undefined) },
            { kind: "nav", name: "Date format", glyph: "calendar", target: "bardate",
              summary: (dateStyles.find(d => d[0] === barDate) || [])[1] },
            { kind: "barlogo", name: "Logo", glyph: "square", summary: "opens the Launcher",
              trailGlyph: logoOn ? "check" : "minus", dimmed: !logoOn },
            { kind: "nav", name: "Items", glyph: "layout-list", target: "baritems",
              summary: TopBar.modules.length + " of " + TopBar.allModules.length + " shown" }
        ]
    }

    function items(level, q) {
        const l = launcher
        if (level === "topbar") return { all: topbarItems().map(t => ({ item: t, text: t.name, extra: l.settingsAliases[t.name] || "" })) }
        if (level === "baropacity") {
            // Number in the query → exactly that value; otherwise 100–0 in steps of ten. Current one marked.
            const typed = l.query.trim(), n = parseInt(typed, 10)
            const vals = /^\d+$/.test(typed) && n <= 100 ? [n] : [100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0]
            return vals.map(v => ({ kind: "baropacity", value: v, name: v + "%", glyph: v === barOpacity ? "check" : "panel-top",
                                    summary: v === barOpacity ? "current" : (v === 100 ? "opaque" : v === 0 ? "transparent" : undefined) }))
        }
        if (level === "baricons") {
            const ops = [100, 90, 85, 80, 70, 60, 50]
            return [{ kind: "header", name: "Color" },
                    { kind: "baricons", value: "light", name: "White", glyph: barIcons === "light" ? "check" : "sun", summary: barIcons === "light" ? "current" : undefined },
                    { kind: "baricons", value: "dark", name: "Black", glyph: barIcons === "dark" ? "check" : "moon", summary: barIcons === "dark" ? "current" : undefined },
                    { kind: "header", name: "Opacity" }]
                .concat(ops.map(v => ({ kind: "bariconop", value: v, name: v + "%", glyph: v === barIconOp ? "check" : "contrast",
                                        summary: v === barIconOp ? "current" : undefined })))
        }
        if (level === "barhl") {
            return [["theme", "Theme color"], ["white", "White"], ["black", "Black"]].map(h => ({
                kind: "barhl", value: h[0], name: h[1], glyph: barHl === h[0] ? "check" : "highlighter",
                summary: barHl === h[0] ? "current" : (h[0] === "theme" ? "default" : undefined) }))
        }
        if (level === "bardate") {
            return dateStyles.map(d => ({ kind: "bardate", value: d[0], name: d[1], glyph: barDate === d[0] ? "check" : "calendar",
                                          summary: d[2] !== "" ? Qt.formatDate(new Date(), d[2]) : "the order of the system's language" }))
        }
        if (level === "baritems") {
            // What the bar shows, in its order (left to right); Enter turns one on or off
            const all = TopBar.allModules.map(m => {
                const on = TopBar.hidden.indexOf(m.name) < 0
                return { item: { kind: "baritem", value: m.name, name: TopBar.moduleLabel(m), glyph: TopBar.moduleGlyph(m),
                                 trailGlyph: on ? "check" : "minus", dimmed: !on }, text: TopBar.moduleLabel(m), extra: m.name }
            })
            if (q === "") return all.map(x => x.item)      // a fixed order: toggling doesn't move rows
            return { all: all }
        }
        if (level === "screensaver") return { all: screensaverItems().map(t => ({ item: t, text: t.name })) }
        if (level === "saverstyle") {
            return saverStyles.map(t => ({ kind: "idlestyle", value: t[0], name: t[1], glyph: t[0] === idleStyle ? "check" : t[2],
                                           summary: t[0] === idleStyle ? "current" : (t[0] === "random" ? "default" : undefined) }))
        }
        if (level === "saverafter" || level === "screenoff") {
            const cur = level === "saverafter" ? idleSaver : idleOff
            const vals = level === "saverafter" ? [2, 5, 10, 15, 20, 30, 60, 0] : [5, 10, 15, 20, 30, 45, 60, 0]
            return vals.map(v => ({ kind: level === "saverafter" ? "idlesaver" : "idleoff", value: v, name: minutes(v),
                                    glyph: v === cur ? "check" : (level === "saverafter" ? "timer" : "monitor-off"), summary: v === cur ? "current" : undefined }))
        }
        return []
    }

    // Stays open: values can be tried one after another
    function activate(it) {
        // The bar's N█ logo: kept in the same hidden list as the modules (no module is named "logo")
        if (it.kind === "barlogo") { launcher.keepSelection(); TopBar.setHidden("logo", TopBar.hidden.indexOf("logo") < 0); return true }
        if (it.kind === "baritem") { launcher.keepSelection(); TopBar.setHidden(it.value, TopBar.hidden.indexOf(it.value) < 0); return true }
        if (it.kind === "bardate") {   // the clock refreshes the bar itself
            launcher.keepSelection()
            a.barDate = it.value
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/topbar/scripts/clock", "style", it.value])
            return true
        }
        const l = live[it.kind]
        if (!l) return false
        launcher.keepSelection()
        a[l[2]] = it.value
        Quickshell.execDetached([scripts + "/" + l[0], l[1], String(it.value)])
        return true
    }
    // Ctrl+Up/Down in Items (empty search): the selected module moves, the selection with it
    function moveSelected(dir) {
        const l = launcher
        if (l.level !== "baritems") return false
        const cur = l.results[l.selIndex]
        if (cur && cur.kind === "baritem" && l.query === "") {
            const j = TopBar.move(cur.value, dir)
            Qt.callLater(() => l.select(j))
        } else l.shakeNow()
        return true
    }

    // Screensaver: current idle times; select the current one
    Sh {
        id: idleProc
        script: 's="$HOME/.config/hypr/scripts/idle"; "$s" saver; "$s" off; "$s" style'
        onResult: text => {
            const f = text.trim().split("\n")
            a.idleSaver = parseInt(f[0], 10)
            a.idleOff = parseInt(f[1], 10)
            a.idleStyle = f[2] || ""
            const l = a.launcher
            if (l.level === "saverstyle" && l.query === "") l.selectWhere(r => r.value === a.idleStyle)
            if ((l.level === "saverafter" || l.level === "screenoff") && l.query === "")
                l.selectWhere(r => r.value === (l.level === "saverafter" ? a.idleSaver : a.idleOff))
        }
    }
    // Top bar: opacity, icons, highlight; select the current one
    Sh {
        id: barProc
        script: 's="$HOME/.config/hypr/scripts/bar-style"; "$s" opacity; "$s" icons; "$s" icon-opacity; "$s" highlight; ~/.config/topbar/scripts/clock style'
        onResult: text => {
            const f = text.trim().split("\n")
            a.barOpacity = parseInt(f[0], 10)
            a.barIcons = f[1] || ""
            a.barIconOp = parseInt(f[2], 10)
            a.barHl = f[3] || ""
            a.barDate = f[4] || ""
            const l = a.launcher
            if (l.level === "baropacity" && l.query === "") l.selectWhere(r => r.value === a.barOpacity)
            if (l.level === "barhl" && l.query === "") l.selectWhere(r => r.value === a.barHl)
            if (l.level === "bardate" && l.query === "") l.selectWhere(r => r.value === a.barDate)
            if (l.level === "baricons" && l.query === "") l.selectWhere(r => r.value === a.barIcons)
        }
    }
}
