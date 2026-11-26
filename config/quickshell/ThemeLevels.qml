import QtQuick
import Quickshell
import Quickshell.Io

// The launcher's Settings › Theme: Themes (Nightdrive's and the ones saved in Theme Editor; ⌘⌫ deletes one of yours),
// Color (the desktop's accent; the launcher recolors at once), Background (the wallpapers, yours and the bundled ones;
// ⌘⌫ moves one of yours to the trash), Font (the fonts on trial, #1839: the menus, launcher and apps change at once)
// and Theme Editor (ThemeEditor.qml: the window background, borders and shadow). Background's rows are drawn as a grid
// by Launcher.qml (grid, once wallLoaded), which also marks wallCurrent there.
// Launcher.qml asks it like DefaultAppsLevels (levels, titles, parents, items, activate, footer, entered), and also
// deleteSelected (⌘⌫, Delete).
Item {
    id: t
    property var launcher: null

    property var themeList: []                // Color: [{ value, name, swatch, current }] (hypr/scripts/theme list)
    property var fontList: []                 // Font: [{ family, installed, current }] (hypr/scripts/theme fonts)
    property var savedList: []                // Themes: [{ id, name, swatch, own, state }] (hypr/scripts/theme themes)
    property var wallList: []                 // Background: [{ path, thumb, name, group, own }] (hypr/scripts/wallpaper list)
    property bool wallLoaded: false
    property string wallCurrent: ""           // the current wallpaper

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    readonly property var levels: ["theme", "themes", "themecolor", "themefont", "background"]
    readonly property var titles: ({ theme: "Settings › Theme", themes: "Settings › Theme › Themes", themecolor: "Settings › Theme › Color",
                                     themefont: "Settings › Theme › Font", background: "Settings › Theme › Background" })
    readonly property var parents: ({ theme: "settings", themes: "theme", themecolor: "theme", themefont: "theme", background: "theme" })

    function footer(level, query) { return level === "themes" ? "Cmd+Backspace: delete one of yours" : "" }
    function opened() {}
    function entered(level) {
        if (level === "background") wallProc.running = true
        if (level === "theme" || level === "themecolor") themeProc.running = true
        if (level === "theme" || level === "themes") savedProc.running = true
        if (level === "theme" || level === "themefont") fontProc.running = true
    }
    function shiftActivate(it) {}

    // #1839, #2061: the font picker is on trial (the UI font isn't chosen yet and the sizes are made for JetBrains Mono),
    // so Font shows only where the git-ignored local slot local/trials has a line "font" (README › Make it yours), not on
    // a channel: dev users would get it too. `nightdrive theme font` works without it. To lift it: true.
    readonly property string trialsFile: Quickshell.env("HOME") + "/.config/quickshell/local/trials"
    property var trials: []
    readonly property bool fontOnTrial: trials.indexOf("font") >= 0
    FileView {
        path: t.trialsFile; watchChanges: true; onFileChanged: reload(); printErrors: false   // optional (an overlay)
        onLoaded: t.trials = text().split("\n").map(l => l.replace(/#.*/, "").trim()).filter(l => l !== "")
        onLoadFailed: t.trials = []
    }

    // Theme: Color with its current value, and Background (the root search finds them too)
    function themeItems() {
        const cur = themeList.find(c => c.current)
        const saved = savedList.find(c => c.state !== "")
        const font = fontList.find(f => f.current)
        return [
            { kind: "nav", name: "Themes", glyph: "swatch-book", target: "themes",
              summary: saved ? saved.name + (saved.state === "changed" ? " · changed" : "") : undefined },
            { kind: "nav", name: "Color", glyph: "palette", target: "themecolor", summary: cur ? cur.name.toLowerCase() : undefined },
        ].concat(fontOnTrial ? [
            { kind: "nav", name: "Font", glyph: "type", target: "themefont", summary: font ? fontName(font.family) : undefined }
        ] : [], [
            { kind: "nav", name: "Background", glyph: "wallpaper", target: "background" },
            { kind: "action", name: "Theme Editor…", glyph: "paint-bucket", cmd: ["qs", "ipc", "call", "themeeditor", "open"] }
        ])
    }

    // "Inter Variable" is the family's name, Inter the font's
    function fontName(family) { return family.replace(/ Variable$/, "") }

    function items(level, q) {
        if (level === "theme") return { all: themeItems().map(i => ({ item: i, text: i.name,
                                                                      extra: i.name === "Font" ? "typeface" : launcher.settingsAliases[i.name] || "" })) }
        if (level === "themefont") {
            if (fontList.length === 0) return [{ kind: "hint", name: "Loading…" }]
            return { all: fontList.map((f, i) => ({ item: { kind: "themefont", value: f.family, name: fontName(f.family), glyph: "type",
                                                            installed: f.installed,
                                                            summary: f.current ? "current" : !f.installed ? "not installed"
                                                                   : i === 0 ? "default" : undefined }, text: fontName(f.family) })) }
        }
        if (level === "themes") {
            if (savedList.length === 0) return [{ kind: "hint", name: "Loading…" }]
            return { all: savedList.map(c => ({ item: { kind: "savedtheme", value: c.id, name: c.name, swatch: c.swatch, own: c.own,
                                                        summary: c.state === "current" ? "current" : c.state === "changed" ? "current · changed"
                                                               : c.own ? "yours" : undefined }, text: c.name })) }
        }
        if (level === "themecolor") {
            if (themeList.length === 0) return [{ kind: "hint", name: "Loading…" }]
            return { all: themeList.map(c => ({ item: { kind: "themecolor", value: c.value, name: c.name, swatch: c.swatch,
                                                        summary: c.current ? "current" : (c.value === "violet" ? "default" : undefined) }, text: c.name })) }
        }
        if (level === "background") {
            if (!wallLoaded) return [{ kind: "hint", name: "Loading backgrounds… (first time creates previews)" }]
            // "Add new…" first: an image of your own from a file picker
            return { all: [{ item: { kind: "walladd", name: "Add new…" }, text: "Add new", extra: "import file" }]
                .concat(wallList.map(w => ({ item: Object.assign({ kind: "wall" }, w), text: w.name, extra: w.group }))) }
        }
        return []
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "themecolor") {   // stays open: colors can be tried one after another, and recolor the launcher at once
            l.keepSelection()
            themeList = themeList.map(c => Object.assign({}, c, { current: c.value === it.value }))
            Quickshell.execDetached([scripts + "/theme", "color", String(it.value)])
            return true
        }
        if (it.kind === "themefont") {    // stays open: fonts can be tried one after another, the launcher changes at once
            if (!it.installed) { l.shakeNow(); return true }
            l.keepSelection()
            fontList = fontList.map(f => Object.assign({}, f, { current: f.family === it.value }))
            Quickshell.execDetached([scripts + "/theme", "font", String(it.value)])
            return true
        }
        if (it.kind === "savedtheme") {   // stays open: themes can be tried one after another
            l.keepSelection()
            savedList = savedList.map(c => Object.assign({}, c, { state: c.id === it.value ? "current" : "" }))
            Quickshell.execDetached([scripts + "/theme", "use", String(it.value)])
            return true
        }
        if (it.kind === "walladd") {      // the launcher closes while the picker is open; the script reopens Background
            l.open = false
            Quickshell.execDetached([scripts + "/wallpaper", "add"])
            return true
        }
        if (it.kind === "wall") {         // the launcher stays open: wallpapers can be tried one after another, Esc closes
            wallCurrent = it.path
            Quickshell.execDetached([scripts + "/wallpaper", "set", it.path])
            return true
        }
        return false
    }
    // ⌘⌫ in Background (bindings.lua → IPC deleteSelected) or Delete: a second press moves your own image to the trash.
    // Only your own images (~/Pictures/Wallpapers, `own` from hypr/scripts/wallpaper list); bundled ones can't be deleted.
    function deleteSelected() {
        const l = launcher
        if (l.level === "themes") {      // a theme of yours: a second press deletes it (the values in use stay)
            const it = l.results[l.selIndex]
            if (!it || it.kind !== "savedtheme" || !it.own) { l.shakeNow(); return true }
            if (!arm("deltheme:" + it.value)) return true
            savedList = savedList.filter(c => c.id !== it.value)
            if (l.selIndex >= l.results.length) l.select(l.results.length - 1)
            Quickshell.execDetached([scripts + "/theme", "delete", String(it.value)])
            savedReload.restart()
            return true
        }
        if (l.level !== "background" || !wallLoaded) return false
        const it = l.results[l.selIndex]
        if (!it || it.kind !== "wall" || !it.own) { l.shakeNow(); return true }
        if (!arm("del:" + it.path)) return true
        if (wallCurrent === it.path) wallCurrent = ""
        wallList = wallList.filter(w => w.path !== it.path)
        if (l.selIndex >= l.results.length) l.select(l.results.length - 1)
        Quickshell.execDetached([scripts + "/wallpaper", "remove", it.path])
        wallReload.restart()
        return true
    }
    function arm(key) {
        if (launcher.armed !== key) { launcher.armed = key; disarmTimer.restart(); return false }
        launcher.armed = ""
        return true
    }
    Timer { id: disarmTimer; interval: 4000; onTriggered: if (t.launcher) t.launcher.armed = "" }
    Timer { id: savedReload; interval: 600; onTriggered: savedProc.running = true }
    Timer { id: wallReload; interval: 600; onTriggered: wallProc.running = true }   // current wallpaper (the default, if the deleted one was in use)

    // Background: wallpapers and their previews (the script creates missing previews the first time)
    Sh {
        id: wallProc
        script: 's="$HOME/.config/hypr/scripts/wallpaper"; "$s" current; "$s" list'
        onResult: text => {
            const lines = text.split("\n").filter(l => l !== "")
            t.wallCurrent = lines.length ? lines[0] : ""
            t.wallList = lines.slice(1).map(l => l.split("\t")).filter(f => f.length >= 4)
                .map(f => ({ path: f[0], thumb: f[1], name: f[2], group: f[3], own: f[4] === "1" }))
            const first = !t.wallLoaded
            t.wallLoaded = true
            // On open, select the current wallpaper
            if (first || t.launcher.query === "") t.launcher.selectWhere(r => r.path === t.wallCurrent)
        }
    }
    // Themes: the saved themes; select the one in use
    Sh {
        id: savedProc
        command: [t.scripts + "/theme", "themes"]
        onResult: text => {
            t.savedList = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 6)
                .map(f => ({ id: f[0], name: f[1], swatch: f[2], own: f[4] === "own", state: f[5] }))
            const l = t.launcher
            if (l.level === "themes" && l.query === "") l.selectWhere(r => r.value === (t.savedList.find(c => c.state !== "") || {}).id)
        }
    }
    // Font: the fonts on trial and the current one; select the current one
    Sh {
        id: fontProc
        command: [t.scripts + "/theme", "fonts"]
        onResult: text => {
            t.fontList = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 3 && f[0] !== "")
                .map(f => ({ family: f[0], installed: f[1] === "installed", current: f[2] === "current" }))
            const l = t.launcher
            if (l.level === "themefont" && l.query === "") l.selectWhere(r => r.value === (t.fontList.find(f => f.current) || {}).family)
        }
    }
    // Color: themes and the current one; select the current one
    Sh {
        id: themeProc
        command: [t.scripts + "/theme", "list"]
        onResult: text => {
            t.themeList = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 3)
                .map(f => ({ value: f[0], name: f[1], swatch: f[2], current: f[3] === "current" }))
            const l = t.launcher
            if (l.level === "themecolor" && l.query === "") l.selectWhere(r => r.value === (t.themeList.find(c => c.current) || {}).value)
        }
    }
}
