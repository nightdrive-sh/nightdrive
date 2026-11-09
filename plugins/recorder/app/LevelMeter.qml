import QtQuick
import Quickshell.Services.Pipewire

// The picked microphone's level as a row of bars that fill from the left, so it shows the mic hears before and while
// it records. Read as the bar's microphone icon reads it (config/quickshell/MicLevel.qml): Quickshell's peak monitor
// (a "Peak detect" stream the privacy indicator leaves out), its peak the cube root of the sample peak, so 60·log10 is
// dBFS, put on a scale where a quiet room stays empty and speech fills most of it. Fast rise, slower fall; a peak held
// a moment shows where the loudest was. Dimmed while not recording: it is a check of the mic then, not the recording.
Item {
    id: m
    required property QtObject c
    property var node: null                    // the PwNode to listen to (null: nothing)
    property bool active: true                 // listening at all (the window shown)
    property bool live: false                  // recording: the bars in the accent colour
    // -34 … 0 dBFS: a humming room heard by a MacBook's mic (a fan, ventilation) stays empty, at -50 it filled half and
    // at -40 a fifth; speech (peaks -4 … -20) fills a half to most of it. The top is 0, where it clips, so typing beside
    // the mic (clicks near -10) no longer reads as clipping: only the last tenth, above -3.4 dBFS, is red (redFrom).
    readonly property int floorDb: -34
    readonly property int topDb: 0
    readonly property real redFrom: 0.9
    readonly property int bars: Math.max(8, Math.floor(width / 6))
    property real level: 0
    property real hold: 0                      // the highest peak since the last step
    property real peak: 0                      // the peak shown: falls slowly
    implicitHeight: 18

    PwObjectTracker { objects: m.node ? [m.node] : [] }
    PwNodePeakMonitor {
        node: m.node
        enabled: m.active && m.node !== null
        onPeakChanged: if (peak > 0) m.hold = Math.max(m.hold, Math.min(1, (60 * Math.log10(peak) - m.floorDb) / (m.topDb - m.floorDb)))
    }
    Timer {
        interval: 60; repeat: true; running: m.active && m.node !== null
        onTriggered: {
            m.level = Math.max(m.hold, m.level * 0.75)
            m.peak = Math.max(m.level, m.peak - 0.02)
            m.hold = 0
        }
    }
    onActiveChanged: if (!active) { level = 0; peak = 0; hold = 0 }

    Row {
        anchors.fill: parent
        spacing: 2
        Repeater {
            model: m.bars
            Rectangle {
                required property int index
                readonly property real at: (index + 0.5) / m.bars
                readonly property bool lit: at <= m.level
                readonly property bool held: Math.abs(at - m.peak) < 0.5 / m.bars && m.peak > 0.05
                width: (m.width - (m.bars - 1) * 2) / m.bars
                height: m.height * (0.45 + 0.55 * index / m.bars)     // rising, as a volume wedge
                anchors.bottom: parent.bottom
                radius: 1.5
                // The loudest end warns: there it clips
                color: lit || held ? (at > m.redFrom ? m.c.danger : m.live ? m.c.accent : m.c.dim) : m.c.line
                opacity: lit || held ? 1 : 0.6
            }
        }
    }
}
