import QtQuick
import Quickshell

// The launcher's Settings › Wi-Fi, Bluetooth, Sound, Headphones and Tailscale, and Status (the top bar's System and Claude usage): the
// same things as the top bar's menus (WifiMenu, BluetoothMenu, VolumeMenu, HeadphonesMenu, plugins/tailscale's TailscaleMenu, SystemMenu, ClaudeMenu) as
// launcher rows, so the launcher doesn't hand over to a menu.
// Launcher.qml asks it like its private extension (levels, titles, parents, items, activate, footer, entered).
// The data is read while one of these levels is open; rows use the launcher's kinds (header, hint, stat, action) and a few
// own ones, handled in activate().
Item {
    id: s
    property var launcher: null

    readonly property var inputs: ["wifipw", "mirrorpin"]   // text fields: ⌘⇧V pastes into them (ClipPicker)
    readonly property var levels: ["wifi", "wifipw", "bluetooth", "sound", "headphones", "tailscale", "status", "mirrorpin"]
    readonly property var titles: ({ status: "System › Status", mirrorpin: "Screen Mirroring › Code", wifi: "Settings › Wi-Fi", wifipw: "Wi-Fi › Password", bluetooth: "Settings › Bluetooth",
                                     sound: "Settings › Sound", headphones: "Sound › Headphones", tailscale: "Settings › Tailscale" })
    readonly property var parents: ({ status: "system", mirrorpin: "display", wifi: "settings", wifipw: "wifi", bluetooth: "settings", sound: "settings", headphones: "sound", tailscale: "settings" })
    readonly property string level: launcher ? launcher.level : ""
    readonly property bool shown: launcher !== null && launcher.open && levels.indexOf(level) >= 0

    function hint(t) { return [{ kind: "hint", name: t }] }
    function row(r) { return { item: r, text: r.kind === "header" || r.kind === "hint" ? "" : r.name, extra: r.extra || "" } }
    function sel() { if (launcher) launcher.keepSelection() }   // a refresh rebuilds the rows: keep the selected one

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "slider") return "Left+Right: " + cur.name.toLowerCase() + "  ·  Enter: mute on/off"
        if (cur.kind === "tslogin" || (cur.key === "tailscale" && tsNeedsLogin && !tsRunning)) return "Enter: log in"
        if (cur.kind === "systoggle") return "Enter: on/off"
        if (cur.kind === "wifinet") return cur.active ? "" : "Enter: connect"
        if (cur.kind === "btdev") return "Enter: " + (cur.connected ? "disconnect" : cur.paired ? "connect" : "pair and connect")
        if (cur.kind === "sounddev") return "Enter: use this"
        if (cur.kind === "btmic") return "Enter: switch to headset mode and use this"
        if (cur.kind === "hpdev") return "Enter: " + (cur.current ? "disconnect" : "use as output")
        if (cur.kind === "hpmode") return cur.trailGlyph ? "" : "Enter: switch"
        if (cur.kind === "tsmachine") return "Enter: copy IP address  ·  Cmd+C: copy"
        if (cur.copy !== undefined) return "Enter: copy  ·  Cmd+C: copy"
        if (level === "wifipw") return query !== "" ? "Enter: connect  ·  Esc: back" : ""
        if (level === "mirrorpin") return query !== "" ? "Enter: pair" : ""
        if (cur.kind === "mirrordev") return "Enter: " + (cur.ip === mirrorIp && mirrorState !== "idle" ? "stop mirroring" : "mirror the screen here")
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level === "wifi") { wifiMessage = ""; wifiRefresh(); rescan(); if (activeSsid !== "") ipProc.running = true }
        if (level === "bluetooth") { btMessage = ""; btRefresh() }
        if (level === "sound") soundRefresh()
        if (level === "headphones") hpProc.running = true
        if (level === "tailscale") { tsMessage = ""; tsProc.running = true }
        if (level === "status") { sysProc.running = true; claudeProc.running = true }
        if (level === "mirrorpin" || level === "display") mirrorProc.running = true
    }
    function shiftActivate(item) {}

    function items(level, q) {
        if (level === "wifi") return { all: wifiRows().map(row) }
        if (level === "wifipw") return [{ kind: "wificonnect", name: "Connect to “" + askFor + "”", glyph: "lock",
                                          summary: launcher.query === "" ? "type the password" : undefined, dimmed: launcher.query === "" }]
        if (level === "bluetooth") return { all: btRows().map(row) }
        if (level === "sound") return { all: soundRows().map(row) }
        if (level === "headphones") return { all: hpRows().map(row) }
        if (level === "tailscale") return { all: tsRows().map(row) }
        if (level === "status") return { all: statusRows().map(row) }
        if (level === "mirrorpin") return [{ kind: "mirrorcode", name: "Pair with " + (mirrorName || "the receiver"), glyph: "key-round",
                                             summary: launcher.query === "" ? "type the code on the TV" : undefined, dimmed: launcher.query === "" }]
        return []
    }

    // Enter on a row. Returns true when the row was one of ours.
    function activate(it) {
        if (it.kind === "systoggle") {
            sel()
            if (it.key === "wifi") {
                wifiOn = !wifiOn
                TopBar.run("nmcli radio wifi " + (wifiOn ? "on" : "off"), "wifi")
                if (!wifiOn) nets = []
            } else if (it.key === "bluetooth") {
                powered = !powered
                Quickshell.execDetached(["bluetoothctl", "power", powered ? "on" : "off"])
            } else if (it.key === "tailscale") {
                if (tsNeedsLogin && !tsRunning) tsLogin()   // tailscale up would only wait for the login
                else {
                    tsMessage = ""
                    tsToggle.script = tsRunning ? "tailscale down" : "tailscale up"
                    tsToggle.running = true
                }
            }
            return true
        }
        if (it.kind === "tslogin") { sel(); tsLogin(); return true }
        if (it.kind === "wifinet") { sel(); wifiActivate(it.net); return true }
        if (it.kind === "wifidisconnect") { sel(); wifiActivate(activeNet); return true }
        if (it.kind === "wififorget") {
            if (!arm(it.armKey)) return true
            connecting = activeSsid
            forgetProc.environment = { "SSID": activeSsid }
            forgetProc.running = true
            return true
        }
        if (it.kind === "wificonnect") {
            if (launcher.query === "") { launcher.shakeNow(); return true }
            connectTo(askFor, launcher.query)
            launcher.go("wifi")
            return true
        }
        if (it.kind === "btdev") { sel(); btActivate(it.dev); return true }
        if (it.kind === "bthidden") { sel(); showHidden = !showHidden; return true }
        if (it.kind === "btscan") { sel(); btScan(); return true }
        if (it.kind === "slider") { sel(); toggleMute(it.key); return true }
        if (it.kind === "sounddev") {
            sel()
            // A microphone that isn't the headphones': the headphones go back to music mode (as in OutputList)
            const src = sources.find(x => x.id === it.id)
            if (src && !src.bt) Quickshell.execDetached(["bash", "-c", 'wpctl set-default "$1" && "$2" release', "_", String(it.id), btMic])
            else Quickshell.execDetached(["wpctl", "set-default", String(it.id)])
            soundSoon.restart()
            const d = sinks.find(x => x.id === it.id)
            if (d && d.airplay) Quickshell.execDetached([airplayCheck, "notify", d.node])   // warns if it refuses audio
            return true
        }
        if (it.kind === "btmic") {
            if (btMicBusy !== "") return true
            sel()
            btMicBusy = it.card; btMicFailed = ""
            btMicUse.environment = { "BTMIC": btMic, "CARD": it.card }
            btMicUse.running = true
            return true
        }
        if (it.kind === "hpdev") {
            sel()
            if (it.current) Quickshell.execDetached([eq, "disconnect"])
            else Quickshell.execDetached(["pactl", "set-default-sink", hp.sink])
            hpSoon.restart()
            return true
        }
        if (it.kind === "hpmode") { sel(); hpSet.command = [eq, "anc", it.name]; hpSet.running = true; return true }
        if (it.kind === "tsmachine") { copyText(it.ip); return true }
        if (it.kind === "mirrordev") {
            if (it.ip === mirrorIp && mirrorState !== "idle") { sel(); mirrorState = "idle"; Quickshell.execDetached([mirrorScript, "stop"]); return true }
            // The share window can't be clicked under the launcher (it takes the keyboard): close it; a code request reopens it
            launcher.open = false
            Quickshell.execDetached([mirrorScript, "connect", it.ip])
            return true
        }
        if (it.kind === "mirrorcode") {
            if (launcher.query === "") { launcher.shakeNow(); return true }
            Quickshell.execDetached([mirrorScript, "pin", launcher.query.trim()])
            launcher.open = false           // the share window comes next
            return true
        }
        return false
    }
    // Rows that need a second Enter (the launcher shows the armHint while armed); true = confirmed
    function arm(key) {
        if (launcher.armed !== key) { launcher.armed = key; disarmTimer.restart(); return false }
        launcher.armed = ""
        return true
    }
    Timer { id: disarmTimer; interval: 4000; onTriggered: if (s.launcher) s.launcher.armed = "" }

    // ⌘C (Hyprland sends Ctrl+Insert) or Enter on a row with a `copy` value: the row says "copied" for a moment
    function copyText(v) {
        sel()
        Quickshell.execDetached(["wl-copy", v])
        copied = v
        copiedTimer.restart()
    }
    // Values that change every second are bound in the row (the launcher asks with the row's `live` key), not baked into
    // the rows: rebuilding the rows every second made the list jump while moving in it
    function liveText(key) {
        if (key === "wifirate") return "↓ " + fmtRate(rxRate) + "   ↑ " + fmtRate(txRate)
        if (key === "wifilocal") return !link.ip ? "…" : copied !== "" && copied === link.ip ? "copied"
                                        : link.ip + (linkPing < 0 ? "" : " · " + (linkPing < 1 ? "<1" : Math.round(linkPing)) + " ms")
        return statusLive(key)
    }

    // ---- Sliders (Sound): ←/→ and the row's slider call these ----
    function sliderValue(key) { return key === "mic" ? micVolume : volume }
    function setSlider(key, v) {
        sel()
        if (key === "mic") { micVolume = v; micPending = v } else { volume = v; pending = v }
        if (!volApply.running) volApply.start()
    }
    function stepSlider(key, dir) {
        const p = Math.round(sliderValue(key) * 100)
        const n = dir > 0 ? (Math.floor(p / 5) + 1) * 5 : (p % 5 === 0 ? p - 5 : Math.floor(p / 5) * 5)
        setSlider(key, Math.max(0, Math.min(100, n)) / 100)
    }

    // ================= Wi-Fi (nmcli; as in WifiMenu) =================
    property bool wifiOn: LastState.wifi
    onWifiOnChanged: LastState.wifi = wifiOn
    property var nets: []            // [{ ssid, signal, secure, active, known }]
    property var knownSet: ({})
    property string connecting: ""
    property string askFor: ""       // the network whose password is being typed (level wifipw)
    property string wifiMessage: ""
    property string publicIp: ""
    property real rxRate: 0
    property real txRate: 0
    property real lastRx: -1
    property real lastTx: -1
    property real lastT: 0
    readonly property var activeNet: nets.find(n => n.active) || null
    readonly property string activeSsid: activeNet ? activeNet.ssid : ""
    onActiveSsidChanged: { publicIp = ""; if (activeSsid !== "" && level === "wifi") ipProc.running = true }

    function splitTerse(line) {    // nmcli -t: fields separated by ':', a ':' inside a field escaped as \:
        const out = []; let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line[i]
            if (c === "\\" && i + 1 < line.length) cur += line[++i]
            else if (c === ":") { out.push(cur); cur = "" }
            else cur += c
        }
        out.push(cur)
        return out
    }
    function sigIcon(v) { return v >= 75 ? "wifi" : v >= 50 ? "wifi-high" : v >= 25 ? "wifi-low" : "wifi-zero" }
    function fmtRate(b) {
        const bits = b * 8
        return bits >= 1e9 ? (bits / 1e9).toFixed(2) + " Gb/s" : bits >= 1e6 ? (bits / 1e6).toFixed(1) + " Mb/s"
             : bits >= 1e3 ? Math.round(bits / 1e3) + " kb/s" : Math.round(bits) + " b/s"
    }
    function wifiRefresh() { radioProc.running = true; knownProc.running = true; listProc.running = true }
    function rescan() { Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"]) }
    function connectTo(ssid, password) {
        wifiMessage = ""
        connecting = ssid
        connectProc.environment = { "SSID": ssid, "PW": password || "" }
        connectProc.running = true
    }
    function wifiActivate(n) {
        if (!n || connecting !== "") return
        if (n.active) {
            connecting = n.ssid
            disconnectProc.environment = { "SSID": n.ssid }
            disconnectProc.running = true
        } else if (n.secure && !n.known) {
            askFor = n.ssid
            launcher.go("wifipw")
        } else connectTo(n.ssid, "")
    }
    function wifiRows() {
        const r = [{ kind: "systoggle", key: "wifi", name: "Wi-Fi", glyph: wifiOn ? "wifi" : "wifi-off", switchOn: wifiOn }]
        if (!wifiOn) return r
        const a = activeNet
        if (a) {
            r.push({ kind: "header", name: "Connected" },
                   { kind: "stat", name: a.ssid, glyph: sigIcon(a.signal), live: "wifirate" },
                   { kind: "stat", name: "Public IP", glyph: "globe", copy: /^[0-9a-fA-F:.]+$/.test(publicIp) ? publicIp : undefined,
                     summary: copied !== "" && copied === publicIp ? "copied" : publicIp || "…" })
        }
        // The link (hypr/scripts/wifi-info): the same two lines as the menu, then the details the menu leaves out
        const L = link
        const line = xs => xs.filter(x => x).join(" · ")
        // All rows from the start ("…" until the first reading), so the list doesn't grow under the selection
        if (a) r.push({ kind: "stat", name: "Local IP", glyph: "router", copy: L.ip || undefined, live: "wifilocal" },
                       { kind: "stat", name: "Connection", glyph: "radio-tower", summary: line([L.band, L.gen, L.rate]) || "…" },
                       { kind: "stat", name: "Security", glyph: "lock", summary: L.band === undefined ? "…" : L.sec || "none" },
                       { kind: "stat", name: "Signal", glyph: "signal", summary: line([L.dbm !== null && L.dbm !== undefined ? L.dbm + " dBm" : "", L.width]) || "…" },
                       { kind: "stat", name: "Router", glyph: "house-wifi", copy: L.gw || undefined,
                         summary: copied !== "" && copied === L.gw ? "copied" : line([L.gw, L.bssid]) || "…" },
                       { kind: "stat", name: "DNS", glyph: "server", summary: L.band === undefined ? "…" : (L.dns || "").replace(/,/g, ", ") || "—" })
        if (a) {
            r.push({ kind: "header", name: "Actions" },   // apart from the statistics above
                   { kind: "wifidisconnect", name: "Disconnect", glyph: "unplug", summary: connecting === a.ssid ? "…" : undefined },
                   { kind: "wififorget", name: "Forget network", glyph: "trash-2", armKey: "forget:" + a.ssid,
                     armHint: "Enter again: forget, password too" })
        }
        const others = nets.filter(n => !n.active)
        r.push({ kind: "header", name: a ? "Other networks" : "Networks" })
        if (others.length === 0) r.push({ kind: "hint", name: "Searching for networks…" })
        for (const n of others)
            r.push({ kind: "wifinet", name: n.ssid, glyph: sigIcon(n.signal), net: n, active: false,
                     summary: connecting === n.ssid ? "connecting…" : n.known ? "saved" : undefined,
                     trailGlyph: connecting !== n.ssid && !n.known && n.secure ? "lock" : undefined })
        if (wifiMessage !== "") r.push({ kind: "hint", name: wifiMessage })
        r.push({ kind: "header", name: "More" })
        r.push({ kind: "action", name: "Network settings…", glyph: "settings", cmd: ["nm-connection-editor"], extra: "advanced ip dns vpn" })
        return r
    }
    Timer { interval: 3000; repeat: true; running: s.shown && s.level === "wifi"; onTriggered: s.wifiRefresh() }
    Timer { interval: 10000; repeat: true; running: s.shown && s.level === "wifi"; onTriggered: s.rescan() }
    Timer { interval: 60000; repeat: true; running: s.shown && s.level === "wifi" && s.activeSsid !== ""; onTriggered: ipProc.running = true }
    property var link: ({})          // without the ping: it changes every time, and the rows rebuild when `link` does
    property real linkPing: -1       // ms to the router, -1 = no answer (shown live in the Local IP row)
    Timer { interval: 5000; repeat: true; running: s.shown && s.level === "wifi" && s.activeSsid !== ""; triggeredOnStart: true; onTriggered: linkProc.running = true }
    Sh {
        id: linkProc   // hypr/scripts/wifi-info (as in WifiMenu); the rows rebuild only when something changed
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/wifi-info"]
        onResult: text => {
            let v
            try { v = JSON.parse(text) } catch (e) { return }
            s.linkPing = v.ping === null || v.ping === undefined ? -1 : v.ping
            delete v.ping
            if (JSON.stringify(v) === JSON.stringify(s.link)) return
            s.sel()
            s.link = v
        }
    }
    Timer { interval: 1000; repeat: true; running: s.shown && s.level === "wifi" && s.activeSsid !== ""; triggeredOnStart: true; onTriggered: rateProc.running = true }
    Sh {
        id: radioProc
        command: ["nmcli", "radio", "wifi"]
        onResult: text => { if ((text.trim() === "enabled") !== s.wifiOn) { s.sel(); s.wifiOn = text.trim() === "enabled" } }
    }
    Sh {
        id: knownProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        onResult: text => {
            const set = {}
            for (const line of text.split("\n")) {
                const f = s.splitTerse(line)
                if (f.length >= 2 && f[1] === "802-11-wireless") set[f[0]] = true
            }
            if (JSON.stringify(set) !== JSON.stringify(s.knownSet)) s.knownSet = set
        }
    }
    Sh {
        id: listProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"]
        onResult: text => {
            const by = {}
            for (const line of text.split("\n")) {
                if (!line) continue
                const f = s.splitTerse(line)
                if (f.length < 4 || f[1] === "") continue
                const n = { ssid: f[1], signal: parseInt(f[2]) || 0, secure: f[3] !== "" && f[3] !== "--", active: f[0] === "*", known: !!s.knownSet[f[1]] }
                const old = by[n.ssid]
                if (!old || n.active || (!old.active && n.signal > old.signal)) by[n.ssid] = n
            }
            const arr = Object.values(by)
            arr.sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
            if (JSON.stringify(arr) === JSON.stringify(s.nets)) return
            s.sel()
            s.nets = arr
        }
    }
    Sh {
        id: rateProc
        script: 'for d in /sys/class/net/*/wireless; do i=${d%/wireless}; echo "$(cat $i/statistics/rx_bytes) $(cat $i/statistics/tx_bytes)"; break; done'
        onResult: text => {
            const f = text.trim().split(/\s+/).map(Number)
            if (f.length < 2 || isNaN(f[0])) return
            const now = Date.now()
            if (s.lastRx >= 0 && now > s.lastT) {
                const dt = (now - s.lastT) / 1000
                s.rxRate = Math.max(0, (f[0] - s.lastRx) / dt)
                s.txRate = Math.max(0, (f[1] - s.lastTx) / dt)
            }
            s.lastRx = f[0]; s.lastTx = f[1]; s.lastT = now
        }
    }
    Sh {
        id: ipProc   // external service: api.ipify.org (as in WifiMenu)
        script: 'curl -s --max-time 5 https://api.ipify.org'
        onResult: text => {
            const ip = text.replace(/\s+/g, "")
            const v = ipProc.exitCode === 0 && /^[0-9a-fA-F:.]{3,45}$/.test(ip) ? ip : "unavailable"
            if (v === s.publicIp) return
            s.sel()
            s.publicIp = ipProc.exitCode === 0 && /^[0-9a-fA-F:.]{3,45}$/.test(ip) ? ip : "unavailable"
        }
    }
    Sh {
        id: connectProc
        script: 'if [ -n "$PW" ]; then nmcli --wait 20 device wifi connect "$SSID" password "$PW"; else nmcli --wait 20 device wifi connect "$SSID"; fi'
        onResult: text => {
            s.sel()
            s.connecting = ""
            if (connectProc.exitCode !== 0) {
                const lines = text.trim().split("\n")
                s.wifiMessage = lines[lines.length - 1].replace(/^Error:\s*/, "")
            } else { s.wifiMessage = ""; s.askFor = "" }
            s.wifiRefresh()
        }
    }
    Sh {
        id: disconnectProc
        script: 'nmcli connection down id "$SSID"'
        onResult: text => { s.connecting = ""; s.wifiRefresh() }
    }
    Sh {
        id: forgetProc   // by the SSID stored in each profile: a profile's name can differ from it ("Home 1")
        script: 'nmcli -t -f UUID,TYPE connection show | while IFS=: read -r uuid type; do
  [ "$type" = 802-11-wireless ] && [ "$(nmcli -g 802-11-wireless.ssid connection show "$uuid")" = "$SSID" ] && nmcli connection delete uuid "$uuid"
done; true'
        onResult: text => { s.connecting = ""; s.wifiRefresh(); TopBar.refresh("wifi") }
    }

    // ================= Bluetooth (bluetoothctl; as in BluetoothMenu) =================
    property bool powered: LastState.bluetooth
    onPoweredChanged: LastState.bluetooth = powered
    property var devices: []         // [{ mac, connected, paired, battery, name, named }]
    property bool showHidden: false
    property bool scanning: false
    property string btBusy: ""
    property string btMessage: ""
    function btRefresh() { powerProc.running = true; btListProc.running = true }
    function btScan() { if (!scanning && powered) { scanning = true; scanProc.running = true } }
    function btActivate(d) {
        if (btBusy !== "") return
        btBusy = d.mac; btMessage = ""
        actProc.environment = { "MAC": d.mac, "MODE": d.connected ? "disconnect" : (d.paired ? "connect" : "pair") }
        actProc.running = true
    }
    function btIcon(name) {
        return /head|buds|airpods|wh-|wf-|sony/i.test(name) ? "headphones" : /mouse|mx |trackpad/i.test(name) ? "mouse"
             : /keyboard|keys/i.test(name) ? "keyboard" : /phone|iphone|pixel|galaxy/i.test(name) ? "smartphone"
             : /watch/i.test(name) ? "watch" : /speaker|boom|jbl|soundbar/i.test(name) ? "speaker" : "bluetooth"
    }
    function btRows() {
        const r = [{ kind: "systoggle", key: "bluetooth", name: "Bluetooth", glyph: powered ? "bluetooth" : "bluetooth-off", switchOn: powered }]
        if (!powered) return r
        // Nameless devices (only an address: nearby phones, Macs and AirTags) are hidden unless paired, as in the menu
        const hidden = devices.filter(d => !d.named && !d.paired && !d.connected)
        const list = showHidden ? devices : devices.filter(d => hidden.indexOf(d) < 0)
        r.push({ kind: "header", name: "Devices" })
        if (list.length === 0) r.push({ kind: "hint", name: "No devices: Scan for devices below" })
        for (const d of list)
            r.push({ kind: "btdev", name: d.name, glyph: btIcon(d.name), dev: d, connected: d.connected, paired: d.paired,
                     summary: btBusy === d.mac ? "…" : d.battery !== "" ? d.battery + "%" : !d.paired ? "not paired" : undefined,
                     trailGlyph: d.connected && btBusy !== d.mac ? "check" : undefined })
        if (btMessage !== "") r.push({ kind: "hint", name: btMessage })
        r.push({ kind: "header", name: "More" })
        if (hidden.length > 0)
            r.push({ kind: "bthidden", name: (showHidden ? "Hide unnamed devices" : "Show hidden devices") + " (" + hidden.length + ")",
                     glyph: showHidden ? "eye-off" : "eye" })
        r.push({ kind: "btscan", name: "Scan for devices", glyph: "bluetooth-searching", summary: scanning ? "scanning…" : undefined, extra: "pair new add" },
               { kind: "action", name: "Bluetooth settings…", glyph: "settings", cmd: ["blueman-manager"] })
        return r
    }
    Timer { interval: 2500; repeat: true; running: s.shown && s.level === "bluetooth"; onTriggered: s.btRefresh() }
    Sh {
        id: powerProc
        // Without bluetoothd (the sandbox, a VM) bluetoothctl aborts or hangs
        script: 'systemctl is-active -q bluetooth 2>/dev/null && bluetoothctl show'
        onResult: text => { const p = /Powered:\s*yes/.test(text); if (p !== s.powered) { s.sel(); s.powered = p } }
    }
    Sh {
        id: btListProc
        script: 'systemctl is-active -q bluetooth 2>/dev/null || exit 0\n' +
                'bluetoothctl devices | sed "s/\\x1b\\[[0-9;]*m//g" | while read -r _ mac name; do\n' +
                '  info=$(bluetoothctl info "$mac")\n' +
                '  c=$(grep -c "Connected: yes" <<<"$info"); p=$(grep -c "Paired: yes" <<<"$info"); n=$(grep -c "^\\s*Name:" <<<"$info")\n' +
                '  b=$(grep -oP "Battery Percentage: 0x\\w+ \\(\\K[0-9]+" <<<"$info")\n' +
                '  echo "$mac|$c|$p|$b|$n|$name"\n' +
                'done'
        onResult: text => {
            const arr = []
            for (const line of text.split("\n")) {
                const f = line.split("|")
                if (f.length < 6) continue
                arr.push({ mac: f[0], connected: f[1] !== "0", paired: f[2] !== "0", battery: f[3], named: f[4] !== "0", name: f.slice(5).join("|") })
            }
            arr.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
            if (JSON.stringify(arr) === JSON.stringify(s.devices)) return
            s.sel()
            s.devices = arr
        }
    }
    Sh {
        id: scanProc   // 20 s: headphones' names can take a while to arrive; the list fills in as they do
        command: ["bluetoothctl", "--timeout", "20", "scan", "on"]
        onResult: text => { s.sel(); s.scanning = false; s.btRefresh() }
    }
    Sh {
        id: actProc
        script: 'case "$MODE" in\n' +
                '  disconnect) bluetoothctl disconnect "$MAC" ;;\n' +
                '  connect) bluetoothctl connect "$MAC" ;;\n' +
                '  pair) bluetoothctl pair "$MAC" && bluetoothctl trust "$MAC" && bluetoothctl connect "$MAC" ;;\n' +
                'esac'
        onResult: text => {
            s.sel()
            s.btBusy = ""
            if (actProc.exitCode !== 0) { const lines = text.trim().split("\n"); s.btMessage = lines[lines.length - 1] }
            s.btRefresh()
        }
    }

    // ================= Sound (wpctl, pw-dump; as in VolumeMenu and OutputList) =================
    property real volume: 0
    property bool muted: false
    property real pending: -1
    property real micVolume: 0
    property bool micMuted: false
    property real micPending: -1
    property var sinks: []           // [{ id, name, current, bt }]
    property var sources: []
    // Connected headphones in music mode, which have no microphone then: listed as one anyway, Enter switches them to
    // headset mode (hypr/scripts/bt-mic, as in OutputList)
    readonly property string btMic: Quickshell.env("HOME") + "/.config/hypr/scripts/bt-mic"
    property var btMics: []          // [{ card, name }]
    property string btMicBusy: ""    // switching this card to headset mode
    property string btMicFailed: ""  // the last switch of this card gave no microphone (it stays in music mode)
    // AirPlay speakers that refuse PipeWire's AirPlay 1 (RTSP 403): Apple TV / HomePod since OS 27 (Apple bug FB24452968).
    // Probed live, so the warning disappears by itself once Apple fixes it. See docs/known-issues.md.
    property var airplayRefused: []  // [node.name]
    readonly property string airplayCheck: Quickshell.env("HOME") + "/.config/hypr/scripts/airplay-check"
    property real airplayProbedAt: 0
    function soundRefresh() { volProc.running = true; micProc.running = true; dumpProc.running = true; if (!btMicProc.running) btMicProc.running = true }
    Sh {
        id: btMicProc
        command: [s.btMic, "list"]
        onResult: text => {
            let v = []
            try { v = JSON.parse(text) } catch (e) {}
            if (JSON.stringify(v) !== JSON.stringify(s.btMics)) { s.sel(); s.btMics = v }
        }
    }
    Sh {
        id: btMicUse
        script: '"$BTMIC" use "$CARD"'
        onResult: text => { s.sel(); s.btMicFailed = btMicUse.exitCode !== 0 ? s.btMicBusy : ""; s.btMicBusy = ""; s.soundRefresh() }
    }
    function toggleMute(key) {
        if (key === "mic") micMuted = !micMuted; else muted = !muted
        Quickshell.execDetached(["wpctl", "set-mute", key === "mic" ? "@DEFAULT_AUDIO_SOURCE@" : "@DEFAULT_AUDIO_SINK@", "toggle"])
        soundSoon.restart()
    }
    function devIcon(d, source) {
        return d.bt || /head|buds|airpods/i.test(d.name) ? "headphones" : source ? "mic"
             : /macbook|built-in|laptop/i.test(d.name) ? "laptop" : /tv|display|monitor/i.test(d.name) ? "tv" : "speaker"
    }
    function soundRows() {
        const pct = v => Math.round(v * 100) + "%"
        const r = [{ kind: "header", name: "Output" },
                   { kind: "slider", key: "volume", name: "Volume", value: volume, dimmed: muted, extra: "mute",
                     glyph: muted || volume === 0 ? "volume-x" : volume < 0.34 ? "volume" : volume < 0.67 ? "volume-1" : "volume-2",
                     summary: muted ? "muted" : pct(volume) }]
        for (const d of sinks)
            r.push({ kind: "sounddev", id: d.id, name: d.name, glyph: devIcon(d, false), trailGlyph: d.current ? "check" : undefined,
                     summary: s.airplayRefused.includes(d.node) ? "no audio (Apple bug)" : d.airplay && !d.current ? "AirPlay" : undefined,
                     extra: "output speakers" + (d.airplay ? " airplay" : "") })
        r.push({ kind: "header", name: "Microphone" },
               { kind: "slider", key: "mic", name: "Microphone", value: micVolume, dimmed: micMuted, extra: "mute input",
                 glyph: micMuted ? "mic-off" : "mic", summary: micMuted ? "muted" : pct(micVolume) })
        for (const d of sources)
            r.push({ kind: "sounddev", id: d.id, name: d.name, glyph: devIcon(d, true), trailGlyph: d.current ? "check" : undefined,
                     summary: d.bt ? "headset mode" : undefined, extra: "input microphone" })
        for (const d of btMics)
            r.push({ kind: "btmic", card: d.card, name: d.name, glyph: "headphones", extra: "input microphone headphones",
                     summary: btMicBusy === d.card ? "switching…" : btMicFailed === d.card ? "didn't switch" : "headset mode" })
        r.push({ kind: "header", name: "More" })
        // Bluetooth headphones' own page (modes, battery, equalizer), while they are connected
        const bt = sinks.find(d => d.bt)
        if (bt) r.push({ kind: "nav", name: "Headphones", glyph: "headphones", target: "headphones", summary: bt.name, extra: "headphones airpods noise" })
        r.push({ kind: "action", name: "Sound settings…", glyph: "settings", cmd: ["pavucontrol"] })
        return r
    }
    Timer { interval: 1000; repeat: true; running: s.shown && s.level === "sound"; onTriggered: { s.soundRefresh(); s.probeAirplay() } }
    function probeAirplay() {
        const nodes = sinks.filter(d => d.airplay).map(d => d.node)
        if (nodes.length === 0 || airplayProbe.running || Date.now() - airplayProbedAt < 30000) return
        airplayProbedAt = Date.now()
        airplayProbe.command = [airplayCheck, "refused"].concat(nodes)
        airplayProbe.running = true
    }
    Sh {
        id: airplayProbe
        onResult: text => {
            const refused = text.split("\n").filter(l => l !== "")
            if (JSON.stringify(refused) === JSON.stringify(s.airplayRefused)) return
            s.sel(); s.airplayRefused = refused
        }
    }
    Timer { id: soundSoon; interval: 150; onTriggered: s.soundRefresh() }
    Timer {
        id: volApply; interval: 60
        onTriggered: {
            if (s.pending >= 0) { Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", s.pending.toFixed(2)]); s.pending = -1 }
            if (s.micPending >= 0) { Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", s.micPending.toFixed(2)]); s.micPending = -1 }
        }
    }
    Sh {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        onResult: text => {
            const r = text.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
            if (!r || s.pending >= 0 || (parseFloat(r[1]) === s.volume && !!r[2] === s.muted)) return
            s.sel(); s.volume = parseFloat(r[1]); s.muted = !!r[2]
        }
    }
    Sh {
        id: micProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        onResult: text => {
            const r = text.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
            if (!r || s.micPending >= 0 || (parseFloat(r[1]) === s.micVolume && !!r[2] === s.micMuted)) return
            s.sel(); s.micVolume = parseFloat(r[1]); s.micMuted = !!r[2]
        }
    }
    Sh {
        id: dumpProc
        command: ["pw-dump"]
        onResult: text => {
            let objs
            try { objs = JSON.parse(text) } catch (e) { return }
            const def = {}
            for (const ob of objs) {
                if (ob.type !== "PipeWire:Interface:Metadata") continue
                for (const e of (ob.metadata || []))
                    if ((e.key === "default.audio.sink" || e.key === "default.audio.source") && e.value) def[e.key] = e.value.name
            }
            const out = { "Audio/Sink": [], "Audio/Source": [] }
            for (const ob of objs) {
                if (ob.type !== "PipeWire:Interface:Node") continue
                const p = (ob.info || {}).props || {}
                const list = out[p["media.class"]]
                if (!list || /^easyeffects_/.test(p["node.name"])) continue   // EasyEffects' virtual device, not a real one
                const key = p["media.class"] === "Audio/Sink" ? "default.audio.sink" : "default.audio.source"
                list.push({ id: ob.id, name: p["node.description"] || p["node.name"], current: p["node.name"] === def[key], bt: /^bluez_/.test(p["node.name"]),
                            airplay: /^raop_sink\./.test(p["node.name"]),   // PipeWire's AirPlay speakers (RAOP)
                            node: p["node.name"] })
            }
            // The same kinds together, as in OutputList: the machine's own, Bluetooth headphones, other wired, AirPlay
            const rank = d => /^MacBook Pro/i.test(d.name) ? 0 : /^Built-in/i.test(d.name) ? 1 : d.bt ? 2 : d.airplay ? 5 : 4
            for (const k in out) out[k].sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name))
            if (JSON.stringify(out["Audio/Sink"]) === JSON.stringify(s.sinks) && JSON.stringify(out["Audio/Source"]) === JSON.stringify(s.sources)) return
            s.sel()
            s.sinks = out["Audio/Sink"]
            s.probeAirplay()
            s.sources = out["Audio/Source"]
        }
    }

    // ================= Headphones (as in HeadphonesMenu: topbar/scripts/eq info) =================
    readonly property string eq: Quickshell.env("HOME") + "/.config/topbar/scripts/eq"
    property var hp: ({})
    function hpRows() {
        if (!hp.sink) return hint("No headphones connected")
        const r = [{ kind: "hpdev", name: hp.name, glyph: "headphones", current: !!hp.default, summary: hp.codec || undefined,
                     trailGlyph: hp.default ? "check" : undefined }]
        // Battery: AirPods per pod and case (hypr/scripts/headphones-ctl), other headphones the level BlueZ reports
        const pods = (hp.airpods && hp.airpods.pods) || {}
        const bats = ["left", "right", "case"].filter(k => pods[k]).map(k => Object.assign({ key: k }, pods[k]))
        if (bats.length === 0 && /^\d+$/.test(hp.battery || "")) bats.push({ key: "", level: parseInt(hp.battery) })
        if (bats.length > 0) r.push({ kind: "header", name: "Battery" })
        for (const b of bats) {
            const where = b.key === "case" ? (b.stale ? "earlier" : b.charging ? "charging" : "")
                        : b.charging ? "charging" : ({ ear: "in ear", out: "out", case: "in case" })[b.where] || ""
            r.push({ kind: "battery", name: ({ left: "Left", right: "Right", case: "Case", "": "Battery" })[b.key], value: b.level / 100,
                     charging: !!b.charging, dimmed: !!b.stale, low: b.level < 20 && !b.charging && !b.stale,
                     glyph: b.charging ? "zap" : b.where === "ear" ? "ear" : "battery-medium",
                     summary: b.level + "%" + (where ? " · " + where : "") })
        }
        if ((hp.ancModes || []).length > 1) {
            r.push({ kind: "header", name: "Listening mode" })
            const icons = { "Noise cancelling": "ear-off", "Adaptive": "sparkles", "Transparency": "ear", "Passive": "mic-audio-lines" }
            const rank = m => { const i = Object.keys(icons).indexOf(m); return i < 0 ? 99 : i }   // in the menu's order
            for (const m of hp.ancModes.slice().sort((a, b) => rank(a) - rank(b)))
                r.push({ kind: "hpmode", name: m, glyph: icons[m] || "headphones", trailGlyph: hp.anc === m ? "check" : undefined })
        }
        r.push({ kind: "header", name: "More" })
        if (hp.airpods) r.push({ kind: "action", name: "AirPods settings…", glyph: "settings", cmd: ["qs", "ipc", "call", "airpods", "open"] })
        r.push({ kind: "menu", name: "Equalizer…", glyph: "sliders-horizontal", target: "headphones",
                 summary: hp.preset && hp.preset !== "off" ? hp.preset : "off" })
        return r
    }
    Timer { interval: 2000; repeat: true; running: s.shown && s.level === "headphones"; onTriggered: hpProc.running = true }
    Timer { id: hpSoon; interval: 800; onTriggered: hpProc.running = true }
    Sh {
        id: hpProc
        command: [s.eq, "info"]
        onResult: text => {
            let v
            try { v = JSON.parse(text) } catch (e) { return }
            if (JSON.stringify(v) === JSON.stringify(s.hp)) return
            s.sel()
            s.hp = v
        }
    }
    Sh {
        id: hpSet
        onResult: () => { hpProc.running = true; TopBar.refresh("headphones") }
    }

    // ================= Tailscale (as in the Tailscale plugin's menu, plugins/tailscale/TailscaleMenu.qml) =================
    property bool tsRunning: LastState.tailscale
    onTsRunningChanged: LastState.tailscale = tsRunning
    property bool tsNeedsLogin: false
    property string selfIp: ""
    property string selfName: ""
    property var peers: []           // [{ host, ip, online, os }]
    property string tsMessage: ""
    property string copied: ""
    Timer { id: copiedTimer; interval: 1500; onTriggered: { s.sel(); s.copied = "" } }
    function tsRows() {
        const r = [{ kind: "systoggle", key: "tailscale", name: "Tailscale", glyph: tsRunning ? "shield-check" : "shield-off", switchOn: tsRunning }]
        if (tsNeedsLogin && !tsRunning)
            r.push({ kind: "tslogin", name: "Log in", glyph: "log-in", summary: "opens the link in the browser" })
        if (tsMessage !== "") r.push({ kind: "hint", name: tsMessage })
        if (!tsRunning) return r
        if (selfIp !== "") r.push({ kind: "header", name: "This machine" },
                                  { kind: "tsmachine", name: selfName, ip: selfIp, copy: selfIp, glyph: "laptop-minimal-check", summary: copied === selfIp ? "copied" : selfIp })
        for (const online of [true, false]) {
            const list = peers.filter(p => p.online === online)
            if (list.length === 0) continue
            r.push({ kind: "header", name: online ? "Online" : "Offline" })
            for (const p of list)
                r.push({ kind: "tsmachine", name: p.host, ip: p.ip, copy: p.ip, dimmed: !online, extra: p.ip + " " + p.os,
                         glyph: /mac|ios/i.test(p.os) ? "laptop" : /android/i.test(p.os) ? "smartphone" : "server",
                         summary: copied === p.ip ? "copied" : p.ip })
        }
        r.push({ kind: "header", name: "More" })
        r.push({ kind: "action", name: "Admin console", glyph: "external-link", cmd: ["xdg-open", "https://login.tailscale.com/admin/machines"] })
        return r
    }
    Timer { interval: 3000; repeat: true; running: s.shown && s.level === "tailscale"; onTriggered: tsProc.running = true }
    Sh {
        id: tsProc
        command: ["tailscale", "status", "--json"]
        onResult: text => {
            let j
            try { j = JSON.parse(text) } catch (e) { s.sel(); s.tsRunning = false; s.peers = []; return }
            const arr = []
            for (const k in (j.Peer || {})) {
                const p = j.Peer[k]
                arr.push({ host: p.HostName, ip: (p.TailscaleIPs || [""])[0], online: !!p.Online, os: p.OS })
            }
            arr.sort((a, b) => (b.online - a.online) || a.host.localeCompare(b.host))
            const running = j.BackendState === "Running"
            const needsLogin = j.BackendState === "NeedsLogin"
            const ip = ((j.Self || {}).TailscaleIPs || [""])[0]
            if (running === s.tsRunning && needsLogin === s.tsNeedsLogin && ip === s.selfIp
                && JSON.stringify(arr) === JSON.stringify(s.peers)) return
            s.sel()
            s.tsRunning = running
            s.tsNeedsLogin = needsLogin
            if (running && s.tsMessage === s.tsWaiting) s.tsMessage = ""
            s.selfIp = ip
            s.selfName = (j.Self || {}).HostName || ""
            s.peers = arr
        }
    }
    // Logging in: the plugin's ./login starts it and opens the link in the browser; the rows follow tailscale status
    // until it's done
    readonly property string tsWaiting: "Finish logging in in the browser"
    function tsLogin() {
        const menu = TopBar.plugin.menus.tailscale || ""
        if (menu === "") { tsMessage = "Turn the Tailscale plugin on to log in here, or run tailscale up in a terminal"; return }
        tsMessage = ""
        tsToggle.script = "'" + menu.replace(/[^/]*$/, "login") + "'"
        tsToggle.loggingIn = true
        tsToggle.running = true
    }
    Sh {
        id: tsToggle
        property bool loggingIn: false
        onResult: text => {
            s.sel()
            if (tsToggle.loggingIn && tsToggle.exitCode === 0) s.tsMessage = s.tsWaiting
            tsToggle.loggingIn = false
            if (tsToggle.exitCode !== 0)
                s.tsMessage = /denied|operator/i.test(text) ? "Permission denied. Run once: sudo tailscale set --operator=$USER"
                                                            : text.trim().split("\n").pop()
            tsProc.running = true
        }
    }

    // ================= Status (topbar/scripts/sysinfo menu and claude-usage; as in SystemMenu and ClaudeMenu) =================
    // The rows only change when their shape does (how many temperatures, processes, usage windows); the values, and the
    // processes' names, are live (liveText), so the list doesn't jump every two seconds
    property var sysData: null       // { cpu, cores, freq, load, memUsed, memTotal, swapUsed, swapTotal, temps: [{ label, c }], top: [{ name, cpu, rss }] }
    property var usage: null         // { plan, windows: [{ key, percent, resetsAt, model }], error }
    property bool usageLoaded: false
    property string statusShape: ""
    property var statusSnap: ({ d: null, u: null })   // the data the rows were built from (statusRows reads only this)
    function updateShape() {
        const d = sysData, u = usage
        const shape = JSON.stringify([d ? d.temps.map(t => t.label) : null, d ? d.top.length : 0,
                                      u && u.windows ? u.windows.map(w => w.key + w.model) : null, u ? u.error || "" : "", u ? u.plan || "" : "", usageLoaded])
        if (shape !== statusShape) { sel(); statusShape = shape; statusSnap = { d: d, u: u } }
    }
    function gb(b) { return (b / 1073741824).toFixed(1) }
    function mb(b) { return b >= 1073741824 ? gb(b) + " GB" : Math.round(b / 1048576) + " MB" }
    function usageLabel(w) { return w.key === "session" ? "5-hour session" : w.key === "weekly" ? "Weekly" : "Weekly · " + (w.model || "model") }
    function resets(iso) {           // "resets in 1h 28m" (under 24 h) or "resets Wed 01:00"
        const t = new Date(iso)
        if (isNaN(t)) return ""
        const d = Math.round((t - new Date()) / 1000)
        if (d <= 0) return "resetting now"
        if (d < 86400) { const h = Math.floor(d / 3600), mi = Math.floor(d % 3600 / 60); return "resets in " + (h > 0 ? h + "h " : "") + mi + "m" }
        return "resets " + Qt.formatDateTime(t, "ddd HH:mm")
    }
    function statusLive(key) {
        const d = sysData
        const [k, i] = key.split(":")
        if (k === "cpu") return d ? d.cpu + "%  ·  load " + d.load.join("  ") : ""
        if (k === "mem") return d ? gb(d.memUsed) + " / " + gb(d.memTotal) + " GB" + (d.swapUsed > 0 ? "  ·  swap " + mb(d.swapUsed) : "") : ""
        if (k === "temp") return d && d.temps[i] ? d.temps[i].c + " °C" : ""
        if (k === "procname") return d && d.top[i] ? d.top[i].name : ""
        if (k === "proc") return d && d.top[i] ? d.top[i].cpu.toFixed(1) + "%  ·  " + mb(d.top[i].rss) : ""
        if (k === "usage") { const w = usage && usage.windows ? usage.windows[i] : null; return w ? w.percent + "%  ·  " + resets(w.resetsAt) : "" }
        return ""
    }
    function statusRows() {
        const d = statusSnap.d, u = statusSnap.u   // not sysData / usage: they change every two seconds
        const r = [{ kind: "header", name: "System" }]
        if (!d) r.push({ kind: "hint", name: "Loading…" })
        else {
            r.push({ kind: "stat", name: "CPU", glyph: "cpu", live: "cpu", extra: "processor load" },
                   { kind: "stat", name: "Memory", glyph: "memory-stick", live: "mem", extra: "ram swap" })
            if (d.temps.length > 0) r.push({ kind: "header", name: "Temperatures" })
            d.temps.forEach((t, i) => r.push({ kind: "stat", name: t.label, glyph: "thermometer", live: "temp:" + i, extra: "temperature" }))
            if (d.top.length > 0) r.push({ kind: "header", name: "Top processes (CPU, 1 core = 100 %)" })
            d.top.forEach((p, i) => r.push({ kind: "stat", name: p.name, liveName: "procname:" + i, glyph: "activity", live: "proc:" + i, extra: "process" }))
        }
        r.push({ kind: "header", name: "Claude usage" + (u && u.plan ? " · " + u.plan : "") })
        if (usageLoaded && (!u || !u.windows || u.windows.length === 0 || u.error))
            r.push({ kind: "hint", name: u && u.error ? u.error : "No usage data. Sign in to Claude Code (run claude) first." })
        if (u && u.windows) u.windows.forEach((w, i) => r.push({ kind: "stat", name: usageLabel(w), glyph: "gauge", live: "usage:" + i, extra: "claude usage limit" }))
        r.push({ kind: "header", name: "More" },
               { kind: "action", name: "Open Claude usage page", glyph: "external-link", cmd: ["xdg-open", "https://claude.ai/settings/usage"], extra: "claude" })
        return r
    }
    Timer { interval: 2000; repeat: true; running: s.shown && s.level === "status"; onTriggered: sysProc.running = true }
    Timer { interval: 5000; repeat: true; running: s.shown && s.level === "status"; onTriggered: claudeProc.running = true }
    Sh {
        id: sysProc
        command: ["bash", "-c", "~/.config/topbar/scripts/sysinfo menu"]
        onResult: text => { try { s.sysData = JSON.parse(text); s.updateShape() } catch (e) {} }
    }
    Sh {
        id: claudeProc
        command: [Quickshell.env("HOME") + "/.config/topbar/scripts/claude-usage"]
        onResult: text => {
            try { s.usage = JSON.parse(text) } catch (e) { s.usage = null }
            s.usageLoaded = true
            s.updateShape()
        }
    }

    // ================= Screen Mirroring (AirPlay with doubletake; the mirroring plugin, plugins/mirroring) =================
    // Rows for Settings › Display (Launcher.qml adds them under Screen Mirroring). Nothing while the plugin isn't installed
    // or is off.
    readonly property string mirrorScript: Quickshell.env("HOME") + "/.local/bin/mirroring"
    property bool mirrorAvail: false
    property var mirrorDevices: []   // [{ name, model, ip }]
    property string mirrorState: "idle"   // idle | connecting | pin_required | streaming
    property string mirrorIp: ""
    readonly property string mirrorName: (mirrorDevices.find(d => d.ip === mirrorIp) || {}).name || ""
    function mirrorRows() {
        if (!mirrorAvail) return []
        const r = [{ kind: "header", name: "Screen Mirroring" }]
        if (mirrorDevices.length === 0) r.push({ kind: "hint", name: "Looking for AirPlay devices…" })
        for (const d of mirrorDevices) {
            const mine = d.ip === mirrorIp && mirrorState !== "idle"
            r.push({ kind: "mirrordev", name: d.name, ip: d.ip, extra: "airplay cast mirror " + d.model,
                     glyph: /STR-|receiver|HomePod|AudioAccessory|speaker/i.test(d.name + " " + d.model) ? "speaker" : "tv",
                     summary: !mine ? "AirPlay" : mirrorState === "streaming" ? "mirroring" : mirrorState === "pin_required" ? "waiting for the code" : "connecting…",
                     trailGlyph: mine && mirrorState === "streaming" ? "check" : undefined })
        }
        return r
    }
    Timer { interval: 2000; repeat: true; running: s.launcher !== null && s.launcher.open && (s.level === "display" || s.level === "mirrorpin"); onTriggered: mirrorProc.running = true }
    Sh {
        id: mirrorProc
        script: 'c="$HOME/.local/bin/doubletake-ctl"; [ -x "$c" ] || exit 0; "$c" status; echo; "$c" devices; echo; printf "{\\"self\\": \\"%s\\"}\\n" "$(hostname -I)"'
        onResult: text => {
            const parts = text.trim().split(/\n(?=\{)/)   // three JSON objects: status, devices, and this computer's addresses
            let st = null, dev = null
            let self = []
            try { st = JSON.parse(parts[0]); dev = JSON.parse(parts[1]); self = JSON.parse(parts[2]).self.trim().split(/\s+/) } catch (e) {}
            const avail = Plugins.has("mirroring") && st !== null && st.ok === true   // off: hidden, though doubletake runs
            // Only what can show a screen: not this computer's own receiver (AirPlay Receiver), nor a speaker. AirPlay's
            // listing doesn't say which can show video, so speakers are told by their model: Sonos (One, Era 300…),
            // HomePods, receivers
            const speaker = /^(One|One SL|Era \d+|Five|Play:\d|Move|Roam|Beam|Arc|Ray|Sub|Port|Amp|Connect)\b|HomePod|AudioAccessory|STR-/i
            const devices = dev && dev.devices ? dev.devices.filter(d => !self.includes(d.ip) && !speaker.test(d.model || ""))
                                                            .map(d => ({ name: d.name, model: d.model || "", ip: d.ip })) : []
            const state = st && st.state ? st.state : "idle"
            const ip = st && st.device_ip ? st.device_ip : ""
            if (avail === s.mirrorAvail && state === s.mirrorState && ip === s.mirrorIp && JSON.stringify(devices) === JSON.stringify(s.mirrorDevices)) return
            s.sel()
            s.mirrorAvail = avail; s.mirrorState = state; s.mirrorIp = ip; s.mirrorDevices = devices
        }
    }
}
