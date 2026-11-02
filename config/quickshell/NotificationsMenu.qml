import QtQuick
import Quickshell
import "NotifGroups.js" as Groups

// Hamburger menu: notifications (Notifs.qml's history + do-not-disturb toggle), ⌘Esc / F3.
// A bare menu (shell.qml draws no card around it): a bar with the title and the controls, then the notifications as
// cards, the same as the popups and in the same place, so one is easy to find again (#1982): under Needs you the pinned
// ones still waiting for an answer (critical, Claude's permission requests), then under Earlier a stack per app, newest
// on top (NotificationStack.qml: "+N more" opens it).
// Click = open the app, ×, right click or a two-finger swipe right = remove it (a closed stack: all of it), Clear =
// remove all (the stacks slide a little to the right and fade out one after another, NotificationStack.sweep()). A
// screenshot's preview drags out as a file; the menu closes when it lands. A notification still open has its app's
// buttons, as in the popup.
// The power actions (lock, suspend, log out, reboot, shut down) live in the launcher (⌘Space › Power).
Column {
    id: m

    // --- Tunables ---
    readonly property int maxCards: 6          // stacks shown whole, then the list scrolls (no sliver of the next one)
    readonly property real bgOpacity: 0.85     // the same as the popups (NotificationPopups.qml)

    readonly property bool bare: true
    readonly property int preferredWidth: 300   // the popups' width
    width: parent ? parent.width : 300
    spacing: 10                                 // the popups' gap

    property real lastShownBottom: -1           // the bottom of stack number maxCards (set by that stack)

    // Pinned ones still open first, then a stack per app. The Repeater's model is the units' keys (NotificationPopups.qml
    // says why).
    readonly property var units: Groups.units(Notifs.history, r => !!Notifs.live[r.uid])
    readonly property var byKey: {
        const m = {}
        for (const u of units) m[u.key] = u
        return m
    }
    readonly property bool anyPinned: units.length > 0 && units[0].pinned
    property int dragging: 0                    // previews being dragged out: shell.qml lets the drop through to the windows below

    // Clear: the cards in view go one after another from the top, the history empties when the last is gone
    property bool clearing: false
    property int sweeping: 0
    function clearAll() {
        if (clearing) return
        clearing = true
        let n = 0
        for (let i = 0; i < rep.count; i++) {
            const c = rep.itemAt(i)
            if (!c || c.y + c.height <= flick.contentY || c.y >= flick.contentY + flick.height) continue
            c.stack.sweep(n * 40)
            n++
        }
        sweeping = n
        if (n === 0) cleared()
    }
    function sweptOne() { if (--sweeping <= 0) cleared() }
    function cleared() { Notifs.history = []; clearing = false }

    Component.onDestruction: {
        Notifs.menuOpen = false
        if (clearing) Notifs.history = []      // the menu closed mid-clear
    }

    signal close()

    Component.onCompleted: { Notifs.now = Date.now(); Notifs.menuOpen = true }     // fresh "min ago" when the menu opens

    // Toggle on = notifications are shown; off = do not disturb (hypr/scripts/dnd: also shows the OSD). Clear next to it.
    Rectangle {
        width: parent.width
        height: 46
        radius: 4
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, m.bgOpacity)
        MenuHeader {
            id: header
            anchors { left: parent.left; right: parent.right; leftMargin: 17; rightMargin: 17; verticalCenter: parent.verticalCenter }
            title: "Notifications"
            showToggle: true; checked: !Notifs.dnd
            onToggled: Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/dnd"])
        }
        Rectangle {
            id: clear
            // keyboard navigation (shell.qml: ⌘⇧Space, arrows): a row the menu can select
            property bool navSelected: false
            readonly property bool navEnabled: Notifs.history.length > 0
            function navActivate() { m.clearAll() }
            readonly property bool on: Notifs.history.length > 0 && !m.clearing
            readonly property bool lit: on && (clearArea.containsMouse || navSelected)
            anchors { right: parent.right; rightMargin: 61; verticalCenter: parent.verticalCenter }   // left of the toggle (17 + 34 + 10)
            width: clearText.implicitWidth + 18; height: 20; radius: 10
            color: lit ? Theme.sel : "transparent"
            border.width: 1
            border.color: lit ? Theme.primary : Theme.border
            opacity: on ? 1 : 0.4
            Text {
                id: clearText
                anchors.centerIn: parent
                text: "CLEAR"
                color: clear.lit ? Theme.accent : Theme.dim
                font { family: Theme.font; pixelSize: 9; letterSpacing: 0.8 }
            }
            MouseArea {
                id: clearArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: clear.on
                cursorShape: Qt.PointingHandCursor
                onClicked: clear.navActivate()
            }
        }
    }

    Flickable {
        id: flick
        visible: Notifs.history.length > 0
        width: parent.width
        height: Notifs.history.length > m.maxCards && m.lastShownBottom > 0 ? m.lastShownBottom : cards.implicitHeight
        contentHeight: cards.implicitHeight
        clip: true
        interactive: !m.clearing
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick   // a sideways swipe is the card's (swipe to dismiss)
        TouchScroll { view: flick; step: 60 }
        Column {
            id: cards
            width: flick.width
            spacing: 10
            // The cards below a removed one slide up into its place
            move: Transition { NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic } }
            Repeater {
                id: rep
                model: ScriptModel { values: m.units.map(u => u.key) }
                Column {
                    id: unitItem
                    required property var modelData
                    required property int index
                    readonly property var unit: m.byKey[modelData] || ({ key: modelData, pinned: false, rows: [] })
                    readonly property alias stack: stack
                    width: cards.width
                    spacing: 10

                    // Needs you above the first pinned one, Earlier above the first stack after them
                    Rectangle {
                        readonly property string text: unitItem.unit.pinned ? "NEEDS YOU" : "EARLIER"
                        visible: m.anyPinned && (unitItem.index === 0
                                 || (!unitItem.unit.pinned && m.units[unitItem.index - 1] && m.units[unitItem.index - 1].pinned))
                        width: sectionText.implicitWidth + 16; height: 18; radius: 9
                        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, m.bgOpacity)
                        Text {
                            id: sectionText
                            anchors.centerIn: parent
                            text: parent.text
                            color: Theme.dim
                            font { family: Theme.font; pixelSize: 9; letterSpacing: 1.2 }
                        }
                    }
                    NotificationStack {
                        id: stack
                        unit: unitItem.unit
                        width: cards.width
                        enabled: !m.clearing
                        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, m.bgOpacity)
                        onSwept: m.sweptOne()
                        property int counted: 0        // its drags already in m.dragging
                        onDragsChanged: { m.dragging += drags - counted; counted = drags }
                        onDropped: m.close()
                        onViewed: m.close()
                        onActivated: row => { Notifs.openApp(row); m.close() }
                        onDismissed: row => Notifs.forget(row.uid)
                        onDismissedAll: { for (const r of stack.rows.slice()) Notifs.forget(r.uid) }
                    }
                    Binding { when: unitItem.index === m.maxCards - 1; target: m; property: "lastShownBottom"; value: unitItem.y + unitItem.height }
                }
            }
        }
    }
}
