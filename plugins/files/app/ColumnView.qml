import QtQuick
import qs.kit
import "Format.js" as Format

// The columns (t after the grid), as Finder's column view and yazi's Miller columns: the folders from home down to the
// window's side by side, each with the next one on the way lit, then the window's own folder (FolderColumn own: its
// rows, pick and marks, where the keys act), then what is picked in it: a folder's files, or a file's preview
// (Preview, as the pane at the right shows it in the list). h and l are ← and → from column to column, because the
// window's up() and go() do the moving: the columns only show the path.
// As many columns as fit show in full, the last ones, and the last slot gets the rest of the width; the folders further
// up are a scroll to the left away (it stops at a column's edge), and the view goes back to the end as the path changes.
Item {
    id: root
    required property QtObject c
    required property var app
    readonly property alias view: mine.view
    clip: true

    // The folders above the window's, from the top: home inside home, else / (a USB stick's path starts there too)
    readonly property string first: app.inHome ? app.home : "/"
    readonly property var ancestors: {
        const out = []
        let q = app.path
        while (q !== first && q !== "/") { q = Format.parent(q); out.unshift(q) }
        return out
    }
    // Kept in a ListModel changed in place, so a step down or up adds or takes away one column and the others keep their
    // folder read (a new array would make the Repeater read every one again)
    ListModel { id: chain }
    onAncestorsChanged: sync()
    Component.onCompleted: { sync(); follow() }
    function sync() {
        const a = ancestors
        while (chain.count > a.length) chain.remove(chain.count - 1)
        for (let i = 0; i < a.length; i++) {
            const way = i + 1 < a.length ? a[i + 1] : app.path
            if (i >= chain.count) chain.append({ dir: a[i], way: way })
            else {
                if (chain.get(i).dir !== a[i]) chain.setProperty(i, "dir", a[i])
                if (chain.get(i).way !== way) chain.setProperty(i, "way", way)
            }
        }
    }

    // The widths come from the window's width alone, never from how deep the path is: a step down or up then only adds
    // or takes away a column, and nothing else moves (when they followed the count, every column changed its width at
    // each step and the view flickered). The last slot is at least lastMin, the columns beside it as many of at least
    // minColumn as fit (no wider than maxColumn); a shallow path leaves the room after the last slot empty, as Finder does
    readonly property int minColumn: 170
    readonly property int maxColumn: 280
    readonly property real lastMin: Math.max(180, Math.min(380, width * 0.36))
    readonly property int fit: Math.max(1, Math.floor((width - lastMin) / minColumn))
    readonly property real columnWidth: Math.max(120, Math.min(maxColumn, (width - lastMin) / fit))
    readonly property real lastWidth: Math.max(lastMin, width - fit * columnWidth)

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
        function onPathChanged() { Qt.callLater(root.toEnd) }
    }
    onVisibleChanged: if (visible) { follow(); toEnd() }

    // A change in the window's folder reads the file in the preview again (the window's settle)
    function again() { preview.again() }
    function toEnd() { flick.contentX = flick.end }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: strip.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width + 1
        readonly property real end: Math.max(0, contentWidth - width)
        onEndChanged: contentX = end
        onMovementEnded: contentX = Math.min(end, Math.round(contentX / root.columnWidth) * root.columnWidth)

        Row {
            id: strip
            height: flick.height
            Repeater {
                model: chain
                delegate: FolderColumn {
                    required property string dir
                    required property string way
                    width: root.columnWidth; height: strip.height
                    c: root.c; app: root.app; store: root
                    path: dir; next: way
                }
            }
            FolderColumn { id: mine; own: true; width: root.columnWidth; height: strip.height; c: root.c; app: root.app; store: root }
            Item {
                width: root.lastWidth; height: strip.height
                FolderColumn {
                    anchors.fill: parent
                    visible: root.showFolder
                    c: root.c; app: root.app; store: root
                    path: root.peek
                }
                // Over the window column's line, so the two don't make a thicker one. Nothing picked (an empty
                // folder) leaves the slot empty, as the empty column beside it is, without words
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
}
