import QtQuick

// Ask Claude's field while you dictate to it (AskClaudePanel.qml, Dashboard #1997, the user's choice of three):
//   mic | a wave across the field's width (DictationMeter) | Listening… / Please wait… / Transcribing…
// The field's own height and inner margins, so the text appears where the wave was. The dictation's own small toast
// keeps DictationIndicator.qml. Its state comes from Dictation.qml.
Item {
    id: l
    required property Dictation dictation
    property bool running: false     // the wave animates only while it's seen
    readonly property var vt: dictation

    // --- Tunables ---
    readonly property int inset: 14          // as the field's text (AskClaudeField's view margins)
    readonly property int barWidth: 4
    readonly property int barGap: 3
    readonly property int waveHeight: 34
    readonly property int labelWidth: 120    // room for the longest word, so the wave doesn't jump as it changes

    implicitHeight: 44

    Text {
        id: ico
        anchors { left: parent.left; leftMargin: l.inset; verticalCenter: parent.verticalCenter }
        text: Icons.g("mic")
        font { family: Icons.family; pixelSize: 20 }
        color: l.vt.waiting || l.vt.transcribing ? Theme.dim : Theme.accent
        // Breathes while it listens; back to full when it stops, so the next dictation doesn't start dimmed
        SequentialAnimation on opacity {
            running: l.vt.listening && !l.vt.waiting; loops: Animation.Infinite
            onRunningChanged: if (!running) ico.opacity = 1
            NumberAnimation { to: 0.45; duration: 700 }
            NumberAnimation { to: 1.0; duration: 700 }
        }
    }

    // As many bars as fill the room between the mic and the word
    Item {
        id: room
        anchors { left: ico.right; leftMargin: 18; right: label.left; rightMargin: 18; verticalCenter: parent.verticalCenter }
        height: l.waveHeight
        DictationMeter {
            anchors.centerIn: parent
            dictation: l.vt
            running: l.running
            cols: Math.max(8, Math.floor((room.width + l.barGap) / (l.barWidth + l.barGap)))
            barWidth: l.barWidth
            barHeight: l.waveHeight
            barRadius: l.barWidth / 2
            spacing: l.barGap
            fadeEdges: true
        }
    }

    Text {
        id: label
        anchors { right: parent.right; rightMargin: l.inset; verticalCenter: parent.verticalCenter }
        width: l.labelWidth
        horizontalAlignment: Text.AlignRight
        text: l.vt.transcribing ? "Transcribing…" : l.vt.waiting ? "Please wait…" : "Listening…"
        color: Theme.dim
        font { family: Theme.font; pixelSize: 14 }
    }
}
