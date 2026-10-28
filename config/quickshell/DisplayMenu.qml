import QtQuick
import Quickshell

// Display: screen brightness (brightnessctl), night light (hypr/scripts/nightlight), Screen Mirroring over AirPlay
// (the mirroring plugin: plugins/mirroring, bin/mirroring; hidden without it or while it's off) and the scale of each output (hypr/scripts/display: only scales the
// panel divides evenly, shown as the resulting desktop size) and its refresh rate.
// The launcher's Settings › Display has the same settings.
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 10

    property real screen: -1         // -1 = no display backlight (a VM)
    property real pending: -1
    property string night: ""        // on | off
    property var displays: []        // [{ name, desc, scale, opts: [{ value, size }] }]
    property var rates: ({})         // { output: { chosen: hz or "auto", hz: [...] } } (display rates)
    property bool mirrorAvail: false
    property var mirrorDevices: []   // [{ name, model, ip }] (doubletake-ctl devices)
    property string mirrorState: "idle"   // idle | connecting | pin_required | streaming
    property string mirrorIp: ""
    readonly property string mirrorScript: Quickshell.env("HOME") + "/.local/bin/mirroring"
    signal close()

    function refresh() { briProc.running = true; nightProc.running = true; mirrorProc.running = true }
    Component.onCompleted: { refresh(); displayProc.running = true; ratesProc.running = true }
    Timer { interval: 3000; repeat: true; running: true; onTriggered: m.refresh() }

    Timer {
        id: apply; interval: 60
        onTriggered: {
            if (m.pending < 0) return
            Quickshell.execDetached(["brightnessctl", "-c", "backlight", "-n2", "set", Math.round(m.pending * 100) + "%"])
            m.pending = -1
        }
    }
    Sh {
        id: briProc
        // -c backlight: without a backlight brightnessctl would pick the first LED (a keyboard's Compose light)
        command: ["brightnessctl", "-m", "-c", "backlight"]
        onResult: text => {
            if (slider.pressed || m.pending >= 0) return
            const f = text.trim().split(",")
            m.screen = f.length >= 4 ? parseInt(f[3]) / 100 : -1
        }
    }
    Sh {
        id: nightProc
        script: '"$HOME/.config/hypr/scripts/nightlight" status'
        onResult: text => { m.night = text.trim() }
    }
    Sh {
        id: mirrorProc
        script: 'c="$HOME/.local/bin/doubletake-ctl"; [ -x "$c" ] || exit 0; "$c" status; echo; "$c" devices'
        onResult: text => {
            const parts = text.trim().split(/\n(?=\{)/)   // two JSON objects: status, then devices
            let st = null, dev = null
            try { st = JSON.parse(parts[0]); dev = JSON.parse(parts[1]) } catch (e) {}
            m.mirrorAvail = Plugins.has("mirroring") && st !== null && st.ok === true   // off: hidden, though doubletake runs
            m.mirrorState = st && st.state ? st.state : "idle"
            m.mirrorIp = st && st.device_ip ? st.device_ip : ""
            m.mirrorDevices = dev && dev.devices ? dev.devices.map(d => ({ name: d.name, model: d.model || "", ip: d.ip })) : []
        }
    }
    Sh {
        id: displayProc
        script: '"$HOME/.config/hypr/scripts/display" list'
        onResult: text => {
            // The desk's own: a virtual screen (HEADLESS-*, an iPad over VNC) has its size from its plugin
            m.displays = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 4 && !/^HEADLESS-/.test(f[0])).map(f => ({
                name: f[0], desc: f[1], scale: parseFloat(f[2]),
                opts: f.slice(3).map(o => { const [v, size] = o.split(":"); return { value: parseFloat(v), size: size.replace("×", " × ") } }) }))
        }
    }
    Sh {
        id: ratesProc
        script: '"$HOME/.config/hypr/scripts/display" rates'
        onResult: text => {
            const r = {}
            for (const f of text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 3))
                r[f[0]] = { chosen: f[2] === "auto" ? "auto" : parseFloat(f[2]), hz: f.slice(3).map(parseFloat) }
            m.rates = r
        }
    }

    MenuHeader { width: parent.width; title: "Display" }

    MenuSection { visible: m.screen >= 0; title: "Brightness" }
    Row {
        visible: m.screen >= 0
        width: parent.width
        spacing: 12
        Text {
            id: sunIcon
            width: 22
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: Icons.g("sun")
            color: Theme.text
            font { family: Icons.family; pixelSize: 18 }
        }
        Slider {
            id: slider
            width: parent.width - sunIcon.width - pct.width - 24
            anchors.verticalCenter: parent.verticalCenter
            value: Math.max(0, m.screen)
            onMoved: v => { m.screen = v; m.pending = v; if (!apply.running) apply.start() }
        }
        Text {
            id: pct
            width: 44
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: Math.round(Math.max(0, m.screen) * 100) + "%"
            color: Theme.text
            font { family: Theme.font; pixelSize: 13 }
        }
    }
    // Night light: laid out like the brightness row above it (the moon under the sun), with a switch on the right
    Item {
        id: nightRow
        visible: m.night !== ""
        width: parent.width
        height: 30
        property bool navSelected: false
        readonly property bool navEnabled: visible
        function navActivate() { toggle() }
        function toggle() {
            m.night = m.night === "on" ? "off" : "on"
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/nightlight", m.night])
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nightRow.toggle() }
        Text {
            id: moonIcon
            width: 22
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: Icons.g("moon")
            color: Theme.text
            font { family: Icons.family; pixelSize: 18 }
        }
        Text {
            anchors { left: moonIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: "Night light"
            color: Theme.text
            font { family: Theme.font; pixelSize: 13 }
        }
        Toggle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            checked: m.night === "on"
            navSelected: nightRow.navSelected
            onToggled: nightRow.toggle()
        }
    }

    MenuSection { visible: m.mirrorAvail; apart: true; title: "Screen Mirroring" }
    MenuNote {
        visible: m.mirrorAvail && m.mirrorDevices.length === 0
        text: "Looking for AirPlay devices…"
    }
    Column {
        visible: m.mirrorAvail
        width: parent.width
        spacing: 2
        Repeater {
            model: m.mirrorAvail ? m.mirrorDevices : []
            delegate: MenuRow {
                required property var modelData
                readonly property bool mine: modelData.ip === m.mirrorIp && m.mirrorState !== "idle"
                width: parent.width
                icon: /STR-|receiver|HomePod|AudioAccessory|speaker/i.test(modelData.name + " " + modelData.model) ? "speaker" : "tv"
                label: modelData.name
                active: mine && m.mirrorState === "streaming"
                checkIcon: mine && m.mirrorState === "streaming" ? "check" : ""
                hoverCheckIcon: mine ? "x" : ""   // a click stops mirroring
                busy: mine && m.mirrorState !== "streaming"
                detail: "AirPlay"   // the only kind for now (doubletake); Google Cast goes through Chromium
                onClicked: {
                    if (mine) { m.mirrorState = "idle"; Quickshell.execDetached([m.mirrorScript, "stop"]); return }
                    // The share window comes next (and the launcher for a receiver's code): the menu gets out of the way
                    Quickshell.execDetached([m.mirrorScript, "connect", modelData.ip])
                    m.close()
                }
            }
        }
    }

    // Each display's scales under its own name (the laptop's screen, the external one's model), "scale" on the right
    Repeater {
        model: m.displays
        delegate: Column {
            required property var modelData
            readonly property var d: modelData
            width: m.width
            spacing: 2
            readonly property bool laptop: /^eDP-/.test(d.name)   // a laptop's panel (BUILTIN_DISPLAY in hyprland.lua)
            MenuSection {
                apart: true
                title: m.displays.length < 2 ? "Scale" : laptop ? "Laptop screen" : (d.desc !== "-" ? d.desc.replace(/\s+0x[0-9A-Fa-f]+$/, "") : d.name)
                subtitle: m.displays.length < 2 ? "" : "Scale"
            }
            Repeater {
                model: d.opts
                delegate: MenuRow {
                    required property var modelData
                    readonly property bool cur: Math.abs(modelData.value - d.scale) < 0.01
                    width: parent.width
                    icon: laptop ? "laptop" : "monitor"
                    label: modelData.size
                    detail: "scale " + +modelData.value.toFixed(2)
                    active: cur
                    checkIcon: cur ? "check" : ""
                    onClicked: {
                        if (cur) return
                        // Copied first: the new m.displays rebuilds this delegate, and d and modelData go with it
                        const name = d.name, value = modelData.value
                        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/display", "scale", name, String(value)])
                        // Shown as chosen at once; Hyprland reloads with the new scale and the menu follows
                        m.displays = m.displays.map(x => x.name === name ? Object.assign({}, x, { scale: value }) : x)
                    }
                }
            }
            // Its refresh rates, only with a choice: Automatic is the display's preferred mode (a TV's is often 60 Hz)
            readonly property var r: m.rates[d.name] || null
            readonly property var rateRows: r && r.hz.length > 1
                ? r.hz.map(hz => ({ value: String(hz), label: Math.round(hz) + " Hz", detail: +hz.toFixed(2) + " Hz",
                                    cur: r.chosen !== "auto" && Math.abs(hz - r.chosen) < 0.01 }))
                      .concat([{ value: "auto", label: "Automatic", detail: "preferred mode", cur: r.chosen === "auto" }])
                : []
            MenuSection { visible: rateRows.length > 0; title: "Refresh rate" }
            Repeater {
                model: rateRows
                delegate: MenuRow {
                    required property var modelData
                    width: parent.width
                    icon: laptop ? "laptop" : "monitor"
                    label: modelData.label
                    detail: modelData.detail
                    active: modelData.cur
                    checkIcon: modelData.cur ? "check" : ""
                    onClicked: {
                        if (modelData.cur) return
                        const name = d.name, value = modelData.value
                        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/display", "rate", name, value])
                        const r = Object.assign({}, m.rates)
                        r[name] = Object.assign({}, r[name], { chosen: value === "auto" ? "auto" : parseFloat(value) })
                        m.rates = r
                    }
                }
            }
        }
    }
}
