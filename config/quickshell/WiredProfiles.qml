import QtQuick
import Quickshell

// The network menu's wired profiles (WifiMenu.qml): NetworkManager's Ethernet connections as rows to pick, the active one
// marked, when there are two or more. Also tells the menu whether the machine has a Wi-Fi device at all: without one (a
// VM, a desktop PC on a cable) the menu leaves its Wi-Fi parts out.
Column {
    id: w
    width: parent ? parent.width : 300
    spacing: 2

    property bool ready: false          // the first reading is in: until then the menu shows neither Wi-Fi nor these
    property bool hasWifi: true
    property var profiles: []           // [{ name, uuid, active }], the active one first
    property string switching: ""       // uuid of the profile being brought up
    property string message: ""
    property bool apart: true           // false right under the header, with nothing above to set it apart from
    // Only when there is a choice: the menu's Ethernet row already shows the one cable in use
    readonly property bool shown: ready && profiles.length > 1
    visible: shown

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

    function refresh() { listProc.running = true }
    Component.onCompleted: refresh()
    Timer { interval: 3000; repeat: true; running: true; onTriggered: w.refresh() }

    function pick(p) {
        if (p.active || w.switching !== "") return
        w.message = ""
        w.switching = p.uuid
        upProc.environment = { "UUID": p.uuid }
        upProc.running = true
    }

    Sh {
        id: listProc
        // Devices first (is there a Wi-Fi one?), then the profiles, apart by a line of their own
        script: 'nmcli -t -f TYPE device; echo --; nmcli -t -f NAME,UUID,TYPE,ACTIVE connection show'
        onResult: text => {
            const parts = text.split("\n--\n")
            if (parts.length < 2) return
            w.hasWifi = parts[0].split("\n").some(t => t.trim() === "wifi")
            const arr = []
            for (const line of parts[1].split("\n")) {
                const f = w.splitTerse(line)
                if (f.length >= 4 && f[2] === "802-3-ethernet") arr.push({ name: f[0], uuid: f[1], active: f[3] === "yes" })
            }
            arr.sort((a, b) => (b.active - a.active) || a.name.localeCompare(b.name))
            w.profiles = arr
            w.ready = true
        }
    }
    Sh {
        id: upProc
        script: 'nmcli --wait 20 connection up uuid "$UUID"'
        onResult: text => {
            w.switching = ""
            if (upProc.exitCode !== 0) {
                const lines = text.trim().split("\n")
                w.message = lines[lines.length - 1].replace(/^Error:\s*/, "")
            }
            w.refresh()
            TopBar.refresh("wifi")
        }
    }

    MenuSection { title: "Wired"; apart: w.apart }
    Item { width: 1; height: 4 }
    Repeater {
        model: w.profiles
        delegate: MenuRow {
            required property var modelData
            width: w.width
            icon: "cable"
            label: modelData.name
            active: modelData.active
            busy: w.switching === modelData.uuid
            checkIcon: modelData.active ? "check" : ""
            checkIconSize: 13
            onClicked: w.pick(modelData)
        }
    }
    MenuNote {
        visible: w.message !== ""
        variant: "danger"
        text: w.message
    }
}
