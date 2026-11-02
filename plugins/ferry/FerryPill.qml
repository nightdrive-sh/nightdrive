import QtQuick
import qs

// Ferry's menu: the pill that says which device a send goes to (the last one picked). A click lists the devices
// (FerryPicker.qml floats above it), or opens Add Device while there is none. The wrapper gives it 10 px more room
// above than the menu's column spacing, but not over a long list (roomAbove false), which runs on under it.
Item {
    id: pw
    required property var menu
    property bool roomAbove: true
    height: pill.height + (roomAbove ? 10 : 0)
    Rectangle {
        id: pill
        anchors.bottom: parent.bottom
        property bool navSelected: false
        function navActivate() { pillArea.clicked(null) }
        anchors.horizontalCenter: parent.horizontalCenter
        width: pillRow.width + 26
        height: 28; radius: 14
        color: pw.menu.mode === "pick" ? Theme.sel : pillArea.containsMouse || navSelected ? Theme.hover : Theme.card
        border { width: 1; color: pw.menu.mode === "pick" || navSelected ? Theme.primary : Theme.border }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                visible: !!pw.menu.target
                anchors.verticalCenter: parent.verticalCenter
                width: 7; height: 7; radius: 4
                color: pw.menu.target && pw.menu.target.online ? Theme.ok : Theme.border
            }
            Text {
                visible: !pw.menu.target
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.g("qr-code")
                color: Theme.accent
                font { family: Icons.family; pixelSize: 13 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pw.menu.target ? pw.menu.target.name : "Add Device"
                color: Theme.accent
                font { family: Theme.font; pixelSize: 12 }
            }
            Text {
                visible: !!pw.menu.target
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.g(pw.menu.mode === "pick" ? "chevron-up" : "chevron-down")
                color: Theme.dim
                font { family: Icons.family; pixelSize: 12 }
            }
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!pw.menu.target && pw.menu.devices.length === 0) pw.menu.addDevice()
                else pw.menu.mode = pw.menu.mode === "pick" ? "list" : "pick"
            }
        }
    }
}
