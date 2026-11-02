import QtQuick
import Quickshell

// The launcher's Settings › Bluetooth: the top bar's BluetoothMenu as launcher rows, so the launcher doesn't hand over to
// the menu. Launcher.qml asks it like its other Levels files (levels, titles, parents, items, activate, footer, entered).
// The devices are read only while the level is open. Split from SystemLevels.qml (#1937).
Item {
    id: s
    property var launcher: null

    readonly property var levels: ["bluetooth"]
    readonly property var titles: ({ bluetooth: "Settings › Bluetooth" })
    readonly property var parents: ({ bluetooth: "settings" })
    readonly property string level: launcher ? launcher.level : ""
    readonly property bool shown: launcher !== null && launcher.open && levels.indexOf(level) >= 0

    function row(r) { return { item: r, text: r.kind === "header" || r.kind === "hint" ? "" : r.name, extra: r.extra || "" } }
    function sel() { if (launcher) launcher.keepSelection() }   // a refresh rebuilds the rows: keep the selected one

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "systoggle") return "Enter: on/off"
        if (cur.kind === "btdev") return "Enter: " + (cur.connected ? "disconnect" : cur.paired ? "connect" : "pair and connect")
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level === "bluetooth") { btMessage = ""; btRefresh() }
    }
    function shiftActivate(item) {}

    function items(level, q) {
        if (level === "bluetooth") return { all: btRows().map(row) }
        return []
    }

    // Enter on a row. Returns true when the row was one of ours.
    function activate(it) {
        if (it.kind === "systoggle" && it.key === "bluetooth") {
            sel()
            powered = !powered
            Quickshell.execDetached(["bluetoothctl", "power", powered ? "on" : "off"])
            return true
        }
        if (it.kind === "btdev") { sel(); btActivate(it.dev); return true }
        if (it.kind === "bthidden") { sel(); showHidden = !showHidden; return true }
        if (it.kind === "btscan") { sel(); btScan(); return true }
        return false
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
}
