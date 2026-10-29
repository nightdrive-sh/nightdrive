import QtQuick
import Quickshell
import qs

// VNC Display's Add a display (plugin-parts lists it while the plugin is on; Settings › Other displays' Add a display row is
// VncDisplayLevels.qml's): the sizes `vnc-display add` knows, and Other device, a small form for any other: its width
// and height in pixels, a scale shown as the size things look (as Display's Scale), and a name. Once added, the device's
// page (VncDisplayLevels.qml's vncdevice) opens.
// Launcher.qml asks it like its own level files (levels, titles, parents, items, activate, footer, entered).
Item {
    id: a
    property var launcher: null               // Launcher.qml sets it once the file is loaded

    readonly property string cmdPath: Qt.resolvedUrl("bin/vnc-display").toString().replace(/^file:\/\//, "")
    // The sizes `vnc-display add` knows, in the order a user looks for them; the summary is the models a size fits
    // (where it goes is Place on its page, afterwards)
    readonly property var kinds: [
        { device: "ipad", name: "iPad", glyph: "tablet", summary: "11-inch, Air 11" },
        { device: "ipad-13", name: "iPad 13-inch", glyph: "tablet", summary: "Air 13, Pro 13" },
        { device: "ipad-mini", name: "iPad mini", glyph: "tablet" },
        { device: "iphone", name: "iPhone", glyph: "smartphone", summary: "15, 16" },
        { device: "iphone-max", name: "iPhone Pro Max", glyph: "smartphone" },
        { device: "macbook-16", name: "MacBook Pro 16-inch", glyph: "laptop", summary: "2021 and later" }]
    // Other device's form filled in one go: common screens
    readonly property var common: [
        { w: 2560, h: 1600, name: "tablet", label: "Android tablet", glyph: "tablet", summary: "Tab S9, Pixel" },
        { w: 1920, h: 1200, name: "tablet", label: "Smaller Android tablet", glyph: "tablet", summary: "Galaxy Tab A9+" },
        { w: 1080, h: 2400, name: "phone", label: "Android phone", glyph: "smartphone" },
        { w: 1920, h: 1080, name: "laptop", label: "Laptop", glyph: "laptop", summary: "Full HD" }]
    readonly property var scales: [1, 1.25, 1.5, 2, 2.5, 3]

    property var devices: []                  // list --json, for names that are free
    property bool home: false                 // also on the home Wi-Fi (--home)
    property string network: ""               // the network the computer is on now, for that row
    property string busy: ""                  // adding: on the page's last row
    property string error: ""                 // the command's complaint
    // Other device's form
    property int formW: 0
    property int formH: 0
    property real formScale: 0                // 0 = the suggested one (suggest)
    property string formName: ""              // "" = tablet, phone or laptop, from its shape

    readonly property var levels: ["vncadd", "vncother", "vncscale"]
    readonly property var inputs: ["vncother"]   // its fields: ⌘⇧V pastes into them (ClipPicker)
    readonly property var titles: ({ vncadd: "Settings › Other displays › Add a display", vncother: "Settings › Other displays › Add a display › Other device",
                                     vncscale: "Settings › Other displays › Add a display › Other device › Scale" })
    readonly property var parents: ({ vncadd: "otherdisplays", vncother: "vncadd", vncscale: "vncother" })

    // The device page's spelling (iPad, MacBook), so both levels name a device alike
    function label(n) { return display() ? display().label(n) : n }
    function display() { return launcher.pluginExts.find(e => e.levels.indexOf("vncdevice") >= 0) || null }
    // ipad, then ipad2, ipad3…: `add` refuses a name that's taken
    function freeName(base) {
        if (!devices.some(d => d.name === base)) return base
        for (let n = 2; ; n++) if (!devices.some(d => d.name === base + n)) return base + n
    }

    // The scale that makes things about the size they are on such a device: a tablet's or laptop's short side ~800 px
    // as things look (an iPad 11: 820), a phone's ~400 (an iPhone: 393)
    function suggest(w, h) {
        const target = w >= h ? 800 : 400
        return scales.reduce((best, s) => Math.abs(Math.min(w, h) / s - target) < Math.abs(Math.min(w, h) / best - target) ? s : best, 1)
    }
    readonly property bool sized: formW > 0 && formH > 0
    readonly property real useScale: formScale || (sized ? suggest(formW, formH) : 2)
    readonly property string useName: formName || (formW > 0 && formW < formH ? "phone" : "tablet")
    function looks(s) { return Math.round(formW / s) + " × " + Math.round(formH / s) }

    function footer(level, query) {
        if (level === "vncadd") return "Enter: add, and turn its display on"
        if (level === "vncother") return launcher.fieldRow ? (query.trim() !== "" ? "Enter: set" : "Type the value") : "Enter: change, or add the display"
        return ""
    }
    function opened() { listProc.running = true }
    function entered(level) {
        error = ""
        if (level === "vncadd") { netProc.running = true; listProc.running = true }
    }
    function shiftActivate(it) {}
    // Leaving Add for Display: the next Add starts afresh
    Connections {
        target: a.launcher
        function onLevelChanged() {
            if (a.launcher.level === "otherdisplays") { a.home = false; a.formW = 0; a.formH = 0; a.formScale = 0; a.formName = "" }
        }
    }

    function items(level, q) {
        const l = launcher
        const tail = rows => {
            if (busy !== "") rows.push({ kind: "hint", name: busy })
            if (error !== "") rows.push({ kind: "note", name: error })
            return rows
        }
        if (level === "vncadd") {
            return tail([{ kind: "vnchome", name: "Also on the home Wi-Fi", glyph: "wifi", switchOn: home,
                           summary: network !== "" ? network : "not on a network now" },
                         { kind: "header", name: "Device" }]
                .concat(kinds.map(k => Object.assign({ kind: "vncnew" }, k)),
                        [{ kind: "nav", name: "Other device", glyph: "monitor-smartphone", target: "vncother", summary: "any size" }]))
        }
        if (level === "vncother") {
            // Width, height and name are fields: typed into their rows (FieldBox.qml), set with Enter
            return tail([{ kind: "vncfield", key: "width", field: true, name: "Width", glyph: "move-horizontal", unit: " px",
                           summary: formW ? formW + " px" : "", placeholder: "pixels" },
                         { kind: "vncfield", key: "height", field: true, name: "Height", glyph: "move-vertical", unit: " px",
                           summary: formH ? formH + " px" : "", placeholder: "pixels" },
                         { kind: "nav", name: "Scale", glyph: "zoom-in", target: "vncscale",
                           summary: sized ? "looks like " + looks(useScale) + " · " + useScale : "–" },
                         { kind: "vncfield", key: "name", field: true, name: "Name", glyph: "tag", summary: useName },
                         { kind: "vncform", name: "Add the display", glyph: "plus", dimmed: !sized,
                           summary: sized ? undefined : "its width and height first" },
                         { kind: "header", name: "Common sizes" }]
                .concat(common.map(c => ({ kind: "vncfill", c: c, name: c.label, glyph: c.glyph,
                                           summary: (c.summary ? c.summary + " · " : "") + c.w + " × " + c.h }))))
        }
        if (level === "vncscale") {
            if (!sized) return l.hint("Its width and height first")
            const best = suggest(formW, formH)
            return scales.map(s => ({ kind: "vncpick", value: s, name: looks(s), glyph: s === useScale ? "check" : "monitor",
                                      summary: "scale " + s + (s === best ? " · suggested" : "") }))
        }
        return []
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "vnchome") {
            if (network === "") { l.shakeNow(); return true }
            l.keepSelection(); home = !home; return true
        }
        if (it.kind === "vncnew") { add(it.device, freeName(it.device.split("-")[0])); return true }
        if (it.kind === "vncfield") {   // Enter: set, then on to the next row
            if (l.query.trim() !== "" && !commitField(it, l.query)) return true
            l.clearQuery(); l.keepSelection(); l.step(1)
            return true
        }
        if (it.kind === "vncpick") { formScale = it.value; l.back(); return true }
        if (it.kind === "vncfill") {
            l.keepSelection()
            formW = it.c.w; formH = it.c.h; formScale = 0; formName = freeName(it.c.name)
            return true
        }
        if (it.kind === "vncform") {
            if (!sized) { l.shakeNow(); return true }
            add(formW + "x" + formH + "@" + useScale, formName ? formName : freeName(useName))
            return true
        }
        return false
    }

    // A field's value, on Enter or on leaving its row (Launcher.qml's leaveField): a pixel count, or a name as `add`
    // takes it. False (and a shake) if it isn't one
    function commitField(it, text) {
        const t = text.trim().toLowerCase(), n = parseInt(t, 10)
        if (it.key === "name" ? !/^[a-z0-9][a-z0-9-]{0,15}$/.test(t) : !/^\d+$/.test(t) || n < 320 || n > 8192) { launcher.shakeNow(); return false }
        launcher.keepSelection()
        if (it.key === "width") formW = n; else if (it.key === "height") formH = n; else formName = t
        return true
    }

    // Adds and turns its screen on, then opens its page
    function add(device, name) {
        if (cmd.running) return
        launcher.keepSelection()
        busy = "Adding " + label(name) + "…"; error = ""
        cmd.added = name
        // As a script for its complaints on stderr; the words are sizes and names checked above ([a-z0-9x@.-])
        cmd.script = '"' + cmdPath + '" add ' + device + " " + name + (home ? " --home" : "")
        cmd.running = true
    }
    Sh {
        id: cmd
        property string added: ""
        onResult: text => {
            const l = a.launcher
            l.keepSelection()
            a.busy = ""
            if (cmd.exitCode !== 0) {
                a.error = text.split("\n").filter(t => t.startsWith("vnc-display: ")).map(t => t.slice(13)).join(" ")
                          || "Didn't work: " + text.trim().split("\n").pop()
                return
            }
            listProc.running = true
            const d = a.display()
            if (d && (l.level === "vncadd" || l.level === "vncother")) { d.cur = cmd.added; d.refresh(); l.go("vncdevice") }
        }
    }
    Sh {
        id: listProc
        command: [a.cmdPath, "list", "--json"]
        onResult: text => { try { a.devices = JSON.parse(text) } catch (e) { a.devices = [] } }
    }
    Sh {
        id: netProc
        command: [a.cmdPath, "network"]
        onResult: text => { a.launcher.keepSelection(); a.network = text.trim() }
    }
}
