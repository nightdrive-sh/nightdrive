import QtQuick
import qs
import qs.kit

// A message's picture over the whole window, as large as it fits (never larger than it is), its name and place under
// it: ← → the others, Esc, a click or Space back to the message. o opens it in the desktop's image viewer.
Rectangle {
    id: root
    required property QtObject c
    property var images: []              // Attachments.images
    property int index: 0
    property Item behind: null
    readonly property var current: images.length ? images[Math.max(0, Math.min(images.length - 1, index))] : null
    signal closed()
    anchors.fill: parent
    visible: false
    color: Qt.rgba(0, 0, 0, 0.92)
    Binding { target: root.behind; property: "enabled"; value: false; when: root.visible && root.behind !== null }
    function show(list, i) { images = list; index = i; visible = true; forceActiveFocus() }
    function close() { visible = false; closed() }
    function step(d) { if (images.length) index = (index + d + images.length) % images.length }

    Keys.onPressed: e => {
        const k = e.key
        if (k === Qt.Key_Escape || k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) close()
        else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_J) step(1)
        else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_K) step(-1)
        else if (e.text === "o" && current) Qt.openUrlExternally("file://" + current.path)
        else return
        e.accepted = true
    }
    TapHandler { onTapped: root.close() }

    Image {
        id: pic
        anchors.fill: parent
        anchors.margins: 24
        anchors.bottomMargin: 52
        source: root.current ? "file://" + root.current.path : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true; mipmap: true
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 18
        width: parent.width - 48
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideMiddle
        textFormat: Text.PlainText
        text: !root.current ? "" : root.current.name
            + (root.images.length > 1 ? "   " + (root.index + 1) + " / " + root.images.length + "   ← →" : "") + "   Esc"
        font.family: root.c.font; font.pixelSize: 12; color: root.c.dim
    }
}
