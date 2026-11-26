import QtQuick

// A menu's button (Open …, Disconnect, Settings…): a round-ended pill with a soft wash of the theme colour, the icon and
// the label in its middle, as Ferry's Send Clipboard. Every menu's buttons are these (plugins/README.md › The menu).
//   icon, label, onClicked
//   usable: false dims it and takes no clicks (Send while nothing can be sent)
//   busy: animated dots after the label (Disconnecting…)
//   danger: red (Click again to forget)
//   gap: more room above it than the menu's spacing, so it stands apart from the rows over it
// Keyboard navigation (⌘⇧Space) comes with it.
Item {
    id: b
    property string icon: ""
    property string label: ""
    property bool usable: true
    property bool busy: false
    property bool danger: false
    property int gap: 0
    property bool navSelected: false
    readonly property bool navEnabled: visible && usable
    function navActivate() { b.clicked() }
    signal clicked()

    width: parent ? parent.width : 300
    height: visible ? gap + 36 : 0

    readonly property color fg: danger ? Theme.danger : Theme.accent

    Rectangle {
        y: b.gap
        width: parent.width
        height: 36
        radius: 18
        color: area.containsMouse && !MenuPointer.pointerAway && b.usable ? Qt.lighter(Theme.sel, 1.3) : Theme.sel   // under the mouse just brighter
        border { width: 1; color: b.navSelected ? Theme.primary : b.danger ? Theme.danger : Theme.border }
        opacity: b.usable ? 1 : 0.4
        Row {
            anchors.centerIn: parent
            spacing: 9
            Text {
                visible: b.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.g(b.icon)
                color: b.fg
                font { family: Icons.family; pixelSize: 16 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: b.label
                textFormat: Text.PlainText   // may hold a device's name (Ferry's "Sent to …"): never markup
                color: b.fg
                font { family: Theme.font; pixelSize: 13; weight: Font.Medium }
            }
            BusyDots {
                visible: b.busy
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            enabled: b.usable
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: b.clicked()
        }
    }
}
