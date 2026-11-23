import QtQuick
import Quickshell
import qs

// A small menu that floats at a place in the window, with a search over its rows (Files' Open with): no scrim, the
// window stays as it was around it. open(anchor, items) shows it under the anchor item (above it where the window has
// no room below), inside the window's edges; typing narrows the rows, ↑ ↓ move, ⏎ or a click picks, Esc or a click
// outside closes. picked(item, modifiers) gives the app the row and the keys held with it (⌘⏎: Ctrl or Meta), closed()
// comes out either way and the keys go back where they were.
// items: [{ text, detail, icon, section }]: detail is quiet text at the row's right ("default"), icon a theme icon's
// name or a file's path (a row without one, or whose icon can't be found, shows a glyph), section a heading shown
// above the first row of it that is left after the search. The menu knows nothing of what the rows are: the app does.
// Like Tip and AppDatePicker's grid, what shows moves up to the window's content item, so a pane that comes later in
// the tree or a parent that clips can't cover or cut it. Part of the apps' kit (README.md).
Item {
    id: root
    required property QtObject c
    property string title: ""             // a quiet line over the search ("Open report.pdf with")
    property string hint: ""              // a quiet line under the rows ("the default for every PDF")
    property string hintKeys: ""          // its keys before it as caps, the launcher's way ("⌘⏎": [⌘][⏎])
    property string placeholder: "Search"
    property int menuWidth: 320
    property int rowHeight: 30
    property int maxRows: 9               // more scroll
    signal picked(var item, int modifiers)
    signal closed()

    property var items: []
    property bool shown: false
    readonly property var shownItems: {
        const w = field.text.trim().toLowerCase()
        return w ? items.filter(i => (i.text || "").toLowerCase().includes(w)) : items
    }
    property int current: 0
    onShownItemsChanged: current = 0

    readonly property Item over: Window.window ? Window.window.contentItem : null
    property Item anchorItem: null
    property Item focusBefore: null
    readonly property int edge: 6

    function open(anchor, list) {
        items = list
        field.text = ""
        current = 0
        anchorItem = anchor
        focusBefore = Window.activeFocusItem
        shown = true
        Qt.callLater(place)
        field.forceActiveFocus()
    }
    function close() {
        if (!shown) return
        // The field had the keys: once hidden, the window's content item holds them (not nothing, as after a panel), so
        // they go back where they were unless the app has put them somewhere of its own meanwhile
        const back = focusBefore
        field.focus = false
        Qt.callLater(() => {
            const now = over ? over.Window.activeFocusItem : null
            if (back && (!now || now === over || now === field)) back.forceActiveFocus()
        })
        shown = false
        closed()
    }
    function pick(i, modifiers) {
        const it = shownItems[i]
        if (!it) return
        close()
        picked(it, modifiers)
    }
    // Under the anchor at its left, above it where there's no room below; never past the window's edges
    function place() {
        if (!over) return
        const a = anchorItem ? anchorItem.mapToItem(over, 0, 0) : Qt.point((over.width - card.width) / 2, over.height / 3)
        const ah = anchorItem ? anchorItem.height : 0
        card.x = Math.max(edge, Math.min(a.x + 24, over.width - card.width - edge))
        const below = a.y + ah + 2
        card.y = below + card.height <= over.height - edge ? below
               : Math.max(edge, Math.min(a.y - card.height - 2, over.height - card.height - edge))
    }
    function move(d) {
        if (!shownItems.length) return
        current = Math.max(0, Math.min(shownItems.length - 1, current + d))
        rows.positionViewAtIndex(current, ListView.Contain)
    }

    Item {
        id: layer
        parent: root.shown && root.over ? root.over : root
        visible: root.shown
        anchors.fill: parent
        z: 1000
        // A click outside closes it, and goes no further: the row under it isn't picked as well
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.close() }

        Rectangle {
            id: card
            width: Math.min(root.menuWidth, (root.over ? root.over.width : root.menuWidth) - 2 * root.edge)
            height: column.height + 12
            onHeightChanged: if (root.shown) root.place()
            radius: 10
            color: root.c.solid
            // It floats over rows of the same colour with no scrim: a 2 px edge in the theme's colour keeps it apart (a
            // quiet line, as a panel's, let it melt into the list)
            // Mixed into the card's own colour, not see-through: a row lit under it showed through the edge
            border.color: Qt.tint(root.c.solid, Qt.rgba(root.c.primary.r, root.c.primary.g, root.c.primary.b, 0.55))
            border.width: 2
            MouseArea { anchors.fill: parent }            // a click between the rows stays in the menu

            Column {
                id: column
                x: 6; y: 6
                width: parent.width - 12
                spacing: 4
                Text {
                    visible: root.title !== ""
                    width: parent.width
                    leftPadding: 8; topPadding: 4
                    text: root.title; elide: Text.ElideMiddle
                    // The title and the headings in capitals in the theme's colour: apart from the rows at a glance
                    color: root.c.primary; font.family: root.c.font; font.pixelSize: 11
                    font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
                }
                Item {
                    width: parent.width; height: 30
                    Text {
                        id: glass
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        text: Icons.g("search"); font.family: Icons.family; font.pixelSize: 14; color: root.c.faint
                    }
                    TextInput {
                        id: field
                        anchors.left: glass.right; anchors.leftMargin: 8; anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.c.text; font.family: root.c.font; font.pixelSize: 14
                        selectionColor: root.c.sel
                        clip: true
                        Text {
                            visible: !field.text
                            width: field.width; elide: Text.ElideRight
                            text: root.placeholder; color: root.c.faint; font: field.font
                        }
                        Keys.onPressed: e => {
                            const k = e.key
                            if (k === Qt.Key_Down || k === Qt.Key_Tab) root.move(1)
                            else if (k === Qt.Key_Up || k === Qt.Key_Backtab) root.move(-1)
                            else if (k === Qt.Key_PageDown) root.move(root.maxRows - 1)
                            else if (k === Qt.Key_PageUp) root.move(1 - root.maxRows)
                            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.pick(root.current, e.modifiers)
                            else if (k === Qt.Key_Escape) root.close()
                            else return
                            e.accepted = true
                        }
                    }
                }
                Text {
                    visible: !root.shownItems.length
                    width: parent.width; leftPadding: 8; topPadding: 6; bottomPadding: 6
                    text: "Nothing matches"; color: root.c.faint; font.family: root.c.font; font.pixelSize: 13
                }
                ListView {
                    id: rows
                    TouchScroll { view: rows }
                    visible: root.shownItems.length > 0
                    width: parent.width
                    height: Math.min(contentHeight, root.maxRows * root.rowHeight + 34)     // room for one heading ("Other apps")
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.shownItems
                    currentIndex: root.current
                    delegate: Column {
                        id: entry
                        required property var modelData
                        required property int index
                        width: rows.width
                        readonly property bool heading: !!modelData.section
                            && (index === 0 || root.shownItems[index - 1].section !== modelData.section)
                        Text {
                            visible: entry.heading
                            height: visible ? (entry.index === 0 ? 22 : 34) : 0      // apart from the rows above it
                            leftPadding: 8; verticalAlignment: Text.AlignBottom; bottomPadding: 3
                            text: entry.modelData.section || ""
                            color: root.c.primary; font.family: root.c.font; font.pixelSize: 11
                            font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
                        }
                        AppRow {
                            c: root.c
                            width: rows.width
                            height: root.rowHeight
                            selected: entry.index === root.current
                            TapHandler { onTapped: (pt, button) => root.pick(entry.index, pt.modifiers) }
                            Image {
                                id: icon
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18; sourceSize: Qt.size(36, 36)
                                readonly property string name: entry.modelData.icon || ""
                                source: !name ? "" : name.startsWith("/") ? "file://" + name : Quickshell.iconPath(name, true)
                                visible: status === Image.Ready
                            }
                            Text {
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                visible: !icon.visible
                                text: Icons.g("app-window"); font.family: Icons.family; font.pixelSize: 16; color: root.c.dim
                            }
                            Text {
                                id: detail
                                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                                text: entry.modelData.detail || ""
                                color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
                            }
                            Text {
                                x: 36; anchors.verticalCenter: parent.verticalCenter
                                width: detail.x - x - 8
                                text: entry.modelData.text || ""; elide: Text.ElideRight
                                color: root.c.text; font.family: root.c.font; font.pixelSize: 13
                            }
                        }
                    }
                }
                Item {
                    visible: root.hint !== "" || root.hintKeys !== ""
                    width: parent.width; height: 26
                    KeyCap {
                        id: hintCaps
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        visible: root.hintKeys !== ""
                        c: root.c; keys: root.hintKeys; capSize: 18
                    }
                    Text {
                        anchors.left: hintCaps.visible ? hintCaps.right : parent.left
                        anchors.leftMargin: 8; anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.hint; elide: Text.ElideRight
                        color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
                    }
                }
            }
        }
    }
}
