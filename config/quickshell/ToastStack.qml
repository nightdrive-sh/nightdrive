import QtQuick
import Quickshell
import Quickshell.Wayland

// The toasts' place: one surface at the top centre, just below the bar, with the shown cards (Toast.qml) stacked
// downwards in the order they're declared in shell.qml. A long-lived card (dictation, later Ask Claude) goes first, so
// a volume toast meanwhile appears below it instead of covering it.
// Toasts don't take input, so the surface lets clicks through and has no keyboard. A card that is written in (Ask
// Claude, Dashboard #1895) sets takesKeys: then the surface takes the keyboard as the launcher does, and the whole
// screen's clicks, so a click beside the card closes it (its outsideClicked) instead of leaving the keys with a card
// that no longer seems to be in use.
PanelWindow {
    id: stack
    default property alias cards: column.data
    readonly property bool anyShown: {
        for (let i = 0; i < column.children.length; i++)
            if (column.children[i].shown) return true
        return false
    }
    readonly property var keyCard: {
        for (let i = 0; i < column.children.length; i++) {
            const c = column.children[i]
            if (c.shown && c.takesKeys) return c
        }
        return null
    }

    // The whole screen, so the click catcher can cover it; nothing but the cards is drawn, and without a keyCard the
    // input region is empty
    visible: anyShown
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nightdrive-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: keyCard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: keyCard ? everything : nothing

    Region { id: nothing }
    Region { id: everything; item: catcher }

    MouseArea {
        id: catcher
        anchors.fill: parent
        enabled: stack.keyCard !== null
        onClicked: if (stack.keyCard) stack.keyCard.outsideClicked()
    }

    Column {
        id: column
        anchors { top: parent.top; topMargin: Theme.barHeight + 8; horizontalCenter: parent.horizontalCenter }
        spacing: 8
    }
}
