import QtQuick
import Quickshell
import Quickshell.Wayland

// Notification popups (top right, below the bar; data in Notifs.qml, the card in NotificationCard.qml). Click = open (the
// app's default action or its window), right click, × or a two-finger swipe right = dismiss, the mouse over a card keeps it.
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

    Column {
        id: cards
        width: win.cardWidth
        spacing: win.gap
        // The cards below a removed one slide up into its place
        move: Transition { NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic } }
        Repeater {
            // ScriptModel keeps the other cards when one goes (a plain array would make them all again and slide them in anew)
            model: ScriptModel { values: Notifs.popups }
            NotificationCard {
                id: card
                required property var modelData
                n: modelData.n
                row: modelData.entry
                width: win.cardWidth
                color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, win.bgOpacity)
                onActivated: Notifs.activate(modelData)
                onViewed: Notifs.hide(modelData.uid)   // the viewer has it now; it stays in the history
                onDismissed: if (n) n.dismiss()

                // Slides in from the right
                appear: 0
                enterX: 40
                Component.onCompleted: enter.start()
                ParallelAnimation {
                    id: enter
                    NumberAnimation { target: card; property: "appear"; to: 1; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: card; property: "enterX"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                }

                // Goes after Notifs.timeout, sliding out the way it came; the mouse over the card restarts the wait,
                // pinned ones stay
                Timer {
                    running: !card.row.pinned && !card.hovered && !leave.running
                    interval: Notifs.timeout
                    onTriggered: { enter.stop(); leave.start() }
                }
                ParallelAnimation {
                    id: leave
                    NumberAnimation { target: card; property: "appear"; to: 0; duration: 180; easing.type: Easing.InCubic }
                    NumberAnimation { target: card; property: "enterX"; to: 40; duration: 180; easing.type: Easing.InCubic }
                    onFinished: Notifs.hide(card.modelData.uid)
                }
            }
        }
    }
}
