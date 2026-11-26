import QtQuick
import qs

// Ferry's menu: a round button beside Send Clipboard (Aa, +), an icon or a short text. Its own file so FerryMenu.qml
// keeps to the menu's state and layout; keyboard navigation (shell.qml's navRows) finds it by navActivate.
Rectangle {
    id: rb
    property string icon: ""
    property string label: ""
    property bool on: false
    property bool usable: true
    property bool navSelected: false
    readonly property bool navEnabled: usable
    function navActivate() { rb.clicked() }
    signal clicked()
    width: 36; height: 36; radius: 18
    color: on ? Theme.sel : rbArea.containsMouse && !MenuPointer.pointerAway || navSelected ? Theme.hover : Theme.card
    border { width: 1; color: on || navSelected ? Theme.primary : Theme.border }
    opacity: usable ? 1 : 0.4
    Text {
        anchors.centerIn: parent
        text: rb.icon !== "" ? Icons.g(rb.icon) : rb.label
        color: Theme.accent
        font { family: rb.icon !== "" ? Icons.family : Theme.font; pixelSize: rb.icon !== "" ? 17 : 13 }
    }
    MouseArea {
        id: rbArea
        anchors.fill: parent
        enabled: rb.usable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: rb.clicked()
    }
}
