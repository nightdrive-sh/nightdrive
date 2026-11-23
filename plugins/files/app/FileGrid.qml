import QtQuick
import qs.kit

// The grid (t): the same rows as the list (FileList), as tiles with thumbnails (FileTile, Thumbs), as many to a line
// as the width takes, the spare room shared out between them. Its keys move in two directions: h l ← → along a line,
// j k ↓ ↑ a line down or up, and ⇧ with an arrow marks on the way; the rest are the list's (FileKeys), so ⏎ opens and
// ⌫ goes up. Dropped on its free space, files land in the folder on show, as in the list.
Item {
    id: root
    required property QtObject c
    required property var app
    readonly property alias view: grid
    readonly property int columns: Math.max(1, Math.floor(grid.width / (app.tile + 28)))
    // How many tiles a page holds, for PageUp and PageDown
    readonly property int perPage: columns * Math.max(1, Math.floor(grid.height / grid.cellHeight) - 1)

    GridView {
        id: grid
        anchors.fill: parent
        anchors.leftMargin: 12; anchors.rightMargin: 12
        clip: true
        model: root.app.rows
        currentIndex: root.app.current
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        TouchScroll { view: grid }
        topMargin: 4
        bottomMargin: 12
        reuseItems: true
        cellWidth: width / root.columns
        cellHeight: root.app.tile + 58          // the square, the gaps and two lines of name
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth; height: grid.cellHeight
            FileTile { anchors.centerIn: parent; modelData: cell.modelData; index: cell.index; c: root.c; app: root.app }
        }

        DropArea {
            anchors.fill: parent
            z: -1
            enabled: !root.app.trashShown
            keys: ["text/uri-list"]
            onDropped: e => root.app.acts.dropped(e, root.app.path, false)
        }
        TapHandler { onTapped: root.app.toList() }

        EmptyNote { anchors.centerIn: parent; c: root.c; app: root.app }
    }

    // A step of d tiles: off the top nothing; down past the last tile, to it if it is on a line below, as Finder does
    function step(d, mark) {
        const a = app, n = a.rows.length
        if (!n) return
        const from = a.current < 0 ? 0 : a.current
        let to = from + d
        if (to < 0) return
        if (to >= n) {
            if (Math.floor((n - 1) / columns) <= Math.floor(from / columns)) return
            to = n - 1
        }
        if (mark) a.setMark(a.rows[from].path, true)
        a.moveTo(to)
        if (mark) a.setMark(a.rows[to].path, true)
    }

    // The grid's own keys, before the list's (FileKeys): whether e was one
    function press(e) {
        const k = e.key, t = e.text
        if (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier)) return false
        const shift = (e.modifiers & Qt.ShiftModifier) !== 0
        if (k === Qt.Key_Left || t === "h") step(-1, shift && k === Qt.Key_Left)
        else if (k === Qt.Key_Right || t === "l") step(1, shift && k === Qt.Key_Right)
        else if (k === Qt.Key_Down || t === "j") step(columns, shift && k === Qt.Key_Down)
        else if (k === Qt.Key_Up || t === "k") step(-columns, shift && k === Qt.Key_Up)
        else if (t === "+" || t === "=" || k === Qt.Key_Plus) app.tileStep(1)       // = is + without ⇧ on a US keyboard
        else if (t === "-" || k === Qt.Key_Minus) app.tileStep(-1)
        else return false
        return true
    }
}
