import QtQuick

// Dictation's indicator (F5, docs/dictation.md) while Voxtype records or transcribes:
//   mic icon (Claude's when it goes to Ask Claude) | equalizer (DictationMeter) | LISTENING / PLEASE WAIT / TRANSCRIBING
// When Nightdrive's iOS app listens instead (the lid closed, #3173), it says so, so you know which microphone hears you:
//   tablet icon | IPAD | LISTENING … (no equalizer: the app sends no level)
// The whole of the toast during dictation (AskClaudeToast.qml); Ask Claude's field has a wave of its own while you
// dictate to it (AskClaudeListening.qml). Its state comes from Dictation.qml.
Item {
    id: ind
    required property Dictation dictation
    property bool running: false     // the meter animates only while it's seen
    property bool toClaude: false    // the dictation goes to Ask Claude (⌘⇧, #3122): Claude's glyph for the mic
    readonly property var vt: dictation
    readonly property bool remote: vt.source !== ""

    // The card fits its content
    implicitWidth: 16 + ico.implicitWidth + 14 + (remote ? where.implicitWidth : meter.implicitWidth) + 12
                   + Math.max(88, label.implicitWidth) + 16
    implicitHeight: 48

    Text {
        id: ico
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        text: Icons.g(ind.remote ? "tablet" : ind.toClaude ? AskClaudeSession.thinkingGlyph : "mic")
        font { family: Icons.family; pixelSize: 18 }
        color: ind.vt.waiting ? Theme.dim : Theme.accent
        // Breathes while it listens; back to full when it stops, so the next dictation doesn't start dimmed
        SequentialAnimation on opacity {
            running: ind.vt.listening && !ind.vt.waiting; loops: Animation.Infinite
            onRunningChanged: if (!running) ico.opacity = 1
            NumberAnimation { to: 0.45; duration: 700 }
            NumberAnimation { to: 1.0; duration: 700 }
        }
    }
    DictationMeter {
        id: meter
        visible: !ind.remote
        dictation: ind.vt
        running: ind.running && !ind.remote
        anchors { left: ico.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
    }
    // Which microphone: the app's device by name, where the meter would be
    Text {
        id: where
        visible: ind.remote
        anchors { left: ico.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
        text: ind.vt.source.toUpperCase()
        color: Theme.accent
        font { family: Theme.font; pixelSize: 11; bold: true; letterSpacing: 0.8 }
    }
    Text {
        id: label
        anchors { left: ind.remote ? where.right : meter.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
        text: ind.vt.transcribing ? "TRANSCRIBING" : ind.vt.waiting ? (ind.remote ? "STARTING" : "PLEASE WAIT")
            : "LISTENING"
        color: ind.vt.waiting ? Theme.dim : Theme.primary
        font { family: Theme.font; pixelSize: 10; letterSpacing: 0.6 }
    }
}
