import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "Words.js" as Words

// Dictation's toast, which grows into Ask Claude's (Dashboard #1895): one card in ToastStack.
// - While Voxtype records it is the dictation indicator (DictationIndicator.qml), and it never takes a key: what you
//   say is typed into the window you're in.
// - ⌘⇧ + the dictation key (hypr/scripts/dictate) makes the dictation Claude's (dictating): the card stays through the
//   transcription, and when the text comes (draft), the indicator fades out, the same card grows wide and down to the
//   launcher's place, and Ask Claude's field, conversation and keys (AskClaudePanel.qml) fade in, with the text to check
//   before Enter sends it.
//   Now it has the keyboard, as the launcher does.
// - Esc, or a click beside it, closes it without stopping Claude; what was written stays in the field for next time.
//   While Claude works, the card stays small (AskClaudeStatus.qml), and says for a while when it has answered; a click
//   on it, or ⌘⌥Space (hypr/scripts/ask-claude --toggle), opens it again.
//   qs ipc call askClaude dictating     a dictation to Claude has started
//   qs ipc call askClaude draft TEXT    its text: into the field (after what was there, when the toast is open)
//   qs ipc call askClaude cancel        it gave no text
//   qs ipc call askClaude toggle        opens it with the conversation (a new one after AskClaudeSession.freshAfter),
//                                       or closes it: "ok"
Toast {
    id: toast
    property bool stepAside: false        // a password prompt or Claude's full card is up: they get the keys

    // --- Tunables ---
    readonly property int askWidth: 660            // as the launcher's card
    readonly property real screenShare: 0.6        // the most of the screen's height it grows to before it scrolls
    readonly property int listenGrace: 3000        // ms the card waits for the text after Voxtype is done
    readonly property int answeredFor: 10000       // ms the closed card says Claude answered

    property string mode: ""              // "" | listen (holds the card until the dictation's text) | ask
    readonly property bool asking: mode === "ask"
    property bool grown: false            // the card has its Ask Claude size (after the small content faded out)
    property bool answeredShown: false    // an answer came while it was closed: the small card says so for a while
    readonly property bool working: !asking && (AskClaudeSession.busy || answeredShown)
    // The small card's content: the dictation's indicator while you speak (and while it fades out as the card grows out
    // of it), else Claude's state
    property bool fromDictation: false
    readonly property bool dictationCard: vt.shown || mode === "listen" || (fromDictation && !grown)

    shown: vt.shown || mode !== "" || working
    takesKeys: asking && !stepAside
    clickable: working && !dictationCard
    cardWidth: grown ? askWidth : dictationCard ? indicator.implicitWidth : status.implicitWidth
    cardHeight: grown ? panel.implicitHeight : 48
    // In Ask Claude's size it looks like the launcher and sits where the launcher's card does (Theme.cardTop), as it
    // takes over from it (#1895): its background, corners and border. The small cards stay black and borderless (#1910),
    // so the colour changes as the dictation's card grows.
    border { color: Theme.primary; width: grown ? 2 : 0 }
    color: grown ? Theme.launcherBg : Theme.bg
    Behavior on color { enabled: !toast.instant; ColorAnimation { duration: 180 } }
    radius: grown ? 12 : 10
    lowered: Math.max(0, Math.round((Screen.height || 900) * Theme.cardTop) - Theme.barHeight - 8)
    onOutsideClicked: close()
    onTapped: open(panel.field.text)

    Binding { target: AskClaudeSession; property: "toastViewing"; value: toast.takesKeys }
    onTakesKeysChanged: if (takesKeys) panel.field.edit.forceActiveFocus()   // back from a card that had the keys
    Binding { target: AskClaudeSession; property: "draft"; value: panel.field.text }
    Connections {
        target: AskClaudeSession
        function onAnswered() { if (!toast.asking) { toast.answeredShown = true; answeredTimer.restart() } }
        function onShowRequested(text, send) { toast.request(text, send) }
        function onHideRequested() { toast.close() }
        function onDeleteBackRequested(word) { if (toast.takesKeys) Words.deleteBack(panel.field.edit, word) }
    }
    Timer { id: answeredTimer; interval: toast.answeredFor; onTriggered: toast.answeredShown = false }

    Dictation { id: vt }

    // Out of the dictation's card it grows (the user's choice, #1895); from anywhere else (⌘⌥Space, the launcher, the
    // small card) it appears at its size at once
    function open(text) {
        const animate = dictationCard
        fromDictation = animate
        instant = !animate
        mode = "ask"
        answeredShown = false
        AskClaudeSession.unseen = false
        panel.field.begin(text)
        if (animate) grow.restart()
        else { grow.stop(); small.opacity = 0; grown = true; panel.opacity = 1 }
        Qt.callLater(() => toast.instant = false)   // the conversation's own growth still animates
    }
    // While Claude works the small card takes its place at once
    function close() {
        grow.stop()
        instant = true
        fromDictation = false
        mode = ""
        grown = false
        small.opacity = 1
        panel.opacity = 0
        Qt.callLater(() => toast.instant = false)
    }
    // Back to the conversation, or a new one when it's been quiet for a while (AskClaudeSession.freshAfter)
    function reopen() {
        const s = AskClaudeSession
        if (!s.busy && s.sessionId !== "" && Date.now() - s.lastAt > s.freshAfter) { s.reset(); panel.field.begin("") }
        open(panel.field.text)
    }
    function toggle() { if (asking) close(); else reopen() }
    // From the launcher (AskClaudeLevels.qml): a request typed there starts a new conversation, as a search does; while
    // one still runs it waits in the field. Without one to send, the toast just opens.
    function request(text, send) {
        if (!send) { if (!asking) reopen(); return }
        if (AskClaudeSession.busy) { open(text); panel.refuse(); return }
        AskClaudeSession.reset()
        open("")
        AskClaudeSession.ask(text)
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
        open(text)
    }

    // The small content fades out, the card takes its new size (Toast animates it), then Ask Claude's part fades in
    SequentialAnimation {
        id: grow
        NumberAnimation { target: small; property: "opacity"; to: 0; duration: 120 }
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

    Item {
        id: small
        visible: opacity > 0 && !toast.grown
        width: toast.cardWidth
        height: 48
        DictationIndicator {
            id: indicator
            visible: toast.dictationCard
            dictation: vt
            running: toast.shown && !toast.grown && visible
        }
        AskClaudeStatus {
            id: status
            visible: !toast.dictationCard
        }
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
        function toggle(): string { toast.toggle(); return "ok" }
    }
}
