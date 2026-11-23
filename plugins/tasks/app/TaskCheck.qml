import QtQuick
import qs
import qs.kit

// A task's circle: empty while open, ticked when done. Ticking one (its press, or Space) turns the circle to the accent
// (the theme's violet) and pops a filled disc into it, a little smaller than the circle, at once: it shows that the press
// landed and on which task, before the row leaves the view (Actions waits a moment before it runs the change). Opening a
// done one again shows the accent circle with the disc shrinking out of it. The press is its own, larger than the glyph,
// so the row's tap (pick) and double tap (edit) don't come with it.
Item {
    id: root
    required property QtObject c
    property bool done: false           // as the row shows it: the change on its way, else the file's
    property bool fresh: false          // just pressed: the change is on its way (Actions.ticking)
    property bool important: false
    signal clicked()

    readonly property int size: 16
    readonly property int disc: 9       // inside the glyph's ring (~12 px across at 16) with a gap
    implicitWidth: size; implicitHeight: size

    // At rest: the glyph the list always had, faint once done. Just pressed: the empty circle, in the accent
    Text {
        id: glyph
        anchors.centerIn: parent
        text: Icons.g(root.done && !root.fresh ? "circle-check" : "circle")
        font.family: Icons.family; font.pixelSize: root.size
        color: root.fresh || (root.important && !root.done) ? root.c.accent : root.done ? root.c.faint : root.c.dim
    }
    // The ring's ink isn't at the Text's centre (the font's line box is taller than the glyph): the disc goes to the
    // middle of the ink itself, or it sat half a pixel up and left in the ring
    TextMetrics { id: ink; font: glyph.font; text: Icons.g("circle") }
    Rectangle {
        id: fill
        x: glyph.x + ink.tightBoundingRect.x + (ink.tightBoundingRect.width - width) / 2
        y: glyph.y + glyph.baselineOffset + ink.tightBoundingRect.y + (ink.tightBoundingRect.height - height) / 2
        width: root.disc; height: root.disc
        radius: width / 2
        color: root.c.accent
        visible: root.fresh
        scale: 0
    }

    // In: from nothing, a touch past its size and back. Out (opened again): from full to nothing
    SequentialAnimation {
        id: popIn
        NumberAnimation { target: fill; property: "scale"; from: 0; to: 1.2; duration: 140; easing.type: Easing.OutCubic }
        NumberAnimation { target: fill; property: "scale"; to: 1; duration: 120; easing.type: Easing.InOutQuad }
    }
    NumberAnimation { id: popOut; target: fill; property: "scale"; from: 1; to: 0; duration: 260; easing.type: Easing.InCubic }
    onFreshChanged: {
        popIn.stop(); popOut.stop()
        if (fresh && done) popIn.restart()
        else if (fresh) popOut.restart()
        else fill.scale = 0
    }

    MouseArea {
        anchors.centerIn: parent
        width: 36; height: 36
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
