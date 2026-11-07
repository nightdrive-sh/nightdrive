// The synthwave face's ridge (SynthwaveFace.qml): three waves added up into a skyline that repeats every screen width and
// scrolls right, a screen in ~140 s. Each column of cells is a dark block whose top cell is half lit (a terminal's ▄),
// the glowing edge.
import QtQuick

Item {
    id: ridge
    property real cw: 7
    property real ch: 16
    property int cols: 80
    property int rows: 24
    property real t: 0
    property color body: "#1c083a"
    property color edge: "#be46ff"
    // The waves' phases, fixed so the ridge is the same every time
    readonly property var phase: [2.31, 5.07, 0.84]

    Repeater {
        model: ridge.cols
        Item {
            required property int index
            readonly property real u: index / ridge.cols - ridge.t * 0.007
            readonly property int h: {
                const tau = 2 * Math.PI, ph = ridge.phase
                const s = (0.5 + 0.5 * Math.sin(tau * 2 * u + ph[0])) * 0.45
                        + (0.5 + 0.5 * Math.sin(tau * 5 * u + ph[1])) * 0.3
                        + (0.5 + 0.5 * Math.sin(tau * 11 * u + ph[2])) * 0.15
                return Math.trunc(s * ridge.rows * 0.3)
            }
            visible: h > 0
            x: index * ridge.cw; y: (ridge.rows - h) * ridge.ch
            width: ridge.cw; height: h * ridge.ch
            Rectangle { anchors.fill: parent; color: ridge.body }
            Rectangle { y: ridge.ch / 2; width: parent.width; height: ridge.ch / 2; color: ridge.edge }
        }
    }
}
