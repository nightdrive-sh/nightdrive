import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// The toasts' place: one surface at the top centre, just below the bar, with the shown cards (Toast.qml) stacked
// downwards in the order they're declared in shell.qml. A long-lived card (dictation, later Ask Claude) goes first, so
// a volume toast meanwhile appears below it instead of covering it.
// Toasts don't take input, so the surface lets clicks through and has no keyboard; a clickable card takes the clicks
// on itself (Ask Claude's closed one). A card that is written in (Ask Claude, Dashboard #1895) sets takesKeys: then the
// surface takes the keyboard as the launcher does, and the whole screen's clicks, so a click beside the card closes it
// (its outsideClicked) instead of leaving the keys with a card that no longer seems to be in use.
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
    // A card that takes the keys says when its first frame is on screen (Toast.drawn)
    property var drawPending: null
    onKeyCardChanged: drawPending = keyCard
    Connections {
        target: column.Window.window
        function onFrameSwapped() {
            const c = stack.drawPending
            if (c) { stack.drawPending = null; c.drawn() }
        }
    }
    // The card that puts the stack lower (Toast.sitsLow)
    readonly property var lowCard: {
        for (let i = 0; i < column.children.length; i++) {
            const c = column.children[i]
            if (c.shown && c.sitsLow) return c
        }
        return null
    }
    readonly property var clickCard: {
        for (let i = 0; i < column.children.length; i++) {
            const c = column.children[i]
            if (c.shown && c.clickable) return c
        }
        return null
    }

    // The whole screen, so the click catcher can cover it; nothing but the cards is drawn, and without a keyCard the
    // input region is the clickable card or nothing
    visible: anyShown
    // The screen it will show on, chosen while hidden (#2062): left to Hyprland, the surface learned its screen only
    // once mapped, so the first frame used the previous screen's height for Ask Claude's lowered (Screen.height) and
    // the card jumped down a frame later. While shown it stays put, so focus moving doesn't carry a card along.
    function followFocus() {
        if (anyShown) return
        const f = Hyprland.focusedMonitor
        const s = (f && Quickshell.screens.find(x => x.name === f.name)) || Quickshell.screens[0]
        if (s && screen !== s) screen = s
    }
    Component.onCompleted: followFocus()
    onAnyShownChanged: followFocus()
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() { stack.followFocus() }
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nightdrive-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: keyCard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: keyCard ? everything : clickCard ? oneCard : nothing

    Region { id: nothing }
    Region { id: everything; item: catcher }
    Region { id: oneCard; item: stack.clickCard }

    MouseArea {
        id: catcher
        anchors.fill: parent
        enabled: stack.keyCard !== null
        onClicked: if (stack.keyCard) stack.keyCard.outsideClicked()
    }

    Column {
        id: column
        anchors { top: parent.top; topMargin: topGap; horizontalCenter: parent.horizontalCenter }
        // A card with the keys (or sitsLow) sits lower (its lowered), there at once: no slide (#2062). Ask Claude's
        // lowered follows Screen.height, which a hidden stack learns only once it's mapped, after the card's instant
        // has ended, so a Behavior here slid the card down from the top on every open.
        property real topGap: Theme.barHeight + 8 + (stack.lowCard ? stack.lowCard.lowered : 0)
        spacing: 8
    }
}
