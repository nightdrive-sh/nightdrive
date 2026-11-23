import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs
import qs.kit
import "Format.js" as Format

// The big preview, Space as in macOS's Quick Look: a layer over the whole screen Files is on, dimmed, with a card of
// about 90 % of it in the middle (QuickLookBody: the picked file as large as it fits, a text, or what it is). A layer
// and not a window of its own: no Hyprland rule for it, it takes the keyboard for as long as it is open (↑ ↓ j k go
// through the files, ⏎ opens one, Space or Esc closes it, so does a click beside the card), and the window under it
// gets the keys back when it goes. Its window's list or grid (#3303) only has to give `app` what is read here: picked,
// current, rows, move(d), openPicked(), toList(), helper, look and the window's screen.
PanelWindow {
    id: root
    required property QtObject c
    required property var app
    readonly property var file: app.picked
    property bool open: false
    visible: open
    screen: app.screen                    // the screen Files is on, read as it opens
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "nightdrive-files-preview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    function toggle() { if (open) close(); else if (file) { screen = app.screen; open = true; keys.forceActiveFocus(); read() } }
    function close() { open = false; app.toList() }

    property var info: null
    property string asked: ""
    onFileChanged: if (open) settle.restart()
    Timer { id: settle; interval: 60; onTriggered: root.read() }
    function read() {
        const p = file ? file.path : ""
        if (!p) { close(); return }
        if (p === asked && info) return
        asked = p
        info = null
        if (peeker.running) peeker.running = false
        peeker.command = ["python3", app.helper, "peek", p, "--long"]
        peeker.running = true
    }
    Process {
        id: peeker
        stdout: StdioCollector {
            onStreamFinished: { try { const d = JSON.parse(text); if (d.path === root.asked) root.info = d } catch (e) {} }
        }
    }

    Rectangle {
        id: keys
        anchors.fill: parent
        color: root.c.scrim
        focus: true
        Keys.onPressed: e => {
            const k = e.key, t = e.text
            if (k === Qt.Key_Space || k === Qt.Key_Escape) root.close()
            else if (k === Qt.Key_Down || t === "j") root.app.move(1)
            else if (k === Qt.Key_Up || t === "k") root.app.move(-1)
            else if (k === Qt.Key_PageDown) body.page(1)
            else if (k === Qt.Key_PageUp) body.page(-1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || t === "l") { root.close(); root.app.openPicked() }
            else return
            e.accepted = true
        }
        // A click beside the card closes it; the card's own MouseArea keeps clicks on it from coming here
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.9)
            height: Math.round(parent.height * 0.9)
            radius: 12
            color: root.c.solid
            border.color: root.c.line
            MouseArea { anchors.fill: parent }

            RowLayout {
                id: head
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.leftMargin: 20; anchors.rightMargin: 12; anchors.topMargin: 12
                spacing: 10
                Text {
                    text: Icons.g(root.file ? Format.glyph(root.file) : "file")
                    font.family: Icons.family; font.pixelSize: 15; color: root.c.dim
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    text: root.file ? root.file.name : ""
                    color: root.c.title; font.family: root.c.font; font.pixelSize: 14; font.weight: Font.Medium
                }
                Text {
                    textFormat: Text.PlainText
                    text: !root.info ? "" : [root.info.kind, root.info.dir ? "" : Format.size(root.info.size),
                                             root.info.pixels ? root.info.pixels[0] + " × " + root.info.pixels[1] : ""].filter(x => x).join("  ·  ")
                    color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
                }
                Text {
                    text: root.app.current + 1 + " / " + root.app.rows.length
                    color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
                    Layout.leftMargin: 8
                }
                AppIconButton { c: root.c; glyph: "x"; tip: "Close"; keys: "Space"; tipAlign: "right"; onClicked: root.close() }
            }

            QuickLookBody {
                id: body
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: head.bottom; anchors.bottom: parent.bottom
                anchors.margins: 20; anchors.topMargin: 14
                c: root.c
                file: root.file
                info: root.info
            }
        }
    }
}
