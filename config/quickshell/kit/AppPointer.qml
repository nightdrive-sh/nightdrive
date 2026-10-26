import QtQuick

// The frame of the row the keys are on (AppLook's frame) shows only after a key, as a browser's :focus-visible: the
// pointer moving in the window hides it until the next key. Put it in the item that holds the window's content (its
// RowLayout): a handler there hears the pointer over every part without taking it from them, as an item over them
// would. The app's key handlers call c.moved(e) (AppLook.qml).
HoverHandler {
    id: root
    required property QtObject c
    readonly property int still: 3      // px the pointer may stray: a nudged desk isn't the mouse put to use
    property point last: Qt.point(-1, -1)
    // A frame redrawn under a pointer standing still is no move
    onPointChanged: {
        const p = point.scenePosition
        if (Math.abs(p.x - last.x) > still || Math.abs(p.y - last.y) > still) {
            last = p
            c.keyboard = false
        }
    }
}
