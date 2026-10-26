import QtQuick
import Quickshell

// Wi-Fi: on/off, network list, connecting (asks for a password for new secured networks). The wired profiles
// (WiredProfiles.qml) below it when there are two or more; without a Wi-Fi device only the cable and those.
// Uses nmcli (Quickshell's Networking module returns no data on this machine).
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 8

    property bool wifiOn: LastState.wifi
    onWifiOnChanged: LastState.wifi = wifiOn
    property var nets: []            // [{ ssid, signal, secure, active, known }]
    property var knownSet: ({})
    property string connecting: ""
    property string askFor: ""       // network whose password is being asked for
    // The typed password lives here, not in the field: the 3 s refresh rebuilds the list's rows, and the field with them
    property string pwText: ""
    onAskForChanged: pwText = ""
    property string message: ""
    signal close()

    // nmcli -t separates fields with ':' and escapes a ':' inside a field as \:
    function splitTerse(line) {
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
    function sigIcon(s) { return s >= 75 ? "wifi" : s >= 50 ? "wifi-high" : s >= 25 ? "wifi-low" : "wifi-zero" }

    readonly property var activeNet: nets.find(n => n.active) || null
    // The connection the traffic goes out on (hypr/scripts/net-primary): with a cable plugged in, the cable, and Wi-Fi
    // stays connected as a standby (NetworkManager's route metrics, as in macOS's service order)
    property var primary: ({})
    readonly property bool onCable: primary.type === "ethernet"
    readonly property bool wifiUp: wifiOn && activeNet !== null
    readonly property var otherNets: nets.filter(n => !n.active)
    // No Wi-Fi device (a VM, a PC on a cable): no toggle, no search, only the cable and its profiles
    readonly property bool hasWifi: wired.hasWifi
    readonly property bool wifiShown: wired.ready && hasWifi

    // Public IP (external service api.ipify.org): fetched when the menu opens, every minute and when the connected network changes
    property string publicIp: ""
    property bool ipFailed: false
    readonly property string activeSsid: activeNet ? activeNet.ssid : ""
    readonly property string route: onCable ? primary.dev : activeSsid   // what the public IP depends on
    onRouteChanged: { publicIp = ""; ipFailed = false; if (route !== "") ipProc.running = true }
    Timer { interval: 60000; repeat: true; running: m.route !== ""; onTriggered: ipProc.running = true }
    Sh {
        id: ipProc
        script: 'curl -s --max-time 5 https://api.ipify.org'
        onResult: text => {
            const ip = text.replace(/\s+/g, "")
            if (ipProc.exitCode === 0 && /^[0-9a-fA-F:.]{3,45}$/.test(ip)) { m.publicIp = ip; m.ipFailed = false }
            else if (m.publicIp === "") m.ipFailed = true
        }
    }

    // The link (hypr/scripts/wifi-info): band, standard, link rate; local IP and the router's ping. Every 5 s. Security and
    // the rest are in the launcher's Settings › Wi-Fi (the line would not fit the menu).
    property var link: ({})
    Timer { interval: 5000; repeat: true; running: m.activeSsid !== ""; triggeredOnStart: true; onTriggered: linkProc.running = true }
    Sh {
        id: linkProc
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/wifi-info"]
        onResult: text => { try { m.link = JSON.parse(text) } catch (e) {} }
    }
    function ms(v) { return v === null || v === undefined ? "" : v < 1 ? "<1 ms" : Math.round(v) + " ms" }
    // "…" until the first reading: the rows are there from the start, so the menu keeps its size
    readonly property string linkLine: [link.band, link.gen, link.rate].filter(x => x).join(" · ") || "…"
    readonly property string localLine: [link.ip, ms(link.ping)].filter(x => x).join(" · ") || "…"

    // Live throughput: read the byte counters of the interface in use (the cable's or Wi-Fi's) every second (only while
    // the menu is open)
    property real rxRate: 0
    property real txRate: 0
    // Shown values roll towards the measured ones over the second until the next reading (no jumps)
    property real rxShown: rxRate
    property real txShown: txRate
    Behavior on rxShown { NumberAnimation { duration: 950; easing.type: Easing.OutCubic } }
    Behavior on txShown { NumberAnimation { duration: 950; easing.type: Easing.OutCubic } }
    property real lastRx: -1
    property real lastTx: -1
    property real lastT: 0
    property string lastDev: ""
    function fmtRate(b) {
        const bits = b * 8
        if (bits >= 1e9) return (bits / 1e9).toFixed(2) + " Gb/s"
        if (bits >= 1e6) return (bits / 1e6).toFixed(1) + " Mb/s"
        if (bits >= 1e3) return Math.round(bits / 1e3) + " kb/s"
        return Math.round(bits) + " b/s"
    }
    Timer {
        interval: 1000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { rateProc.environment = { "DEV": m.onCable ? m.primary.dev : "" }; rateProc.running = true }
    }
    Sh {
        id: rateProc
        script: 'if [ -n "$DEV" ]; then i=/sys/class/net/$DEV; else for d in /sys/class/net/*/wireless; do i=${d%/wireless}; break; done; fi
[ -n "$i" ] && echo "$(cat $i/statistics/rx_bytes) $(cat $i/statistics/tx_bytes) ${i##*/}"'
        onResult: text => {
            const w = text.trim().split(/\s+/)
            const f = w.slice(0, 2).map(Number)
            if (w.length < 3 || isNaN(f[0])) return
            const now = Date.now()
            // Another interface (the cable plugged in or out) starts its counters from scratch, not as a jump from the old one's
            if (w[2] !== m.lastDev) { m.lastDev = w[2]; m.lastRx = -1; m.rxRate = 0; m.txRate = 0 }
            if (m.lastRx >= 0 && now > m.lastT) {
                const dt = (now - m.lastT) / 1000
                m.rxRate = Math.max(0, (f[0] - m.lastRx) / dt)
                m.txRate = Math.max(0, (f[1] - m.lastTx) / dt)
            }
            m.lastRx = f[0]; m.lastTx = f[1]; m.lastT = now
        }
    }

    function refresh() { radioProc.running = true; knownProc.running = true; listProc.running = true; primaryProc.running = true }
    function rescan() { Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"]) }
    Component.onCompleted: { refresh(); rescan() }

    Timer { interval: 3000; repeat: true; running: true; onTriggered: m.refresh() }
    Timer { interval: 10000; repeat: true; running: true; onTriggered: m.rescan() }

    function connectTo(n, password) {
        m.message = ""
        m.connecting = n.ssid
        connectProc.environment = { "SSID": n.ssid, "PW": password || "" }
        connectProc.running = true
    }
    function activate(n) {
        if (m.connecting !== "") return
        if (n.active) {
            m.connecting = n.ssid
            disconnectProc.environment = { "SSID": n.ssid }
            disconnectProc.running = true
        } else if (n.secure && !n.known) {
            m.askFor = (m.askFor === n.ssid) ? "" : n.ssid
        } else {
            connectTo(n, "")
        }
    }

    Sh {
        id: primaryProc
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/net-primary"]
        onResult: text => { try { m.primary = JSON.parse(text) } catch (e) {} }
    }
    Sh {
        id: radioProc
        command: ["nmcli", "radio", "wifi"]
        onResult: text => m.wifiOn = text.trim() === "enabled"
    }
    Sh {
        id: knownProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        onResult: text => {
            const set = {}
            for (const line of text.split("\n")) {
                const f = m.splitTerse(line)
                if (f.length >= 2 && f[1] === "802-11-wireless") set[f[0]] = true
            }
            m.knownSet = set
        }
    }
    Sh {
        id: listProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"]
        onResult: text => {
            const by = {}
            for (const line of text.split("\n")) {
                if (!line) continue
                const f = m.splitTerse(line)
                if (f.length < 4 || f[1] === "") continue
                const n = { ssid: f[1], signal: parseInt(f[2]) || 0, secure: f[3] !== "" && f[3] !== "--", active: f[0] === "*", known: !!m.knownSet[f[1]] }
                const old = by[n.ssid]
                if (!old || n.active || (!old.active && n.signal > old.signal)) by[n.ssid] = n
            }
            const arr = Object.values(by)
            arr.sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
            m.nets = arr
        }
    }
    Sh {
        id: connectProc
        script: 'if [ -n "$PW" ]; then nmcli --wait 20 device wifi connect "$SSID" password "$PW"; else nmcli --wait 20 device wifi connect "$SSID"; fi'
        onResult: text => {
            m.connecting = ""
            if (connectProc.exitCode !== 0) {
                const lines = text.trim().split("\n")
                m.message = lines[lines.length - 1].replace(/^Error:\s*/, "")
            } else {
                m.message = ""; m.askFor = ""
            }
            m.refresh()
        }
    }
    Sh {
        id: disconnectProc
        script: 'nmcli connection down id "$SSID"'
        onResult: text => { m.connecting = ""; m.refresh() }
    }
    // Forget: deletes the saved connection(s) of the network (its password too), which also disconnects. By the SSID
    // stored in each profile, as a profile's name can differ from it ("Home 1"). Needs a second click within 4 s.
    property string forgetArmed: ""
    Timer { id: forgetDisarm; interval: 4000; onTriggered: m.forgetArmed = "" }
    function forget(ssid) {
        if (m.forgetArmed !== ssid) { m.forgetArmed = ssid; forgetDisarm.restart(); return }
        m.forgetArmed = ""
        m.connecting = ssid
        forgetProc.environment = { "SSID": ssid }
        forgetProc.running = true
    }
    Sh {
        id: forgetProc
        script: 'nmcli -t -f UUID,TYPE connection show | while IFS=: read -r uuid type; do
  [ "$type" = 802-11-wireless ] && [ "$(nmcli -g 802-11-wireless.ssid connection show "$uuid")" = "$SSID" ] && nmcli connection delete uuid "$uuid"
done; true'
        onResult: text => { m.connecting = ""; m.refresh(); TopBar.refresh("wifi") }
    }

    // An IP line under the network's name: a click copies the address (wl-copy). Under the mouse a faint background and a
    // copy icon after it; a check for a moment once copied.
    component CopyLine: Rectangle {
        id: cl
        property string icon
        property string text
        property string value                     // what a click copies; "" = nothing to copy yet
        property bool copied: false
        visible: m.wifiUp
        x: 27                                     // the text stays under the network's name (33) with 6 px padding
        width: line.width + 12
        height: line.height + 4
        radius: 4
        color: area.containsMouse && value !== "" ? Theme.hover : "transparent"
        Row {
            id: line
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Text { text: Icons.g(cl.icon); color: Theme.accent; font { family: Icons.family; pixelSize: 13 } anchors.verticalCenter: parent.verticalCenter }
            Text { text: cl.text; color: cl.value !== "" ? Theme.text : Theme.dim; font { family: Theme.font; pixelSize: 12 } }
            Text {
                text: Icons.g(cl.copied ? "check" : "copy")
                opacity: cl.copied || (area.containsMouse && cl.value !== "") ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                color: cl.copied ? Theme.accent : Theme.dim
                font { family: Icons.family; pixelSize: 12 }
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: cl.value !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: { if (cl.value === "") return; Quickshell.execDetached(["wl-copy", cl.value]); cl.copied = true; copiedTimer.restart() }
        }
        Timer { id: copiedTimer; interval: 1500; onTriggered: cl.copied = false }
    }

    MenuHeader {
        width: parent.width
        title: m.onCable || !m.hasWifi ? "Network" : "Wi-Fi"
        subtitle: m.onCable && m.hasWifi ? "Wi-Fi" : ""   // what the toggle turns on and off
        showToggle: m.hasWifi
        checked: m.wifiOn
        onToggled: {
            m.wifiOn = !m.wifiOn
            // The bar's wifi icon updates as soon as nmcli is done, not on its next 5 s poll
            TopBar.run("nmcli radio wifi " + (m.wifiOn ? "on" : "off"), "wifi")
            if (!m.wifiOn) m.nets = []
        }
    }

    // A cable in use first: Ethernet with its link speed, throughput, public and local IP. Wi-Fi below it is the standby.
    MenuRow {
        visible: m.onCable
        width: parent.width
        icon: "cable"
        label: "Ethernet"
        detail: !m.primary.speed ? "" : m.primary.speed >= 1000 ? (m.primary.speed / 1000) + " Gb/s" : m.primary.speed + " Mb/s"
        interactive: false
        iconFilled: true
    }
    Rates { visible: m.onCable }
    CopyLine {
        visible: m.onCable
        icon: "globe"
        text: m.publicIp !== "" ? m.publicIp : (m.ipFailed ? "public IP unavailable" : "…")
        value: m.publicIp
    }
    CopyLine {
        visible: m.onCable
        icon: "router"
        text: m.primary.ip || "…"
        value: m.primary.ip || ""
    }
    Item { visible: m.onCable && m.wifiUp; width: 1; height: 6 }

    // Connected network at the top (an information row), throughput and public IP below it, then Disconnect and Forget.
    // Behind a cable only its own link: the traffic and the public IP are the cable's.
    MenuRow {
        visible: m.wifiUp
        width: parent.width
        icon: m.sigIcon(m.activeNet ? m.activeNet.signal : 0)
        label: m.activeSsid
        detail: m.onCable ? "standby" : ""
        interactive: false
        iconFilled: !m.onCable   // connected and in use (as in macOS: no highlighted row)
    }
    Rates { visible: m.wifiUp && !m.onCable }
    component Rates: Row {
        leftPadding: 33   // under the network's name (circle inset 3 + icon 20 + gap 10)
        spacing: 18
        Row {
            spacing: 6
            Text { text: Icons.g("arrow-down"); color: Theme.accent; font { family: Icons.family; pixelSize: 13 } anchors.verticalCenter: parent.verticalCenter }
            Text { text: m.fmtRate(m.rxShown); color: Theme.text; font { family: Theme.font; pixelSize: 12 } }
        }
        Row {
            spacing: 6
            Text { text: Icons.g("arrow-up"); color: Theme.accent; font { family: Icons.family; pixelSize: 13 } anchors.verticalCenter: parent.verticalCenter }
            Text { text: m.fmtRate(m.txShown); color: Theme.text; font { family: Theme.font; pixelSize: 12 } }
        }
    }
    CopyLine {
        visible: m.wifiUp && !m.onCable
        icon: "globe"
        text: m.publicIp !== "" ? m.publicIp : (m.ipFailed ? "public IP unavailable" : "…")
        value: m.publicIp
    }
    CopyLine {     // local IP and how long the router takes to answer (slow here = the Wi-Fi, not the internet)
        icon: "router"
        text: m.localLine
        value: m.link.ip || ""
    }
    Row {      // the link: 6 GHz · Wi-Fi 6E · 1.9 Gb/s
        visible: m.wifiOn && m.activeNet !== null
        leftPadding: 33
        spacing: 6
        Text { text: Icons.g("radio-tower"); color: Theme.accent; font { family: Icons.family; pixelSize: 13 } anchors.verticalCenter: parent.verticalCenter }
        Text { text: m.linkLine; color: Theme.dim; font { family: Theme.font; pixelSize: 12 } }
    }
    Item { visible: m.wifiOn && m.activeNet !== null; width: 1; height: 6 }   // extra space between the statistics and Disconnect
    MenuButton {
        visible: m.wifiOn && m.activeNet !== null
        width: parent.width
        icon: "unplug"
        label: "Disconnect"
        busy: m.connecting === m.activeSsid
        onClicked: m.activate(m.activeNet)
    }
    MenuButton {      // unlike Disconnect, also deletes the saved password: the network won't connect again by itself
        visible: m.wifiOn && m.activeNet !== null
        width: parent.width
        icon: "trash-2"
        danger: m.forgetArmed === m.activeSsid
        label: m.forgetArmed === m.activeSsid ? "Click again to forget" : "Forget network"
        onClicked: m.forget(m.activeSsid)
    }

    Item {      // the dots at the right edge, like the toggle above them
        visible: m.wifiShown && m.wifiOn && m.nets.length === 0
        width: parent.width
        height: searching.height
        MenuNote {
            id: searching
            text: "Searching for networks"
        }
        BusyDots { anchors.right: parent.right; y: (searching.height - height) / 2 + 1 }
    }
    MenuNote {
        visible: m.wifiShown && !m.wifiOn
        text: "Wi-Fi is off"
    }

    MenuNote {
        visible: wired.ready && !m.hasWifi && !m.onCable
        text: "Not connected"
    }

    MenuSection { visible: m.wifiShown && m.wifiOn && m.otherNets.length > 0; apart: m.activeNet !== null; title: m.activeNet ? "Other networks" : "Networks" }

    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: m.otherNets.slice(0, 8)
            delegate: Column {
                id: item
                required property var modelData
                width: parent.width
                spacing: 4

                MenuRow {
                    width: parent.width
                    icon: m.sigIcon(item.modelData.signal)
                    label: item.modelData.ssid
                    active: item.modelData.active
                    busy: m.connecting === item.modelData.ssid
                    detail: item.modelData.known && !item.modelData.active ? "saved" : ""
                    checkIcon: item.modelData.active ? "check" : (item.modelData.secure ? "lock" : "")
                    checkIconSize: 13
                    onClicked: m.activate(item.modelData)
                }

                // Password field for a new secured network
                Rectangle {
                    visible: m.askFor === item.modelData.ssid
                    width: parent.width
                    height: visible ? 36 : 0
                    radius: 8
                    color: Theme.hover
                    border.color: Theme.border
                    TextInput {
                        id: pw
                        anchors { left: parent.left; right: go.left; leftMargin: 12; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        echoMode: TextInput.Password
                        color: Theme.text
                        selectionColor: Theme.sel
                        font { family: Theme.font; pixelSize: 13 }
                        focus: parent.visible
                        onVisibleChanged: if (visible) forceActiveFocus()
                        Component.onCompleted: if (parent.visible) { text = m.pwText; forceActiveFocus() }
                        onTextChanged: if (parent.visible) m.pwText = text
                        onAccepted: if (text !== "") m.connectTo(item.modelData, text)
                        Text {
                            visible: pw.text === ""
                            text: "Password"
                            color: Theme.dim
                            font: pw.font
                        }
                    }
                    Text {
                        id: go
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: "Connect"
                        color: pw.text === "" ? Theme.dim : Theme.accent
                        font { family: Theme.font; pixelSize: 12 }
                        MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill: parent; onClicked: if (pw.text !== "") m.connectTo(item.modelData, pw.text) }
                    }
                }
            }
        }
    }

    MenuNote {
        visible: m.message !== ""
        variant: "danger"
        text: m.message
    }

    WiredProfiles {
        id: wired
        width: parent.width
        apart: m.onCable || m.wifiShown
    }

    MenuButton {
        width: parent.width
        gap: 10   // no divider above it: the room sets it apart
        icon: "settings"
        label: "Network settings…"
        onClicked: { Quickshell.execDetached(["nm-connection-editor"]); m.close() }   // all of NetworkManager's settings (IP, DNS, VPN)
    }
}
