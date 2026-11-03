pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Dates.js" as D

// Settings › Region for the apps: how dates and times are written, from LC_TIME in ~/.config/locale.conf (set by
// hypr/scripts/region, `nightdrive region`) and the regions in regions.json. Read from the file, not the environment, so
// a change reaches every open app at once (Quickshell keeps the LC_TIME it started with). The formatting itself is in
// Dates.js; these are the same functions with the current region filled in:
//   Regional.format(dateOrIso, "short" | "day" | "medium" | "long" | "time" | "month")
//   Regional.time("14:30")             2:30 PM in the US
//   Regional.range(a, b, short)        "2 – 8 Nov 2026", "Nov 2 – 8, 2026"
//   Regional.parse("5.11.", baseIso)   "2026-11-05", "" when it isn't a day
//   Regional.parseTime("2:30 pm")      "14:30", "" when it isn't a time
//   Regional.weekStart (0 Sun, 1 Mon), Regional.startOfWeek(date), Regional.weekdays: [1 … 6, 0]
//   Regional.h24, Regional.example ("5.11.2026": what a field's hint shows)
Singleton {
    id: root

    readonly property string confPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/locale.conf"
    // Without the region chosen, ISO: what the apps wrote before there was one. en_US is Fedora's default for all who
    // keep English, so it doesn't say where they are (hypr/scripts/region does the same)
    readonly property string fallback: "iso"

    property var table: ({})
    property string confLocale: ""
    readonly property string key: {
        const loc = confLocale || Quickshell.env("LC_TIME") || Quickshell.env("LANG") || ""
        const base = loc.split(".")[0]
        for (const k in table)
            if (k[0] !== "_" && table[k].locale.split(".")[0] === base)
                return !confLocale && k === "us" ? fallback : k
        return fallback
    }
    readonly property var region: table[key] || { name: "ISO 8601", order: "ymd", short: "yyyy-MM-dd", day: "MM-dd",
                                                 medium: "d MMM yyyy", long: "ddd d MMMM yyyy", time: "HH:mm", weekStart: 1 }
    readonly property string name: region.name
    readonly property int weekStart: region.weekStart
    readonly property var weekdays: D.weekdays(region)
    readonly property bool h24: region.time.indexOf("AP") < 0
    readonly property string example: D.example(region)

    function format(v, kind) { return D.format(v, kind, region) }
    function time(hhmm) { return D.time(hhmm, region) }
    function range(a, b, short) { return D.range(a, b, region, short) }
    function parse(text, base) { return D.parse(text, region, base) }
    function parseTime(text) { return D.parseTime(text) }
    function startOfWeek(d) { return D.weekStart(d, region) }
    function iso(d) { return D.iso(d) }
    function dayName(wd, short) { return D.dayName(wd, short) }

    FileView {
        path: Qt.resolvedUrl("regions.json").toString().replace(/^file:\/\//, "")
        blockLoading: true   // the first frame already has the right format
        onLoaded: { try { root.table = JSON.parse(text()) } catch (e) { root.table = ({}) } }
    }
    FileView {
        path: root.confPath
        blockLoading: true
        watchChanges: true
        printErrors: false   // no locale.conf is the usual case
        onFileChanged: reload()
        onLoaded: {
            const m = /^\s*LC_TIME=["']?([^"'\s]*)/m.exec(text())
            root.confLocale = m ? m[1] : ""
        }
        onLoadFailed: root.confLocale = ""
    }
}
