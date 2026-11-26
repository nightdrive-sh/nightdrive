import QtQuick
import qs

// The sound outputs, just above the player's speaker button: the same list as the Sound menu's (OutputList). A click
// anywhere else, on the button too, or Esc closes them. Its own file as an overlay over the whole window, apart from the
// player it opens from.
Item {
    id: outputs
    required property var win
    required property Item speaker              // the button it opens above
    readonly property QtObject c: win.look
    visible: false
    // Where the button is, taken when the list opens (the window may have been resized since)
    property point at: Qt.point(0, 0)
    onVisibleChanged: {
        if (visible) at = speaker.mapToItem(outputs, speaker.width / 2, 0)
        else win.list.forceActiveFocus()
    }
    // Over everything, so the click that closes the list doesn't also reach what is under it
    MouseArea { anchors.fill: parent; onClicked: outputs.visible = false }
    Rectangle {
        width: 320
        height: outCol.implicitHeight + 26
        x: Math.min(outputs.at.x + 28 - width, parent.width - width - 12)
        y: outputs.at.y - height - 12
        radius: 10
        // The window's own colour, a step darker, so the list stands out from what is under it
        color: Qt.darker(c.solid, 1.05)
        border.color: c.line
        // Clicks between the rows stay on the list
        MouseArea { anchors.fill: parent }
        Column {
            id: outCol
            x: 10; y: 14
            width: parent.width - 20
            spacing: 8
            Text { leftPadding: 10; text: "Sound output"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            OutputList { active: outputs.visible; width: parent.width }
        }
    }
    Shortcut { enabled: outputs.visible; sequence: "Escape"; onActivated: outputs.visible = false }
}
