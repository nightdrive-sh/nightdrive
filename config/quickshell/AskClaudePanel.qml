import QtQuick
import Quickshell

// Ask Claude's toast once it is written in (AskClaudeToast.qml, Dashboard #1895): the field (AskClaudeField), the conversation (AskClaudeThread, from AskClaudeSession) and its keys (KeyFooter). As in a chat,
// the field is under the conversation, so the newest message is always just above it, where you wrote (the user's
// choice, #1895); a new conversation is the field alone, so dictated text still appears where the indicator was.
// fieldOnTop puts it above instead. While you dictate more, the indicator stands in the field's place.
// A long conversation scrolls inside it: the toast stays within maxHeight.
Item {
    id: p
    property int maxHeight: 600
    property bool fieldOnTop: false
    property bool dictating: false
    property var dictation: null          // Dictation, for the indicator
    readonly property alias field: field
    signal close()

    function refuse() { Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "event", "error"]) }

    // --- Tunables ---
    readonly property int fontSize: 17      // as the launcher's
    readonly property int pad: 12           // the card's edge to its content
    readonly property int gap: 8            // between the field, the conversation and the footer

    readonly property var session: AskClaudeSession
    readonly property bool hasThread: session.entries.length > 0 || session.busy
    readonly property real fieldH: field.height
    readonly property real threadH: hasThread ? thread.height + gap : 0
    readonly property real footerH: footer.visible ? footer.height + gap : 0
    implicitHeight: 2 * pad + fieldH + threadH + footerH

    // Shift+Enter (a new line) and Esc (close) aren't listed: what text fields and toasts do. Claude's card has its keys on
    // its buttons.
    readonly property string keys: session.pendingCard ? ""
        : session.busy ? "Ctrl+C: stop"
        : session.entries.length ? "Enter: send  ·  Cmd+N: new chat"
        : "Enter: ask"

    Item {
        id: fieldRow
        x: p.pad
        y: p.fieldOnTop ? p.pad : p.pad + p.threadH
        width: p.width - 2 * p.pad
        height: field.height

        AskClaudeField {
            id: field
            width: parent.width
            baseSize: p.fontSize
            placeholder: p.session.entries.length ? "Write back…" : "Ask Claude…"
            opacity: p.dictating ? 0 : 1
            // One still running: the text waits in the field
            onSent: text => { if (p.session.ask(text)) field.begin(""); else p.refuse() }
            onNewChat: { p.session.reset(); field.begin("") }
            onLeaving: p.close()
            onRefused: p.refuse()
            onPaged: dir => thread.page(dir)
        }
        DictationIndicator {
            visible: p.dictating && p.dictation !== null
            dictation: p.dictation
            running: visible
            anchors.verticalCenter: field.verticalCenter
        }
    }

    AskClaudeThread {
        id: thread
        visible: p.hasThread
        x: p.pad
        y: p.fieldOnTop ? p.pad + p.fieldH + p.gap : p.pad
        width: p.width - 2 * p.pad
        maxHeight: Math.max(120, p.maxHeight - 2 * p.pad - p.fieldH - p.gap - p.footerH)
        fontSize: p.fontSize
    }

    KeyFooter {
        id: footer
        anchors { right: parent.right; rightMargin: p.pad; bottom: parent.bottom; bottomMargin: p.pad }
        maxWidth: p.width - 2 * p.pad
        text: p.keys
    }
}
