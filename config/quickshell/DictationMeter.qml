import QtQuick

// Dictation's equalizer: stationary bars that grow up and down from the centre line with the mic's level, tallest in
// the middle. Voxtype gives only the level (no spectrum), so the difference between bars is random. While
// transcribing, a dot sweeps from side to side instead.
Row {
    id: meter
    required property Dictation dictation
    property bool running: false
    readonly property int cols: 24
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
    Component.onCompleted: reset()

    Connections {
        target: meter.dictation
        function onFrame(peak) { meter.framePeak = Math.max(meter.framePeak, peak) }
    }

    // ~14 Hz: a bar rises at once and falls more slowly
    Timer {
        interval: 70; repeat: true; running: meter.running
        onTriggered: {
            if (meter.dictation.transcribing) { meter.scan = (meter.scan + 1) % (meter.cols * 2 - 2); return }
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
            width: 3; height: 30
            readonly property real amount: meter.dictation.transcribing
                ? (index === meter.scanPos ? 1.0 : (Math.abs(index - meter.scanPos) === 1 ? 0.45 : 0))
                : (meter.levels[index] || 0)
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: Math.max(2, parent.amount * parent.height)
                radius: 1
                color: meter.dictation.transcribing ? Theme.dim : Theme.primary
                Behavior on height { NumberAnimation { duration: 60 } }
            }
        }
    }
}
