import QtQuick
import qs.kit

// One thread in the list: who wrote, how many messages, unread, when, the subject; a click opens it, a sideways drag
// takes it to a folder, ⇧- and Ctrl-click pick several. Apart from ThreadList.qml, which lays out the list around it.
AppRow {
    id: row
    // Set by the list (not required: a delegate's required properties are what it takes from the model)
    property var win
    property var ops                    // Actions.qml
    property var writer                 // Writing.qml
    property var panes
    required property var modelData
    required property int index
    readonly property bool unread: modelData.tags.indexOf("unread") >= 0
    readonly property bool picked: win.picked.indexOf(modelData.thread) >= 0
    implicitHeight: col.implicitHeight + 28
    c: win.look
    // With Tab in the folders (Panes.qml), the open one is only marked
    selected: picked || index === win.current && !win.picked.length && panes.at === "list"
    marked: index === win.current
    active: panes.at === "list" && !win.picked.length
    // With threads picked, the keyboard's place among them
    border.color: index === win.current && win.picked.length ? c.line : selected && active ? c.frame : "transparent"
    // Dragged sideways (towards the folders) it moves; up and down the list scrolls as before.
    DragHandler {
        target: null
        grabPermissions: PointerHandler.TakeOverForbidden
        cursorShape: Qt.ClosedHandCursor
        onActiveChanged: if (active) ops.startDrag(row.modelData); else ops.drop()
        onCentroidChanged: if (active) ops.dragOver(centroid.scenePosition)
    }
    TapHandler {
        acceptedModifiers: Qt.NoModifier
        onTapped: { win.open(row.index); panes.pane = "list"; win.list.forceActiveFocus(); win.openReader() }   // in one pane: point, then open
        onDoubleTapped: if (writer.draft()) win.compose("resume"); else win.openWindow(row.index)
    }
    // ⇧-click picks the threads from the open one to this; Ctrl-click picks this one or leaves it
    // out (⌘-click is the desktop's: it moves the window)
    TapHandler { acceptedModifiers: Qt.ShiftModifier; onTapped: { win.pickRange(row.index); win.list.forceActiveFocus() } }
    TapHandler { acceptedModifiers: Qt.ControlModifier; onTapped: { win.togglePick(row.index); win.list.forceActiveFocus() } }
    Column {
        id: col
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 16; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Item {
            width: parent.width; height: who.implicitHeight
            // The names take what the count and the date leave, so only they elide and the
            // count always shows right after them. Plain text, as every field with a message's
            // words: Qt reads text with a tag in it as HTML, so an <img> in a name or subject
            // loaded as the list showed it, unopened, past the body's blocked images.
            Text {
                id: who
                textFormat: Text.PlainText
                anchors.left: parent.left
                width: Math.max(0, Math.min(implicitWidth, date.x - 16 - (count.visible ? count.implicitWidth : 0)))
                elide: Text.ElideRight
                text: row.modelData.authors
                font.family: c.font; font.pixelSize: 13
                font.weight: row.unread ? Font.Medium : Font.Normal
                color: c.title
            }
            Text {
                id: count
                visible: row.modelData.total > 1
                anchors.left: who.right; anchors.baseline: who.baseline
                text: "  " + row.modelData.total
                font: who.font; color: who.color
            }
            // Unread: a dot in the row's left padding, in the accent of the cursor by the name.
            Rectangle {
                visible: row.unread
                width: 6; height: 6; radius: 3
                x: -11; anchors.verticalCenter: who.verticalCenter
                color: c.primary
            }
            Text {
                id: date
                anchors.right: parent.right; anchors.baseline: who.baseline
                text: win.when(row.modelData.timestamp)
                font.family: c.font; font.pixelSize: 11; color: row.unread ? c.title : c.faint
            }
        }
        Text {
            textFormat: Text.PlainText
            width: parent.width; elide: Text.ElideRight
            text: row.modelData.subject || "(no subject)"
            font.family: c.font; font.pixelSize: 12
            color: row.unread ? c.title : c.dim
        }
    }
}
