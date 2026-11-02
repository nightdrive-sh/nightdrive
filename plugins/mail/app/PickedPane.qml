import QtQuick
import qs.kit

// In place of the open thread while several threads are picked: how many, and what a key or a click does to them all.
// Apart from shell.qml, which shows it over the reading pane.
Column {
    required property var win
    required property var ops           // Actions.qml
    readonly property QtObject c: win.look
    anchors.centerIn: parent
    visible: win.picked.length > 0
    spacing: 28
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: win.picked.length + " threads selected"
        color: c.title; font.family: c.font; font.pixelSize: 22; font.weight: Font.Medium
    }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2
        Repeater {
            // A click does what the key does
            model: [["a", "Archive", "archive"], ["d", win.folders[win.folder].dir === "Trash" ? "Delete for good" : "Move to Trash", "trash"],
                    ["!", win.folders[win.folder].dir === "Spam" ? "Not spam" : "Spam", "spam"],
                    ["u", "Read or unread", "unread"], ["Esc", "Select only one", "single"]]
            delegate: Rectangle {
                required property var modelData
                implicitWidth: pickRow.implicitWidth + 24; implicitHeight: 32
                radius: 8
                color: ph.hovered ? c.hover : "transparent"
                HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { ops.act(modelData[2]); win.list.forceActiveFocus() } }
                Row {
                    id: pickRow
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 14
                    Item {
                        width: 44; height: cap.implicitHeight
                        KeyCap { id: cap; anchors.right: parent.right; c: win.look; keys: modelData[0] }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: ph.hovered ? c.text : c.dim; font.family: c.font; font.pixelSize: 13 }
                }
            }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Or drag them to a folder"
        color: c.faint; font.family: c.font; font.pixelSize: 12
    }
}
