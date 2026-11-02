import QtQuick

// What is being dragged from the list to a folder: the thread's subject (or how many), by the pointer. Apart from
// shell.qml, over the whole window; Actions.qml says where the pointer is and which folder takes the drop.
Rectangle {
    id: ghost
    required property var ops           // Actions.qml
    required property QtObject c
    x: ops.dragPos.x + 12; y: ops.dragPos.y - height / 2
    visible: ops.dragged !== null
    width: Math.min(320, ghostText.implicitWidth + 28); height: 34
    radius: 8
    color: c.solid
    border.color: ops.dropFolder >= 0 ? c.primary : c.line
    Text {
        id: ghostText
        textFormat: Text.PlainText
        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: !ops.dragged ? "" : ops.dragged.length > 1 ? ops.dragged.length + " threads" : ops.dragged[0].subject || "(no subject)"
        color: c.title; font.family: c.font; font.pixelSize: 12
    }
}
