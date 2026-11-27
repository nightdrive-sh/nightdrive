import QtQuick
import QtQuick.Shapes

// Ask Claude's own mark (#3428, #3704): a speech bubble with three dots, which hop one after the other while Claude works
// (running). It was the robot's head, which the Claude menu and the sessions already use, so Ask Claude read as one of
// them. Drawn here rather than taken from the icon font, as the font's bubble (message-circle-more) can't move its dots;
// the shape is Lucide's message-circle in its 24-unit box, scaled to size.
Item {
    id: g
    property real size: 18
    property color color: Theme.accent
    property bool running: false

    // --- Tunables ---
    readonly property real hop: 2.2          // how high a dot hops, in the 24-unit box
    readonly property int hopMs: 300         // one dot's way up or down
    readonly property int staggerMs: 150     // between one dot and the next

    implicitWidth: size
    implicitHeight: size

    Item {
        width: 24
        height: 24
        scale: g.size / 24
        transformOrigin: Item.TopLeft

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: g.color
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M7.9 20A9 9 0 1 0 4 16.1L2 22Z" }
            }
        }
        Repeater {
            model: 3
            Rectangle {
                id: dot
                required property int index
                readonly property real rest: 12 - height / 2
                x: 8 + 4 * index - width / 2
                y: rest
                width: 2.6
                height: 2.6
                radius: 1.3
                color: g.color
                // Each waits its turn, hops, and waits for the others, so the three keep one beat
                SequentialAnimation on y {
                    running: g.running
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) dot.y = dot.rest
                    PauseAnimation { duration: dot.index * g.staggerMs }
                    NumberAnimation { to: dot.rest - g.hop; duration: g.hopMs; easing.type: Easing.OutQuad }
                    NumberAnimation { to: dot.rest; duration: g.hopMs; easing.type: Easing.InQuad }
                    PauseAnimation { duration: (2 - dot.index) * g.staggerMs + 200 }
                }
            }
        }
    }
}
