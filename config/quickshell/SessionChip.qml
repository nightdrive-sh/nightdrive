import QtQuick

// One session in the sessions bar (SessionsBar.qml): a low rounded box with its state's icon and its name. Asking you
// something: the theme colour's box; done (its last reply signs off with ✅): a green check; finished while you were in
// another window: the bell with a dot, as in the Claude menu; working: the spinner. iconOnly on a crowded, narrow bar.
// No border: a fill of its own. A lead (a session that opened others, SessionGroups.js) has a quiet border, its name in
// bold and the bot for its icon, which breathes while it works; a chip it opened is linked: a line to the one before.
Rectangle {
    id: chip
    property var session: ({})
    property string text: ""
    property bool active: false          // its window has the focus
    property bool iconOnly: false
    property int padding: 10
    property bool lead: false
    property bool linked: false          // a line across the gap to the chip before it (its group's)
    property int linkWidth: 8
    property color lineColor: Theme.border
    readonly property bool hovered: area.containsMouse
    signal clicked()

    readonly property bool asking: !!session.asking
    readonly property bool done: !!session.done
    readonly property bool working: session.state === "working"
    readonly property string icon: asking ? "message-circle-question" : lead ? "bot" : done ? "circle-check-big"
                                 : session.wants ? "bell-dot" : working ? "loader" : "terminal"
    readonly property color iconColor: asking || lead || (session.wants && !done) ? Theme.accent : done ? Theme.ok
                                     : working ? Theme.text : Theme.dim

    height: 24
    radius: 6
    color: asking ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, hovered ? 0.4 : 0.28)
         : hovered ? Theme.hover : active ? Theme.sel : Theme.card
    border { width: lead ? 1 : 0; color: chip.lineColor }

    Rectangle {
        visible: chip.linked
        x: -chip.linkWidth; width: chip.linkWidth; height: 2
        anchors.verticalCenter: parent.verticalCenter
        color: chip.lineColor
    }

    Text {
        id: ic
        anchors { left: parent.left; leftMargin: chip.iconOnly ? (chip.width - width) / 2 : chip.padding
                  verticalCenter: parent.verticalCenter }
        width: 16
        horizontalAlignment: Text.AlignHCenter
        text: Icons.g(chip.icon)
        color: chip.iconColor
        font { family: Icons.family; pixelSize: 14 }
        // The spinner turns while it works (on the render thread: no cost to the rest)
        RotationAnimator on rotation {
            running: chip.working && !chip.asking && !chip.lead && chip.visible
            from: 0; to: 360; duration: 1600; loops: Animation.Infinite
            onRunningChanged: if (!running) ic.rotation = 0
        }
        // A lead keeps its bot while it works: it breathes instead
        SequentialAnimation on opacity {
            running: chip.working && !chip.asking && chip.lead && chip.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) ic.opacity = 1
        }
    }
    Text {
        visible: !chip.iconOnly
        anchors { left: ic.right; leftMargin: 6; right: parent.right; rightMargin: chip.padding
                  verticalCenter: parent.verticalCenter }
        text: chip.text
        elide: Text.ElideRight
        color: chip.asking || chip.active ? Theme.accent : chip.lead ? Theme.title : Theme.text
        font { family: Theme.font; pixelSize: 12; bold: chip.lead }   // SessionsBar.widths measures a lead's bold
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
