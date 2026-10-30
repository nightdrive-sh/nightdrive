import QtQuick

// Dictation's toast (F5, docs/dictation.md), a card in ToastStack while Voxtype records or transcribes:
//   mic icon | equalizer (DictationMeter) | LISTENING / PLEASE WAIT / TRANSCRIBING
// Its state comes from Dictation.qml. Ask Claude (Dashboard #1895) is meant to grow out of this card.
Toast {
    id: toast
    shown: vt.shown
    cardWidth: 16 + ico.implicitWidth + 14 + meter.implicitWidth + 12 + 88 + 16   // the card fits its content

    Dictation { id: vt }

    Text {
        id: ico
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        text: Icons.g("mic")
        font { family: Icons.family; pixelSize: 18 }
        color: vt.waiting ? Theme.dim : Theme.accent
        // Breathes while it listens; back to full when it stops, so the next dictation doesn't start dimmed
        SequentialAnimation on opacity {
            running: vt.listening && !vt.waiting; loops: Animation.Infinite
            onRunningChanged: if (!running) ico.opacity = 1
            NumberAnimation { to: 0.45; duration: 700 }
            NumberAnimation { to: 1.0; duration: 700 }
        }
    }
    DictationMeter {
        id: meter
        dictation: vt
        running: toast.shown
        anchors { left: ico.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
    }
    Text {
        anchors { left: meter.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
        text: vt.transcribing ? "TRANSCRIBING" : vt.waiting ? "PLEASE WAIT" : "LISTENING"
        color: vt.waiting ? Theme.dim : Theme.primary
        font { family: Theme.font; pixelSize: 10; letterSpacing: 0.6 }
    }
}
