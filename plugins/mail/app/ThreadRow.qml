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
    // Dragged sideways (towards the folders) it moves; up and down the list scrolls as before. Dragged out of the
    // window, it goes as a line of text, for Claude in a terminal (Actions.dragOver, OutDrag.qml).
    DragHandler {
        target: null
        grabPermissions: PointerHandler.TakeOverForbidden
        cursorShape: Qt.ClosedHandCursor
        onActiveChanged: if (active) ops.startDrag(row.modelData, row); else ops.drop()
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
    // A right click: its menu, of your own folders (SortMenus.qml); a picked row's acts on all the picked
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: win.menus.threadMenu(row, row.picked ? win.targets() : [row.modelData]) }
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
                width: Math.max(0, Math.min(implicitWidth, date.x - 16 - (count.visible ? count.width + count.anchors.leftMargin : 0)))
                elide: Text.ElideRight
                text: row.modelData.authors
                font.family: c.font; font.pixelSize: 13
                font.weight: row.unread ? Font.Medium : Font.Normal
                color: c.title
            }
            // The thread's messages, in a small pill so the number reads as the names' count and not loose text; muted,
            // not the accent (that is unread's). Centred on the names and no taller than them: the row keeps its height.
            Rectangle {
                id: count
                visible: row.modelData.total > 1
                anchors.left: who.right; anchors.leftMargin: 7
                anchors.verticalCenter: who.verticalCenter
                width: num.implicitWidth + 10; height: Math.min(who.implicitHeight, num.implicitHeight + 2)
                radius: 4
                color: c.line
                Text {
                    id: num
                    anchors.centerIn: parent
                    text: row.modelData.total
                    font.family: c.font; font.pixelSize: 11; color: row.unread ? c.title : c.dim
                }
            }
            // Unread: a dot in the row's left padding, in the accent of the cursor by the name.
            Rectangle {
                visible: row.unread
                width: 6; height: 6; radius: 3
                x: -11; anchors.verticalCenter: who.verticalCenter
                color: c.primary
            }
            // A file attached somewhere in the thread (Notmuch.attachments): a paperclip at the right edge, in the
            // date's colour, and the date moves left to make room; the names elide before either.
            Text {
                id: clip
                visible: row.modelData.attachments === true
                anchors.right: parent.right; anchors.verticalCenter: date.verticalCenter
                text: Icons.g("paperclip")
                font.family: Icons.family; font.pixelSize: 11; color: date.color
            }
            Text {
                id: date
                anchors.right: clip.visible ? clip.left : parent.right
                anchors.rightMargin: clip.visible ? 5 : 0
                anchors.baseline: who.baseline
                text: win.when(row.modelData.timestamp)
                font.family: c.font; font.pixelSize: 11; color: row.unread ? c.title : c.faint
            }
        }
        Item {
            width: parent.width; height: subject.implicitHeight
            Text {
                id: subject
                textFormat: Text.PlainText
                width: Math.max(0, (place.visible ? place.x - 12 : parent.width))
                elide: Text.ElideRight
                text: row.modelData.subject || "(no subject)"
                font.family: c.font; font.pixelSize: 12
                color: row.unread ? c.title : c.dim
            }
            // In a search of all folders, the folder the thread was found in (Search.qml), in the date's quiet colour
            // under it, with the sidebar's glyph; the subject elides before it, so it shows in the narrowest list too.
            Row {
                id: place
                readonly property var folder: win.searcher.wide ? win.folders[win.homeOf(row.modelData)] : null
                visible: folder !== null
                anchors.right: parent.right; anchors.verticalCenter: subject.verticalCenter
                spacing: 5
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: place.folder ? Icons.g(place.folder.glyph) : ""
                    font.family: Icons.family; font.pixelSize: 11; color: c.faint
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: place.folder ? place.folder.name : ""
                    font.family: c.font; font.pixelSize: 11; color: c.faint
                }
            }
        }
    }
}
