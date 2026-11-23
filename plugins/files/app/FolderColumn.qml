import QtQuick
import qs.kit

// One column of the columns (ColumnView): a folder's files and folders as ColumnRows, a line at its right edge. The
// window's own column (own) shows the window's rows, pick and marks, and the keys act there; any other column (a
// folder above it, or the folder picked in it) reads its folder itself (Folder), sorted and with the hidden files as
// the window has them, and lights the row on the way (next). Dropped on its free space, files land in its folder.
Item {
    id: root
    required property QtObject c
    required property var app
    property bool own: false
    property string path: ""                  // the folder; the window's own column's is the window's path
    property string next: ""                  // another column: the row on the way to the window's own column
    readonly property alias view: list
    readonly property string folderPath: own ? app.path : path
    readonly property var rows: own ? app.rows : folder.rows
    readonly property int pick: own ? app.current : next ? rows.findIndex(r => r.path === next) : -1

    Folder {
        id: folder
        path: root.own ? "" : root.path
        showHidden: root.app.showHidden
        sortBy: root.app.sortBy
        reversed: root.app.reversed
        // The row on the way into sight as the folder comes (another column has no pick the keys move)
        onRebuilt: Qt.callLater(root.reveal)
    }
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
            enabled: !root.app.trashShown
            keys: ["text/uri-list"]
            onDropped: e => root.app.acts.dropped(e, root.folderPath, false)
        }
        // A click below the rows: the keys back to the list, or into this column's folder
        TapHandler { onTapped: root.own ? root.app.toList() : (root.app.go(root.path, ""), root.app.toList()) }

        // The window's own column says what an empty folder or filter says, in the column's width
        EmptyNote { visible: root.own && shown; anchors.centerIn: parent; most: list.width - 16; c: root.c; app: root.app }
        Text {
            visible: !root.own && root.rows.length === 0 && !folder.loading && root.path !== ""
            anchors.centerIn: parent
            text: "Empty"
            color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
        }
    }
}
