import QtQuick
import Quickshell
import Quickshell.Io

// Which folders show as a grid (t): ~/.config/nightdrive/files/views.json, { "/path": "grid" }. A folder not in it is
// a list, so only the grids are kept and a folder turned back into a list leaves the file. Each window reads the same
// file and watches it, so a choice made in one shows in the others.
Item {
    id: root
    required property string dir         // shell.qml's configDir, which it makes
    property var grids: ({})

    FileView {
        id: file
        path: root.dir + "/views.json"
        watchChanges: true
        printErrors: false                // none yet: every folder a list
        onFileChanged: reload()
        onLoaded: { try { const d = JSON.parse(text()); root.grids = d && typeof d === "object" ? d : {} } catch (e) {} }
    }
    function isGrid(path) { return grids[path] === "grid" }
    function set(path, grid) {
        const g = Object.assign({}, grids)
        if (grid) g[path] = "grid"; else delete g[path]
        grids = g
        file.setText(JSON.stringify(g, null, 2) + "\n")
    }
}
