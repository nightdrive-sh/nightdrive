import QtQuick

// Dictation's equalizer: stationary bars that grow up and down from the centre line with the mic's level, tallest in
// the middle. Voxtype gives only the level (no spectrum), so the difference between bars is random. While
// transcribing, a dot sweeps from side to side instead.
// The dictation's toast uses it as it is; Ask Claude's listening field (AskClaudeListening.qml, #1997) sets the bars'
// size, a count that fills its width, and fadeEdges, so it reads as a wave across the field.
Row {
    id: meter
    required property Dictation dictation
    property bool running: false
    property int cols: 24
    property int barWidth: 3
    property int barHeight: 30       // the tallest bar
    property real barRadius: 1
    property bool fadeEdges: false   // bars dim towards the ends
    // The sweep crosses a wide meter in about the time it crosses the toast's 24 bars
    readonly property int scanStep: Math.max(1, Math.round(cols / 24))
    property var levels: []          // bar heights 0..1
    property real framePeak: 0       // the loudest frame since the last tick
    property int scan: 0
    readonly property int scanPos: scan < cols ? scan : (cols * 2 - 2 - scan)

    spacing: 2

    function reset() {
        levels = new Array(cols).fill(0)
        framePeak = 0
        scan = 0
    }
    onRunningChanged: if (running) reset()
    onColsChanged: reset()
    Component.onCompleted: reset()

    Connections {
        target: meter.dictation
        function onFrame(peak) { meter.framePeak = Math.max(meter.framePeak, peak) }
    }

    // ~14 Hz: a bar rises at once and falls more slowly
    Timer {
        interval: 70; repeat: true; running: meter.running
        onTriggered: {
            if (meter.dictation.transcribing) { meter.scan = (meter.scan + meter.scanStep) % (meter.cols * 2 - 2); return }
            const level = Math.min(1, Math.pow(meter.framePeak, 0.5))
            const h = meter.levels.slice()
            const mid = (meter.cols - 1) / 2
            for (let i = 0; i < meter.cols; i++) {
                const d = (i - mid) / (meter.cols / 3.4)
                const env = 0.35 + 0.65 * Math.exp(-d * d)
                const target = level < 0.10 ? 0 : Math.min(1, level * env * (0.55 + 0.45 * Math.random()) * 1.5)
                h[i] = target > h[i] ? target : h[i] * 0.72 + target * 0.28
            }
            meter.levels = h
            meter.framePeak = 0
        }
    }

    Repeater {
        model: meter.cols
        Item {
            required property int index
            width: meter.barWidth; height: meter.barHeight
            readonly property real edge: (index - (meter.cols - 1) / 2) / (meter.cols / 3.4)
            readonly property real amount: meter.dictation.transcribing
                ? (meter.scanStep > 1 ? 0.5 * Math.exp(-Math.pow((index - meter.scanPos) / meter.scanStep, 2))   // a soft glow
                   : index === meter.scanPos ? 1.0 : (Math.abs(index - meter.scanPos) === 1 ? 0.45 : 0))
                : (meter.levels[index] || 0)
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: Math.max(meter.fadeEdges ? parent.width : 2, parent.amount * parent.height)
                radius: meter.barRadius
                opacity: meter.fadeEdges ? 0.35 + 0.65 * Math.exp(-parent.edge * parent.edge / 2) : 1
                color: meter.dictation.transcribing ? Theme.dim : Theme.primary
                Behavior on height { NumberAnimation { duration: 60 } }
            }
        }
    }
}
