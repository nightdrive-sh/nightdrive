import QtQuick
import qs

// Ferry's menu › the pill's list (FerryPicker.qml): a device, its kind's icon, name and state, a check on the picked
// one. Without a device it is the list's Add Device… row. The menu is passed in: what a device can take and which
// one is picked are the menu's (FerryMenu.qml).
Rectangle {
    id: dr
    required property var menu
    property var dev: null
    property string label: dev ? dev.name : ""
    property string icon: menu.deviceIcon(dev)
    readonly property bool usable: !dev || menu.canTake(dev)
    readonly property bool picked: !!dev && dev.id === menu.targetId
    property bool navSelected: false
    readonly property bool navEnabled: usable
    function navActivate() { dr.clicked() }
    signal clicked()
    width: parent.width; height: 40; radius: 9
    color: picked ? Theme.sel : drArea.containsMouse && !MenuPointer.pointerAway || navSelected ? Theme.hover : "transparent"
    border { width: navSelected ? 1 : 0; color: Theme.primary }
    opacity: usable ? 1 : 0.45
    Text {
        id: drIcon
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        text: Icons.g(dr.icon)
        color: Theme.accent
        font { family: Icons.family; pixelSize: 16 }
    }
    Text {
        anchors { left: drIcon.right; leftMargin: 12; right: drState.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: dr.label
        textFormat: Text.PlainText   // a device names itself: never markup
        elide: Text.ElideRight
        color: dr.picked ? Theme.accent : Theme.text
        font { family: Theme.font; pixelSize: 13 }
    }
    Row {
        id: drState
        visible: !!dr.dev
        anchors { right: drCheck.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 6
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 7; height: 7; radius: 4
            color: dr.dev && dr.dev.online ? Theme.ok : Theme.border
        }
        Text {
            text: dr.dev ? dr.menu.deviceState(dr.dev) : ""
            color: Theme.dim
            font { family: Theme.font; pixelSize: 11 }
        }
    }
    Text {
        id: drCheck
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        width: 14
        text: dr.picked ? Icons.g("check") : ""
        color: Theme.accent
        font { family: Icons.family; pixelSize: 13 }
    }
    MouseArea {
        id: drArea
        anchors.fill: parent
        enabled: dr.usable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: dr.clicked()
    }
}
