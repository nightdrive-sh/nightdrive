import QtQuick
import qs.kit

// In place of the open message while several are selected (Selection.qml, #3455), as Mail's PickedPane: how many, and
// what a key or a click does to them all. MessageView shows it; shell.qml does what it asks.
Column {
    id: root
    required property QtObject c
    required property QtObject store
    signal archive()
    signal toggleRead()
    signal remove()
    readonly property QtObject sel: store.selection
    visible: sel.any
    spacing: 28
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.sel.count + " messages selected"
        color: root.c.title; font.family: root.c.font; font.pixelSize: 22; font.weight: Font.Medium
    }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2
        Repeater {
            // A click does what the key does
            model: [["a", root.store.view === "archive" ? "Back to the inbox" : "Archive", "archive"],
                    ["u", "Read or unread", "read"], ["d", "Delete for good", "delete"], ["Esc", "Select only one", "single"]]
            delegate: Rectangle {
                required property var modelData
                implicitWidth: pickRow.implicitWidth + 24; implicitHeight: 32
                radius: 8
                color: ph.hovered ? root.c.hover : "transparent"
                HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        const id = modelData[2]
                        if (id === "archive") root.archive()
                        else if (id === "read") root.toggleRead()
                        else if (id === "delete") root.remove()
                        else root.sel.clear()
                    }
                }
                Row {
                    id: pickRow
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 14
                    Item {
                        width: 44; height: cap.implicitHeight
                        KeyCap { id: cap; anchors.right: parent.right; c: root.c; keys: modelData[0] }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData[1]; color: ph.hovered ? root.c.text : root.c.dim; font.family: root.c.font; font.pixelSize: 13
                    }
                }
            }
        }
    }
}
