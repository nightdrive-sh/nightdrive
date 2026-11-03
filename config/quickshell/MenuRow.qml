import QtQuick

// Menu row: icon, label, dimmed detail text and a trailing icon on the right edge.
Rectangle {
    id: row
    property string icon: ""
    property string label: ""
    property string detail: ""
    property string checkIcon: ""
    property string hoverCheckIcon: "" // replaces checkIcon under the mouse: what a click does (e.g. "unplug" on a connected device);
                                       // without a checkIcon it takes the detail's place under the mouse, so the detail
                                       // stays at the right edge (Ferry's items: the time, and × to remove one)
    property int checkIconSize: 16
    property bool active: false
    property bool tinted: false        // a light highlight (the action buttons' faint theme colour), e.g. this machine in Tailscale
    property bool iconFilled: false    // the icon in a filled circle of the theme colour (e.g. the connected Wi-Fi network, as in macOS)
    property bool danger: false
    property bool navSelected: false   // selected during keyboard navigation (⌘⇧Space)
    function navActivate() { row.clicked() }
    property bool action: false        // action button (Open …): uppercase, smaller font
    property bool centered: false      // icon and label centred (buttons side by side, e.g. Ferry's)
    property bool busy: false          // in progress (connecting …): animated dots instead of the detail text
    property bool interactive: true    // false: an information row (no hover, not clickable, skipped by the keyboard, no side padding)
    readonly property bool navEnabled: interactive
    property bool padded: interactive  // side padding like a clickable row (an information row among clickable ones)
    readonly property int pad: padded ? 10 : 0
    signal clicked()
    signal rightClicked()
    // The mouse's hover, put away by a key till the mouse moves (MenuPointer.qml)
    readonly property bool pointed: area.containsMouse && !MenuPointer.pointerAway
    readonly property bool hoverShown: hoverCheckIcon !== "" && (pointed || navSelected)
    readonly property bool hoverOnly: checkIcon === "" && hoverCheckIcon !== ""   // nothing to show until the mouse comes

    height: 34
    radius: 5
    // Action buttons (Open …, Disconnect) get a faint wash of the theme colour so they read as buttons
    color: (pointed && interactive) || navSelected ? Theme.hover
         : active && interactive ? Theme.sel
         : action || tinted ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.07) : "transparent"
    border { width: navSelected ? 1 : 0; color: Theme.primary }

    readonly property color fg: danger ? Theme.danger : (active ? Theme.accent : Theme.text)

    // level 0..1: a ring around the icon (Home: a light's brightness); -1 = none. iconColor: the icon's own colour
    property real level: -1
    property color iconColor: "transparent"
    LevelRing {
        visible: row.level >= 0 && ic.visible
        anchors.centerIn: ic
        size: 28
        value: Math.max(0, row.level)
    }

    Rectangle {
        visible: row.iconFilled && ic.visible
        anchors.centerIn: ic
        width: 26; height: 26; radius: 13
        color: Theme.primary
    }
    Text {
        id: ic
        visible: row.icon !== ""
        // A filled circle (26 px) is wider than the icon (20 px): without side padding it starts at the left edge
        anchors { left: parent.left; verticalCenter: parent.verticalCenter
                  leftMargin: row.centered ? Math.max(6, (row.width - width - 10 - lbl.implicitWidth) / 2)
                                           : row.pad + (row.iconFilled && !row.padded ? 3 : 0) }
        width: 20
        horizontalAlignment: Text.AlignHCenter
        text: Icons.g(row.icon)
        color: row.iconFilled ? Theme.bg : row.iconColor.a > 0 ? row.iconColor : (row.active || row.danger ? row.fg : Theme.dim)
        font { family: Icons.family; pixelSize: row.iconFilled ? 17 : 16 }
    }
    Text {
        id: lbl
        anchors {
            left: ic.visible ? ic.right : parent.left; leftMargin: ic.visible ? 10 : (row.padded ? 12 : 0)
            right: row.centered ? parent.right : trailing.left; rightMargin: row.centered ? 6 : 8   // centred: a narrow button, no detail
            verticalCenter: parent.verticalCenter
            // An action's uppercase text has no descenders, so centring by line height leaves it high next to the icon
            verticalCenterOffset: row.action ? 1 : 0
        }
        elide: Text.ElideRight
        text: row.action ? row.label.toUpperCase() : row.label
        color: row.fg
        font { family: Theme.font; pixelSize: row.action ? 11 : 13; letterSpacing: row.action ? 0.6 : 0 }
    }
    Row {
        id: trailing
        anchors { right: parent.right; rightMargin: row.pad; verticalCenter: parent.verticalCenter }
        spacing: 8
        BusyDots {
            visible: row.busy
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: row.detail !== "" && !row.busy
            anchors.verticalCenter: parent.verticalCenter
            text: row.detail
            color: Theme.dim
            font { family: Theme.font; pixelSize: 11 }
            opacity: row.hoverOnly && row.hoverShown ? 0 : 1   // the hover icon comes in its place
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
        }
        // Under the mouse the hover icon cross-fades over the check: one shrinks and fades out while the other grows in
        Item {
            id: checkBox
            readonly property bool hovering: row.hoverShown
            visible: row.checkIcon !== ""   // a hover-only icon has no place of its own: hoverIcon, below
            anchors.verticalCenter: parent.verticalCenter
            width: checkText.implicitWidth; height: checkText.implicitHeight
            Text {
                id: checkText
                readonly property bool on: !checkBox.hovering && row.checkIcon !== ""
                anchors.centerIn: parent
                text: Icons.g(row.checkIcon || row.hoverCheckIcon)
                color: row.active ? Theme.accent : Theme.dim
                font { family: Icons.family; pixelSize: row.checkIconSize }
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
            }
            Text {
                readonly property bool on: checkBox.hovering
                anchors.centerIn: parent
                text: Icons.g(row.hoverCheckIcon)
                color: row.active ? Theme.accent : Theme.dim
                font { family: Icons.family; pixelSize: row.checkIconSize }
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
            }
        }
    }
    // A hover icon without a check: over the right edge, where the detail fades out (hoverOnly)
    Text {
        id: hoverIcon
        visible: row.hoverOnly
        anchors { right: parent.right; rightMargin: row.pad; verticalCenter: parent.verticalCenter }
        text: Icons.g(row.hoverCheckIcon)
        color: row.active ? Theme.accent : Theme.dim
        font { family: Icons.family; pixelSize: row.checkIconSize }
        opacity: row.hoverShown ? 1 : 0
        scale: row.hoverShown ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
    }
    MouseArea {
        visible: row.interactive   // not just disabled: a disabled MouseArea still sets the hand cursor
        cursorShape: Qt.PointingHandCursor
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => mouse.button === Qt.RightButton ? row.rightClicked() : row.clicked()
    }
}
