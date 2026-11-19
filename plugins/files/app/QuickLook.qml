import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.kit
import "Format.js" as Format

// The big preview, Space as in macOS's Quick Look: over the whole window, the picked file as large as it fits (a
// picture, a PDF's first page, a video's frame), a text scrolled through, or what it is. ↑ ↓ j k go to the next file
// while it is open, so a folder of pictures is looked through without closing it; ⏎ opens it in its app, Space or Esc
// closes it, and so does a click outside it. A folder shows its count; ⏎ goes into it.
Rectangle {
    id: root
    required property QtObject c
    required property var app
    readonly property var file: app.picked
    property bool open: false
    visible: open
    color: c.scrim
    z: 50

    function toggle() { if (open) close(); else if (file) { open = true; forceActiveFocus(); read() } }
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
    readonly property string picture: !info ? "" : info.image ? Format.url(info.path) : info.picture ? Format.url(info.picture) : ""
    readonly property bool isText: !!info && !picture && info.text !== undefined

    Keys.onPressed: e => {
        const k = e.key, t = e.text
        if (k === Qt.Key_Space || k === Qt.Key_Escape) close()
        else if (k === Qt.Key_Down || t === "j") app.move(1)
        else if (k === Qt.Key_Up || t === "k") app.move(-1)
        else if (k === Qt.Key_PageDown && isText) textFlick.flick(0, -3000)
        else if (k === Qt.Key_PageUp && isText) textFlick.flick(0, 3000)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || t === "l") { close(); app.openPicked() }
        else return
        e.accepted = true
    }
    // A click beside the card closes it; the card's own MouseArea keeps clicks on it from coming here
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: Math.min(48, parent.width / 20)
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

        Item {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: head.bottom; anchors.bottom: parent.bottom
            anchors.margins: 20; anchors.topMargin: 14
            clip: true

            Image {
                visible: root.picture !== "" && status !== Image.Error
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                source: root.picture
                sourceSize.width: Math.max(width, 1) * 2
                sourceSize.height: Math.max(height, 1) * 2
            }
            Flickable {
                id: textFlick
                visible: root.isText
                anchors.fill: parent
                contentHeight: bigText.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                TouchScroll { view: textFlick }
                Text {
                    id: bigText
                    width: parent.width
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    text: root.isText ? root.info.text : ""
                    color: root.c.text; font.family: "monospace"; font.pixelSize: 13
                }
            }
            Column {
                visible: !!root.info && root.picture === "" && !root.isText
                anchors.centerIn: parent
                spacing: 10
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Icons.g(root.file ? Format.glyph(root.file) : "file")
                    font.family: Icons.family; font.pixelSize: 72
                    color: root.file && root.file.dir ? root.c.primary : root.c.faint
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: !root.info ? "" : root.info.dir ? (root.info.items === 0 ? "Empty folder" : root.info.items + (root.info.items === 1 ? " item" : " items"))
                        : "Modified " + Regional.format(root.info.modified, "medium")
                    color: root.c.dim; font.family: root.c.font; font.pixelSize: 13
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.info && root.info.dir ? "⏎ goes into it" : "⏎ opens it"
                    color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
                }
            }
        }
    }
}
