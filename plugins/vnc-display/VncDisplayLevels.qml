import QtQuick
import Quickshell
import qs

// VNC Display's part of the launcher (plugin-parts lists it while the plugin is on): its rows in Settings › Other displays
// (displayRows: each device, on or off, and Add a display, whose pages are VncAddLevels.qml's), and a device's page (its
// screen on or off, its workspace, place, size (VncAddLevels.qml's form) and name, how to connect, remove). bin/vnc-display does the work; this reads
// `list --json` and `show NAME --json`.
// The password stays out of the rows until asked for (Enter on its row, or the QR card: VncDisplayCard.qml), so a
// screenshot of the launcher doesn't give it away.
// Launcher.qml asks it like its own level files (levels, titles, parents, items, activate, footer, entered).
Item {
    id: v
    property var launcher: null               // Launcher.qml sets it once the file is loaded

    readonly property string cmdPath: Qt.resolvedUrl("bin/vnc-display").toString().replace(/^file:\/\//, "")

    property var devices: []                  // list --json: [{ name, size, place, workspace, port, on, tailscale, home }]
    property string cur: ""                   // the device whose page is open
    property var info: null                   // its show --json (the password too), null while loading
    property bool reveal: false               // its password shown on its row: until leaving the page
    property string busy: ""                  // a command running: what it is doing, on the page's last row
    property string error: ""                 // the last command's complaint

    readonly property var levels: ["vncdevice", "vncws", "vncplace"]
    readonly property var inputs: ["vncdevice"]   // its Name field: ⌘⇧V pastes into it (ClipPicker)
    // virtual-display.lua's places: a side of the desk's screens, or out of the pointer's reach
    // "your display", or "displays" with more than one at the desk: the side is counted from all of them
    readonly property string yours: Quickshell.screens.filter(s => !s.name.startsWith("HEADLESS-")).length > 1 ? "your displays" : "your display"
    readonly property var places: [["right", "Right of " + yours, "arrow-right"], ["left", "Left of " + yours, "arrow-left"],
                                   ["above", "Above " + yours, "arrow-up"], ["below", "Below " + yours, "arrow-down"],
                                   ["away", "Away", "circle-off"]]
    function placeName(p) { const f = places.find(x => x[0] === (p === "beside" ? "right" : p)); return f ? f[1] : p }
    readonly property var titles: ({ vncdevice: "Settings › Other displays › " + label(cur),
                                     vncws: "Settings › Other displays › " + label(cur) + " › Workspace",
                                     vncplace: "Settings › Other displays › " + label(cur) + " › Place" })
    readonly property var parents: ({ vncdevice: "otherdisplays", vncws: "vncdevice", vncplace: "vncdevice" })

    function label(n) {
        if (/^(ip(ad|hone)|macbook)/.test(n)) return n.replace(/^ipad/, "iPad").replace(/^iphone/, "iPhone").replace(/^macbook/, "MacBook")
        return n.charAt(0).toUpperCase() + n.slice(1)
    }
    // Taller than wide: a phone's icon
    function phone(d) { const m = String(d.size || "").match(/^(\d+)x(\d+)/); return m !== null && +m[1] < +m[2] }
    function addr(host, port) { return host + ":" + port }

    // Settings › Other displays, with AirPlay's (DisplayLevels.qml asks every plugin's file for displayRows); `active`: on.
    // On, the display is there only while the device is connected (lib/serve.py): until then it waits for it
    function displayRows() {
        const r = []
        for (const d of devices)
            r.push({ kind: "vncopen", dev: d.name, name: label(d.name), glyph: phone(d) ? "smartphone" : /^macbook/.test(d.name) ? "laptop" : /^display/.test(d.name) ? "monitor" : "tablet",
                     summary: !d.on ? "off" : d.connected ? "connected · workspace " + d.workspace : "on · waiting for the device",
                     active: d.on })
        r.push({ kind: "nav", name: "Add a display", glyph: "plus", target: "vncadd",
                 summary: devices.length === 0 ? "an iPad, iPhone or any device with a VNC app" : undefined })
        return r
    }

    function footer(level, query) {
        if (level === "vncdevice") return "Enter: the display on or off, show the password, copy the address or the shown password"
        return ""
    }
    function opened() { listProc.running = true }
    function refresh() { listProc.running = true }   // VncAddLevels.qml, once it has added one
    function entered(level) {
        error = ""
        if (level === "vncdevice") { reveal = false; info = null; showProc.running = true }
    }
    function shiftActivate(it) {}

    // The display level isn't this file's, so its entering isn't told here: the list is read again on the way in
    Connections {
        target: v.launcher
        function onLevelChanged() {
            if (v.launcher.level === "otherdisplays" || v.launcher.level === "settings") listProc.running = true
            if (v.launcher.level !== "vncdevice") { v.reveal = false; v.info = null }   // the password not kept around
        }
    }
    function items(level, q) {
        const l = launcher
        if (level === "vncdevice") {
            if (info === null) return l.hint(error !== "" ? error : "Loading…")
            const i = info
            const rows = [{ kind: "vncswitch", name: "Display", glyph: phone(dev()) ? "smartphone" : "tablet", switchOn: i.on },   // the workspace is on its own row
                          { kind: "nav", name: "Workspace", glyph: "layout-grid", target: "vncws", summary: "⌘" + i.workspace },
                          { kind: "nav", name: "Place", glyph: "move", target: "vncplace", summary: placeName(dev().place) },
                          { kind: "vncsize", name: "Size", glyph: "scaling", summary: sizeName(dev()) },
                          // Typed into in place (FieldBox.qml), set with Enter or by leaving the row: rename
                          { kind: "vncname", key: "name", field: true, name: "Name", glyph: "tag", summary: cur },
                          { kind: "header", name: "Connect" },
                          { kind: "vncqr", name: "Show QR code", glyph: "qr-code" },
                          { kind: "stat", name: "Address", glyph: "globe", summary: addr(i.tailscale, i.port),
                            copy: addr(i.tailscale, i.port) }]
            if (i.tailscale !== i.tailscale_ip && i.tailscale_ip !== "")
                rows.push({ kind: "stat", name: "IP address", glyph: "globe", summary: addr(i.tailscale_ip, i.port),
                            copy: addr(i.tailscale_ip, i.port) })
            if (i.home_name)
                rows.push({ kind: "stat", name: "At home", glyph: "house", copy: i.home ? addr(i.home, i.port) : undefined,
                            summary: i.home ? addr(i.home, i.port) + " · on " + i.home_name : "on " + i.home_name + " · not on it now" })
            // DES, the only login macOS's Screen Sharing has for wayvnc: off unless this device needs it (#1926)
            rows.push({ kind: "vncshare", name: "macOS Screen Sharing", glyph: "laptop", switchOn: i.screen_sharing === true,
                        summary: "the old VNC password, over Tailscale" })
            rows.push({ kind: "stat", name: "User", glyph: "user", summary: i.username, copy: i.username },
                      // Enter shows it; shown, Enter and ⌘C copy it past the clipboard history (the launcher's `sensitive`)
                      reveal ? { kind: "stat", name: "Password", glyph: "eye", summary: i.password, copy: i.password, sensitive: true }
                             : { kind: "vncpass", name: "Password", glyph: "eye-off", summary: "•".repeat(i.password.length) },
                      { kind: "header", name: "" },
                      { kind: "vncremove", name: "Remove " + label(cur), glyph: "trash-2", armKey: "vncrm:" + cur,
                        armHint: "Enter again: remove, its password stops working", summary: "its display and its password" })
            if (busy !== "") rows.push({ kind: "hint", name: busy })
            if (error !== "") rows.push({ kind: "note", name: error })
            return rows
        }
        if (level === "vncws") {
            // 2–9, as virtual-display.lua and the top bar's device icons (1 is the main screen's): one another device has is swapped with it
            const mine = (dev().workspace) || 0
            const rows = [9, 8, 7, 6, 5, 4, 3, 2].map(w => {
                const other = devices.find(d => d.name !== cur && d.workspace === w)
                return { kind: "vncws", ws: w, name: "Workspace " + w, glyph: w === mine ? "check" : "layout-grid",
                         summary: w === mine ? "current · ⌘" + w : other ? label(other.name) + "'s: swaps with it" : "⌘" + w }
            })
            if (busy !== "") rows.push({ kind: "hint", name: busy })
            if (error !== "") rows.push({ kind: "note", name: error })
            return rows
        }
        if (level === "vncplace") {
            const mine = dev().place === "beside" ? "right" : dev().place
            const rows = places.map(([p, name, glyph]) => ({ kind: "vncplace", place: p, name: name, glyph: p === mine ? "check" : glyph,
                summary: p === mine ? "current" : p === "away" ? "out of the pointer's reach" : undefined }))
            if (busy !== "") rows.push({ kind: "hint", name: busy })
            if (error !== "") rows.push({ kind: "note", name: error })
            return rows
        }
        return []
    }
    function dev() { return devices.find(d => d.name === cur) || {} }
    // "2360 × 1640 · looks like 1180 × 820": the pixels, and the size things look at its scale, as Add a display shows it
    function sizeName(d) {
        const m = String(d.size || "").match(/^(\d+)x(\d+)/)
        if (!m) return ""
        const s = d.scale || 1
        return m[1] + " × " + m[2] + " · looks like " + Math.round(m[1] / s) + " × " + Math.round(m[2] / s)
    }
    function adder() { return launcher.pluginExts.find(e => e.levels.indexOf("vncother") >= 0) || null }

    function activate(it) {
        const l = launcher
        if (it.kind === "vncopen") { cur = it.dev; l.go("vncdevice"); return true }
        if (it.kind === "vncswitch") {
            l.keepSelection()
            run(info.on ? "Turning the display off…" : "Turning the display on…", [info.on ? "off" : "on", cur])
            return true
        }
        if (it.kind === "vncws") {
            if (it.ws === dev().workspace) { l.back(); return true }
            run("Moving to workspace " + it.ws + "…", ["workspace", cur, String(it.ws)], () => { if (l.level === "vncws") l.back() })
            return true
        }
        if (it.kind === "vncplace") {
            run("Moving…", ["place", cur, it.place], () => { if (l.level === "vncplace") l.back() })
            return true
        }
        if (it.kind === "vncsize") { if (adder()) adder().edit(dev()); return true }
        if (it.kind === "vncname") {   // Enter: rename to what was typed
            // The row kept first: run()'s busy row resets the list's selection at once, so later it would keep that
            l.keepSelection()
            const text = l.query
            l.clearQuery()
            if (text.trim() !== "") commitField(it, text)
            return true
        }
        if (it.kind === "vncshare") {
            run(info.screen_sharing ? "Turning Screen Sharing off…" : "Turning Screen Sharing on…",
                ["screen-sharing", cur, info.screen_sharing ? "off" : "on"])
            return true
        }
        if (it.kind === "vncpass") { l.keepSelection(); reveal = true; return true }
        if (it.kind === "vncqr") { card.show(info); l.open = false; return true }
        if (it.kind === "vncremove") {
            if (l.armed !== it.armKey) { l.keepSelection(); l.armed = it.armKey; disarm.restart(); return true }
            l.armed = ""
            run("Removing…", ["remove", cur], () => { if (l.level === "vncdevice") l.back() })
            return true
        }
        return false
    }
    // The Name field's value, on Enter or on leaving its row (Launcher.qml's leaveField): a name as `rename` takes it.
    // The page follows the device to its new name
    function commitField(it, text) {
        const t = text.trim().toLowerCase()
        if (!/^[a-z0-9][a-z0-9-]{0,15}$/.test(t)) { launcher.shakeNow(); return false }
        if (t === cur) return true
        if (devices.some(d => d.name === t)) { error = label(t) + " is already a device's name"; return false }
        run("Renaming…", ["rename", cur, t], () => { cur = t })
        return true
    }
    property var after: null                  // what to do once the running command has succeeded
    function run(what, args, then) {
        if (cmd.running) return
        launcher.keepSelection()
        busy = what; error = ""; after = then || null
        // As a script for its complaints on stderr; the words are the command's own and names from `list` ([a-z0-9-])
        cmd.script = '"' + cmdPath + '" ' + args.join(" ")
        cmd.running = true
    }
    Sh {
        id: cmd
        onResult: text => {
            const ok = cmd.exitCode === 0
            v.launcher.keepSelection()
            v.busy = ""
            // Its own complaints only: on success the command prints the login, which isn't shown here
            v.error = ok ? "" : text.split("\n").filter(t => t.startsWith("vnc-display: ")).map(t => t.slice(13)).join(" ")
                                || "Didn't work: " + text.trim().split("\n").pop()
            if (ok && v.after) v.after()
            v.after = null
            listProc.running = true
            if (v.launcher.level === "vncdevice") showProc.running = true
        }
    }
    Timer { id: disarm; interval: 4000; onTriggered: if (v.launcher.armed.startsWith("vncrm:")) v.launcher.armed = "" }

    Sh {
        id: listProc
        command: [v.cmdPath, "list", "--json"]
        onResult: text => {
            let d = []
            try { d = JSON.parse(text) } catch (e) {}
            if (JSON.stringify(d) === JSON.stringify(v.devices)) return
            v.launcher.keepSelection()
            v.devices = d
        }
    }
    Sh {
        id: showProc
        command: [v.cmdPath, "show", v.cur, "--json"]
        onResult: text => {
            v.launcher.keepSelection()
            try { v.info = JSON.parse(text) } catch (e) { v.info = null; v.error = text.trim() }
        }
    }

    VncDisplayCard { id: card }
}
