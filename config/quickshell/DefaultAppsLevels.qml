import QtQuick
import Quickshell

// The launcher's Settings › Apps › Default apps: which app opens links, mail, folders, images… One row per kind with its app;
// Enter opens the kind's apps (Default apps › Browser), whose Enter makes one the default. The last row there goes to
// Install › Software for apps that aren't installed yet: a search ("document viewer") or a category (Browsers).
// Data and changes: hypr/scripts/default-apps (nightdrive defaults), which also starts the apps behind Hyper B / F / I.
// Launcher.qml asks it like its other Levels files (levels, titles, parents, items, activate, footer, entered).
Item {
    id: d
    property var launcher: null
    property var kinds: null                 // default-apps --json: [{ key, name, glyph, more, current, apps }]
    property var kind: ({ key: "", name: "" })   // Default apps › <kind>: the open one

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/default-apps"
    readonly property var levels: ["defaults", "defaultpick"]
    readonly property var titles: ({ defaults: "Apps › Default apps", defaultpick: "Default apps › " + kind.name })
    readonly property var parents: ({ defaults: "appsettings", defaultpick: "defaults" })
    readonly property var settingsItems: [{ kind: "nav", name: "Default apps", glyph: "layout-grid", target: "defaults" }]

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "defkind") return "Enter: choose"
        if (cur.kind === "defapp") return cur.current ? "" : "Enter: use this"
        if (cur.kind === "defmore") return cur.cat ? "Enter: open the category" : "Enter: search Fedora + Flathub"
        return ""
    }
    function opened() {}
    property bool fresh: false               // just entered: the cursor goes to the current app once the list is read
    function entered(level) { fresh = true; listProc.running = true }
    function shiftActivate(item) {}

    function open() { return (kinds || []).find(k => k.key === kind.key) || null }

    function items(level, q) {
        if (kinds === null) return [{ kind: "hint", name: "Loading…" }]
        if (level === "defaults") {
            return { all: kinds.map(k => ({ item: { kind: "defkind", key: k.key, name: k.name, glyph: k.glyph, chevron: true,
                                                    summary: k.current ? k.current.name : "none" },
                                            text: k.name, extra: (k.current ? k.current.name : "") + " " + k.key })) }
        }
        const k = open()
        if (k === null) return []
        const cur = k.current ? k.current.id : ""
        const apps = k.apps.map(a => ({ item: { kind: "defapp", id: a.id, name: a.name, current: a.id === cur,
                                                // the app's own icon stays; the current one's check goes to the right end
                                                // (as the AirPlay speakers'), not over the icon like the other choices'
                                                iconFile: a.icon, trailGlyph: a.id === cur ? "check" : undefined },
                                        text: a.name, extra: a.id }))
        const cat = k.more.startsWith("cat:") ? (launcher.swCats.find(c => "cat:" + c.key === k.more) || null) : null
        const more = { kind: "defmore", name: "Find more in Install › Software", glyph: "package-search", chevron: true, cat: cat,
                       summary: cat ? cat.name : "“" + k.more + "”" }
        return { all: apps.concat(apps.length === 0 ? [{ item: { kind: "hint", name: "No " + k.name.toLowerCase() + " app installed" }, text: "" }] : [],
                                  [{ item: more, text: more.name, extra: "install software" }]) }
    }

    function activate(it) {
        if (it.kind === "defkind") { kind = { key: it.key, name: it.name }; launcher.go("defaultpick"); return true }
        if (it.kind === "defmore") {
            if (it.cat) launcher.openCategory(it.cat.key, it.cat.name)
            else launcher.search("swsearch", open().more)
            return true
        }
        if (it.kind !== "defapp") return false
        if (it.current) { launcher.shakeNow(); return true }
        launcher.keepSelection()
        setProc.command = [script, "set", kind.key, it.id]
        setProc.running = true
        return true
    }

    Sh {
        id: listProc
        command: [d.script, "--json"]
        onResult: text => {
            let v
            try { v = JSON.parse(text) } catch (e) { return }
            const l = d.launcher
            if (!d.fresh) l.keepSelection()
            d.kinds = v
            if (d.fresh && l.level === "defaultpick" && l.query === "") l.selectWhere(r => r.current === true)
            d.fresh = false
        }
    }
    Sh {
        id: setProc   // then read again: the check moves to the new one
        onResult: text => { if (text.trim() !== "") Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Default apps", "Couldn't change it", text.trim()]); listProc.running = true }
    }
}
