// The synthwave face's sun (SynthwaveFace.qml): a disc of cells, yellow at the top to pink at the bottom, rising at the
// left and setting at the right over `day` seconds, then rising again. Its lower half is cut by stripes that thicken
// downwards and creep slowly up. A row of cells is one rectangle, twice as wide as the disc is tall: cells are tall.
import QtQuick

Item {
    id: sun
    property real cw: 7
    property real ch: 16
    property int cols: 80
    property int rows: 24
    property real t: 0
    property real day: 240
    property var topColor: [255, 230, 90]
    property var bottomColor: [255, 40, 150]

    readonly property int r: Math.max(6, Math.trunc(rows * 0.3))
    readonly property real p: (t / day) % 1
    readonly property real cx: -2 * r + p * (cols + 4 * r)
    readonly property int cy: Math.trunc(rows + r - Math.sin(Math.PI * p) * (rows * 0.78 + r))

    Repeater {
        model: 2 * sun.r + 1
        Rectangle {
            required property int index
            readonly property int dy: index - sun.r
            readonly property int row: sun.cy + dy
            readonly property real f: index / (2 * sun.r)
            readonly property int half: Math.trunc(Math.sqrt(sun.r * sun.r - dy * dy) * 2)
            readonly property int x0: Math.max(0, Math.trunc(sun.cx) - half)
            readonly property int x1: Math.min(sun.cols, Math.trunc(sun.cx) + half)
            // The cut-outs: a fixed period of 4 rows, the gap growing towards the bottom (Python's % is never negative)
            readonly property bool cut: f > 0.5 && (((row - sun.t * 0.25) % 4) + 4) % 4 < Math.min(2.4, (f - 0.5) * 7)
            visible: row >= 0 && row < sun.rows && x1 > x0 && !cut
            x: x0 * sun.cw; y: row * sun.ch
            width: (x1 - x0) * sun.cw; height: sun.ch
            color: {
                const c = [0, 1, 2].map(i => Math.trunc(sun.topColor[i] + (sun.bottomColor[i] - sun.topColor[i]) * f))
                return Qt.rgba(c[0] / 255, c[1] / 255, c[2] / 255, 1)
            }
        }
    }
}
