import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Power dialog in the middle of the screen: Lock, Sleep, Log out, Restart, Shut down.
// Opened by the power button (Touch ID key, hypr/bindings.lua):  qs ipc call power toggle
// ←/→ (or Tab) select, Enter/Space activates, Esc or a click outside closes. The dialog itself is the confirmation.
// (Not named *Menu.qml: shell.qml treats those as top bar menus.)
PanelWindow {
    id: win
    property bool open: false
    property int index: actions.length - 1     // Shut down is selected when the dialog opens

    // Log out, Restart and Shut down play their sound first and wait for it (hypr/scripts/session-end)
    readonly property string sessionEnd: Quickshell.env("HOME") + "/.config/hypr/scripts/session-end"
    readonly property var actions: [
        { name: "Lock",      glyph: "lock",      cmd: ["loginctl", "lock-session"] },
        { name: "Sleep",     glyph: "moon",      cmd: ["systemctl", "suspend"] },
        { name: "Log out",   glyph: "log-out",   cmd: [win.sessionEnd, "logout"] },
        { name: "Restart",   glyph: "rotate-cw", cmd: [win.sessionEnd, "reboot"] },
        { name: "Shut down", glyph: "power",     cmd: [win.sessionEnd, "poweroff"] }
    ]

    function show() { index = actions.length - 1; open = true; keys.forceActiveFocus() }
    function run(i) { open = false; Quickshell.execDetached(actions[i].cmd) }
    function step(d) { index = (index + d + actions.length) % actions.length }

    IpcHandler {
        target: "power"
        function toggle(): void { if (win.open) win.open = false; else win.show() }
        function close(): void { win.open = false }
    }

    visible: open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "#99000000"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea { anchors.fill: parent; onClicked: win.open = false }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) win.open = false
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) win.step(-1)
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) win.step(1)
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) win.run(win.index)
            else return
            e.accepted = true
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: row.implicitWidth + 48
        height: row.implicitHeight + 48
        radius: 16
        color: Theme.launcherBg
        border.color: Theme.primary
        border.width: 2
        MouseArea { anchors.fill: parent }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 12
            Repeater {
                model: win.actions
                Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool current: win.index === index
                    width: 132; height: 132
                    radius: 12
                    color: current ? Theme.sel : area.containsMouse ? Theme.hover : "transparent"
                    border.color: current ? Theme.primary : "transparent"
                    border.width: 2
                    Column {
                        anchors.centerIn: parent
                        spacing: 14
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Icons.g(tile.modelData.glyph)
                            color: tile.current ? Theme.accent : Theme.text
                            font { family: Icons.family; pixelSize: 40 }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.name
                            color: tile.current ? Theme.accent : Theme.text
                            font { family: Theme.font; pixelSize: 15 }
                        }
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: win.index = tile.index
                        onClicked: win.run(tile.index)
                    }
                }
            }
        }
    }
}
