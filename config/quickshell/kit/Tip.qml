import QtQuick

// A button's tip: what it does and its key, shown once the pointer has rested on it (delay). Place it with x and y
// beside the button, and bind hovered to the button's HoverHandler.
// It stays where it is put only as a place: once shown, the bubble moves up to the window's content item, so it draws
// over everything in the window (a list or a pane that comes later in the tree, a parent that clips) and is kept inside
// the window's edges. A z on the button alone can't do that: it only lifts it over its own siblings.
// Part of the apps' kit (README.md).
Item {
    id: root
    required property QtObject c
    property string text
    property string keys
    property bool hovered: false
    readonly property int delay: 500       // ms under the pointer before it shows
    readonly property int edge: 6          // kept this far inside the window
    Timer { id: wait; interval: root.delay; running: root.hovered && root.text !== "" }
    readonly property bool shown: hovered && !wait.running && text !== ""
    // The same size as the bubble, so x: parent.width - width and y: -height - 8 still place it
    implicitWidth: bubble.implicitWidth; implicitHeight: bubble.implicitHeight

    readonly property Item over: Window.window ? Window.window.contentItem : null
    onShownChanged: if (shown) place()
    function place() {
        if (!over) return
        const p = root.mapToItem(over, 0, 0)
        bubble.x = Math.max(edge, Math.min(p.x, over.width - bubble.width - edge))
        bubble.y = Math.max(edge, Math.min(p.y, over.height - bubble.height - edge))
    }

    Rectangle {
        id: bubble
        parent: root.shown && root.over ? root.over : root
        visible: root.shown
        z: 1000
        implicitWidth: row.implicitWidth + 20; implicitHeight: 32
        width: implicitWidth; height: implicitHeight
        radius: 8
        color: root.c.solid
        border.color: root.c.line
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 10
            Text { anchors.verticalCenter: parent.verticalCenter; text: root.text; color: root.c.text; font.family: root.c.font; font.pixelSize: 12 }
            KeyCap { anchors.verticalCenter: parent.verticalCenter; visible: root.keys !== ""; c: root.c; keys: root.keys }
        }
    }
}
