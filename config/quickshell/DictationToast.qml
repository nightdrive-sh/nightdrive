import QtQuick

// Dictation's card at the top centre (ToastStack), while Voxtype records or transcribes (DictationIndicator.qml), as it
// was before #3428: what you say is typed into your window. A dictation to Ask Claude (⌘⌥, AskClaudeToast.listenOnly)
// is shown by the sessions bar's speech bubble instead while that bar shows (SessionsAsk.qml: Listening); without the
// bar it is this card with Claude's glyph. Never while Ask Claude's toast is open: its field has a wave of its own.
// It never takes a key.
Toast {
    id: dt
    required property var ask                 // AskClaudeToast: its dictation and whether it listens for Claude

    readonly property bool toBar: ask.listenOnly && AskClaudeSession.barButtonX >= 0
    shown: ask.dictation.shown && !ask.asking && !toBar
    cardWidth: indicator.implicitWidth
    cardHeight: indicator.implicitHeight

    DictationIndicator {
        id: indicator
        dictation: dt.ask.dictation
        toClaude: dt.ask.listenOnly
        running: dt.shown
    }
}
