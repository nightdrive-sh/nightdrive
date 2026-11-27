import QtQuick
import Quickshell

// Ask Claude's toast once it is written in (AskClaudeToast.qml, Dashboard #1895): the field (AskClaudeField), the conversation (AskClaudeThread, from AskClaudeSession) and its keys (KeyFooter). As in a chat,
// the field is under the conversation, so the newest message is always just above it, where you wrote (the user's
// choice, #1895); a new conversation is the field alone, so dictated text still appears where the wave was.
// fieldOnTop puts it above instead. While you dictate, a wave across the field (AskClaudeListening) stands in its place.
// A long conversation scrolls inside it: the toast stays within maxHeight.
Item {
    id: p
    property int maxHeight: 600
    property bool fieldOnTop: false
    property bool dictating: false
    property bool listenOnly: false       // opened to listen (#1996): no keys yet, so no footer either
    property var dictation: null          // Dictation, for the listening wave
    readonly property alias field: field
    signal close()

    function refuse() { Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "event", "error"]) }

    // --- Tunables ---
    readonly property int pad: 10           // the card's edge to its content: tight, it sits at the bottom (#3704)
    readonly property int gap: 6            // between the field, the conversation and the footer
    readonly property int fieldFontSize: 12 // the field's base (its text is 2 px bigger: AskClaudeField.bigSize)
    readonly property int fieldPad: 11      // above and below the field's text
    // The field's one line: its big text's height and fieldPad on each side (the launcher's is 44)
    readonly property int lineH: Math.ceil(fieldLine.height) + 2 * fieldPad
    FontMetrics { id: fieldLine; font { family: Theme.font; pixelSize: p.fieldFontSize + 2 } }
    readonly property int threadFontSize: 15   // the conversation's: bigger than the field's, it's what you read
    readonly property int fieldAbove: 10    // more room between the conversation and the field
    readonly property int tileInset: 6      // the Send button from the field's edges
    readonly property color fieldColor: Theme.sel   // your requests' bubbles: the theme's highlight, clear on the glass
    readonly property int fieldSide: 6      // and on its left and right, inside the card's pad (the keys keep in line)
    property color background: "transparent"   // the card's, for the conversation's fade

    readonly property var session: AskClaudeSession
    // A card from another Claude (a terminal's) can come with no conversation here: it is shown all the same, as Enter in
    // the field answers it (Dashboard #1921)
    readonly property bool hasThread: session.entries.length > 0 || session.busy || session.pendingCard
    readonly property real fieldH: field.height
    readonly property real threadH: hasThread ? thread.height + gap + fieldAbove : 0
    // The other keys under the field, which keeps the whole width (#3704)
    readonly property real footerH: footer.visible ? footer.height + gap : 0
    readonly property int topPad: pad + fieldSide   // above the first thing: as the field's sides, so they line up
    implicitHeight: topPad + pad + fieldH + threadH + footerH

    // Shift+Enter (a new line) and Esc (close) aren't listed: what text fields and toasts do. Claude's card has its keys on
    // its buttons. ⌘Enter is Hyprland's key, not the field's (so it never sends or adds a line): over the toast it comes
    // over IPC (askClaude key in Launcher.qml) and goes on with the conversation in a terminal (AskClaudeLevels.terminal),
    // as ⌘Enter on the launcher's Ask Claude row does (#1980); without one yet, what was written is a new session's prompt.
    readonly property string terminalKey: "Cmd+Enter: open in terminal"
    // Earlier conversations, in the launcher's Ask Claude › History (#3428): first in the row, at its right end
    readonly property string historyKey: "Cmd+H: history"
    // A selection in the conversation (#1904): ⌘C copies it, and the footer says so for a moment once it has. Last in the
    // footer, so the main key stays at its right edge
    property bool copied: false
    Timer { id: copiedTimer; interval: 1500; onTriggered: p.copied = false }
    readonly property string copyKey: copied ? "Cmd+C: copied" : thread.selectedText !== "" ? "Cmd+C: copy" : ""
    // Enter's action is a small tile inside the field, at its right end (#3704); the other keys stay beside it, quiet
    readonly property string sendKey: listenOnly || session.pendingCard || session.busy ? "" : "Enter: send"
    readonly property string keys: listenOnly ? "" : [historyKey, session.pendingCard ? ""
        : session.busy ? "Ctrl+C: stop  ·  " + terminalKey
        : session.entries.length ? terminalKey + "  ·  Cmd+N: new chat"
        : terminalKey, copyKey].filter(k => k !== "").join("  ·  ")

    Item {
        id: fieldRow
        x: p.pad + p.fieldSide
        y: p.fieldOnTop ? p.topPad : p.topPad + p.threadH
        width: p.width - 2 * (p.pad + p.fieldSide)
        height: field.height

        // The field's room, Send in it at the right; no ground of its own: a hairline sets it off from the conversation
        Item {
            id: fieldBox
            width: parent.width
            height: field.height
        }
        // On the field's last line, as far from the field's right edge as from its top and bottom
        AskClaudeSendButton {
            id: sendTile
            visible: p.sendKey !== ""
            anchors { right: fieldBox.right; rightMargin: p.tileInset }
            y: fieldBox.height - field.minHeight + p.tileInset
            height: field.minHeight - 2 * p.tileInset
            onClicked: { if (p.session.ask(field.text)) field.begin(""); else p.refuse() }
        }
        AskClaudeField {
            id: field
            width: fieldBox.width - (sendTile.visible ? sendTile.width + p.tileInset : 0)
            baseSize: p.fieldFontSize
            minHeight: p.lineH
            // Claude asks about a dictation (#3155): write or dictate the answer
            placeholder: p.session.look !== "" ? "Answer, or dictate…" : p.session.entries.length ? "Send message…" : "Ask Claude…"
            opacity: p.dictating ? 0 : 1
            // One still running: the text waits in the field
            onSent: text => { if (p.session.ask(text)) field.begin(""); else p.refuse() }
            onNewChat: { p.session.reset(); field.begin("") }
            onHistory: p.session.historyRequested()
            onLeaving: p.close()
            onRefused: p.refuse()
            onPaged: dir => thread.page(dir)
            copyElsewhere: () => { if (!thread.copySelection()) return false; p.copied = true; copiedTimer.restart(); return true }
        }
        AskClaudeListening {
            visible: p.dictating && p.dictation !== null
            width: field.width
            dictation: p.dictation
            running: visible
            anchors.verticalCenter: field.verticalCenter
        }
    }

    AskClaudeThread {
        id: thread
        visible: p.hasThread
        x: p.pad
        y: p.fieldOnTop ? p.topPad + p.fieldH + p.gap : p.topPad
        width: p.width - 2 * x
        maxHeight: Math.max(120, p.maxHeight - p.topPad - p.pad - p.fieldH - p.gap - p.fieldAbove - p.footerH)
        fontSize: p.threadFontSize
        fadeColor: p.background
        youColor: p.fieldColor
        youInset: p.fieldSide   // the bubbles end where the line and the field do
    }

    // The line between the conversation and the field (#3704), as wide as the field: clear of the card's edges
    Rectangle {
        visible: p.hasThread && !p.fieldOnTop
        x: fieldRow.x
        width: fieldRow.width
        height: 1
        y: fieldRow.y - Math.round((p.fieldAbove + p.gap) / 2)
        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
    }
    KeyFooter {
        id: footer
        visible: text !== ""
        quiet: true
        opacity: 0.7     // further back than Send: they're seldom what you want
        capTint: 0.12    // the caps a little lighter than Kit.Key's 0.08, which the opacity darkens
        anchors { right: parent.right; rightMargin: p.pad + p.fieldSide }
        y: p.height - p.pad - height
        maxWidth: p.width - 2 * p.pad
        text: p.keys
    }
}
