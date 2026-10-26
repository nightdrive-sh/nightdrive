pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The top bar's data (Bar.qml draws it). Everything is read from files that are watched, so edits show at once:
//   ~/.config/topbar/modules.jsonc (+ local.modules.jsonc)   the modules, in order
//   ~/.config/topbar/adjust.conf   (+ local.adjust.conf)     icon and text sizes
//   ~/.cache/nightdrive/plugins.d/bar.json                    the installed plugin folders' modules, menus and icon sizes
//                                                             (hypr/scripts/plugin-parts)
//   ~/.cache/nightdrive/bar.json                              colours (hypr/scripts/bar-style)
//   ~/.local/state/nightdrive/bar-items.json                  {hidden, order}: modules turned off and their order
//                                                             (launcher › Settings › Top bar › Items, ⌘+drag in the bar)
// A module's state comes from its status command (one line of JSON {icon, text, class}); icons are SVGs from
// topbar/scripts/icon, cached here by name.
Singleton {
    id: tb
    readonly property string dir: Quickshell.env("HOME") + "/.config/topbar"

    // --- Modules ---
    property var publicModules: []
    property var localModules: []
    // The plugin folders' parts: { modules, menus: { name: path of its <Name>Menu.qml }, sizes: { name: px },
    // levels: [paths of its <Name>Levels.qml, the launcher's] }
    property var plugin: ({ modules: [], menus: ({}), sizes: ({}), levels: [] })
    FileView {
        path: Quickshell.env("HOME") + "/.cache/nightdrive/plugins.d/bar.json"; watchChanges: true; onFileChanged: reload(); printErrors: false
        onLoaded: {
            let v = null
            try { v = JSON.parse(text()) } catch (e) {}
            if (v) tb.plugin = { modules: v.modules || [], menus: v.menus || {}, sizes: v.sizes || {}, levels: v.levels || [] }
        }
        onLoadFailed: tb.plugin = ({ modules: [], menus: ({}), sizes: ({}), levels: [] })
    }
    // The files' order: a plugin's module goes right of the one its "after" names, or left of its "before" (at the right
    // end without either). Either can be a list: the first name in the bar counts (Home Assistant: before Deck, or before
    // Claude without Deck). Plugins after (or before) the same module keep the folders' order (Ferry, then Tailscale, after
    // System), as they were in modules.jsonc.
    function withPlugins(list) {
        const out = list.slice()
        const names = v => Array.isArray(v) ? v : (v ? [v] : [])
        const place = (m, key) => {      // { i: index, n: name } of the first of its names in the bar, or null
            for (const n of names(m[key])) {
                const i = out.findIndex(o => o.name === n)
                if (i >= 0) return { i: i, n: n }
            }
            return null
        }
        for (const m of plugin.modules) {
            const a = place(m, "after"), b = a ? null : place(m, "before")
            if (a) {
                let i = a.i
                while (i + 1 < out.length && names(out[i + 1].after).indexOf(a.n) >= 0) i++
                out.splice(i + 1, 0, m)
            } else if (b) out.splice(b.i, 0, m)   // right of the earlier folders' modules before the same one
            else out.push(m)
        }
        return out
    }
    // In your order (Items: Ctrl+arrows, or ⌘+drag in the bar), then modules not in it in the files' order (a new one goes
    // to the right end).
    // A module whose optional part isn't installed ("needs") isn't listed at all. One with "first" stays at the left end
    // whatever the order: it comes and goes (the microphone and camera in use), and there it doesn't shift the others.
    readonly property var allModules: {
        const def = localModules.concat(withPlugins(publicModules)).filter(m => !m.needs || Plugins.has(m.needs))
        const key = m => { const i = items.order.indexOf(m.name); return (m.first ? -1e6 : 0) + (i >= 0 ? i : items.order.length + def.indexOf(m)) }
        return def.slice().sort((a, b) => key(a) - key(b))
    }
    // The ones shown: a module turned off isn't run at all
    readonly property var modules: allModules.filter(m => hidden.indexOf(m.name) < 0)
    readonly property var hidden: items.hidden
    property var items: ({ hidden: [], order: [] })
    readonly property string itemsFile: Quickshell.env("HOME") + "/.local/state/nightdrive/bar-items.json"
    FileView {
        path: tb.itemsFile; watchChanges: true; onFileChanged: reload(); printErrors: false
        // Only a real change: the same lists again would rebuild the launcher's list and lose its selection
        onLoaded: {
            let v = {}
            try { v = JSON.parse(text()) || {} } catch (e) {}
            const n = { hidden: v.hidden || [], order: v.order || [] }
            if (JSON.stringify(n) !== JSON.stringify(tb.items)) tb.items = n
        }
        onLoadFailed: tb.items = ({ hidden: [], order: [] })
    }
    // Shown at once here, then saved (the file watch brings the same lists back)
    function saveItems(n) {
        items = n
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$2")" && printf "%s\\n" "$1" > "$2.tmp" && mv "$2.tmp" "$2"',
                                 "_", JSON.stringify(n), itemsFile])
    }
    function setHidden(name, off) {
        saveItems({ hidden: items.hidden.filter(n => n !== name).concat(off ? [name] : []), order: items.order })
    }
    // Moves a module one place left (-1) or right (+1); returns its new index in allModules
    function move(name, dir) {
        const names = allModules.map(m => m.name)
        const i = names.indexOf(name), j = i + dir
        if (i < 0 || j < 0 || j >= names.length) return i
        names[i] = names[j]; names[j] = name
        saveItems({ hidden: items.hidden, order: names })
        return j
    }
    // The shown modules in a new order (⌘+drag in the bar); the hidden ones keep their places between them
    function reorder(shown) {
        if (shown.length !== modules.length) return
        let k = 0
        const names = allModules.map(m => hidden.indexOf(m.name) < 0 ? shown[k++] : m.name)
        if (names.join() !== allModules.map(m => m.name).join()) saveItems({ hidden: items.hidden, order: names })
    }
    // Names and glyphs for the launcher's list; a module can give its own "label" and "glyph" in modules.jsonc
    readonly property var moduleLabels: ({ claude: ["Claude", "gauge"], system: ["CPU and memory", "cpu"],
                                           bluetooth: ["Bluetooth", "bluetooth"], wifi: ["Wi-Fi", "wifi"],
                                           volume: ["Volume", "volume-2"], headphones: ["Headphones", "headphones"], display: ["Display", "monitor"], battery: ["Battery", "battery-medium"],
                                           calendar: ["Date and time", "clock"], notifications: ["Notifications", "menu"],
                                           microphone: ["Microphone in use", "mic"], camera: ["Camera in use", "video"] })
    function moduleLabel(m) { return m.label || (moduleLabels[m.name] || [])[0] || m.name.charAt(0).toUpperCase() + m.name.slice(1) }
    function moduleGlyph(m) { return m.glyph || (moduleLabels[m.name] || [])[1] || "panel-top" }
    property var states: ({})          // name -> {icon, text, class}
    // The modules in the "…" menu (OverflowMenu.qml) of the bar that opened it last: [{ def, menu }] (Bar.qml)
    property var overflow: []
    function parseJsonc(t) {
        try { return JSON.parse(t.split("\n").filter(l => !/^\s*\/\//.test(l)).join("\n")) } catch (e) { return null }
    }
    FileView {
        path: tb.dir + "/modules.jsonc"; watchChanges: true; onFileChanged: reload()
        onLoaded: tb.publicModules = tb.parseJsonc(text()) || tb.publicModules
    }
    FileView {
        path: tb.dir + "/local.modules.jsonc"; watchChanges: true; onFileChanged: reload(); printErrors: false   // optional (an overlay)
        onLoaded: tb.localModules = tb.parseJsonc(text()) || tb.localModules
        onLoadFailed: tb.localModules = []
    }

    property var runners: ({})
    Instantiator {
        model: tb.modules
        delegate: Scope {
            id: runner
            required property var modelData
            readonly property string name: modelData.name
            function run() { if (!proc.running) proc.running = true }
            Component.onCompleted: tb.runners[name] = runner
            Component.onDestruction: if (tb.runners[name] === runner) delete tb.runners[name]
            Process {
                id: proc
                command: ["bash", "-c", runner.modelData.status || ("~/.config/topbar/scripts/status " + runner.name)]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const line = text.trim().split("\n").pop() || ""
                        if (JSON.stringify(tb.states[runner.name]) === line) return
                        let s = null
                        try { s = JSON.parse(line) } catch (e) {}
                        const n = Object.assign({}, tb.states); n[runner.name] = s; tb.states = n
                    }
                }
            }
            Timer {
                interval: (runner.modelData.interval || 5) * 1000
                running: true; repeat: true; triggeredOnStart: true
                onTriggered: runner.run()
            }
        }
    }
    // Updates one module now, or all of them ("": also re-reads the icons, e.g. after adding an SVG)
    function refresh(name) {
        if (!name) svgs = ({})
        for (const k in runners) if (!name || k === name) runners[k].run()
    }
    // Right / middle click: the module's command, then an update of the module. args: extra arguments ("$@"), e.g.
    // the files dropped on it
    function run(cmd, name, args) {
        const p = cmdProc.createObject(tb, { command: ["bash", "-c", args ? cmd + ' "$@"' : cmd, "_"].concat(args || []), name: name })
        p.running = true
    }
    Component {
        id: cmdProc
        Process {
            property string name
            onExited: { tb.refresh(name); destroy() }
        }
    }

    // --- Sizes: rows "element size" (an old third column, y, is ignored); text = every text, icon = icons without a row
    // of their own (or a plugin module's "size") ---
    property var sizesPublic: ({})
    property var sizesLocal: ({})
    function parseSizes(t) {
        const out = {}
        for (const line of t.split("\n")) {
            const f = line.split("#")[0].trim().split(/\s+/)
            if (f.length >= 2 && !isNaN(parseFloat(f[1]))) out[f[0]] = { size: parseFloat(f[1]) }
        }
        return out
    }
    FileView {
        path: tb.dir + "/adjust.conf"; watchChanges: true; onFileChanged: reload()
        onLoaded: tb.sizesPublic = tb.parseSizes(text())
    }
    FileView {
        path: tb.dir + "/local.adjust.conf"; watchChanges: true; onFileChanged: reload(); printErrors: false
        onLoaded: tb.sizesLocal = tb.parseSizes(text())
        onLoadFailed: tb.sizesLocal = ({})
    }
    function size(el) {
        return sizesLocal[el] || sizesPublic[el] || (plugin.sizes[el] ? { size: plugin.sizes[el] } : null)
            || (el === "text" ? { size: 13 } : sizesPublic.icon || { size: 16 })
    }

    // --- Colours (bar-style); defaults = white icons on black ---
    property var col: ({})
    FileView {
        path: Quickshell.env("HOME") + "/.cache/nightdrive/bar.json"; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { tb.col = JSON.parse(text()) } catch (e) {} }
    }
    function c(k) {
        return col[k] || { bg: "#ff000000", fg: "#d9ffffff", dim: "#8cffffff", off: "#57ffffff", hlBg: "#4db17bcb",
                           hlFg: "#ffffff", actBg: "#40c071eb", wsBg: "#4db17bcb" }[k]
    }

    // --- Icons: SVG text by name ("" = not found); fetched once, then cached ---
    // A missing one is asked again after 5 s and 30 s: a branch switch removes a plugin's icon links for a moment
    // (link.sh puts them back), and the bar reloading in between would otherwise keep the icon blank.
    property var svgs: ({})
    property var loading: ({})
    property var misses: ({})
    function svg(ref) {
        if (!ref) return ""
        if (svgs[ref] !== undefined) return svgs[ref]
        const g = ref.match(/^gauge@(\d+)$/)
        if (g) return gauge(Math.min(100, parseInt(g[1])))
        if (!loading[ref]) {
            loading[ref] = true
            iconProc.createObject(tb, { ref: ref }).running = true
        }
        return ""
    }
    Component {
        id: iconProc
        Process {
            id: ip
            property string ref
            command: [tb.dir + "/scripts/icon", ref]
            stdout: StdioCollector {
                onStreamFinished: {
                    const found = text.indexOf("<svg") >= 0
                    const n = Object.assign({}, tb.svgs); n[ip.ref] = found ? text : ""; tb.svgs = n
                    delete tb.loading[ip.ref]
                    const tries = found ? 0 : (tb.misses[ip.ref] || 0) + 1
                    tb.misses[ip.ref] = tries
                    if (tries === 1 || tries === 2) iconRetry.createObject(tb, { ref: ip.ref, interval: tries === 1 ? 5000 : 30000 })
                    ip.destroy()
                }
            }
        }
    }
    Component {     // drops a missing icon from the cache, so the next svg() asks for it again
        id: iconRetry
        Timer {
            id: ir
            property string ref
            running: true
            onTriggered: {
                const n = Object.assign({}, tb.svgs); delete n[ir.ref]; tb.svgs = n
                ir.destroy()
            }
        }
    }
    // gauge@<percent>: Lucide's gauge with its needle pointing at the percentage (the Claude module's usage). The dial is
    // the arc around (12, 14) from lower left (0 %, 210°) over the top to lower right (100 %, -30°).
    function gauge(p) {
        const a = (210 - 2.4 * p) * Math.PI / 180, len = 5.66
        const x = (12 + len * Math.cos(a)).toFixed(2), y = (14 - len * Math.sin(a)).toFixed(2)
        return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
             + 'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 14 L' + x + ' ' + y + '"/>'
             + '<path d="M3.34 19a10 10 0 1 1 17.32 0"/></svg>'
    }
    // An SVG drawn in one colour: currentColor -> the colour (opaque; the caller applies its alpha as opacity)
    function iconUrl(ref, color) {
        const s = svg(ref)
        if (!s) return ""
        const rgb = Qt.rgba(color.r, color.g, color.b, 1).toString()
        return "data:image/svg+xml;utf8," + encodeURIComponent(s.replace(/currentColor/g, rgb))
    }
}
