import QtQuick
import Quickshell

// The launcher's Settings › Wi-Fi and its password page: the top bar's WifiMenu as launcher rows, so the launcher doesn't
// hand over to the menu. Launcher.qml asks it like its other Levels files (levels, titles, parents, items, activate, footer,
// entered), and for liveText: the rate and the ping change every second, so they are bound in their rows instead of
// rebuilding the list. The networks are read only while one of its levels is open. Split from SystemLevels.qml (#1937).
Item {
    id: s
    property var launcher: null

    readonly property var inputs: ["wifipw"]   // text fields: ⌘⇧V pastes into them (ClipPicker)
    readonly property var levels: ["wifi", "wifipw"]
    readonly property var titles: ({ wifi: "Settings › Wi-Fi", wifipw: "Wi-Fi › Password" })
    readonly property var parents: ({ wifi: "settings", wifipw: "wifi" })
    readonly property string level: launcher ? launcher.level : ""
    readonly property bool shown: launcher !== null && launcher.open && levels.indexOf(level) >= 0
    readonly property string copied: launcher ? launcher.rowCopy.copied : ""   // a row just copied says so (RowCopy)

    function row(r) { return { item: r, text: r.kind === "header" || r.kind === "hint" ? "" : r.name, extra: r.extra || "" } }
    function sel() { if (launcher) launcher.keepSelection() }   // a refresh rebuilds the rows: keep the selected one

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "systoggle") return "Enter: on/off"
        if (cur.kind === "wifinet") return cur.active ? "" : "Enter: connect"
        if (cur.copy !== undefined) return "Enter: copy  ·  Cmd+C: copy"
        if (level === "wifipw") return query !== "" ? "Enter: connect  ·  Esc: back" : ""
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level === "wifi") { wifiMessage = ""; wifiRefresh(); rescan(); if (activeSsid !== "") ipProc.running = true }
    }
    function shiftActivate(item) {}

    function items(level, q) {
        if (level === "wifi") return { all: wifiRows().map(row) }
        if (level === "wifipw") return [{ kind: "wificonnect", name: "Connect to “" + askFor + "”", glyph: "lock",
                                          summary: launcher.query === "" ? "type the password" : undefined, dimmed: launcher.query === "" }]
        return []
    }

    // Enter on a row. Returns true when the row was one of ours.
    function activate(it) {
        if (it.kind === "systoggle" && it.key === "wifi") {
            sel()
            wifiOn = !wifiOn
            TopBar.run("nmcli radio wifi " + (wifiOn ? "on" : "off"), "wifi")
            if (!wifiOn) nets = []
            return true
        }
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
        return false
    }
    // Rows that need a second Enter (the launcher shows the armHint while armed); true = confirmed
    function arm(key) {
        if (launcher.armed !== key) { launcher.armed = key; disarmTimer.restart(); return false }
        launcher.armed = ""
        return true
    }
    Timer { id: disarmTimer; interval: 4000; onTriggered: if (s.launcher) s.launcher.armed = "" }

    // Values that change every second are bound in the row (the launcher asks with the row's `live` key), not baked into
    // the rows: rebuilding the rows every second made the list jump while moving in it
    function liveText(key) {
        if (key === "wifirate") return "↓ " + fmtRate(rxRate) + "   ↑ " + fmtRate(txRate)
        if (key === "wifilocal") return !link.ip ? "…" : copied !== "" && copied === link.ip ? "copied"
                                        : link.ip + (linkPing < 0 ? "" : " · " + (linkPing < 1 ? "<1" : Math.round(linkPing)) + " ms")
        return undefined   // not one of ours: Launcher.qml asks the next file
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
        script: 'if [ -n "$PW" ]; then printf "%s\\n" "$PW" | nmcli --ask --wait 20 device wifi connect "$SSID" >/dev/null; else nmcli --wait 20 device wifi connect "$SSID"; fi'
        // ^ The password on nmcli's stdin (--ask), not in its arguments (as WifiMenu, #1740); the prompt on stdout dropped
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
}
