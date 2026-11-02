import QtQuick
import "Words.js" as Words

// Ask Claude's field: one line in the look of the launcher's search field, but it wraps into more lines as the request
// grows, up to maxLines and then scrolls, and its font gets a little smaller the longer the text is, so a long request
// still fits in view. Enter sends it (sent), Shift+Enter starts a new line, ⌃C stops Claude, ⌘N starts a new
// conversation (newChat), Esc leaves (leaving), PgUp / PgDn are the conversation's (paged); the view decides what those
// do. ⌘Enter, ⌘⌥Enter and ⌘⌃Enter are Hyprland's keys and come over IPC, which reads `text` (AskClaudeSession.draft).
// It knows nothing of where it is shown (Ask Claude's toast, AskClaudePanel.qml, Dashboard #1895).
Item {
    id: f
    property int baseSize: 17                  // the view's own text size; the field's is a little bigger
    property int fontWeight: Font.Light
    property int minHeight: 44                 // one line's height, as the launcher's search field
    property string placeholder: "Ask Claude…"
    readonly property alias text: edit.text
    readonly property alias edit: edit    // for ⌘⌫ / ⌥⌫ (Words.deleteBack, from Launcher.qml's IPC)
    signal sent(string text)
    signal newChat()
    signal leaving(string text)
    signal refused()                            // Enter with nothing to send
    signal paged(int dir)                       // PgUp (-1) / PgDn (1): the conversation's, not the field's

    // --- Tunables ---
    readonly property int bigSize: baseSize + 2   // the search field's size, for a short request
    readonly property int smallSize: baseSize - 3 // the smallest, from smallFrom characters on
    readonly property int bigUntil: 60                     // characters that still get the search field's size
    readonly property int smallFrom: 400
    readonly property int lineWeight: 40                   // a line break counts as this many characters
    readonly property int maxLines: 8                      // lines in view before the field scrolls
    // Above and below the text: one line of the search field's font centred in its minHeight, as TextInput centres it,
    // so the text stays where it was when the search turns into this field
    readonly property real pad: Math.floor((minHeight - bigLine.height) / 2)
    FontMetrics { id: bigLine; font { family: Theme.font; pixelSize: f.bigSize; weight: f.fontWeight } }

    // By the length rather than the lines: lines depend on the size, and the size would then flicker at a line's end
    readonly property int amount: edit.text.length + (edit.text.split("\n").length - 1) * lineWeight
    property real size: (bigSize - (bigSize - smallSize)
                                           * Math.max(0, Math.min(1, (amount - bigUntil) / (smallFrom - bigUntil))))
    Behavior on size { NumberAnimation { duration: 120 } }
    FontMetrics { id: lineMetrics; font: edit.font }
    readonly property real lineH: lineMetrics.height

    implicitHeight: Math.max(minHeight, Math.min(edit.contentHeight, maxLines * lineH) + 2 * pad)

    // Opens with the search's text, the cursor at its end, ready to go on writing
    function begin(text) {
        edit.text = text
        edit.cursorPosition = edit.length
        edit.forceActiveFocus()
    }

    // No "Ask Claude ›" before it, unlike other levels' fields: the text gets the card's whole width, as in the search
    Text {      // as the search field shows nothing when empty, but here there's a field to explain
        visible: edit.text === ""
        anchors { left: view.left; top: view.top }
        text: f.placeholder
        color: Theme.dim
        opacity: 0.6
        font: edit.font
    }

    Flickable {
        id: view
        anchors { fill: parent; topMargin: f.pad; bottomMargin: f.pad; leftMargin: 14; rightMargin: 14 }
        contentWidth: width
        contentHeight: edit.contentHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // The cursor's line stays in view when the text is taller than the field
        function follow(r) {
            if (contentY > r.y) contentY = r.y
            else if (contentY + height < r.y + r.height) contentY = r.y + r.height - height
        }

        TextEdit {
            id: edit
            width: view.width
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            color: Theme.text
            selectionColor: Theme.sel
            selectByMouse: true
            font { family: Theme.font; pixelSize: Math.round(f.size); weight: f.fontWeight }
            onCursorRectangleChanged: view.follow(cursorRectangle)
            // Text changed by other means than a key here (⌘⌫ over IPC, a paste with the mouse) is typing too
            onTextChanged: if (AskClaudeSession.pendingCard) AskClaudeSession.card.disarm()
            Keys.onPressed: event => {
                const shift = event.modifiers & Qt.ShiftModifier
                // ⌘N arrives as Ctrl+N or as Meta+N, depending on what's between (keyd)
                const cmd = event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
                const card = AskClaudeSession.pendingCard ? AskClaudeSession.card : null
                // Claude's card in the conversation: Enter allows (not a held key, and only after a quiet second and a
                // moment, as the card's own rule), Esc denies; the rest still edits the text. Any other key, and an
                // Enter too early, is typing: it disarms the card, so an Enter meant to send the text never allows it
                const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                if (card && !(enter && !event.isAutoRepeat && card.keyArmed) && event.key !== Qt.Key_Escape) card.disarm()
                if (card && enter) {
                    if (!event.isAutoRepeat && card.keyArmed) card.decide("allow")
                    event.accepted = true
                } else if (card && event.key === Qt.Key_Escape) {
                    card.decide("deny"); event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (shift) insert(cursorPosition, "\n")
                    else if (text.trim() === "") f.refused()
                    else f.sent(text)
                    event.accepted = true
                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && selectedText === "" && AskClaudeSession.busy) {
                    AskClaudeSession.stop(); event.accepted = true   // ⌃C as in a terminal; with a selection it copies
                } else if (cmd && event.key === Qt.Key_N) {
                    f.newChat(); event.accepted = true
                } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                    f.paged(event.key === Qt.Key_PageUp ? -1 : 1); event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                    f.leaving(text); event.accepted = true
                } else if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                    // ⌥← / ⌥→ by word, as in the search field
                    const pos = Words.pos(text, cursorPosition, event.key === Qt.Key_Left ? -1 : 1)
                    if (shift) moveCursorSelection(pos, TextEdit.SelectCharacters)
                    else { deselect(); cursorPosition = pos }
                    event.accepted = true
                }
            }
        }
    }
}
