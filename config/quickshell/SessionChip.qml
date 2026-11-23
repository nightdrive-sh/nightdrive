import QtQuick

// One session in the sessions bar (SessionsBar.qml): its state's icon and its name, in a low rounded box only when its
// window has the focus or the mouse is on it (boxes on every chip made the bar busy). Asking you something: the
// question icon in red and its name in the theme colour (no coloured box: it was too loud); done (its last reply signs
// off with ✅): a green check; finished while you were in another window: the bell with a dot, as in the Claude menu;
// working: the spinner; waiting for you: a prompt (›; the terminal >_ read as noise). iconOnly on a crowded, narrow
// bar.
// Asking and not yet seen (Claude.qml's hop: you haven't been to its window since it began to ask, a permission request
// too): its icon hops twice, hopHeight px up and back, every hopEvery ms, the bar's one movement that wants you
// (#3126). One 2 px hop every 8 s went unseen. A permission request (Claude Code's record waits for a "permission
// prompt", not a question's "input needed") has a shield in the warning colour instead of the question: it stops the
// session mid-work, while a question waits at its end. While the bar shows, the chip is all you get of it (no
// notification, #3182), so one left unseen for urgentAfter (SessionsBar) turns red and hops every 2 s: a stuck
// session doesn't go unnoticed, and still nothing pops up.
// A lead (a session that opened others, SessionGroups.js) has its name in bold and the bot for its icon, which
// breathes while it works; the chips it opened follow it.
// After its name, small and grey: how long it has worked on this turn or waited for you (SessionsBar.age); a turn
// past stuckAfter is in the warning colour, as it's likely stuck. Before the time, as small and grey: the task number
// of a session named "#N topic" (SessionsBar.tag; #2427), left out of its name. The bar hides the time when crowded;
// the number shows only while the name fits whole beside it, so the name wins the room (#2443). A done session has
// no time (SessionsBar.chipTime).
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
    property string tag: ""              // "#2427", or ""
    property bool showTag: true
    property bool stuck: false
    property int timeGap: 10             // between the name and the time (or the tag)
    property int tagGap: 5               // between the tag and the time
    readonly property bool hovered: area.containsMouse
    // The tag only while the whole name fits beside it (and the time, when that shows): crowded, the number goes and
    // the name keeps its room (#2443). Measured on implicit widths, so it doesn't loop through nm's width.
    readonly property bool tagShown: showTag && !iconOnly && tag !== ""
        && nm.implicitWidth + timeGap + tg.implicitWidth + (tm.visible ? tagGap + bracketed.width : 0)
           <= width - nm.x - padding
    // What follows the name; the name's width takes the same measures as tagShown, or a name that just fits is elided
    readonly property real afterName: tagShown ? timeGap + tg.implicitWidth + (tm.visible ? tagGap + bracketed.width : 0)
                                     : tm.visible ? timeGap + tm.implicitWidth : 0
    signal clicked()

    readonly property bool asking: !!session.asking
    readonly property bool done: !!session.done
    readonly property bool working: session.state === "working"
    readonly property bool hop: !!session.hop
    // What it waits for, from Claude Code's record (claude-sessions): "input needed" is a question (AskUserQuestion),
    // the rest ("permission prompt", "sandbox request", …) want your permission
    readonly property bool permission: asking && !!session.waitingFor && session.waitingFor !== "input needed"
    property bool urgent: false          // a permission request left unseen too long (SessionsBar.urgentAfter)
    property int hopEvery: urgent ? 2000 : 6000
    property int hopHeight: 3
    readonly property string icon: permission ? "shield-alert" : asking ? "message-circle-question" : lead ? "bot"
                                 : done ? "circle-check-big" : session.wants ? "bell-dot" : working ? "loader" : "chevron-right"
    // Asking: the question in the top bar's critical red (as the Dashboard's tasks there), so it stands out without a
    // box; a permission request's shield in the warning colour, red once urgent
    readonly property color iconColor: permission && !urgent ? Theme.warning : asking ? Theme.danger
                                     : lead || (session.wants && !done) ? Theme.accent
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
        transform: Translate { id: lift }
        // The hop: at once when it begins to ask, then every hopEvery ms; two quick ones, a knock rather than a wave
        SequentialAnimation {
            running: chip.hop && chip.visible
            loops: Animation.Infinite
            NumberAnimation { target: lift; property: "y"; to: -chip.hopHeight; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: lift; property: "y"; to: 0; duration: 140; easing.type: Easing.InQuad }
            NumberAnimation { target: lift; property: "y"; to: -chip.hopHeight; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: lift; property: "y"; to: 0; duration: 220; easing.type: Easing.OutBounce }
            PauseAnimation { duration: Math.max(0, chip.hopEvery - 600) }
            onRunningChanged: if (!running) lift.y = 0
        }
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
        width: Math.min(implicitWidth, chip.width - x - chip.padding - chip.afterName)
        text: chip.text
        elide: Text.ElideRight
        color: chip.asking || chip.active ? Theme.accent : chip.lead ? Theme.title : Theme.text
        font { family: Theme.font; pixelSize: 12; bold: chip.lead }   // SessionsBar.layout measures these fonts
    }
    Text {
        id: tg
        visible: chip.tagShown
        anchors { left: nm.right; leftMargin: chip.timeGap; verticalCenter: parent.verticalCenter }
        text: chip.tag
        color: Theme.dim
        font { family: Theme.font; pixelSize: 10 }   // SessionsBar.tagW measures this font
    }
    Text {
        id: tm
        visible: chip.showTime && !chip.iconOnly && chip.time !== ""
        anchors { left: tg.visible ? tg.right : nm.right; leftMargin: tg.visible ? chip.tagGap : chip.timeGap
                  verticalCenter: parent.verticalCenter }
        text: tg.visible ? "(" + chip.time + ")" : chip.time   // "#2427 (8 min)"
        color: chip.stuck ? Theme.warning : Theme.dim
        font { family: Theme.font; pixelSize: 10; bold: chip.stuck }   // SessionsBar.timeW measures this font
    }
    // The time as it reads after a tag, for tagShown (tm's own width changes with the tag: a loop)
    TextMetrics { id: bracketed; font: tm.font; text: "(" + chip.time + ")" }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
