import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "kit/Words.js" as Words

// Dictation's toast, which grows into Ask Claude's (Dashboard #1895): one card in ToastStack.
// - While Voxtype records it is the dictation indicator (DictationIndicator.qml), and it never takes a key: what you
//   say is typed into the window you're in.
// - ⌘⌥ + the dictation key (hypr/scripts/dictate) makes the dictation Claude's (dictating), "say and forget" (Dashboard
//   #3122): the small card listens with Claude's glyph and never takes a key, and the text (draft) is sent at once as a
//   new request, without Enter; the card then says Claude is working and, for a while, what it answered. Claude busy
//   with an earlier one: the toast opens with the text in its field instead, to send once it's done. With the toast
//   open (and its keys) the dictation is a reply: a listening wave stands in for the field (AskClaudeListening.qml,
//   #1997) and the text goes into it to check before Enter sends it.
// - Esc, or a click beside it, closes it without stopping Claude; what was written stays in the field for next time.
//   While Claude works the speech bubble says so, and that it has answered; a click on it, or ⌘⌥Space
//   (hypr/scripts/ask-claude --toggle), opens it again.
// - This toast is only the open conversation (#3428). Claude's state while it's closed is the speech bubble's, the
//   sessions bar's (SessionsAsk.qml) or else the top bar's; the dictation's card is DictationToast.qml, at the top
//   centre, with this toast's dictation (or the bubble, listening, for a dictation to Claude with the sessions bar).
// - A dictated request that ends in an error, or that Claude marked unsure (AskClaudeSession.look, #3155), opens it large
//   with the keys instead: what was heard and Claude's question are in the conversation, to answer by writing or by
//   dictating into the field. Not while you dictate into a window: it waits until that's done.
//   qs ipc call askClaude dictating     a dictation to Claude has started
//   qs ipc call askClaude draft TEXT    its text: sent, or into the field (after what was there) when the toast is open
//   qs ipc call askClaude cancel        it gave no text
//   qs ipc call askClaude toggle        opens it with the conversation (a new one after AskClaudeSession.freshAfter),
//                                       or closes it: "ok"
//   qs ipc call askClaude open          opens it, as the notification of a turn that ended does (ask-claude.d/notify.sh)
//   qs ipc call askClaude shown         "open" or "closed": whether that notification is needed
Toast {
    id: toast
    property bool stepAside: false        // a password prompt or Claude's full card is up: they get the keys

    // --- Tunables ---
    // As wide as the launcher's card, and as it does on a narrow screen (a phone's, a VM's window): edge px from each side
    // (#3274). Its content wraps to it (AskClaudeThread's text, AskClaudeMarkdown's code blocks, the footer's lines).
    readonly property int wideWidth: 660
    readonly property int edge: 12                 // the launcher's
    readonly property int askWidth: Math.min(wideWidth, (Screen.width || wideWidth + 2 * edge) - 2 * edge)
    readonly property real screenShare: 0.6        // the most of the screen's height it grows to before it scrolls,
    readonly property int extraHeight: 100         // and this much more (#3704), within the bars
    readonly property int listenGrace: 3000        // ms the card waits for the text after Voxtype is done

    property bool asking: false           // Ask Claude's size, with its field and conversation
    // A dictation to Claude is on, before its text. listenOnly: it began with the toast closed, so its text is sent
    // as it comes, and nothing takes the keys meanwhile (what you type goes to your window)
    property bool listening: false
    property bool listenOnly: false
    property bool grown: false            // the card has its Ask Claude size
    // A dictated request's answer needs a look (AskClaudeSession.look): the toast opens large as soon as no dictation
    // is typing into a window, which would otherwise type into its field
    property bool lookPending: false
    readonly property bool lookNow: lookPending && !asking && !vt.shown && !listening && AskClaudeSession.look !== ""
    // Later, not in the handler: opening changes what lookNow is bound to (a binding loop)
    onLookNowChanged: if (lookNow) Qt.callLater(() => { if (toast.lookNow) toast.open(panel.field.text) })

    property alias dictation: vt
    // The sessions bar's bubble listens with it (SessionsAsk.qml)
    Binding { target: AskClaudeSession; property: "listening"; value: toast.listenOnly && vt.shown }
    Binding { target: AskClaudeSession; property: "dictation"; value: vt }
    shown: asking
    takesKeys: asking && !stepAside && !listenOnly
    // It sits in ToastStack's bottomCards (#3704): above the sessions bar's bubble, or at the bottom centre
    cardWidth: askWidth
    cardHeight: grown ? panel.implicitHeight : 48
    // Its top corners rounded and its foot on the bar (or the screen's edge); no keys border (the user's choice, #3704):
    // the field's caret says where the keys are.
    // Glass, as the notifications' cards (the user's pick of three, #3704): translucent, what's behind blurred
    // (hypr/rules.lua), and a hairline round it. Flat black read as a hole in the screen rather than a card over it.
    readonly property real glassOpacity: 0.90
    // The launcher's (and the terminals') shade, tinted towards the theme, at the glass's opacity
    color: Qt.rgba(Theme.launcherBg.r, Theme.launcherBg.g, Theme.launcherBg.b, glassOpacity)
    border { width: 2; color: Theme.primary }   // the launcher's edge (#3428)
    radius: 4   // as the windows' (Hyprland's rounding, hypr/appearance.lua)
    // Floating above the sessions bar's button (ToastStack.floating, #3704) it is a card of its own, rounded all round;
    // else its foot stands on the bar or the screen's edge
    property bool floating: false
    bottomLeftRadius: floating ? radius : 0
    bottomRightRadius: floating ? radius : 0
    onOutsideClicked: close()
    // Opened with a key (⌘⌥Space) or from the launcher, its conversation lays itself out just after it shows: that first
    // growth isn't animated, as the card is meant to appear at its size (#3704). Later growth (an answer coming) is.
    Timer { id: settle; interval: 300; onTriggered: toast.instant = false }

    Binding { target: AskClaudeSession; property: "toastViewing"; value: toast.takesKeys }
    onTakesKeysChanged: if (takesKeys) panel.field.edit.forceActiveFocus()   // back from a card that had the keys
    Binding { target: AskClaudeSession; property: "draft"; value: panel.field.text }
    Connections {
        target: AskClaudeSession
        function onAnswered() {
            if (toast.asking) return
            if (AskClaudeSession.look !== "") toast.lookPending = true
        }
        function onShowRequested(text, send) { toast.request(text, send) }
        function onHideRequested() { toast.close() }
        function onDeleteBackRequested(word) { if (toast.takesKeys) Words.deleteBack(panel.field.edit, word) }
    }

    Dictation { id: vt }

    // It appears at its size at once, from the dictation too (#1996: it no longer grows out of the dictation's card)
    function open(text) {
        instant = true
        asking = true
        lookPending = false                 // opened anyway: it needn't open again once closed
        AskClaudeSession.unseen = false
        panel.field.begin(text)
        grown = true
        settle.restart()                    // the conversation's own growth animates once it has laid itself out
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
        if (s.stale()) { s.reset(); panel.field.begin("") }
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
        lookPending = false
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

    AskClaudePanel {
        id: panel
        visible: toast.grown
        background: toast.color
        // By its foot: as the card grows upwards out of the island, the field and the newest lines show first
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: toast.askWidth
        maxHeight: Math.min(Math.round((Screen.height || 900) * toast.screenShare) + toast.extraHeight,
                            (Screen.height || 900) - 3 * Theme.barHeight)
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
        function open(): string { if (!toast.asking) toast.reopen(); return "ok" }
        function shown(): string { return toast.asking ? "open" : "closed" }
        // For the top bar's bubble (topbar/scripts/status askclaude): "bar" while the sessions bar's button has it
        // (SessionsAsk.qml), else open, busy, unseen (an answer not looked at) or idle
        function state(): string {
            const s = AskClaudeSession
            return s.barButtonX >= 0 ? "bar" : toast.asking ? "open" : s.busy ? "busy" : s.unseen ? "unseen" : "idle"
        }
        // The small card's Undo (#3157), for a key or a test: "ok", or "nothing" when the last turn left nothing to undo
        function undo(): string {
            if (!AskClaudeSession.undoable) return "nothing"
            AskClaudeSession.undoTurn()
            return "ok"
        }
    }
}
