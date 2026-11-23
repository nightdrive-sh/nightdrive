import QtQuick
import Qt.labs.folderlistmodel
import "Format.js" as Format

// The folder on show: Qt's FolderListModel reads it on a thread of its own and watches it, and rows is what the list
// shows, in Files' own order (Format.order: folders first, numbers counted) and narrowed by the filter (/), as plain
// objects { name, path, dir, size, modified }. The model's own sort is off: it has no natural order and keeps
// folders apart only by a flag. A change in the folder (a copy landing, another app's) comes back as a rebuild.
Item {
    id: root
    property string path: ""
    property bool showHidden: false
    property string sortBy: "name"          // name, modified, size, type
    property bool reversed: false
    property string filter: ""              // words in the name, case left aside
    property var rows: []
    property int total: 0                   // before the filter
    readonly property bool loading: model.status === FolderListModel.Loading || later.running
    signal changing()                       // rows are about to be set again (the window holds its view's place)
    signal rebuilt()

    FolderListModel {
        id: model
        folder: root.path ? Format.url(root.path) : ""
        showDirsFirst: false
        sortField: FolderListModel.Unsorted
        showHidden: root.showHidden
        showDotAndDotDot: false
        showOnlyReadable: false
        caseSensitive: false
    }
    // Rows come and go one by one as a folder is read: one rebuild for the lot
    Timer { id: later; interval: 40; onTriggered: root.rebuild() }
    Connections {
        target: model
        function onCountChanged() { later.restart() }
        function onStatusChanged() { later.restart() }
        function onDataChanged() { later.restart() }
    }
    onFilterChanged: rebuild()
    onSortByChanged: rebuild()
    onReversedChanged: rebuild()

    property var all: []
    // The folder whose rows these are. A change in it reads it again, and the model is Loading meanwhile with no rows
    // to give: a rebuild then emptied the list for a moment, and the pick went back to the top (#3415). The rows stay
    // until it is Ready; only another folder's are dropped at once.
    property string readPath: ""
    function rebuild() {
        if (later.running) later.stop()
        if (model.status !== FolderListModel.Ready && readPath === path && rows.length) return
        readPath = model.status === FolderListModel.Ready ? path : ""
        const out = []
        if (model.status === FolderListModel.Ready) {
            for (let i = 0; i < model.count; i++) {
                const name = model.get(i, "fileName")
                if (name === "." || name === "..") continue
                out.push({ name: name, path: Format.join(root.path, name), dir: model.get(i, "fileIsDir"),
                           size: model.get(i, "fileSize"), modified: model.get(i, "fileModified") })
            }
        }
        all = out
        total = out.length
        changing()
        const words = filter.trim().toLowerCase()
        rows = Format.order(words ? out.filter(r => r.name.toLowerCase().indexOf(words) >= 0) : out, sortBy, reversed)
        rebuilt()
    }
}
