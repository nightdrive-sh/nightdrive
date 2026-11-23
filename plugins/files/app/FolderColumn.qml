import QtQuick
import qs.kit

// One column of the columns (ColumnView): a folder's files and folders as ColumnRows, a line at its right edge. The
// window's own column (own) shows the window's rows, pick and marks, and the keys act there; any other column (a
// folder above it, or the folder picked in it) reads its folder itself (Folder), sorted and with the hidden files as
// the window has them, and lights the row on the way (next). Dropped on its free space, files land in its folder.
// While a folder is read, the column shows its rows as last seen (store, ColumnView), else the rows it showed: never
// a blank moment or the folder before, which flickered at each step. A folder in the archive looked into (Archive) has
// its rows from the archive's listing instead, and takes no drop. An empty folder shows nothing; a filter that matches
// nothing, or an archive still being read, says so.
Item {
    id: root
    required property QtObject c
    required property var app
    required property var store               // ColumnView: put() and rowsOf() the rows seen lately
    property bool own: false
    property string path: ""                  // the folder; the window's own column's is the window's path
    property string next: ""                  // another column: the row on the way to the window's own column
    readonly property alias view: list
    readonly property string folderPath: own ? app.path : path
    readonly property bool inArchive: own ? app.inArchive : app.inArchive && (path === app.archive.file || path.startsWith(app.archive.file + "/"))
    // The window's rows once they are its folder's; till then those seen last there
    readonly property var rows: own ? (app.fresh ? app.rows : store.rowsOf(app.path) || []) : shown
    readonly property int pick: own ? (app.fresh ? app.current : -1) : next ? rows.findIndex(r => r.path === next) : -1

    property var shown: []
    Folder {
        id: folder
        path: root.own || root.inArchive ? "" : root.path
        showHidden: root.app.showHidden
        sortBy: root.app.sortBy
        reversed: root.app.reversed
        onRebuilt: root.refresh()
    }
    onPathChanged: refresh()
    onInArchiveChanged: refresh()
    Connections {
        target: root.inArchive && !root.own ? root.app.archive : null
        function onChildrenChanged() { root.refresh() }
    }
    Connections {
        target: root.inArchive && !root.own ? root.app : null
        function onSortByChanged() { root.refresh() }
        function onReversedChanged() { root.refresh() }
        function onShowHiddenChanged() { root.refresh() }
    }
    function refresh() {
        if (own) return
        if (inArchive) { shown = app.archive.rowsAt(path) || []; Qt.callLater(reveal); return }
        if (path && folder.readPath === path) { shown = folder.rows; store.put(path, folder.rows) }
        else if (!path) shown = []
        else { const seen = store.rowsOf(path); if (seen) shown = seen }    // else keep what shows until it comes
        Qt.callLater(reveal)
    }
    // The row on the way into sight as the folder comes (another column has no pick the keys move)
    function reveal() { if (!own && pick >= 0) list.positionViewAtIndex(pick, ListView.Contain) }
    onNextChanged: reveal()

    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: root.c.divider }

    ListView {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 6; anchors.rightMargin: 7
        clip: true
        model: root.rows
        currentIndex: root.pick
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        TouchScroll { view: list }
        spacing: 1
        topMargin: 4
        bottomMargin: 12
        reuseItems: true
        delegate: ColumnRow { c: root.c; app: root.app; column: root }

        DropArea {
            anchors.fill: parent
            z: -1
            enabled: !root.app.trashShown && !root.inArchive
            keys: ["text/uri-list"]
            onDropped: e => root.app.acts.dropped(e, root.folderPath, false)
        }
        // A click below the rows: the keys back to the list, or into this column's folder
        TapHandler { onTapped: root.own ? root.app.toList() : (root.app.go(root.path, ""), root.app.toList()) }

        // Only a filter that found nothing, or an archive still read or unreadable, is worth words here: an empty
        // folder is an empty column
        EmptyNote {
            visible: root.own && shown && (root.app.filter !== "" || root.app.inArchive && (root.app.archive.loading || root.app.archive.error !== ""))
            anchors.centerIn: parent; most: list.width - 16; c: root.c; app: root.app
        }
    }
}
