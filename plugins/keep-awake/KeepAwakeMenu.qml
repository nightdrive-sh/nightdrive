import QtQuick
import Quickshell
import qs

// Keep Awake: keep the computer awake (no screensaver, lock, screen-off or lid sleep) until turned off or for a few
// hours, and when it goes back to the usual idle times. bin/keep-awake does the work; this reads its status.
Column {
    id: m
    width: parent ? parent.width : 320
    spacing: 8
    signal close()

    readonly property string cmdPath: Qt.resolvedUrl("bin/keep-awake").toString().replace(/^file:\/\//, "")
    readonly property var choices: [{ min: 0, label: "Until turned off" }, { min: 60, label: "1 hour" },
                                    { min: 120, label: "2 hours" }, { min: 240, label: "4 hours" },
                                    { min: 480, label: "8 hours" }]
    property bool on: false
    property int until: 0            // epoch seconds; 0 = until turned off
    property int minutes: 0          // the choice it was turned on with
    property real now: Date.now()    // ticks, so the times below stay current while the menu is open

    function clock(ms) { return Qt.formatTime(new Date(ms), "HH:mm") }
    function run(args) { cmd.command = [m.cmdPath].concat(args); cmd.running = true }

    Component.onCompleted: status.running = true
    Timer { interval: 15000; repeat: true; running: true; onTriggered: { m.now = Date.now(); status.running = true } }

    Sh {
        id: status
        command: [m.cmdPath, "status"]
        onResult: text => {
            try { const j = JSON.parse(text); m.on = j.on; m.until = j.until; m.minutes = j.minutes } catch (e) { m.on = false }
        }
    }
    Sh { id: cmd; onResult: { m.now = Date.now(); status.running = true } }

    MenuHeader {
        width: parent.width
        title: "Keep Awake"
        showToggle: true
        checked: m.on
        onToggled: m.run([m.on ? "off" : "on"])
    }

    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: m.choices
            delegate: MenuRow {
                required property var modelData
                readonly property bool cur: m.on && m.minutes === modelData.min
                width: m.width
                icon: modelData.min ? "timer" : "infinity"
                label: modelData.label
                // The end time if picked now; the current one keeps its own
                detail: !modelData.min ? "" : "until " + m.clock(cur ? m.until * 1000 : m.now + modelData.min * 60000)
                active: cur
                checkIcon: cur ? "check" : ""
                onClicked: m.run(["on", String(modelData.min)])
            }
        }
    }
}
