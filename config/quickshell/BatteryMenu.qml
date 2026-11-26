import QtQuick
import Quickshell

// Battery: charging state and time remaining (upower), the battery's details (topbar/scripts/sysinfo battery:
// power draw, temperature, health = capacity left of the original, cycles, voltage, age), and Low Power Mode's switch
// (hypr/scripts/low-power: tuned's power-saver until the charger goes in). Screen brightness is in
// DisplayMenu, the keyboard's backlight in the launcher's Settings › Display.
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 10

    property int percent: 0
    property string state: ""
    property string timeText: ""
    property var bat: null           // sysinfo battery
    property string low: ""          // Low Power Mode: on | off ("" until read, or without power-profiles-daemon)
    signal close()


    function fmt(v, unit) {
        let min = Math.round(parseFloat(v) * (/hour/.test(unit) ? 60 : /second/.test(unit) ? 1 / 60 : 1))
        const h = Math.floor(min / 60)
        return h > 0 ? h + " h " + (min % 60) + " min" : min + " min"
    }
    function refresh() { battProc.running = true; detailProc.running = true; lowProc.running = true }
    Component.onCompleted: refresh()
    Timer { interval: 3000; repeat: true; running: true; onTriggered: m.refresh() }

    Sh {
        id: battProc
        // The machine's own battery, found like in topbar/scripts/status (MacBook: macsmc-battery; Bluetooth devices skipped)
        script: 'for d in /sys/class/power_supply/*; do [ "$(cat "$d/type")" = Battery ] && [ "$(cat "$d/scope" 2>/dev/null)" != Device ] &&
                 { upower -i "/org/freedesktop/UPower/devices/battery_$(basename "$d" | tr - _)"; break; }; done'
        onResult: text => {
            const g = re => { const r = text.match(re); return r ? r[1].trim() : "" }
            m.percent = parseInt(g(/percentage:\s*(\d+)/)) || 0
            m.state = g(/state:\s*(\S+)/)
            const tte = text.match(/time to empty:\s*([\d.,]+)\s*(\w+)/)
            const ttf = text.match(/time to full:\s*([\d.,]+)\s*(\w+)/)
            m.timeText = m.state === "discharging" && tte ? m.fmt(tte[1].replace(",", "."), tte[2])
                       : m.state === "charging" && ttf ? m.fmt(ttf[1].replace(",", "."), ttf[2]) : ""
        }
    }
    Sh {
        id: detailProc
        command: ["bash", "-c", "~/.config/topbar/scripts/sysinfo battery"]
        onResult: text => { try { m.bat = JSON.parse(text) } catch (e) { m.bat = null } }
    }

    Sh {
        id: lowProc
        script: 'l="$HOME/.config/hypr/scripts/low-power"; "$l" status --json'
        onResult: text => { try { const j = JSON.parse(text); m.low = j.available ? j.state : "" } catch (e) { m.low = "" } }
    }

    MenuHeader { width: parent.width; title: "Battery" }

    // The battery drawn large (BatteryShape), the percentage after it: the fill's colour shows charging / low, and a bolt
    // sits inside it while charging
    readonly property color battColor: m.state === "charging" ? Theme.accent : (m.percent <= 10 ? Theme.danger : (m.percent <= 20 ? Theme.warning : Theme.primary))

    Column {
        width: parent.width
        spacing: 7   // the battery and the status line below it
        Row {
            width: parent.width
            spacing: 14
            BatteryShape {
                width: parent.width - pct.width - parent.spacing
                height: 34
                anchors.verticalCenter: parent.verticalCenter
                level: m.percent
                color: m.battColor
                bolt: m.state === "charging"
            }
            Text {
                id: pct
                anchors.verticalCenter: parent.verticalCenter
                text: m.percent + "%"
                color: Theme.text
                font { family: Theme.font; pixelSize: 18; bold: true }
            }
        }
        MenuNote {
            text: (m.state === "discharging" ? "Discharging" : m.state === "charging" ? "Charging"
                 : m.state === "fully-charged" ? "Fully charged" : m.state === "pending-charge" ? "Not charging" : m.state)
                + (m.timeText !== "" ? " · " + m.timeText + (m.state === "charging" ? " until full" : " remaining") : "")
        }
    }

    // Low Power Mode: laid out like Display's night light row, the switch on the right
    Item {
        id: lowRow
        visible: m.low !== ""
        width: parent.width
        height: 30
        property bool navSelected: false
        readonly property bool navEnabled: visible
        function navActivate() { toggle() }
        function toggle() {
            m.low = m.low === "on" ? "off" : "on"
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/low-power", m.low])
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: lowRow.toggle() }
        Text {
            id: leafIcon
            width: 22
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: Icons.g("leaf")
            color: m.low === "on" ? Theme.warning : Theme.text
            font { family: Icons.family; pixelSize: 18 }
        }
        Text {
            anchors { left: leafIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: "Low Power Mode"
            color: Theme.text
            font { family: Theme.font; pixelSize: 13 }
        }
        Toggle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            checked: m.low === "on"
            navSelected: lowRow.navSelected
            onToggled: lowRow.toggle()
        }
    }

    MenuSection { visible: m.bat !== null; apart: true; title: "Details" }
    Column {
        visible: m.bat !== null
        width: parent.width
        spacing: 2
        Repeater {
            model: !m.bat ? [] : [
                { icon: "zap", label: "Power", detail: m.bat.watts > 0 ? m.bat.watts + " W" : "" },
                { icon: "thermometer", label: "Temperature", detail: m.bat.temp !== null ? m.bat.temp + " °C" : "", danger: m.bat.temp >= 45 },
                { icon: "heart-pulse", label: "Health",
                  detail: m.bat.health !== null ? m.bat.health + "% · " + m.bat.fullWh + " / " + m.bat.designWh + " Wh" : "" },
                { icon: "repeat", label: "Cycles", detail: m.bat.cycles !== null ? String(m.bat.cycles) : "" },
                { icon: "activity", label: "Voltage", detail: m.bat.volts !== null ? m.bat.volts.toFixed(2) + " V" : "" },
                { icon: "calendar", label: "Manufactured", detail: m.bat.made }
            ].filter(r => r.detail !== "")
            delegate: MenuRow {
                required property var modelData
                width: parent.width
                height: 28
                interactive: false
                icon: modelData.icon
                label: modelData.label
                detail: modelData.detail
                danger: !!modelData.danger
            }
        }
    }
}
