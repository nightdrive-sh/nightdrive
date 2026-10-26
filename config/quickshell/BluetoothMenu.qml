import QtQuick
import Quickshell
import Quickshell.Io

// Bluetooth: on/off, devices, connecting, scanning for devices. Uses bluetoothctl.
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 8

    property bool powered: LastState.bluetooth
    onPoweredChanged: LastState.bluetooth = powered
    property var devices: []         // [{ mac, connected, paired, battery, name, named }]
    // Nameless devices (only an address: mostly nearby phones, Macs and AirTags with a changing random address) are
    // hidden unless paired; "Show hidden devices" lists them too
    property bool showHidden: false
    readonly property var hidden: devices.filter(d => !d.named && !d.paired && !d.connected)
    readonly property var shown: showHidden ? devices : devices.filter(d => hidden.indexOf(d) < 0)
    property bool scanning: false
    property string busy: ""
    property string message: ""
    property string messageMac: ""   // the device the error is about: it clears once that device is connected
    property string passkey: ""      // shown while pairing a keyboard that asks for it to be typed
    signal close()

    function refresh() { powerProc.running = true; listProc.running = true }
    function scan() {
        if (m.scanning || !m.powered) return
        m.scanning = true
        scanProc.running = true
    }
    function activate(d) {
        if (m.busy !== "") return
        m.busy = d.mac; m.message = ""; m.messageMac = d.mac
        if (!d.connected && !d.paired) {
            pairProc.environment = { "MAC": d.mac }
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
    function iconFor(name) {
        return /head|buds|airpods|wh-|wf-|sony/i.test(name) ? "headphones"
             : /mouse|mx |trackpad/i.test(name) ? "mouse"
             : /keyboard|keys/i.test(name) ? "keyboard"
             : /phone|iphone|pixel|galaxy/i.test(name) ? "smartphone"
             : /watch/i.test(name) ? "watch"
             : /speaker|boom|jbl|soundbar/i.test(name) ? "speaker" : "bluetooth"
    }
    Component.onCompleted: refresh()

    Timer { interval: 2500; repeat: true; running: true; onTriggered: m.refresh() }

    Sh {
        id: powerProc
        // Without bluetoothd (the sandbox, a VM) bluetoothctl aborts or hangs
        script: 'systemctl is-active -q bluetooth 2>/dev/null && bluetoothctl show'
        onResult: text => m.powered = /Powered:\s*yes/.test(text)
    }
    Sh {
        id: listProc
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
                arr.push({ mac: f[0], connected: f[1] !== "0", paired: f[2] !== "0", battery: f[3], named: f[4] !== "0",
                           name: f.slice(5).join("|") })
            }
            arr.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
            m.devices = arr
            // e.g. connecting failed while the headphones were off, and they connected by themselves once switched on
            if (m.message !== "" && arr.some(d => d.mac === m.messageMac && d.connected)) m.message = ""
        }
    }
    Sh {
        id: scanProc
        // 20 s: headphones' names (e.g. AirPods) can take a while to arrive; the list fills in as they do (refresh timer)
        command: ["bluetoothctl", "--timeout", "20", "scan", "on"]
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
    // Pairing reads the output as it comes: a keyboard may show a passkey to type on it (the agent prints it), and
    // that has to be on the screen while bluetoothctl waits, not after it
    Process {
        id: pairProc
        property string last: ""
        command: ["bash", "-c", 'exec 2>&1; bluetoothctl --agent KeyboardDisplay --timeout 60 pair "$MAC" && ' +
                  'bluetoothctl trust "$MAC" && bluetoothctl connect "$MAC"']
        stdout: SplitParser {
            onRead: line => {
                const l = line.replace(/\x1b\[[0-9;]*m/g, "").trim()
                if (l === "") return
                pairProc.last = l
                const k = l.match(/(?:passkey|pin code)\D*(\d{4,6})/i)
                if (k) m.passkey = k[1]
            }
        }
        onExited: code => { m.passkey = ""; m.done(code === 0, pairProc.last) }
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
                    width: parent.width
                    icon: m.iconFor(modelData.name)
                    label: modelData.name
                    active: modelData.connected
                    checkIcon: modelData.connected ? "check" : ""
                    hoverCheckIcon: modelData.connected ? "unplug" : ""   // a click disconnects
                    busy: m.busy === modelData.mac
                    detail: modelData.battery !== "" ? modelData.battery + "%"
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
