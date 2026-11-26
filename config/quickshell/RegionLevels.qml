import QtQuick
import Quickshell
import qs.kit
import "kit/Dates.js" as Dates

// The launcher's Settings › Region: how dates and times are written (3.11.2026 or 11/3/2026, 24 or 12 h, the week from
// Monday or Sunday), apart from the language, which stays. One row a region, each showing today its way. The choice is
// LC_TIME in ~/.config/locale.conf (hypr/scripts/region, `nightdrive region set`), so other programs follow it too;
// Nightdrive's apps read it through the kit's Regional singleton, which watches that file, so the rows' check moves as
// soon as it is written. Launcher.qml asks it like its other Levels files (levels, titles, parents, items, activate,
// footer, entered).
Item {
    id: r
    property var launcher: null

    readonly property var levels: ["region"]
    readonly property var titles: ({ region: "Settings › Region" })
    readonly property var parents: ({ region: "settings" })
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/region"

    // What a region's row says: today's date, a time and the week's first day, its way ("3.11.2026 · 14:30 · Mon")
    function sample(key) {
        const reg = Regional.table[key]
        const now = new Date(), t = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 14, 30)
        return Dates.format(now, "short", reg) + "  ·  " + Dates.format(t, "time", reg) + "  ·  " + Dates.dayName(reg.weekStart, true)
    }

    function footer(level, query) { return level === "region" ? "Enter: use it" : "" }
    function opened() {}
    function entered(level) {
        if (level === "region" && launcher) launcher.selectWhere(it => it.value === Regional.key)
    }
    function shiftActivate(it) {}

    function items(level, q) {
        if (level !== "region") return []
        const rows = Object.keys(Regional.table).filter(k => k[0] !== "_").map(k => ({
            kind: "region", value: k, name: Regional.table[k].name, glyph: k === Regional.key ? "check" : "calendar-clock",
            summary: sample(k), extra: Regional.table[k].locale }))
        return { all: rows.concat([{ kind: "note", name: "Dates, times, the week's first day. The language stays" }])
                         .map(it => ({ item: it, text: it.kind === "note" ? "" : it.name, extra: it.extra || "" })) }
    }

    function activate(it) {
        if (it.kind !== "region") return false
        if (it.value === Regional.key) { launcher.shakeNow(); return true }
        launcher.keepSelection()
        Quickshell.execDetached([script, "set", it.value])
        return true
    }
}
