import QtQuick

// One session in the sessions bar (SessionsBar.qml): its state's icon and its name, in a low rounded box only when its
// window has the focus or the mouse is on it (boxes on every chip made the bar busy). Asking you something: the
// question icon in red and its name in the theme colour (no coloured box: it was too loud); done (its last reply signs
// off with ✅): a green check; finished while you were in another window: the bell with a dot, as in the Claude menu;
// working: the spinner; waiting for you: a prompt (›; the terminal >_ read as noise). iconOnly on a crowded, narrow
// bar.
// A lead (a session that opened others, SessionGroups.js) has its name in bold and the bot for its icon, which
// breathes while it works; the chips it opened follow it.
// After its name, small and grey: how long it has worked on this turn or waited for you (SessionsBar.age); a turn
// past stuckAfter is in the warning colour, as it's likely stuck. The bar hides it when crowded, before the name.
Rectangle {
    id: chip
    property var session: ({})
    property string text: ""
    property bool active: false          // its window has the focus
    property bool iconOnly: false
    property int padding: 10
    property bool lead: false
    property string time: ""             // "" = none
    property bool showTime: true
    property bool stuck: false
    property int timeGap: 10             // between the name and the time
    readonly property bool hovered: area.containsMouse
    signal clicked()

    readonly property bool asking: !!session.asking
    readonly property bool done: !!session.done
    readonly property bool working: session.state === "working"
    readonly property string icon: asking ? "message-circle-question" : lead ? "bot" : done ? "circle-check-big"
                                 : session.wants ? "bell-dot" : working ? "loader" : "chevron-right"
    // Asking: the question in the top bar's critical red (as the Dashboard's tasks there), so it stands out without a box
    readonly property color iconColor: asking ? Theme.danger : lead || (session.wants && !done) ? Theme.accent
                                     : done ? Theme.ok : working ? Theme.text : Theme.dim

    height: 27   // SessionsBar.chipH sets it (anchors.fill)
    radius: 6
    // The focused session's chip: the top bar's active workspace colour (see-through, so it matches over any bar
    // opacity); under the mouse a step stronger, as plain hover is darker than it
    readonly property color activeBg: TopBar.c("wsBg")
    color: hovered && active ? Qt.rgba(activeBg.r, activeBg.g, activeBg.b, Math.min(1, activeBg.a * 1.4))
         : hovered ? Theme.hover : active ? activeBg : "transparent"

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
    // The time follows the name (the bar sizes a chip to fit both; shared, the name is shortened before the time)
    Text {
        id: nm
        visible: !chip.iconOnly
        anchors { left: ic.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
        width: Math.min(implicitWidth, chip.width - x - chip.padding - (tm.visible ? tm.implicitWidth + chip.timeGap : 0))
        text: chip.text
        elide: Text.ElideRight
        color: chip.asking || chip.active ? Theme.accent : chip.lead ? Theme.title : Theme.text
        font { family: Theme.font; pixelSize: 12; bold: chip.lead }   // SessionsBar.layout measures these fonts
    }
    Text {
        id: tm
        visible: chip.showTime && !chip.iconOnly && chip.time !== ""
        anchors { left: nm.right; leftMargin: chip.timeGap; verticalCenter: parent.verticalCenter }
        text: chip.time
        color: chip.stuck ? Theme.warning : Theme.dim
        font { family: Theme.font; pixelSize: 10; bold: chip.stuck }   // SessionsBar.timeW measures this font
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
