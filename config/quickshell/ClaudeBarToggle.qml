import QtQuick
import qs.kit

// The Claude menu's Sessions bar switch: the bar at the bottom of the screen (SessionsBar.qml), on or off. Laid out
// like Display's Night light row; Enter toggles it in keyboard mode (navActivate).
Item {
    id: barRow
    width: parent ? parent.width : 300
    height: 30
    property bool navSelected: false
    readonly property bool navEnabled: true
    function navActivate() { Claude.setBar(!Claude.barOn) }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: barRow.navActivate() }
    Text {
        id: barIcon
        x: 10
        width: 20
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: Icons.g("panel-bottom")
        color: Theme.dim
        font { family: Icons.family; pixelSize: 16 }
    }
    Text {
        anchors { left: barIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
        text: "Sessions bar"
        color: Theme.text
        font { family: Theme.font; pixelSize: 13 }
    }
    Toggle {
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        checked: Claude.barOn
        navSelected: barRow.navSelected
        onToggled: barRow.navActivate()
    }
}
