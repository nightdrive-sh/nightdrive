import QtQuick
import qs

// A button that is only a glyph (Back, Settings, Mark all read): a fill under the pointer, and a tip with its key. Under
// the pointer it rises over its neighbours, which would otherwise draw over its tip.
Rectangle {
    id: root
    required property QtObject c
    property string glyph
    property int glyphSize: 14
    property color glyphColor: c.dim        // at rest; under the pointer it takes the text colour
    property color hoverColor: c.hover
    property string tip: ""
    property string keys: ""
    property string tipSide: "below"       // "below", "above" or "right"
    property string tipAlign: "left"       // below or above: the tip's edge that lines up with the button's ("left", or
                                           // "right" for one at the window's right edge, so a clipping page doesn't cut it)
    readonly property alias hovered: hover.hovered
    signal clicked()
    implicitWidth: 26; implicitHeight: 26; radius: 6
    z: hovered ? 1 : 0
    color: hovered ? hoverColor : "transparent"
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.clicked() }
    Text {
        anchors.centerIn: parent
        text: Icons.g(root.glyph); font.family: Icons.family; font.pixelSize: root.glyphSize
        color: root.hovered ? root.c.text : root.glyphColor
    }
    Tip {
        x: root.tipSide === "right" ? parent.width + 8 : root.tipAlign === "right" ? parent.width - width : 0
        y: root.tipSide === "right" ? (parent.height - height) / 2 : root.tipSide === "above" ? -height - 8 : parent.height + 8
        c: root.c; text: root.tip; keys: root.keys; hovered: root.hovered
    }
}
