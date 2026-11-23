import QtQuick
import qs
import qs.kit
import "Format.js" as Format

// What the big preview (QuickLook) shows of a file under its title: a picture (a PDF's first page, a video's frame) to
// zoom into (QuickLookPicture), a sound to play (its cover and AudioPlayer, started at once), a text to scroll through,
// else what it is, with what ⏎ does.
Item {
    id: root
    required property QtObject c
    required property var file
    required property var info
    property bool active: false               // the big preview is open: a sound plays only then
    clip: true

    readonly property bool isAudio: !!info && info.audio === true
    readonly property string picture: !info || isAudio ? "" : info.image ? Format.url(info.file || info.path) : info.picture ? Format.url(info.picture) : ""
    readonly property bool isText: !!info && !picture && info.text !== undefined
    // A file in an archive (Archive) isn't on disk to open: y and p take it out
    readonly property string opens: file && file.member !== undefined ? "y, then p in a folder, takes it out" : "⏎ opens it"
    function page(d) { if (isText) textFlick.flick(0, -3000 * d) }
    function toggleSound() { if (isAudio) player.toggle() }
    function skipSound(d) { if (isAudio) player.skip(d) }

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
    // A sound: its cover (or a note glyph), its name, the player
    Column {
        visible: root.isAudio
        anchors.centerIn: parent
        width: Math.min(560, parent.width * 0.86)
        spacing: 18
        Image {
            id: cover
            visible: status === Image.Ready
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(320, root.height * 0.45); height: width
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            source: root.isAudio && root.info.picture ? Format.url(root.info.picture) : ""
        }
        Text {
            visible: !cover.visible
            anchors.horizontalCenter: parent.horizontalCenter
            text: Icons.g("music")
            font.family: Icons.family; font.pixelSize: 72
            color: root.c.faint
        }
        AudioPlayer {
            id: player
            width: parent.width
            big: true
            autoplay: true
            c: root.c
            // Only while it is still the picked file: ↑ ↓ stop it at once, not when the next one has been read
            path: root.active && root.isAudio && root.file && root.file.path === root.info.path ? root.info.file || root.info.path : ""
            duration: root.isAudio && root.info.duration ? root.info.duration : 0
            title: root.file ? root.file.name : ""
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "p plays or pauses  ·  ← → 5 s  ·  " + root.opens
            color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
        }
    }
    Column {
        visible: !!root.info && root.picture === "" && !root.isText && !root.isAudio
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
            text: root.info && root.info.dir ? "⏎ goes into it" : root.opens
            color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
        }
    }
}
