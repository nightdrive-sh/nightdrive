import QtQuick

// The sessions bar's Ask Claude button (#3704), left of Inbox's: Ask Claude's bubble (AskClaudeGlyph). With the bar
// showing it is where Ask Claude's state is (#3428):
//   idle       the bubble, in the accent colour as the mailbox beside it
//   listening  a dictation to Claude (⌘⌥ + the dictation key): the button widens, the bubble moving aside for the
//              microphone's level (DictationMeter) and "Listening", as dictation's own card (DictationToast.qml)
//   working    the button widens to the left, the bubble moving aside for "Working", its dots hopping
//   answered   (an answer you haven't seen: AskClaudeSession.unseen) the bubble red, knocking with two small hops
//              now and then, as a session asking you does (SessionChip.qml)
// A click opens Ask Claude's conversation, or closes it, as ⌘⌥Space does; the conversation then floats above the bar at
// its right end, its arrow pointing at this button (ToastStack.floating). While it is open, a click here lands on
// ToastStack's click catcher, which closes it: the same toggle. Where it is goes to AskClaudeSession (barButtonX,
// barButtonScreen), for that arrow and for DictationToast to leave a dictation to Claude to it.
Rectangle {
    id: btn
    required property var bar             // SessionsBar: its screen and whether it shows

    // --- Tunables ---
    readonly property int pad: 9
    readonly property int iconW: 18
    readonly property int labelGap: 7
    readonly property int resizeMs: 260
    readonly property int hopEvery: 6000  // as SessionChip's asking hop
    readonly property int hopHeight: 3

    readonly property bool listening: AskClaudeSession.listening && AskClaudeSession.dictation !== null
    readonly property bool working: AskClaudeSession.busy && !listening
    readonly property bool answered: AskClaudeSession.unseen && !working && !listening
    readonly property bool wide: listening || working

    width: pad + iconW + (listening ? labelGap + meter.width : 0) + (wide ? labelGap + label.implicitWidth : 0) + pad
    Behavior on width { NumberAnimation { duration: btn.resizeMs; easing.type: Easing.OutCubic } }
    radius: 6
    // Active while its conversation is open, as a bar button is while its menu is (the workspace's highlight)
    color: AskClaudeSession.toastViewing ? Theme.sel : area.containsMouse ? Theme.hover : "transparent"
    clip: true

    AskClaudeGlyph {
        id: glyph
        anchors { left: parent.left; leftMargin: btn.pad; verticalCenter: parent.verticalCenter }
        size: btn.iconW
        color: btn.answered ? Theme.danger : Theme.accent  // as Inbox's mailbox beside it (dim read as grey, out of use)
        running: btn.working && btn.bar.visible
        transform: Translate { id: lift }
        // The knock: two quick hops, then a rest
        SequentialAnimation {
            running: btn.answered && btn.bar.visible
            loops: Animation.Infinite
            NumberAnimation { target: lift; property: "y"; to: -btn.hopHeight; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: lift; property: "y"; to: 0; duration: 140; easing.type: Easing.InQuad }
            NumberAnimation { target: lift; property: "y"; to: -btn.hopHeight; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: lift; property: "y"; to: 0; duration: 220; easing.type: Easing.OutBounce }
            PauseAnimation { duration: btn.hopEvery - 600 }
            onRunningChanged: if (!running) lift.y = 0
        }
    }
    // The microphone's level while it listens; only then, as its Dictation comes from Ask Claude's toast
    Loader {
        id: meter
        anchors { left: glyph.right; leftMargin: btn.labelGap; verticalCenter: parent.verticalCenter }
        active: btn.listening
        width: active ? implicitWidth : 0
        sourceComponent: DictationMeter {
            dictation: AskClaudeSession.dictation
            running: btn.bar.visible
            cols: 10
            barHeight: 14
        }
    }
    Text {
        id: label
        anchors { left: btn.listening ? meter.right : glyph.right; leftMargin: btn.labelGap; verticalCenter: parent.verticalCenter }
        // Listening as dictation's own card says it (DictationIndicator.qml); Working quieter
        text: btn.listening ? "LISTENING" : "Working"
        opacity: btn.wide ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: btn.resizeMs } }
        color: btn.listening ? Theme.primary : Theme.dim
        font { family: Theme.font; pixelSize: btn.listening ? 10 : 12; letterSpacing: btn.listening ? 0.6 : 0 }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (AskClaudeSession.toastViewing) AskClaudeSession.hideRequested()
            else AskClaudeSession.showRequested("", false)
        }
    }

    // The bubble's centre in screen coordinates (it sits right in the bar, which spans its screen): the arrow points
    // at the bubble, which stays put at the button's left as the button widens
    readonly property real centreX: bar.visible ? x + pad + iconW / 2 : -1
    Binding { target: AskClaudeSession; property: "barButtonX"; value: btn.centreX }
    Binding {
        target: AskClaudeSession; property: "barButtonScreen"
        value: btn.bar.visible && btn.bar.screen ? btn.bar.screen.name : ""
    }
}
