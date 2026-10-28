import QtQuick
import Quickshell

// The launcher's Settings › Display (brightness, night light, Screen Mirroring's rows from SystemLevels.qml, where the
// laptop's screen is next to an external one, the keyboard's backlight, and each output's scales and refresh rates) and Battery (charge and state, then the details, as in the top bar's battery menu).
// The brightness rows (screen, keyboard: the row's key) are sliders that Launcher.qml draws (bright, keys, setBright) and
// ←/→ steps (stepBright), also in the root search; Launcher.qml's displayItems() puts them there.
// Launcher.qml asks it like DefaultAppsLevels (levels, titles, parents, items, activate, footer, entered).
Item {
    id: p
    property var launcher: null

    property var displays: null               // [{ name, desc, scale, opts: [{ value, size }] }] (hypr/scripts/display list)
    property var rates: ({})                  // { output: { current, chosen: hz or "auto", hz: [...] } } (display rates)
    property string side: ""                  // the laptop's screen: left | right | above | below | auto (display side)
    property real bright: -1                  // Brightness: 0..1 (brightnessctl), -1 = no backlight (a VM) or not read yet
    property real pendingBright: -1           // the slider's value waiting to be applied (throttled)
    property real keys: -1                    // Keyboard backlight: 0..1, -1 = none (a desktop) or not read yet
    property real pendingKeys: -1
    property string night: ""                 // Night light: on | off (hypr/scripts/nightlight status)
    property var batt: null                   // Battery: { percent, state, timeText } (upower)
    property var battDetail: null             // and its details (topbar/scripts/sysinfo battery), null on a desktop
    property bool hasBattery: false           // the machine has its own battery: Settings lists Battery only then
    readonly property int brightStep: 5       // ←/→ on the brightness row, the same step as the brightness keys (hypr/scripts/brightness)

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    readonly property var levels: ["display", "otherdisplays", "battery"]
    readonly property var titles: ({ display: "Settings › Display", otherdisplays: "Settings › Other displays", battery: "Settings › Battery" })
    readonly property var parents: ({ display: "settings", otherdisplays: "settings", battery: "settings" })

    // Settings › Other displays: the screens beyond this computer's, by device, however they connect: AirPlay's
    // (Screen Mirroring, SystemLevels.qml's mirrorRows, empty without doubletake) and a plugin's (displayRows: VNC
    // Display's iPads), as macOS's "Mirror or extend to". Display is this computer's own screens only.
    function others() {
        const l = launcher
        if (!l) return []
        return [...l.mirrorRows(), ...[].concat(...l.pluginExts.map(e => e.displayRows ? e.displayRows() : []))].filter(r => r.kind !== "header")
    }
    function hasOthers() { return launcher !== null && (launcher.mirrorRows().length > 0 || launcher.pluginExts.some(e => e.displayRows)) }
    // On Settings' row: what is in use now ("iPad, iPhone on"), else nothing
    function othersSummary() {
        const on = others().filter(r => r.active === true).map(r => r.name)
        return on.length > 0 ? on.join(", ") + " on" : undefined
    }

    // The brightness and night light rows' footers are Launcher.qml's: the root search has them too
    function footer(level, query) { return "" }
    // On every open: the root search has the brightness and night light rows too
    function opened() { brightProc.running = true; keysProc.running = true; nightProc.running = true }
    function entered(level) {
        if (level === "display") { displayProc.running = true; ratesProc.running = true; sideProc.running = true; brightProc.running = true; keysProc.running = true; nightProc.running = true }
        if (level === "battery") { battProc.running = true; battDetailProc.running = true }
    }
    function shiftActivate(it) {}

    function items(level, q) {
        const l = launcher
        if (level === "display") {
            // Brightness (slider rows for the screen and the keyboard, when they have a backlight, and night light), then Scale
            if (displays === null) return l.hint("Loading…")
            // The desk's own: a virtual screen (HEADLESS-*, an iPad over VNC) has its size and place from its plugin
            const desk = displays.filter(d => !/^HEADLESS-/.test(d.name))
            const out = bright < 0 ? [] : [{ kind: "brightness", key: "screen", name: "Screen", glyph: "sun", summary: Math.round(bright * 100) + "%" }]
            if (keys >= 0) out.push({ kind: "brightness", key: "keys", name: "Keyboard", glyph: "keyboard", summary: Math.round(keys * 100) + "%" })
            if (night !== "") out.push({ kind: "nightlight", name: "Night light", glyph: "moon", switchOn: night === "on" })
            if (out.length > 0) out.unshift({ kind: "header", name: "Brightness" })
            // Scales the panel divides evenly, shown as the resulting desktop size ("looks like" in macOS); current one marked
            // Where the laptop's own screen is, so the pointer crosses where the screens meet: only with both on.
            // eDP is the connector of a laptop's panel (BUILTIN_DISPLAY in hyprland.lua)
            if (side !== "" && desk.length > 1 && desk.some(d => /^eDP-/.test(d.name))) {
                out.push({ kind: "header", name: "Laptop screen" })
                for (const [v, label, glyph] of [["below", "Below the display", "arrow-down"], ["above", "Above the display", "arrow-up"],
                                                 ["left", "Left of the display", "arrow-left"], ["right", "Right of the display", "arrow-right"],
                                                 ["auto", "Automatic", "monitor"]]) {
                    const cur = side === v
                    out.push({ kind: "side", value: v, name: label, glyph: cur ? "check" : glyph,
                               summary: cur ? "current" : v === "auto" ? "side by side" : undefined })
                }
            }
            for (const d of desk) {
                out.push({ kind: "header", name: "Scale" + (desk.length > 1 ? " · " + d.name + (d.desc !== "-" ? "  " + d.desc : "") : "") })
                for (const o of d.opts) {
                    const cur = Math.abs(o.value - d.scale) < 0.01
                    out.push({ kind: "scale", output: d.name, value: o.value, name: o.size, glyph: cur ? "check" : "monitor",
                               summary: (cur ? "current · " : "") + "scale " + +o.value.toFixed(2) })
                }
                // Refresh rates at its resolution, only with a choice: Automatic is the display's preferred mode
                const r = rates[d.name]
                if (r && r.hz.length > 1) {
                    out.push({ kind: "header", name: "Refresh rate" + (desk.length > 1 ? " · " + d.name : "") })
                    for (const hz of r.hz) {
                        const cur = r.chosen !== "auto" && Math.abs(hz - r.chosen) < 0.01
                        out.push({ kind: "rate", output: d.name, value: String(hz), name: Math.round(hz) + " Hz", glyph: cur ? "check" : "monitor",
                                   summary: (cur ? "current · " : "") + +hz.toFixed(2) + " Hz" })
                    }
                    const auto = r.chosen === "auto"
                    out.push({ kind: "rate", output: d.name, value: "auto", name: "Automatic", glyph: auto ? "check" : "monitor",
                               summary: (auto ? "current · " : "") + "the display's preferred mode" })
                }
            }
            return out
        }
        if (level === "otherdisplays") {
            // Hints (still looking for AirPlay devices) last
            const o = others()
            if (o.length === 0) return l.hint("Screen Mirroring and VNC Display add them: Install › Plugins")
            return [...o.filter(r => r.kind !== "hint"), ...o.filter(r => r.kind === "hint")]
        }
        if (level === "battery") {
            // The same as the top bar's battery menu: charge and state, then the details
            if (batt === null) return l.hint(p.hasBattery ? "Loading…" : "No battery in this computer")
            const b = battDetail
            const stateText = { discharging: "Discharging", charging: "Charging", "fully-charged": "Fully charged", "pending-charge": "Not charging" }[batt.state] || batt.state
            const rows = [{ kind: "stat", name: batt.percent + "%  " + stateText,
                            glyph: batt.state === "charging" ? "battery-charging" : batt.percent < 40 ? "battery-low" : batt.percent < 60 ? "battery-medium" : "battery-full",
                            summary: batt.timeText !== "" ? batt.timeText + (batt.state === "charging" ? " until full" : " remaining") : undefined }]
            if (b) {
                rows.push({ kind: "header", name: "Details" })
                for (const r of [["zap", "Power", b.watts > 0 ? b.watts + " W" : ""],
                                 ["thermometer", "Temperature", b.temp !== null ? b.temp + " °C" : ""],
                                 ["heart-pulse", "Health", b.health !== null ? b.health + "% · " + b.fullWh + " / " + b.designWh + " Wh" : ""],
                                 ["repeat", "Cycles", b.cycles !== null ? String(b.cycles) : ""],
                                 ["activity", "Voltage", b.volts !== null ? b.volts.toFixed(2) + " V" : ""],
                                 ["calendar", "Manufactured", b.made]])
                    if (r[2] !== "") rows.push({ kind: "stat", glyph: r[0], name: r[1], summary: r[2] })
            }
            return rows
        }
        return []
    }

    // The brightness and night light rows come from the root search too, so these work on any level
    function activate(it) {
        const l = launcher
        if (it.kind === "brightness") { l.shakeNow(); return true }   // ←/→ or the slider
        if (it.kind === "nightlight") {
            l.keepSelection()
            night = night === "on" ? "off" : "on"
            Quickshell.execDetached([scripts + "/nightlight", night])
            return true
        }
        if (it.kind === "side") {         // stays open like the scale rows; Hyprland reloads with the new arrangement
            l.keepSelection()
            side = it.value
            Quickshell.execDetached([scripts + "/display", "side", it.value])
            return true
        }
        if (it.kind === "rate") {         // stays open like the scale rows; Hyprland reloads with the new mode
            l.keepSelection()
            const r = Object.assign({}, rates)
            r[it.output] = Object.assign({}, r[it.output], { chosen: it.value === "auto" ? "auto" : parseFloat(it.value) })
            rates = r
            Quickshell.execDetached([scripts + "/display", "rate", it.output, it.value])
            return true
        }
        if (it.kind === "scale") {        // stays open like the theme rows; Hyprland reloads with the new scale
            l.keepSelection()
            displays = displays.map(d => d.name === it.output ? Object.assign({}, d, { scale: it.value }) : d)
            Quickshell.execDetached([scripts + "/display", "scale", it.output, String(it.value)])
            return true
        }
        return false
    }

    // keepSelection: the new percentage rebuilds the rows, which would move the selection to the top
    // key: "keys" = the keyboard's backlight, otherwise the screen's
    function setBright(v, key) {
        launcher.keepSelection()
        if (key === "keys") { keys = v; pendingKeys = v } else { bright = v; pendingBright = v }
        if (!brightApply.running) brightApply.start()
    }
    // ←/→: to the next even step, like the brightness keys
    function stepBright(dir, key) {
        const pc = Math.round((key === "keys" ? keys : bright) * 100)
        const n = dir > 0 ? (Math.floor(pc / brightStep) + 1) * brightStep : (pc % brightStep === 0 ? pc - brightStep : Math.floor(pc / brightStep) * brightStep)
        setBright(Math.max(0, Math.min(100, n)) / 100, key)
    }
    Timer {
        id: brightApply; interval: 60
        onTriggered: {
            if (p.pendingBright >= 0) Quickshell.execDetached(["brightnessctl", "-c", "backlight", "-n2", "set", Math.round(p.pendingBright * 100) + "%"])
            if (p.pendingKeys >= 0) Quickshell.execDetached(["brightnessctl", "-d", "*kbd_backlight*", "set", Math.round(p.pendingKeys * 100) + "%"])
            p.pendingBright = -1; p.pendingKeys = -1
        }
    }

    // Display: outputs and their even scales
    Sh {
        id: displayProc
        script: '"$HOME/.config/hypr/scripts/display" list'
        onResult: text => {
            const first = p.displays === null
            p.displays = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 4).map(f => ({
                name: f[0], desc: f[1], scale: parseFloat(f[2]),
                opts: f.slice(3).map(o => { const [v, size] = o.split(":"); return { value: parseFloat(v), size: size.replace("×", " × ") } }) }))
            if (first && p.launcher.level === "display" && p.launcher.query === "") p.launcher.selectFirst()   // was the Loading… hint
        }
    }
    Sh {
        id: ratesProc
        script: '"$HOME/.config/hypr/scripts/display" rates'
        onResult: text => {
            const r = {}
            for (const f of text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 3))
                r[f[0]] = { current: parseFloat(f[1]), chosen: f[2] === "auto" ? "auto" : parseFloat(f[2]), hz: f.slice(3).map(parseFloat) }
            p.launcher.keepSelection()
            p.rates = r
        }
    }
    Sh {
        id: sideProc
        script: '"$HOME/.config/hypr/scripts/display" side'
        onResult: text => { p.launcher.keepSelection(); p.side = text.trim() }
    }
    // Brightness: read on entering and every 2 s while there (the brightness keys also work then),
    // not while the slider is held or a value is waiting to be applied
    Sh {
        id: brightProc
        // -c backlight: without a backlight brightnessctl would pick the first LED (a keyboard's Compose light)
        command: ["brightnessctl", "-m", "-c", "backlight"]
        onResult: text => {
            if (p.pendingBright >= 0) return
            const l = p.launcher
            const first = p.bright < 0
            const f = text.trim().split(",")
            const v = f.length >= 4 ? parseInt(f[3]) / 100 : -1
            if (v !== p.bright && !first) l.keepSelection()   // changed elsewhere (the brightness keys)
            p.bright = v
            // The rows above the scales appear only now: select the first one (the brightness row)
            if (first && p.bright >= 0 && l.level === "display" && l.query === "") l.selectFirst()
        }
    }
    Sh {
        id: keysProc
        command: ["brightnessctl", "-m", "-d", "*kbd_backlight*"]
        onResult: text => {
            if (p.pendingKeys >= 0) return
            const f = text.trim().split(",")
            const v = f.length >= 4 ? parseInt(f[3]) / 100 : -1
            if (v !== p.keys && p.keys >= 0) p.launcher.keepSelection()   // changed elsewhere (⌘F1/⌘F2)
            p.keys = v
        }
    }
    Timer { interval: 2000; repeat: true; running: p.launcher !== null && p.launcher.open && p.launcher.level === "display"; onTriggered: { brightProc.running = true; keysProc.running = true } }
    Sh {
        id: nightProc
        script: '"$HOME/.config/hypr/scripts/nightlight" status'
        onResult: text => { p.night = text.trim() }
    }
    // Battery: the machine's own battery, found like in topbar/scripts/status (MacBook: macsmc-battery);
    // read on entering and every 5 s while there
    Sh {
        id: battProc
        script: 'for d in /sys/class/power_supply/*; do [ "$(cat "$d/type")" = Battery ] && [ "$(cat "$d/scope" 2>/dev/null)" != Device ] &&
                 { upower -i "/org/freedesktop/UPower/devices/battery_$(basename "$d" | tr - _)"; break; }; done'
        onResult: text => {
            const g = re => { const r = text.match(re); return r ? r[1].trim() : "" }
            const fmt = (v, unit) => {
                const min = Math.round(parseFloat(v.replace(",", ".")) * (/hour/.test(unit) ? 60 : /second/.test(unit) ? 1 / 60 : 1))
                return Math.floor(min / 60) > 0 ? Math.floor(min / 60) + " h " + (min % 60) + " min" : min + " min"
            }
            const st = g(/state:\s*(\S+)/)
            const tte = text.match(/time to empty:\s*([\d.,]+)\s*(\w+)/)
            const ttf = text.match(/time to full:\s*([\d.,]+)\s*(\w+)/)
            if (st === "") { p.batt = null; return }
            p.launcher.keepSelection()
            p.batt = { percent: parseInt(g(/percentage:\s*(\d+)/)) || 0, state: st,
                       timeText: st === "discharging" && tte ? fmt(tte[1], tte[2]) : st === "charging" && ttf ? fmt(ttf[1], ttf[2]) : "" }
        }
    }
    // Once at start: a desktop has none, and its Battery page would only say so
    Sh {
        running: true
        script: 'for d in /sys/class/power_supply/*; do [ "$(cat "$d/type")" = Battery ] && [ "$(cat "$d/scope" 2>/dev/null)" != Device ] && { echo yes; break; }; done'
        onResult: text => { p.hasBattery = text.trim() === "yes" }
    }
    Sh {
        id: battDetailProc
        command: ["bash", "-c", "~/.config/topbar/scripts/sysinfo battery"]
        onResult: text => { try { p.battDetail = JSON.parse(text) } catch (e) { p.battDetail = null } }
    }
    Timer { interval: 5000; repeat: true; running: p.launcher !== null && p.launcher.open && p.launcher.level === "battery"; onTriggered: { battProc.running = true; battDetailProc.running = true } }
}
