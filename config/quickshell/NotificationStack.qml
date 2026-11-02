import QtQuick
import Quickshell
import "NotifGroups.js" as Groups

// One unit of notifications (#1982), in the popups (NotificationPopups.qml) and the menu (NotificationsMenu.qml): a
// stack of an app's notifications, or a pinned one on its own.
// - Closed, a stack shows its newest card whole, with its buttons, and the next two peeking out below it; "+N more" on the
//   card, or a click on the edges below it, opens it.
// - Open, every card shows with its own buttons (Undo, Allow, Show session stay reachable), under a header with the
//   stack's name, Show less and × (all of them).
// - A pinned one (critical, Claude's permission request) has a coloured edge: red for critical, the theme's for the rest.
// The ×, right click or swipe of a closed stack's card goes for the whole stack (as it stands for all of them), an open
// stack's for that card alone.
Item {
    id: st

    // --- Tunables ---
    readonly property int peek: 2              // cards peeking out below a closed stack
    readonly property int edgeStep: 6          // px each of them shows
    readonly property int edgeInset: 8         // px narrower on each side than the one above
    readonly property int headerHeight: 30

    property var unit: ({ key: "", pinned: false, rows: [] })
    property bool expanded: false
    property color color: Theme.bg
    // The popups slide a stack in and out with this; Clear in the menu adds its own (sweep())
    property real shiftX: 0

    readonly property var rows: unit.rows || []
    readonly property bool stacked: rows.length > 1
    readonly property bool open: expanded && stacked
    readonly property var shown: open ? rows : rows.slice(0, 1)
    readonly property int behind: open ? 0 : Math.min(peek, rows.length - 1)
    property int drags: 0                      // previews being dragged out of its cards
    readonly property bool hovered: hover.hovered || drags > 0

    signal activated(var row)                  // a card's click
    signal dismissed(var row)                  // an open stack's card: that one
    signal dismissedAll()                      // a closed stack's card, or the header's ×: all of them
    signal viewed(var row)                     // a preview opened in the image viewer
    signal dropped()                           // a preview dragged out landed
    signal swept()                             // Clear's animation is over

    width: 300
    height: col.implicitHeight + behind * edgeStep
    transform: Translate { x: st.shiftX + st.sweepX }

    HoverHandler { id: hover }

    // The cards behind the newest, below it; a click on them opens the stack
    Repeater {
        model: st.behind
        Rectangle {
            required property int index
            readonly property int depth: index + 1
            x: depth * st.edgeInset
            width: st.width - 2 * depth * st.edgeInset
            y: col.implicitHeight - 12 + depth * st.edgeStep
            height: 12
            z: -depth
            radius: 4
            color: Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0.92)
            border { width: 1; color: Theme.border }
        }
    }
    MouseArea {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: st.behind * st.edgeStep
        cursorShape: Qt.PointingHandCursor
        onClicked: st.expanded = true
    }

    Column {
        id: col
        width: st.width
        spacing: 10

        // An open stack's header: its name and how many, Show less, ×
        Rectangle {
            visible: st.open
            width: parent.width
            height: st.headerHeight
            radius: 4
            color: st.color
            Text {
                anchors { left: parent.left; leftMargin: 17; right: less.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: Groups.label(st.unit.key).toUpperCase() + "  ·  " + st.rows.length
                color: Theme.dim
                font { family: Theme.font; pixelSize: 10; letterSpacing: 1 }
            }
            Text {
                id: less
                anchors { right: all.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Show less"
                color: lessArea.containsMouse ? Theme.accent : Theme.dim
                font { family: Theme.font; pixelSize: 10 }
                MouseArea {
                    id: lessArea
                    anchors { fill: parent; margins: -6 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: st.expanded = false
                }
            }
            Text {
                id: all
                anchors { right: parent.right; rightMargin: 15; verticalCenter: parent.verticalCenter }
                text: Icons.g("x")
                color: allArea.containsMouse ? Theme.accent : Theme.dim
                font { family: Icons.family; pixelSize: 14 }
                MouseArea {
                    id: allArea
                    anchors { fill: parent; margins: -8 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: st.dismissedAll()
                }
            }
        }

        Repeater {
            // ScriptModel keeps the cards that stay when one comes or goes
            model: ScriptModel { values: st.shown }
            NotificationCard {
                id: card
                required property var modelData
                required property int index
                row: modelData
                // Its notification while the app keeps it open: its buttons answer from here
                n: Notifs.live[modelData.uid] || null
                width: col.width
                color: st.color
                onActivated: st.activated(modelData)
                onViewed: st.viewed(modelData)
                onDropped: st.dropped()
                onDraggingChanged: st.drags += dragging ? 1 : -1
                onDismissed: st.open ? st.dismissed(modelData) : st.dismissedAll()

                footer: Rectangle {
                    visible: !st.open && st.stacked && card.index === 0
                    width: visible ? moreText.implicitWidth + 18 : 0
                    height: visible ? 20 : 0
                    radius: 10
                    color: moreArea.containsMouse ? Theme.sel : "transparent"
                    border { width: 1; color: moreArea.containsMouse ? Theme.primary : Theme.border }
                    Text {
                        id: moreText
                        anchors.centerIn: parent
                        text: "+" + (st.rows.length - 1) + " more"
                        color: Theme.accent
                        font { family: Theme.font; pixelSize: 10 }
                    }
                    MouseArea {
                        id: moreArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: st.expanded = true
                    }
                }

                // A pinned one's edge
                Rectangle {
                    visible: st.unit.pinned
                    x: 0; y: 4
                    width: 3; height: card.height - 8
                    radius: 1.5
                    color: card.row.critical ? Theme.danger : Theme.primary
                }
            }
        }
    }

    // Clear in the menu: the stack slides a little to the right and fades out, then swept()
    property real sweepX: 0
    function sweep(delay) {
        sweeper.delay = delay
        sweeper.start()
    }
    SequentialAnimation {
        id: sweeper

        // --- Tunables ---
        readonly property int duration: 220    // ms, the same as NotificationCard's
        readonly property real distance: 40    // px

        property int delay: 0
        PauseAnimation { duration: sweeper.delay }
        ParallelAnimation {
            NumberAnimation { target: st; property: "sweepX"; to: sweeper.distance; duration: sweeper.duration; easing.type: Easing.OutCubic }
            NumberAnimation { target: st; property: "opacity"; to: 0; duration: sweeper.duration; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: st.swept() }
    }
}
