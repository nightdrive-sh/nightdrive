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
    Component.onCompleted: sync()
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

    // The widths: the last slot at least lastMin, then as many columns of at least minColumn as fit beside it (one at
    // least, of no more than maxColumn), and the last slot takes what is left
    readonly property int minColumn: 170
    readonly property int maxColumn: 280
    readonly property int count: ancestors.length + 1
    readonly property real lastMin: Math.max(180, Math.min(380, width * 0.36))
    readonly property int fit: Math.max(1, Math.min(count, Math.floor((width - lastMin) / minColumn)))
    readonly property real columnWidth: Math.max(120, Math.min(maxColumn, (width - lastMin) / fit))
    readonly property real lastWidth: Math.max(lastMin, width - fit * columnWidth)

    // The folder picked in the window's column, read a moment after the pick stops (j held down a long list doesn't read
    // every folder it passes): its files show in the last slot meanwhile as they were
    readonly property string pickedDir: app.picked && app.picked.dir ? app.picked.path : ""
    property string peek: ""
    onPickedDirChanged: { if (!pickedDir || !peek) { wait.stop(); peek = pickedDir } else wait.restart() }
    Timer { id: wait; interval: 80; onTriggered: root.peek = root.pickedDir }

    // A change in the window's folder reads the file in the preview again (the window's settle)
    function again() { preview.again() }

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
        Connections {
            target: root.app
            function onPathChanged() { flick.contentX = flick.end }
        }

        Row {
            id: strip
            height: flick.height
            Repeater {
                model: chain
                delegate: FolderColumn {
                    required property string dir
                    required property string way
                    width: root.columnWidth; height: strip.height
                    c: root.c; app: root.app
                    path: dir; next: way
                }
            }
            FolderColumn { id: mine; own: true; width: root.columnWidth; height: strip.height; c: root.c; app: root.app }
            Item {
                width: root.lastWidth; height: strip.height
                FolderColumn {
                    anchors.fill: parent
                    visible: root.pickedDir !== ""
                    c: root.c; app: root.app
                    path: visible ? root.peek : ""
                }
                // Over the window column's line, so the two don't make a thicker one
                Preview {
                    id: preview
                    anchors.fill: parent; anchors.leftMargin: -1
                    visible: root.pickedDir === "" && root.app.previewShown
                    c: root.c; app: root.app
                }
            }
        }
    }
}
