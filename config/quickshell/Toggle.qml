import QtQuick

// An on/off switch: MenuHeader's (Wi-Fi, Bluetooth, Microphone) and a settings row's (Display › Night light).
// navSelected: keyboard focus on it turns the whole switch violet. busy: the change is still under way (a password
// prompt behind it), so it stays where it was, dimmed, its knob pulsing, and doesn't take clicks.
Rectangle {
    id: t
    property bool checked: false
    property bool navSelected: false
    property bool busy: false
    signal toggled()
    width: 34; height: 20; radius: 10
    opacity: busy ? 0.5 : 1
    color: navSelected ? Theme.primary : (checked ? Theme.accent : Theme.border)
    Rectangle {
        id: knob
        width: 14; height: 14; radius: 7; y: 3
        x: t.checked ? 17 : 3
        color: t.checked ? Theme.bg : Theme.text
        Behavior on x { NumberAnimation { duration: 120 } }
        SequentialAnimation on opacity {
            running: t.busy; loops: Animation.Infinite
            onRunningChanged: if (!running) knob.opacity = 1
            NumberAnimation { to: 0.2; duration: 450; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
        }
    }
    MouseArea { enabled: !t.busy; cursorShape: Qt.PointingHandCursor; anchors.fill: parent; onClicked: t.toggled() }
}
