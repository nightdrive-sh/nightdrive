import QtQuick
import qs
import qs.kit

// The message's files: its pictures large, as wide as the text, two side by side where there is room (a before and an
// after, a few screenshots), each with its name under it, and a click shows one over the whole window (ImageViewer).
// Its sound files under them, each with a play button (SoundFiles), and the other files after those, a row each with
// its size: a click opens one in its app. The files are the copies in the message's own folder (config/inbox/attach.py),
// so they look as they did when the message was left.
Column {
    id: root
    required property QtObject c
    property var files: []               // Store.message.attachments: { name, type, size, path }
    signal view(int index)               // an index in images
    signal notice(string text, bool danger)   // SoundFiles': a copied name, a sound that can't play
    readonly property alias sounds: soundList
    spacing: 14
    readonly property var images: files.filter(f => (f.type || "").startsWith("image/"))
    // By the name's ending: Python's mimetypes doesn't know every one of them (.opus, .m4a)
    function isSound(f) { return /\.(ogg|oga|opus|wav|mp3|m4a|flac)$/i.test(f.name || "") }
    readonly property var others: files.filter(f => !(f.type || "").startsWith("image/") && !isSound(f))
    readonly property int columns: images.length > 1 && width >= 640 ? 2 : 1
    function size(n) {
        return n >= 1048576 ? (n / 1048576).toFixed(1) + " MB" : n >= 1024 ? Math.round(n / 1024) + " kB" : n + " B"
    }

    Grid {
        visible: root.images.length > 0
        columns: root.columns
        columnSpacing: 12; rowSpacing: 14
        Repeater {
            model: root.images
            delegate: Column {
                required property var modelData
                required property int index
                width: (root.width - (root.columns - 1) * 12) / root.columns
                spacing: 6
                Rectangle {
                    width: parent.width
                    // As the picture is, until it has loaded (a moment for a large one)
                    height: pic.status === Image.Ready ? width * pic.implicitHeight / Math.max(1, pic.implicitWidth) : 120
                    radius: 8
                    color: root.c.solid
                    border.width: 1; border.color: hover.hovered ? root.c.primary : root.c.divider
                    clip: true
                    Image {
                        id: pic
                        anchors.fill: parent; anchors.margins: 1
                        source: modelData.path ? "file://" + modelData.path : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true; mipmap: true
                        // Loaded at about the size shown, not a 6K screenshot's whole
                        sourceSize.width: Math.min(2400, Math.ceil(parent.width * 2))
                    }
                    Text {
                        visible: pic.status === Image.Error
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "Can't show " + modelData.name
                        font.family: root.c.font; font.pixelSize: 12; color: root.c.faint
                    }
                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.view(index) }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    text: modelData.name
                    font.family: root.c.font; font.pixelSize: 11; color: root.c.faint
                }
            }
        }
    }

    SoundFiles {
        id: soundList
        visible: any
        width: parent.width
        c: root.c
        files: root.files.filter(f => root.isSound(f))
        onNotice: (text, danger) => root.notice(text, danger)
    }

    Column {
        visible: root.others.length > 0
        width: parent.width
        spacing: 2
        Repeater {
            model: root.others
            delegate: Rectangle {
                id: fileRow
                required property var modelData
                width: parent.width
                height: 34
                radius: 8
                color: fileHover.hovered ? root.c.hover : "transparent"
                HoverHandler { id: fileHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Qt.openUrlExternally("file://" + fileRow.modelData.path) }
                Text {
                    id: glyph
                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    text: Icons.g("file-text"); font.family: Icons.family; font.pixelSize: 15; color: root.c.dim
                }
                Text {
                    anchors.left: glyph.right; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    anchors.right: sizeText.left; anchors.rightMargin: 10
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    text: fileRow.modelData.name
                    font.family: root.c.font; font.pixelSize: 13; color: root.c.text
                }
                Text {
                    id: sizeText
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: root.size(fileRow.modelData.size || 0)
                    font.family: root.c.font; font.pixelSize: 11; color: root.c.faint
                }
            }
        }
    }
}
