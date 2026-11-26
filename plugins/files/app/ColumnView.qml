import QtQuick
import qs.kit
import "Format.js" as Format

// The columns (t after the grid), as yazi's Miller columns: the folders above the window's, each with the next one down
// lit; the window's own folder (FolderColumn own: its rows, pick and marks, where the keys act); and what is picked in
// it: a folder's files, or a file's preview (Preview, as the pane at the right shows it in the list). h and l are ← and
// → from column to column, because the window's up() and go() do the moving: the columns only show where it is.
// How many folders above show comes from the window's width alone, never from the path (the user's call: a count of
// columns that followed the path's depth was confusing): none in a narrow window, one as yazi has it, up to three in a
// wide one. A folder above gets one share of the width, the window's own and the last slot two each, so nothing moves
// or changes its width as the path changes; above / a column stays empty. The rest are in the path at the top.
Item {
    id: root
    required property QtObject c
    required property var app
    readonly property alias view: mine.view
    clip: true

    readonly property int levels: width < 600 ? 0 : width < 1500 ? 1 : width < 1900 ? 2 : 3
    readonly property real share: width / (levels + 4)
    readonly property real parentWidth: Math.round(share)
    readonly property real ownWidth: Math.round(2 * share)
    // The folder n levels above the window's, "" past /
    function above(n) {
        let p = app.path
        for (let i = 0; i < n; i++) { if (p === "/" || !p) return ""; p = Format.parent(p) }
        return p
    }

    // Rows of folders seen lately, by path (FolderColumn): a column whose folder is being read shows them meanwhile, so
    // a step right or left doesn't blank a column or show the folder before for a moment. The folders the columns read
    // put theirs here, and so does the window's own column once its rows are its folder's
    property var seen: ({})
    property var seenOrder: []
    function put(p, rows) {
        if (!p) return
        if (!(p in seen)) { seenOrder.push(p); if (seenOrder.length > 60) delete seen[seenOrder.shift()] }
        seen[p] = rows
    }
    function rowsOf(p) { return seen[p] || null }
    Connections {
        target: root.app
        function onRowsChanged() {
            const a = root.app
            if (a.fresh && !a.filter && !a.searching && !a.trashShown && !a.inArchive) root.put(a.path, a.rows)
        }
    }

    // What the last slot shows: the picked folder's files (read a moment after the pick stops, so j held down a long list
    // doesn't read every folder it passes) or the picked file's preview. Between folders (a step left or right, the new
    // rows not come yet) nothing is picked for a moment: the slot keeps what it showed until they come
    property var file: null
    property bool showFolder: false
    property string peek: ""
    property string want: ""
    Timer { id: wait; interval: 80; onTriggered: root.peek = root.want }
    function follow() {
        const p = app.picked
        if (!p && (app.loading || !app.fresh)) return
        file = p
        want = p && p.dir ? p.path : ""
        showFolder = want !== ""
        if (!want || !peek) { wait.stop(); peek = want }
        else if (want !== peek) wait.restart()
    }
    Connections {
        target: root.app
        function onPickedChanged() { root.follow() }
        function onLoadingChanged() { root.follow() }
    }
    Component.onCompleted: follow()
    onVisibleChanged: if (visible) follow()

    // A change in the window's folder reads the file in the preview again (the window's settle)
    function again() { preview.again() }

    Row {
        anchors.fill: parent
        Repeater {
            model: root.levels
            delegate: FolderColumn {
                required property int index
                readonly property int level: root.levels - index      // the leftmost is the furthest up
                width: root.parentWidth; height: parent.height
                c: root.c; app: root.app; store: root
                path: root.above(level)              // a binding: above() reads the window's path
                next: root.above(level - 1)
            }
        }
        FolderColumn { id: mine; own: true; width: root.ownWidth; height: parent.height; c: root.c; app: root.app; store: root }
        Item {
            width: root.width - root.levels * root.parentWidth - root.ownWidth; height: parent.height
            FolderColumn {
                anchors.fill: parent
                visible: root.showFolder
                c: root.c; app: root.app; store: root
                path: root.peek
            }
            // Over the window column's line, so the two don't make a thicker one. Nothing picked (an empty folder)
            // leaves the slot empty, as the empty column beside it is, without words
            Preview {
                id: preview
                anchors.fill: parent; anchors.leftMargin: -1
                visible: !root.showFolder && root.app.previewShown && (root.file !== null || root.app.marked.length > 1)
                file: root.file
                c: root.c; app: root.app
            }
        }
    }
}
