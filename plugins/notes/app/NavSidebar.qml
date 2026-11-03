import QtQuick
import QtQuick.Layouts
import qs.kit

// The folders and tags, left of the notes (#2016): All notes, then the folders as they are in ~/Notes (a subfolder under
// its parent, each with how many notes are in it and under it), then the #tags read from the notes' text. A click picks
// one and the list beside shows only its notes (Store.scope*). + by Folders makes one in the folder picked; an empty
// folder has a trash button under the pointer. A note dragged from the list is dropped on a folder here (NoteDrag.qml).
//
// From the keyboard (f, shell.qml): ↑ ↓ pick as they move, ⏎ Esc or Tab go back to the notes, Delete takes an empty folder
// away.
AppSidebar {
    id: root
    required property QtObject store
    property bool active: false          // the keyboard is here: the picked row has the kit's frame
    property string dropPath: "\u0000"   // the folder under a note being dragged ("" the top), "\0" for none
    signal newFolder()
    signal removeFolder(string path)
    signal done()                        // back to the notes (the keyboard's)
    signal chosen()                      // a click picked a row: a narrow window shows the list again
    title: "Notes"
    titleItems: AppIconButton {
        c: root.c; glyph: "folder-plus"; tip: "New folder"; tipAlign: "right"
        onClicked: root.newFolder()
    }

    // Every row in order, for the keys: { kind: "all" | "folder" | "tag", key }
    readonly property var entries: [{ kind: "all", key: "" }]
        .concat(store.folders.map(f => ({ kind: "folder", key: f.path })))
        .concat(store.tags.map(t => ({ kind: "tag", key: t.name })))
    readonly property int current: store.scopeTag
        ? entries.findIndex(e => e.kind === "tag" && e.key.toLowerCase() === store.scopeTag.toLowerCase())
        : entries.findIndex(e => e.kind !== "tag" && e.key === store.scopeFolder)
    function pick(e) { if (e.kind === "tag") store.pickTag(e.key); else store.pickFolder(e.key) }
    function step(d) {
        const i = Math.max(0, Math.min(entries.length - 1, current + d))
        pick(entries[i])
    }

    Keys.onPressed: e => {
        const k = e.key
        if (k === Qt.Key_Down || k === Qt.Key_J) step(1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) step(-1)
        else if (k === Qt.Key_Home) step(-entries.length)
        else if (k === Qt.Key_End) step(entries.length)
        else if (k === Qt.Key_Delete && store.scopeFolder && !store.scopeTag) root.removeFolder(store.scopeFolder)
        else if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Escape, Qt.Key_Tab, Qt.Key_Right, Qt.Key_F].indexOf(k) >= 0) root.done()
        else return
        e.accepted = true
    }

    // The folder (path) a note dragged to pos (in the window) would land in, "\0" for none: every folder row and
    // All notes, which is the top
    function dropAt(pos) {
        const rows = [allRow].concat(folderRows.rows())
        for (const r of rows) if (r.contains(r.mapFromItem(null, pos.x, pos.y))) return r.path
        return "\u0000"
    }

    Flickable {
        id: flick
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: column
            width: flick.width
            spacing: 2

            AppNavRow {
                id: allRow
                readonly property string path: ""
                c: root.c
                glyph: "notebook-pen"; label: "All notes"
                count: root.store.notes.length || ""
                selected: root.current === 0
                active: root.active
                dropTarget: root.dropPath === ""
                onClicked: { root.store.pickFolder(""); root.chosen() }
            }

            Section { visible: root.store.folders.length > 0; text: "Folders" }
            Repeater {
                id: folderRows
                model: root.store.folders
                function rows() { const r = []; for (let i = 0; i < count; i++) if (itemAt(i)) r.push(itemAt(i)); return r }
                delegate: AppNavRow {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property string path: modelData.path
                    Layout.leftMargin: 12 + 14 * modelData.depth      // a subfolder under its parent
                    c: root.c
                    glyph: selected ? "folder-open" : "folder"
                    label: modelData.name
                    count: trashButton.visible ? "" : modelData.count || ""
                    selected: root.current === 1 + index
                    active: root.active
                    dropTarget: root.dropPath === modelData.path
                    onClicked: { root.store.pickFolder(modelData.path); root.chosen() }
                    // An empty folder: under the pointer, its count gives way to taking it away
                    AppIconButton {
                        id: trashButton
                        visible: row.hovered && row.modelData.count === 0
                        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                        c: root.c; glyph: "trash-2"; hoverColor: root.c.sel
                        tip: "Remove the empty folder"; keys: "Del"; tipSide: "right"
                        onClicked: root.removeFolder(row.modelData.path)
                    }
                }
            }

            Section { visible: root.store.tags.length > 0; text: "Tags" }
            Repeater {
                model: root.store.tags
                delegate: AppNavRow {
                    required property var modelData
                    required property int index
                    c: root.c
                    glyph: "hash"
                    label: modelData.name
                    count: modelData.count
                    selected: root.current === 1 + root.store.folders.length + index
                    active: root.active
                    onClicked: { root.store.pickTag(modelData.name); root.chosen() }
                }
            }
            Item { implicitHeight: 12 }
        }
    }

    component Section: Text {
        Layout.fillWidth: true
        Layout.leftMargin: 28; Layout.topMargin: 14; Layout.bottomMargin: 4
        textFormat: Text.PlainText
        font.family: root.c.font; font.pixelSize: 11; font.weight: Font.Medium
        color: root.c.faint
    }
}
