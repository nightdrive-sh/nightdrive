import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Shapes
import QtQuick.Effects

// The toasts' place: one surface at the top centre, just below the bar, with the shown cards (Toast.qml) stacked
// downwards in the order they're declared in shell.qml. Cards in bottomCards sit at the bottom centre instead and grow
// upwards: Ask Claude's conversation (#3704), floating above the sessions bar's speech bubble when the bar shows on
// this screen, else on the screen's bottom edge.
// Toasts don't take input, so the surface lets clicks through and has no keyboard; a clickable card takes the clicks
// on itself (clickable). A card that is written in (Ask Claude, Dashboard #1895) sets takesKeys: then the
// surface takes the keyboard as the launcher does, and the whole screen's clicks, so a click beside the card closes it
// (its outsideClicked) instead of leaving the keys with a card that no longer seems to be in use.
PanelWindow {
    id: stack
    default property alias cards: column.data
    property alias bottomCards: bottom.data
    // Both places' cards, the bottom's first: they are the long-lived ones
    readonly property var all: Array.from(bottom.children).concat(Array.from(column.children))
    readonly property bool anyShown: all.some(c => c.shown)
    readonly property var keyCard: all.find(c => c.shown && c.takesKeys) || null
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
    readonly property var lowCard: Array.from(column.children).find(c => c.shown && c.sitsLow) || null
    readonly property var clickCard: all.find(c => c.shown && c.clickable) || null
    // The sessions bar shows on this screen: the bottom cards sit on it
    readonly property bool overBar: Claude.barVisible && screen !== null && Claude.barScreen === screen.name

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
    // The bottom cards float above the sessions bar's Ask Claude button (SessionsAsk.qml), at the bar's right end,
    // with an arrow at the button, while that bar shows on this screen (#3704); else at the bottom centre
    readonly property real buttonX: AskClaudeSession.barButtonX
    readonly property bool floating: overBar && buttonX >= 0 && AskClaudeSession.barButtonScreen === screen.name
    // As Hyprland's gaps_out (hypr/appearance.lua), so the card's edges line up with the windows' behind it
    readonly property int floatGap: 10     // between the bar and the card, where the arrow is
    readonly property int floatEdge: 10    // the card from the screen's right edge
    readonly property int arrowW: 18
    readonly property int arrowH: 9
    readonly property var bottomCard: Array.from(bottom.children).find(c => c.shown) || null

    // A very soft, faint shadow under the bottom card (#3428), lifting it off the windows
    RectangularShadow {
        visible: stack.bottomCard !== null
        x: bottom.x; y: bottom.y; width: bottom.width; height: bottom.height
        radius: stack.bottomCard ? stack.bottomCard.radius : 0
        blur: 40
        offset.y: 6
        color: Qt.rgba(0, 0, 0, 0.5)
    }
    // By its bottom (y), so a card that grows grows upwards; as wide as its widest card, which centres itself in it
    Item {
        id: bottom
        width: Array.from(children).reduce((w, c) => Math.max(w, c.width), 0)
        height: childrenRect.height
        x: stack.floating ? Math.max(stack.floatEdge, parent.width - width - stack.floatEdge) : (parent.width - width) / 2
        y: parent.height - height - (stack.overBar ? Theme.barHeight + (stack.floating ? stack.floatGap : 0) : 0)
    }
    // The arrow under a floating card, at the button: two filled triangles, no strokes, so there are no line ends to
    // meet the card's edge badly. The outer one in the border's colour starts on the card's bottom border (as thick as
    // it) and runs on from it; the inner one, the card's shade made opaque, covers that border between the slanted
    // sides, so the edge opens where the arrow comes out
    readonly property real cardBorder: bottomCard ? bottomCard.border.width : 0
    Shape {
        id: arrow
        visible: stack.floating && stack.bottomCard !== null
        readonly property real h: stack.arrowH + stack.cardBorder
        readonly property real half: stack.arrowW / 2
        // How much higher the inner tip is: the border's thickness across the slanted side
        readonly property real inset: stack.cardBorder * Math.sqrt(1 + (half / h) * (half / h))
        readonly property real innerHalf: half * (h - inset) / h
        x: Math.max(bottom.x + 16, Math.min(bottom.x + bottom.width - 16 - width, stack.buttonX - width / 2))
        y: bottom.y + bottom.height - stack.cardBorder
        width: stack.arrowW
        height: h
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillColor: stack.bottomCard ? stack.bottomCard.border.color : "transparent"
            startX: 0; startY: 0
            PathLine { x: stack.arrowW; y: 0 }
            PathLine { x: arrow.half; y: arrow.h }
            PathLine { x: 0; y: 0 }
        }
        ShapePath {
            strokeWidth: -1
            fillColor: stack.bottomCard ? Qt.rgba(stack.bottomCard.color.r, stack.bottomCard.color.g, stack.bottomCard.color.b, 1)
                                        : "transparent"
            startX: arrow.half - arrow.innerHalf; startY: 0
            PathLine { x: arrow.half + arrow.innerHalf; y: 0 }
            PathLine { x: arrow.half; y: arrow.h - arrow.inset }
            PathLine { x: arrow.half - arrow.innerHalf; y: 0 }
        }
    }
}
