import QtQuick
import Quickshell
import Quickshell.Io

// Cleaning mode's countdown (hypr/scripts/clean-input): while the keyboards and the touchpad are locked, a card says so
// and counts the seconds down, so it's clear the lock ends by itself. A click on the card (with a mouse, which still
// works) ends it now. The script shows and hides it:  qs ipc call clean countdown SECONDS | hide
// The card also goes by itself a little after its end: the script, not this card, gives the input back, and a card
// left up would say the keyboard is locked when it isn't.
Toast {
    id: card
    property int secondsLeft: 0
    cardWidth: 380
    cardHeight: 64
    clickable: true
    onTapped: Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/clean-input", "stop"])

    IpcHandler {
        target: "clean"
        function countdown(seconds: int): void { card.secondsLeft = seconds; card.shown = true; tick.restart() }
        function hide(): void { card.shown = false; tick.stop() }
    }

    // A second at a time; at zero it waits a few seconds for the script's hide, then goes anyway
    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            card.secondsLeft--
            if (card.secondsLeft <= -3) { card.shown = false; stop() }
        }
    }

    Text {
        id: ico
        anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
        text: Icons.g("keyboard-off")
        font { family: Icons.family; pixelSize: 20 }
        color: Theme.accent
    }
    Column {
        anchors { left: ico.right; leftMargin: 14; right: count.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 3
        Text {
            text: "KEYBOARD AND TOUCHPAD LOCKED"
            color: Theme.primary
            font { family: Theme.font; pixelSize: 12; letterSpacing: 0.6 }
        }
        Text {
            text: "Ends by itself · a click ends it now"
            color: Theme.dim
            font { family: Theme.font; pixelSize: 11 }
            elide: Text.ElideRight
            width: parent.width
        }
    }
    Text {
        id: count
        anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
        text: Math.max(0, card.secondsLeft)
        color: Theme.text
        font { family: Theme.font; pixelSize: 22 }
    }
}
