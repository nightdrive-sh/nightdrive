import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "Words.js" as Words

// Dictation's toast, which grows into Ask Claude's (Dashboard #1895): one card in ToastStack.
// - While Voxtype records it is the dictation indicator (DictationIndicator.qml), and it never takes a key: what you
//   say is typed into the window you're in.
// - ⌘⇧ + the dictation key (hypr/scripts/dictate) makes the dictation Claude's (dictating), "say and forget" (Dashboard
//   #3122): the small card listens with Claude's glyph and never takes a key, and the text (draft) is sent at once as a
//   new request, without Enter; the card then says Claude is working and, for a while, what it answered. Claude busy
//   with an earlier one: the toast opens with the text in its field instead, to send once it's done. With the toast
//   open (and its keys) the dictation is a reply: a listening wave stands in for the field (AskClaudeListening.qml,
//   #1997) and the text goes into it to check before Enter sends it.
// - Esc, or a click beside it, closes it without stopping Claude; what was written stays in the field for next time.
//   While Claude works, the card stays small (AskClaudeStatus.qml), and says for a while when it has answered; a click
//   on it, or ⌘⌥Space (hypr/scripts/ask-claude --toggle), opens it again.
//   qs ipc call askClaude dictating     a dictation to Claude has started
//   qs ipc call askClaude draft TEXT    its text: sent, or into the field (after what was there) when the toast is open
//   qs ipc call askClaude cancel        it gave no text
//   qs ipc call askClaude toggle        opens it with the conversation (a new one after AskClaudeSession.freshAfter),
//                                       or closes it: "ok"
Toast {
    id: toast
    property bool stepAside: false        // a password prompt or Claude's full card is up: they get the keys

    // --- Tunables ---
    // As the launcher's card, and as it does on a narrow screen (a phone's, a VM's window): edge px from each side
    // (#3274). Its content wraps to it (AskClaudeThread's text, AskClaudeMarkdown's code blocks, the footer's lines).
    readonly property int wideWidth: 660
    readonly property int edge: 12                 // the launcher's
    readonly property int askWidth: Math.min(wideWidth, (Screen.width || wideWidth + 2 * edge) - 2 * edge)
    readonly property real screenShare: 0.6        // the most of the screen's height it grows to before it scrolls
    readonly property int listenGrace: 3000        // ms the card waits for the text after Voxtype is done
    readonly property int answeredFor: 10000       // ms the closed card says Claude answered

    property bool asking: false           // Ask Claude's size, with its field and conversation
    // A dictation to Claude is on, before its text. listenOnly: it began with the toast closed, so its text is sent
    // as it comes, and nothing takes the keys meanwhile (what you type goes to your window)
    property bool listening: false
    property bool listenOnly: false
    property bool grown: false            // the card has its Ask Claude size
    property bool answeredShown: false    // an answer came while it was closed: the small card says so for a while
    readonly property bool working: !asking && (AskClaudeSession.busy || answeredShown)
    // The small card's content: the dictation's indicator while you speak, else Claude's state
    readonly property bool dictationCard: vt.shown

    shown: vt.shown || asking || working
    takesKeys: asking && !stepAside && !listenOnly
    sitsLow: grown                        // in the launcher's place whether it has the keys or not
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

    // It appears at its size at once, from the dictation too (#1996: it no longer grows out of the dictation's card)
    function open(text) {
        instant = true
        asking = true
        answeredShown = false
        AskClaudeSession.unseen = false
        panel.field.begin(text)
        grown = true
        Qt.callLater(() => toast.instant = false)   // the conversation's own growth still animates
    }
    // While Claude works the small card takes its place at once
    function close() {
        instant = true
        asking = false
        listening = false
        listenOnly = false
        grown = false
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

    // A dictation to Claude starts. Closed, the toast stays the small card (listenOnly: the dictation's own, with Claude's
    // glyph), as the text will be sent without a look at it (#3122); open, it listens on with the keys it has
    function listen() {
        listening = true
        listenOnly = !asking
    }
    // It gave no text: nothing was opened for it, so nothing to close
    function cancel() {
        listening = false
        listenOnly = false
    }
    // A dictation's text. Into the open toast's field after what was written there, to check before Enter; else sent
    // at once as a request of its own (#3122), and the small card shows its progress and answer. Its call lost
    // (listening never set) counts as closed too.
    function draft(text) {
        listening = false
        listenOnly = false
        if (asking) {
            const before = panel.field.text.trim()
            panel.field.begin(before !== "" ? before + " " + text : text)
            return
        }
        send(text)
    }
    // Say and forget: a new conversation that runs behind the small card. While an earlier request still runs nothing
    // can be sent, so the toast opens with the text in its field, with the error sound (as the launcher's request does).
    function send(text) {
        if (AskClaudeSession.busy) { open(text); panel.refuse(); return }
        AskClaudeSession.reset()
        AskClaudeSession.ask(text, true)
    }

    // Voxtype is done (or never started) but the text hasn't come (dictate gave up, or its cancel was lost): don't
    // listen forever
    Timer {
        interval: toast.listenGrace
        running: toast.listening && !vt.busy
        onTriggered: toast.cancel()
    }

    Item {
        id: small
        visible: !toast.grown
        width: toast.cardWidth
        height: 48
        DictationIndicator {
            id: indicator
            visible: toast.dictationCard
            dictation: vt
            toClaude: toast.listenOnly
            running: toast.shown && !toast.grown && visible
        }
        AskClaudeStatus {
            id: status
            visible: !toast.dictationCard
        }
    }
    AskClaudePanel {
        id: panel
        visible: toast.grown
        width: toast.askWidth
        maxHeight: Math.round((Screen.height || 900) * toast.screenShare)
        dictating: toast.asking && (vt.shown || toast.listening)
        listenOnly: toast.listenOnly
        dictation: vt
        onClose: toast.close()
    }

    IpcHandler {
        target: "askClaude"
        function dictating(): void { toast.listen() }
        function draft(text: string): void { toast.draft(text) }
        function cancel(): void { toast.cancel() }
        function toggle(): string { toast.toggle(); return "ok" }
    }
}
