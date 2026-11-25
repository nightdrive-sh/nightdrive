import QtQuick
import Quickshell
import Quickshell.Io
import "BluetoothDevices.js" as Bt

// Bluetooth: on/off, devices, connecting, scanning for devices. Uses bluetoothctl.
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 8

    property bool powered: LastState.bluetooth
    onPoweredChanged: LastState.bluetooth = powered
    property var devices: []         // [{ mac, connected, paired, bonded, battery, named, near, icon, name }] (BluetoothDevices.js)
    property var seen: ({})          // the devices found near the computer, which go first (Bt.parse)
    // Nameless devices (Bt.isHidden) are listed only with "Show hidden devices"
    property bool showHidden: false
    readonly property var hidden: devices.filter(Bt.isHidden)
    readonly property var shown: showHidden ? devices : devices.filter(d => hidden.indexOf(d) < 0)
    property bool scanning: false
    property string busy: ""
    property string message: ""
    property string messageMac: ""   // the device the error is about: it clears once that device is connected
    property string passkey: ""      // shown while pairing a keyboard that asks for it to be typed
    property string pairHint: ""     // what to do while pairing waits for the device (pairing mode)
    // The input devices paired without bonding, which do nothing until paired again (Bt.needsRepair)
    readonly property var broken: shown.filter(Bt.needsRepair)
    readonly property string pairScript: Quickshell.env("HOME") + "/.config/hypr/scripts/bt-pair"
    signal close()

    function refresh() { powerProc.running = true; listProc.running = true }
    function scan() {
        if (m.scanning || !m.powered) return
        m.scanning = true
        m.seen = {}
        scanProc.running = true
    }
    function activate(d) {
        if (m.busy !== "") return
        m.busy = d.mac; m.message = ""; m.messageMac = d.mac
        // A device paired without bonding is paired anew whatever its state: connected, it still does nothing
        const again = Bt.needsRepair(d)
        if (again || (!d.connected && !d.paired)) {
            m.pairHint = again ? Bt.repairHint(d) : ""
            pairProc.command = again ? [m.pairScript, d.mac, "--again"] : [m.pairScript, d.mac]
            pairProc.running = true
            return
        }
        actProc.environment = { "MAC": d.mac, "MODE": d.connected ? "disconnect" : "connect" }
        actProc.running = true
    }
    function done(ok, lastLine) {
        m.busy = ""
        if (!ok) m.message = lastLine
        m.refresh()
    }
    Component.onCompleted: {
        refresh()
        // A pairing goes on when the menu closes (bt-pair runs on its own): opened again, the menu follows it
        pairProc.command = [m.pairScript, "--follow"]
        pairProc.running = true
    }

    Timer { interval: 2500; repeat: true; running: true; onTriggered: m.refresh() }

    Sh {
        id: powerProc
        // Without bluetoothd (the sandbox, a VM) bluetoothctl aborts or hangs
        script: 'systemctl is-active -q bluetooth 2>/dev/null && bluetoothctl show'
        onResult: text => m.powered = /Powered:\s*yes/.test(text)
    }
    Sh {
        id: listProc
        script: Bt.LIST_SCRIPT
        onResult: text => {
            const arr = Bt.parse(text, m.seen)
            m.devices = arr
            // e.g. connecting failed while the headphones were off, and they connected by themselves once switched on
            if (m.message !== "" && arr.some(d => d.mac === m.messageMac && d.connected)) m.message = ""
        }
    }
    Sh {
        id: scanProc
        // Headphones' names (e.g. AirPods) can take a while to arrive, a controller is put in pairing mode after
        // pressing Scan: the list fills in as they do (refresh timer). Bt.SCAN_SECONDS says why it is a minute
        command: ["bluetoothctl", "--timeout", String(Bt.SCAN_SECONDS), "scan", "on"]
        onResult: text => { m.scanning = false; m.refresh() }
    }
    Sh {
        id: actProc
        script: 'case "$MODE" in\n' +
                '  disconnect) bluetoothctl disconnect "$MAC" ;;\n' +
                '  connect) bluetoothctl connect "$MAC" ;;\n' +
                'esac'
        onResult: text => {
            const lines = text.trim().split("\n")
            m.done(actProc.exitCode === 0, lines[lines.length - 1])
        }
    }
    // Pairing (hypr/scripts/bt-pair: pair, check the bond, trust, connect) reads the output as it comes: a keyboard may
    // show a passkey to type on it, and that has to be on the screen while bluetoothctl waits, not after it
    Process {
        id: pairProc
        property string last: ""
        stdout: SplitParser {
            onRead: line => {
                const l = line.replace(/\x1b\[[0-9;]*m/g, "").trim()
                if (l === "") return
                if (l.startsWith("__mac ")) { m.busy = m.messageMac = l.slice(6); return }
                pairProc.last = l
                const k = l.match(/(?:passkey|pin code)\D*(\d{4,6})/i)
                if (k) m.passkey = k[1]
            }
        }
        onExited: code => { m.passkey = ""; m.pairHint = ""; m.done(code === 0, pairProc.last) }
    }

    MenuHeader {
        width: parent.width
        title: "Bluetooth"
        showToggle: true
        checked: m.powered
        onToggled: {
            m.powered = !m.powered
            Quickshell.execDetached(["bluetoothctl", "power", m.powered ? "on" : "off"])
        }
    }

    MenuNote {
        visible: !m.powered
        text: "Bluetooth is off"
    }
    MenuNote {
        visible: m.powered && m.shown.length === 0
        text: "No devices. Press Scan for devices."
    }

    // A long list (a scan in a busy place) scrolls: maxRows whole rows, no sliver of the next one, so the menu
    // stays on the screen
    Flickable {
        id: flick
        readonly property int maxRows: 8
        visible: m.powered
        width: parent.width
        height: Math.min(rows.implicitHeight, maxRows * (34 + rows.spacing) - rows.spacing)
        contentHeight: rows.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        TouchScroll { view: flick }
        Column {
            id: rows
            width: flick.width
            spacing: 2
            Repeater {
                model: m.powered ? m.shown : []
                delegate: MenuRow {
                    required property var modelData
                    // Connected but without its key: not shown as working, and a click pairs it again
                    readonly property bool broken: Bt.needsRepair(modelData)
                    readonly property bool working: modelData.connected && !broken
                    width: parent.width
                    icon: Bt.iconFor(modelData)
                    label: modelData.name
                    active: working
                    checkIcon: working ? "check" : ""
                    hoverCheckIcon: working ? "unplug" : ""   // a click disconnects
                    busy: m.busy === modelData.mac
                    detail: broken ? "pair again"
                          : modelData.battery !== "" ? modelData.battery + "%"
                          : (!modelData.paired ? "not paired" : "")
                    onClicked: m.activate(modelData)
                }
            }
        }
    }

    MenuButton {
        visible: m.powered && m.hidden.length > 0
        width: parent.width
        icon: m.showHidden ? "eye-off" : "eye"
        label: (m.showHidden ? "Hide unnamed devices" : "Show hidden devices") + " (" + m.hidden.length + ")"
        onClicked: m.showHidden = !m.showHidden
    }

    MenuNote {
        visible: m.broken.length > 0 && m.busy === "" && m.message === ""
        variant: "warning"
        text: m.broken.length > 0 ? m.broken[0].name + " is paired, but its key wasn't saved, so it can't connect. " +
                                    "Click it to pair it again." : ""
    }
    MenuNote {
        visible: m.pairHint !== ""
        variant: "warning"
        text: m.pairHint
    }
    MenuNote {
        visible: m.passkey !== ""
        variant: "warning"
        text: "Type " + m.passkey + " on the keyboard, then Enter"
    }
    MenuNote {
        visible: m.message !== ""
        variant: "danger"
        text: m.message
    }

    MenuButton {
        visible: m.powered
        width: parent.width
        gap: 10   // no divider above it: the room sets it apart
        icon: "bluetooth-searching"
        label: m.scanning ? "Scanning…" : "Scan for devices"
        onClicked: m.scan()
    }
    MenuButton {
        width: parent.width
        icon: "settings"
        label: "Bluetooth settings…"
        onClicked: { Quickshell.execDetached(["blueman-manager"]); m.close() }
    }
}
