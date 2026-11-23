import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.kit
import "Format.js" as Format

// The pane at the right: the picked file's picture, or the start of its text, then what it is (type, size, when it
// changed, a picture's size, a folder's count, a link's target) and where it is. lib/peek.py reads it, a moment after
// the pick stops moving, so j held down a long list doesn't start a read for every row. Several marked: their count
// and size. A sound gets a player under its facts (AudioPlayer: a click plays it); it stops when another file is
// picked, the pane hides or the big preview opens. i hides it, and a narrow window leaves it out.
Rectangle {
    id: root
    required property QtObject c
    required property var app
    readonly property var file: app.picked
    color: "transparent"

    property var info: null
    property string asked: ""
    Timer { id: settle; interval: 120; onTriggered: root.read() }
    onFileChanged: { settle.restart() }
    function read() {
        const p = file ? file.path : ""
        if (!p) { info = null; asked = ""; return }
        if (p === asked && info) return
        asked = p
        if (peeker.running) peeker.running = false
        // A file in an archive is taken out first, into the window's slot (Archive, lib/members.py)
        peeker.command = file.member !== undefined ? app.archive.peek(file, false) : ["python3", app.helper, "peek", p]
        peeker.running = true
    }
    // A change in the folder (the picked file written again) reads it again
    function again() { asked = ""; settle.restart() }
    Process {
        id: peeker
        stdout: StdioCollector {
            onStreamFinished: {
                try { const d = JSON.parse(text); if (d.path === root.asked) root.info = d } catch (e) { root.info = null }
            }
        }
    }
    readonly property bool fresh: info && file && info.path === file.path

    Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: root.c.divider }

    Flickable {
        id: previewFlick
        TouchScroll { view: previewFlick }
        anchors.fill: parent
        anchors.leftMargin: 20; anchors.rightMargin: 18; anchors.topMargin: 18
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: col
            width: parent.width
            spacing: 10

            // Several marked: what they come to
            Text {
                visible: root.app.marked.length > 1
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.app.marked.length + " marked" + (root.app.markedSize ? ", " + Format.size(root.app.markedSize) : "")
                color: root.c.accent; font.family: root.c.font; font.pixelSize: 12
            }

            Image {
                id: pic
                visible: source != "" && status !== Image.Error
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? Math.min(root.height * 0.5, paintedHeight || 200) : 0
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                asynchronous: true
                cache: false
                source: !root.fresh ? "" : root.info.image === true ? Format.url(root.info.file || root.info.path) : root.info.picture ? Format.url(root.info.picture) : ""
                sourceSize.width: 640
            }
            Text {
                visible: !pic.visible && root.file !== null
                text: Icons.g(root.file ? (root.file.dir ? "folder" : Format.glyph(root.file)) : "file")
                font.family: Icons.family; font.pixelSize: 44
                color: root.file && root.file.dir ? root.c.primary : root.c.faint
                Layout.topMargin: 6; Layout.bottomMargin: 4
            }
            Text {
                visible: root.file !== null
                Layout.fillWidth: true
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                text: root.file ? root.file.name : ""
                color: root.c.title; font.family: root.c.font; font.pixelSize: 14; font.weight: Font.Medium
            }
            // Its facts, a line each
            Repeater {
                model: {
                    const i = root.fresh ? root.info : null, f = root.file
                    if (!f) return []
                    const out = []
                    if (i) out.push(i.kind + (i.executable ? ", runs as a program" : ""))
                    if (i && i.dir && i.items !== null && i.items !== undefined)
                        out.push(i.items === 0 ? "Empty" : i.items + (i.items === 1 ? " item" : " items") + (i.hidden ? " and " + i.hidden + " hidden" : ""))
                    if (!f.dir) out.push(Format.size(f.size))
                    if (i && i.pixels) out.push(i.pixels[0] + " × " + i.pixels[1])
                    if (i && i.duration && !i.audio) out.push(Format.length(i.duration))
                    if (root.app.trashShown) {
                        out.push("From " + root.app.tilde(Format.parent(f.origin)))
                        out.push("Deleted " + Regional.format(f.modified, "medium") + " " + Regional.time(String(f.modified).slice(11, 16)))
                    } else if (i) out.push("Modified " + Regional.format(i.modified, "medium") + " " + Regional.time(i.modified.slice(11, 16)))
                    if (i && i.link) out.push("Link to " + i.link)
                    return out
                }
                delegate: Text {
                    required property string modelData
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    text: modelData
                    color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
                }
            }
            // A sound: play it here. Not while the big preview is open, which plays it itself
            AudioPlayer {
                visible: root.fresh && root.info.audio === true
                Layout.fillWidth: true
                Layout.topMargin: 4
                c: root.c
                path: visible && root.visible && !root.app.quick.open ? root.info.file || root.info.path : ""
                duration: visible && root.info.duration ? root.info.duration : 0
                title: root.file ? root.file.name : ""
            }
            // The start of a text, as it is
            Rectangle {
                visible: root.fresh && root.info.text !== undefined && root.info.text !== ""
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.preferredHeight: textView.implicitHeight + 20
                radius: 8
                color: root.c.hover
                clip: true
                Text {
                    id: textView
                    x: 10; y: 10
                    width: parent.width - 20
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 40
                    elide: Text.ElideRight
                    text: root.fresh && root.info.text ? root.info.text : ""
                    color: root.c.text; font.family: "monospace"; font.pixelSize: 11
                }
            }
            Text {
                visible: root.file === null && root.app.marked.length <= 1
                text: root.app.trashShown ? "" : "Nothing picked"
                color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
            }
        }
    }
}
