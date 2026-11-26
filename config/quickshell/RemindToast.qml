import QtQuick
import Quickshell
import Quickshell.Io

// Quick reminders (Dashboard #3118) as a banner of their own below the top bar, not a notification: among the many
// notifications one the user set for themselves went unseen. It comes with the urgent sound, stays until Dismiss, and
// shows through Do Not Disturb (the user asked for it). Several due at once are rows of one card, newest at the bottom.
// A two-finger swipe left or right dismisses too (SwipeOff.qml): the whole card when it has one row, else the row swiped.
// hypr/scripts/remind's `fire` shows it:  qs ipc call remind ring ID MESSAGE NOTE  (without Quickshell, or with an
// older one that has no such target, the script sends a notification instead). Kept only in memory: the reminder
// has left the script's state file once due, so a Quickshell restart drops a banner that is up.
Toast {
    id: card
    property var rows: []                 // [{ id, message, note }], oldest first
    readonly property int rowHeight: 58
    cardWidth: 460
    cardHeight: rows.length * rowHeight + 8
    clickable: true                       // the clicks are the Dismiss buttons'; the rest of the card does nothing
    shown: rows.length > 0
    // Its own look among the toasts: the theme's colour round it, so it reads as an alarm and not as a volume change
    border { width: 1; color: Theme.primary }
    function drop(id) { rows = rows.filter(r => r.id !== id) }

    // One row: the card itself goes with the fingers
    transform: Translate { x: cardSwipe.dx }
    opacity: 1 - cardSwipe.fade
    SwipeOff {
        id: cardSwipe
        enabled: card.rows.length === 1
        onGone: { const id = card.rows.length ? card.rows[0].id : ""; dx = 0; card.drop(id) }
    }

    IpcHandler {
        target: "remind"
        // "ok": the script can't tell otherwise, as qs ipc exits 0 also for a target or function it doesn't find. Not
        // named show: `qs ipc call remind show …` is read as qs ipc's own show
        function ring(id: string, message: string, note: string): string {
            card.rows = card.rows.filter(r => r.id !== id).concat([{ id: id, message: message, note: note }])
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "play", "urgent"])
            return "ok"
        }
        function dismiss(id: string): void { card.drop(id) }
        function list(): string { return JSON.stringify(card.rows) }
    }

    Column {
        anchors { fill: parent; topMargin: 4; bottomMargin: 4 }
        Repeater {
            model: card.rows
            Item {
                id: row
                required property var modelData
                width: card.width
                height: card.rowHeight
                // Several rows: each goes on its own, inside the card (Toast clips it)
                transform: Translate { x: rowSwipe.dx }
                opacity: 1 - rowSwipe.fade
                SwipeOff { id: rowSwipe; enabled: card.rows.length > 1; onGone: card.drop(row.modelData.id) }
                Text {
                    id: ico
                    anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                    text: Icons.g("alarm-clock")
                    font { family: Icons.family; pixelSize: 20 }
                    color: Theme.accent
                }
                Column {
                    anchors { left: ico.right; leftMargin: 14; right: btn.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    Text {
                        width: parent.width
                        text: modelData.message
                        color: Theme.text
                        elide: Text.ElideRight
                        font { family: Theme.font; pixelSize: 14 }
                    }
                    Text {   // why it comes now: missed, on arriving at work, on waking (remind_events.py)
                        width: parent.width
                        visible: text !== ""
                        text: modelData.note
                        color: Theme.dim
                        elide: Text.ElideRight
                        font { family: Theme.font; pixelSize: 11 }
                    }
                }
                Rectangle {
                    id: btn
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    width: label.implicitWidth + 24
                    height: 28
                    radius: 14
                    color: area.containsMouse ? Theme.sel : "transparent"
                    border { width: 1; color: area.containsMouse ? Theme.primary : Theme.border }
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: "Dismiss"
                        color: Theme.accent
                        font { family: Theme.font; pixelSize: 12 }
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.drop(modelData.id)
                    }
                }
            }
        }
    }
}
