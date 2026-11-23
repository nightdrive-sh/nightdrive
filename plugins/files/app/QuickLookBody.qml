import QtQuick
import qs
import qs.kit
import "Format.js" as Format

// What the big preview (QuickLook) shows of a file under its title: a picture (a PDF's first page, a video's frame) to
// zoom into (QuickLookPicture), a text to scroll through, else what it is, with what ⏎ does.
Item {
    id: root
    required property QtObject c
    required property var file
    required property var info
    clip: true

    readonly property string picture: !info ? "" : info.image ? Format.url(info.path) : info.picture ? Format.url(info.picture) : ""
    readonly property bool isText: !!info && !picture && info.text !== undefined
    function page(d) { if (isText) textFlick.flick(0, -3000 * d) }

    QuickLookPicture {
        id: pictureView
        anchors.fill: parent
        source: root.picture
        pixels: root.info && root.info.image && root.info.pixels ? root.info.pixels : null
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
