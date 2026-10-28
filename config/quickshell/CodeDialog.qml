import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// A code to type on another device, in the middle of the screen: AirPlay's PIN when an iPhone connects
// (plugins/airplay-receiver), LocalSend's when a phone sends (plugins/localsend/lib/codes.py). A notification of it went unnoticed, and the device waits for it. Floats as the Claude
// writes card does (ClaudeWrite.qml); Esc, the button or a click outside closes it, and so does the sender once the
// code has been typed (close), or `timeout` passing.
//   qs ipc call code open <glyph> <title> <code> <text>   (glyph: a Lucide name; not "show": qs reads that as its own)
//   qs ipc call code close
// (Not named *Menu.qml: shell.qml treats those as top bar menus.)
PanelWindow {
    id: win

    // --- Tunables ---
    readonly property int timeout: 120000   // ms: the device has given up long before

    property bool open: false
    property string glyph: ""
    property string title: ""
    property string code: ""
    property string text: ""

    function show(g, t, c, x) {
        glyph = g; title = t; code = c; text = x
        const f = Hyprland.focusedMonitor
        screen = (f && Quickshell.screens.find(s => s.name === f.name)) || Quickshell.screens[0]
        open = true
        keys.forceActiveFocus()
        expire.restart()
    }
    function hide() { open = false; expire.stop() }

    IpcHandler {
        target: "code"
        function open(glyph: string, title: string, code: string, text: string): void { win.show(glyph, title, code, text) }
        function close(): void { win.hide() }
    }
    Timer { id: expire; interval: win.timeout; onTriggered: win.hide() }

    visible: open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "code-dialog"

    MouseArea { anchors.fill: parent; onClicked: win.hide() }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key !== Qt.Key_Escape && e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter) return
            win.hide()
            e.accepted = true
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(360, win.width - 32)
        height: body.implicitHeight + 36
        radius: 14
        color: Theme.launcherBg
        border { color: Theme.primary; width: 1 }
        MouseArea { anchors.fill: parent }

        Column {
            id: body
            x: 18; y: 18
            width: parent.width - 36
            spacing: 14

            Row {
                width: parent.width
                spacing: 10
                Text {
                    id: icon
                    width: 36
                    horizontalAlignment: Text.AlignHCenter
                    text: Icons.g(win.glyph)
                    color: Theme.accent
                    font { family: Icons.familyThin; pixelSize: 30 }   // the thin stroke, as on the Claude writes card
                }
                Column {
                    width: parent.width - icon.width - 10
                    spacing: 2
                    Text {
                        text: win.title
                        textFormat: Text.PlainText   // the title and text may hold a name a device gave itself
                        color: Theme.title
                        font { family: Theme.font; pixelSize: 14; bold: true }
                    }
                    Text {
                        width: parent.width
                        text: win.text
                        textFormat: Text.PlainText
                        color: Theme.dim
                        wrapMode: Text.Wrap
                        font { family: Theme.font; pixelSize: 11 }
                    }
                }
            }

            // The digits apart, so they read one by one while typed on the phone
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.code.split("").join(" ")
                color: Theme.title
                font { family: Theme.font; pixelSize: 44; weight: Font.DemiBold }
            }

            ClaudeWriteButton {
                anchors.right: parent.right
                keys: ["Esc"]; label: "Close"
                onClicked: win.hide()
            }
        }
    }
}
