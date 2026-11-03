import QtQuick
import Quickshell
import Quickshell.Wayland

// Closes a popup (a top bar menu, the launcher) when the other screens are clicked: the popup's own window covers its
// own screen and catches the clicks there, but a click on another screen reached the window under it and left the
// popup open, keeping the keyboard (#2039). One transparent overlay per other screen, no keyboard focus; the click
// that closes is not passed on, as with the popup's own screen (and a Mac's menus).
Variants {
    id: root
    property bool active: false
    property string exceptScreen: ""   // the popup's screen (its name): its own window catches the clicks there
    property int topMargin: 0          // Theme.barHeight leaves the bars clickable (another screen's menu opens in one click)
    signal clicked()

    model: active ? Quickshell.screens.filter(s => s.name !== exceptScreen) : []

    delegate: PanelWindow {
        required property var modelData
        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        margins { top: root.topMargin }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "nightdrive-outside"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: root.clicked() }
    }
}
