import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// The island (#3428, #3704): Ask Claude's and dictation's small card, a low bar at the bottom centre of the screen.
// It sat at the top centre, over the windows' top lines, for as long as Claude worked or you dictated; down here it
// grows out of the sessions bar's top edge (just above it, in its colour, borderless, its top corners rounded), or out
// of the screen's bottom edge when there is no sessions bar on its screen.
//   🗨 Claude is working · Searching Deck…  ✕        (AskClaudeStatus.qml: a click opens the conversation)
//   🎙 ▂▅▃ LISTENING                                  (DictationIndicator.qml, while Voxtype records)
// The state is AskClaudeToast's (its smallShown, its dictation); a click on the island opens its conversation, which
// for now still opens in the launcher's place (#3704 grows it up out of the island next).
// Like the toasts it never takes the keyboard (what you dictate is typed into your window), and only the island
// itself takes clicks.
PanelWindow {
    id: isl
    required property var toast        // AskClaudeToast

    // --- Tunables ---
    readonly property int islandH: 40   // lower than the toast's 48: it sits on a bar, and the bar is 36
    readonly property int corner: 14    // its top corners, as a notch upside down

    readonly property bool shown: toast.smallShown
    // On the sessions bar's screen with the bar showing: just above it, else on the bottom edge
    readonly property bool overBar: Claude.barVisible && screen !== null && Claude.barScreen === screen.name

    visible: shown
    // The screen it shows on, chosen while hidden, as ToastStack's (#2062): while shown it stays put
    function followFocus() {
        if (shown) return
        const f = Hyprland.focusedMonitor
        const s = (f && Quickshell.screens.find(x => x.name === f.name)) || Quickshell.screens[0]
        if (s && screen !== s) screen = s
    }
    Component.onCompleted: followFocus()
    onShownChanged: followFocus()
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() { isl.followFocus() }
    }

    // Anchored to the bottom only: layer-shell centres it across the screen
    anchors.bottom: true
    margins.bottom: overBar ? Theme.barHeight : 0
    implicitWidth: card.width
    implicitHeight: islandH
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nightdrive-island"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: card
        width: isl.toast.dictationCard ? indicator.implicitWidth : status.implicitWidth
        height: isl.islandH
        // The sessions bar's (and top bar's) background, so the island reads as part of the bar it grows from, but
        // opaque: it lies over windows, whose text showed through it with the bars' opacity
        color: Qt.rgba(TopBar.windowBg.r, TopBar.windowBg.g, TopBar.windowBg.b, 1)
        topLeftRadius: isl.corner
        topRightRadius: isl.corner

        // A click opens the conversation; under the status's own ✕ and Undo, which come after it
        MouseArea {
            anchors.fill: parent
            enabled: !isl.toast.dictationCard
            cursorShape: Qt.PointingHandCursor
            onClicked: isl.toast.tap()
        }
        DictationIndicator {
            id: indicator
            visible: isl.toast.dictationCard
            height: parent.height
            dictation: isl.toast.dictation
            toClaude: isl.toast.listenOnly
            running: isl.shown && visible
        }
        AskClaudeStatus {
            id: status
            visible: !isl.toast.dictationCard
            height: parent.height
        }
        // The answered card waits while the pointer is on its Undo (AskClaudeToast's answeredTimer)
        Binding { target: isl.toast; property: "statusHolding"; value: status.holding }
    }
}
