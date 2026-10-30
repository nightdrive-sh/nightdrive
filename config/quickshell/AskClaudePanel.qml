import QtQuick
import Quickshell

// Ask Claude's toast once it is written in (AskClaudeToast.qml, Dashboard #1895): Claude's robot head and the field
// (AskClaudeField), the conversation (AskClaudeThread, from AskClaudeSession) and its keys (KeyFooter). The field is on
// top, where the dictation indicator was, so the dictated text appears where you looked; fieldOnTop: false puts it at
// the bottom as in a chat (still to try out). While you dictate more, the indicator stands in the field's place.
// A long conversation scrolls inside it: the toast stays within maxHeight.
Item {
    id: p
    property int maxHeight: 600
    property bool fieldOnTop: true
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

    // Shift+Enter (a new line) isn't listed: it's what text fields do. Claude's card has its keys on its buttons.
    readonly property string keys: session.pendingCard ? ""
        : session.busy ? "Esc: close  ·  Ctrl+C: stop"
        : session.entries.length ? "Enter: send  ·  Esc: close  ·  Cmd+N: new chat"
        : "Enter: ask  ·  Esc: close"

    Item {
        id: fieldRow
        x: p.pad
        y: p.fieldOnTop ? p.pad : p.pad + p.threadH
        width: p.width - 2 * p.pad
        height: field.height

        // Says whose field this is, where the dictation's mic was; in line with the robot heads of Claude's answers
        Text {
            x: 10
            width: 20
            y: Math.round((44 - height) / 2)
            horizontalAlignment: Text.AlignHCenter
            text: Icons.g(p.session.thinkingGlyph)
            color: Theme.accent
            font { family: Icons.family; pixelSize: 18 }
            opacity: p.dictating ? 0 : 1
        }
        AskClaudeField {
            id: field
            x: 28
            width: parent.width - x
            baseSize: p.fontSize
            backspaceLeaves: false             // Backspace on an empty field mustn't close the toast
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
            x: -6                              // its mic where the robot head is
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
