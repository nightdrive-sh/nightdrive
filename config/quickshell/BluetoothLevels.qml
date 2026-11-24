import QtQuick
import Quickshell
import "BluetoothDevices.js" as Bt

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
    property var devices: []         // [{ mac, connected, paired, battery, named, near, icon, name }] (BluetoothDevices.js)
    property var seen: ({})          // the devices found near the computer, which go first (Bt.parse)
    property bool showHidden: false
    property bool scanning: false
    property string btBusy: ""
    property string btMessage: ""
    function btRefresh() { powerProc.running = true; btListProc.running = true }
    function btScan() { if (!scanning && powered) { scanning = true; seen = {}; scanProc.running = true } }
    function btActivate(d) {
        if (btBusy !== "") return
        btBusy = d.mac; btMessage = ""
        actProc.environment = { "MAC": d.mac, "MODE": d.connected ? "disconnect" : (d.paired ? "connect" : "pair") }
        actProc.running = true
    }
    function btRows() {
        const r = [{ kind: "systoggle", key: "bluetooth", name: "Bluetooth", glyph: powered ? "bluetooth" : "bluetooth-off", switchOn: powered }]
        if (!powered) return r
        // Nameless devices are hidden unless paired, as in the menu
        const hidden = devices.filter(Bt.isHidden)
        const list = showHidden ? devices : devices.filter(d => hidden.indexOf(d) < 0)
        r.push({ kind: "header", name: "Devices" })
        if (list.length === 0) r.push({ kind: "hint", name: "No devices: Scan for devices below" })
        for (const d of list)
            r.push({ kind: "btdev", name: d.name, glyph: Bt.iconFor(d), dev: d, connected: d.connected, paired: d.paired,
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
        script: Bt.LIST_SCRIPT
        onResult: text => {
            const arr = Bt.parse(text, s.seen)
            if (JSON.stringify(arr) === JSON.stringify(s.devices)) return
            s.sel()
            s.devices = arr
        }
    }
    Sh {
        id: scanProc   // as long as the menu's: Bt.SCAN_SECONDS
        command: ["bluetoothctl", "--timeout", String(Bt.SCAN_SECONDS), "scan", "on"]
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
