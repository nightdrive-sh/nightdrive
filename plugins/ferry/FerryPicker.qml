import QtQuick
import qs

// Ferry's menu: the pill's list of devices (FerryDeviceRow.qml) and Add Device…, floating above the pill over the
// received list. The menu places it (y) and closes it on a click beside it; a click between its rows does nothing.
Rectangle {
    id: pk
    required property var menu
    width: Math.min(parent.width, 290)
    height: pickList.height + 12
    radius: 14
    color: Theme.card
    border { width: 1; color: Theme.border }
    MouseArea { anchors.fill: parent; hoverEnabled: true }   // a click between the rows doesn't close it, nor light the list below
    Column {
        id: pickList
        x: 6; y: 6
        width: parent.width - 12
        spacing: 2
        Repeater {
            model: pk.menu.devices
            delegate: FerryDeviceRow {
                required property var modelData
                menu: pk.menu
                dev: modelData
                onClicked: pk.menu.pick(modelData)
            }
        }
        Rectangle {
            visible: pk.menu.devices.length > 0
            width: parent.width - 12; x: 6
            height: 1
            color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.6)
        }
        FerryDeviceRow {
            menu: pk.menu
            label: "Add Device…"
            icon: "qr-code"
            onClicked: pk.menu.addDevice()
        }
    }
}
