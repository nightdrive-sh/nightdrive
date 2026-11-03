import QtQuick
import qs
import qs.kit

// m: the open note into another folder (#2016). The folders under a field: typing narrows them to those whose path has
// the text, ↑ ↓ pick one, ⏎ moves the note there; a name no folder has is offered as a new folder, made as the note
// goes in (`notes move` makes it). Esc or a click outside: nothing moves. ask(note, then): then gets the folder's path,
// "" for the top.
AppPanel {
    id: root
    required property QtObject store
    property var note: null
    property var done: null
    property int current: 0
    visible: done !== null
    cardWidth: 440
    onOutsideTapped: answer(null)
    signal closed()

    function ask(n, then) {
        note = n
        done = then
        field.text = ""
        current = 0
        field.input.forceActiveFocus()
    }
    function answer(path) {
        const d = done
        done = null
        if (path !== null && d) d(path)
        closed()
    }

    readonly property string typed: field.text.trim().replace(/^\/+|\/+$/g, "")
    // The top, then every folder; with text, those whose path has it, and the text itself as a new folder unless one is
    // named so already. The note's own folder is there, marked, but not where the highlight starts.
    readonly property var options: {
        const t = typed.toLowerCase()
        const all = [{ path: "", label: "Notes", depth: 0 }]
            .concat(store.folders.map(f => ({ path: f.path, label: f.name, depth: f.depth })))
        let shown = t ? all.filter(o => o.path.toLowerCase().includes(t)).map(o => ({ path: o.path, label: o.path, depth: 0 })) : all
        if (typed && !all.some(o => o.path.toLowerCase() === t))
            shown = shown.concat([{ path: typed, label: "New folder “" + typed + "”", depth: 0, made: true }])
        return shown
    }
    onOptionsChanged: {
        const here = note ? note.folder || "" : ""
        current = options.length > 1 && options[0].path === here && !typed ? 1 : 0
    }

    AppField {
        id: field
        c: root.c
        width: parent.width
        label: root.note ? "Move " + root.note.title + " to" : ""
        hint: "type to find, or a new name"
        keyFilter: e => {
            if (e.key === Qt.Key_Down) root.current = Math.min(root.options.length - 1, root.current + 1)
            else if (e.key === Qt.Key_Up) root.current = Math.max(0, root.current - 1)
            else return
            e.accepted = true
        }
        onAccepted: if (root.options.length) root.answer(root.options[root.current].path)
        onEscaped: root.answer(null)
    }

    ListView {
        id: list
        width: parent.width
        height: Math.min(contentHeight, 36 * 7)
        clip: true
        spacing: 2
        model: root.options
        currentIndex: root.current
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        boundsBehavior: Flickable.StopAtBounds
        delegate: AppRow {
            id: row
            required property var modelData
            required property int index
            width: list.width
            implicitHeight: 34
            c: root.c
            selected: index === root.current
            active: true
            TapHandler { onTapped: root.answer(row.modelData.path) }
            Text {
                id: glyph
                x: 12 + 14 * row.modelData.depth
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.g(row.modelData.made ? "folder-plus" : row.modelData.path ? "folder" : "notebook-pen")
                font.family: Icons.family; font.pixelSize: 14
                color: row.selected ? root.c.accent : root.c.dim
            }
            Text {
                anchors.left: glyph.right; anchors.leftMargin: 10
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                text: row.modelData.label
                    + (root.note && !row.modelData.made && row.modelData.path === (root.note.folder || "") ? "  (here)" : "")
                font.family: root.c.font; font.pixelSize: 13
                color: row.selected ? root.c.title : root.c.text
            }
        }
    }
}
