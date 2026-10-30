import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io

// Dictation's toast, which grows into Ask Claude's (Dashboard #1895): one card in ToastStack.
// - While Voxtype records it is the dictation indicator (DictationIndicator.qml), and it never takes a key: what you
//   say is typed into the window you're in.
// - ⌘⇧ + the dictation key (hypr/scripts/dictate) makes the dictation Claude's (dictating): the card stays through the
//   transcription, and when the text comes (draft), the indicator fades out, the same card grows wide and down, and Ask
//   Claude's field, conversation and keys (AskClaudePanel.qml) fade in, with the text to check before Enter sends it.
//   Now it has the keyboard, as the launcher does.
// - Esc, or a click beside it, closes it without stopping Claude; what was written stays in the field for next time.
//   qs ipc call askClaude dictating     a dictation to Claude has started
//   qs ipc call askClaude draft TEXT    its text: into the field (after what was there, when the toast is open)
//   qs ipc call askClaude cancel        it gave no text
Toast {
    id: toast
    property bool stepAside: false        // a password prompt or Claude's full card is up: they get the keys

    // --- Tunables ---
    readonly property int askWidth: 660            // as the launcher's card
    readonly property real screenShare: 0.6        // the most of the screen's height it grows to before it scrolls
    readonly property int listenGrace: 3000        // ms the card waits for the text after Voxtype is done

    property string mode: ""              // "" | listen (holds the card until the dictation's text) | ask
    readonly property bool asking: mode === "ask"
    property bool grown: false            // the card has its Ask Claude size (after the indicator faded out)

    shown: vt.shown || mode !== ""
    takesKeys: asking && !stepAside
    cardWidth: grown ? askWidth : indicator.implicitWidth
    cardHeight: grown ? panel.implicitHeight : indicator.implicitHeight
    onOutsideClicked: close()

    Binding { target: AskClaudeSession; property: "toastViewing"; value: toast.takesKeys }
    onTakesKeysChanged: if (takesKeys) panel.field.edit.forceActiveFocus()   // back from a card that had the keys

    Dictation { id: vt }

    function open(text, animate) {
        mode = "ask"
        AskClaudeSession.unseen = false
        panel.field.begin(text)
        if (animate) grow.restart()
        else { grow.stop(); indicator.opacity = 0; grown = true; panel.opacity = 1 }
    }
    function close() {
        grow.stop()
        mode = ""
        grown = false
        indicator.opacity = 1
        panel.opacity = 0
    }

    // A dictation's text: over an open toast it goes on after what was written there; else a new conversation starts
    // (unless one still runs), as the launcher's request from the search did
    function draft(text) {
        if (asking) {
            const before = panel.field.text.trim()
            panel.field.begin(before !== "" ? before + " " + text : text)
            return
        }
        if (!AskClaudeSession.busy) AskClaudeSession.reset()
        open(text, vt.shown || mode === "listen")
    }

    // The indicator fades out, the card takes its new size (Toast animates it), then Ask Claude's part fades in
    SequentialAnimation {
        id: grow
        NumberAnimation { target: indicator; property: "opacity"; to: 0; duration: 120 }
        ScriptAction { script: toast.grown = true }
        PauseAnimation { duration: 180 }
        NumberAnimation { target: panel; property: "opacity"; to: 1; duration: 150 }
    }

    // Voxtype is done but the text hasn't come (dictate gave up, or its cancel was lost): don't hold the card forever
    Timer {
        interval: toast.listenGrace
        running: toast.mode === "listen" && !vt.busy
        onTriggered: if (toast.mode === "listen") toast.mode = ""
    }

    DictationIndicator {
        id: indicator
        visible: opacity > 0
        dictation: vt
        running: toast.shown && !toast.grown
    }
    AskClaudePanel {
        id: panel
        visible: opacity > 0
        opacity: 0
        width: toast.askWidth
        maxHeight: Math.round((Screen.height || 900) * toast.screenShare)
        dictating: toast.asking && vt.shown
        dictation: vt
        onClose: toast.close()
    }

    IpcHandler {
        target: "askClaude"
        function dictating(): void { if (!toast.asking) toast.mode = "listen" }
        function draft(text: string): void { toast.draft(text) }
        function cancel(): void { if (toast.mode === "listen") toast.mode = "" }
    }
}
