import QtQuick
import qs.kit as Kit

// Ask Claude's Send, a small button inside its field at the right end (AskClaudePanel.qml, #3704): ↵ Send. Enter does the
// same, and a click on it too. A shade darker than the field (the user's pick of four, #3704).
Rectangle {
    id: b
    signal clicked()

    // --- Tunables ---
    readonly property int padLeft: 4      // the ↵ cap has room of its own on its left
    readonly property int padRight: 10
    readonly property int keyGap: 2
    readonly property int fontSize: 12

    color: area.containsMouse ? Theme.bg : Qt.darker(Theme.card, 1.26)  // under the pointer a shade darker still
    radius: 6
    width: padLeft + row.implicitWidth + padRight

    Row {
        id: row
        x: b.padLeft
        anchors.verticalCenter: parent.verticalCenter
        spacing: b.keyGap
        Kit.Key { key: "Enter"; color: "transparent"; anchors.verticalCenter: parent.verticalCenter }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Send"
            color: Theme.text
            font { family: Theme.font; pixelSize: b.fontSize }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}
