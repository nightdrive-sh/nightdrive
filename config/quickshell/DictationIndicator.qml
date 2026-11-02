import QtQuick

// Dictation's indicator (F5, docs/dictation.md) while Voxtype records or transcribes:
//   mic icon | equalizer (DictationMeter) | LISTENING / PLEASE WAIT / TRANSCRIBING
// The whole of the toast during dictation (AskClaudeToast.qml); Ask Claude's field has a wave of its own while you
// dictate to it (AskClaudeListening.qml). Its state comes from Dictation.qml.
Item {
    id: ind
    required property Dictation dictation
    property bool running: false     // the meter animates only while it's seen
    readonly property var vt: dictation

    implicitWidth: 16 + ico.implicitWidth + 14 + meter.implicitWidth + 12 + 88 + 16   // the card fits its content
    implicitHeight: 48

    Text {
        id: ico
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        text: Icons.g("mic")
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
        dictation: ind.vt
        running: ind.running
        anchors { left: ico.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
    }
    Text {
        anchors { left: meter.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
        text: ind.vt.transcribing ? "TRANSCRIBING" : ind.vt.waiting ? "PLEASE WAIT" : "LISTENING"
        color: ind.vt.waiting ? Theme.dim : Theme.primary
        font { family: Theme.font; pixelSize: 10; letterSpacing: 0.6 }
    }
}
