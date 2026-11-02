import QtQuick
import Quickshell
import Quickshell.Wayland
import "NotifGroups.js" as Groups

// Notification popups (top right, below the bar; data in Notifs.qml, a stack of cards in NotificationStack.qml, a card in
// NotificationCard.qml). Pinned ones first, then an app's notifications stacked, newest on top (#1982). Click = open (the
// app's default action or its window), right click, × or a two-finger swipe right = dismiss (a closed stack: all of it),
// the mouse over a stack keeps it.
// Hyprland blurs what's behind the cards (layer rule in hyprland.lua, namespace nightdrive-notifications).
PanelWindow {
    id: win

    // --- Tunables ---
    readonly property int cardWidth: 300
    readonly property int gap: 10              // between cards, and from the screen edge
    readonly property real bgOpacity: 0.85

    visible: Notifs.popups.length > 0
    // The full height, not the cards': the surface doesn't change size when one goes, so the cards sliding up into
    // its place aren't cut off by a window that already shrank (a flicker). Clicks pass through outside the cards (mask);
    // Hyprland's blur skips the transparent part (ignore_alpha).
    anchors { top: true; right: true; bottom: true }
    margins { top: gap; right: gap; bottom: gap }
    implicitWidth: cardWidth
    mask: Region { item: cards }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal        // below the bar, like mako was
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "nightdrive-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Pinned ones first, then a stack per app (NotifGroups.js). The Repeater's model is the units' keys, which stay the
    // same as a stack grows (a new array of units each time would make every stack anew: closed again, sliding in again)
    readonly property var units: Groups.units(Notifs.popups.map(p => p.entry), r => true)
    readonly property var byKey: {
        const m = {}
        for (const u of units) m[u.key] = u
        return m
    }
    // A popup's notification; its popup goes (dismiss: the history keeps its row)
    function dismiss(row) {
        const n = Notifs.live[row.uid]
        if (n) n.dismiss()
        else Notifs.hide(row.uid)
    }
    function popup(row) { return Notifs.popups.find(p => p.uid === row.uid) }

    Column {
        id: cards
        width: win.cardWidth
        spacing: win.gap
        // The stacks below a removed one slide up into its place
        move: Transition { NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic } }
        Repeater {
            model: ScriptModel { values: win.units.map(u => u.key) }
            NotificationStack {
                id: stack
                required property var modelData
                unit: win.byKey[modelData] || ({ key: modelData, pinned: false, rows: [] })
                width: win.cardWidth
                color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, win.bgOpacity)
                onActivated: row => { const p = win.popup(row); if (p) Notifs.activate(p) }
                onViewed: row => Notifs.hide(row.uid)   // the viewer has it now; it stays in the history
                onDismissed: row => win.dismiss(row)
                onDismissedAll: { for (const r of stack.rows.slice()) win.dismiss(r) }

                // Slides in from the right
                opacity: 0
                shiftX: 40
                Component.onCompleted: enter.start()
                ParallelAnimation {
                    id: enter
                    NumberAnimation { target: stack; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: stack; property: "shiftX"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                }

                // Goes after Notifs.timeout, sliding out the way it came; a new card in the stack, or the mouse over it,
                // restarts the wait. A pinned one stays, and so does an open stack.
                readonly property int newest: stack.rows.length ? stack.rows[0].uid : -1
                onNewestChanged: if (wait.running) wait.restart()
                Timer {
                    id: wait
                    running: !stack.unit.pinned && !stack.open && !stack.hovered && !leave.running
                    interval: Notifs.timeout
                    onTriggered: { enter.stop(); leave.start() }
                }
                ParallelAnimation {
                    id: leave
                    NumberAnimation { target: stack; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                    NumberAnimation { target: stack; property: "shiftX"; to: 40; duration: 180; easing.type: Easing.InCubic }
                    onFinished: { for (const r of stack.rows.slice()) Notifs.hide(r.uid) }
                }
            }
        }
    }
}
