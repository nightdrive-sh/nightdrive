import QtQuick

// A note dragged from the list onto a folder in the sidebar (#2016), as Mail drags a thread: the note's title by the
// pointer, the folder under it marked (NavSidebar.dropPath), and dropped there it moves (shell.qml's moveNote, Undo in
// the toast). Over the whole window; dropped elsewhere, or on its own folder, nothing happens.
Rectangle {
    id: root
    required property QtObject c
    required property Item sidebar          // NavSidebar: which folder lies under the pointer
    signal dropped(string id, string folder)
    property var note: null                 // the one being dragged
    property point pos
    readonly property string target: note ? sidebar.dropPath : "\u0000"

    function start(n) { note = n }
    function over(p) {
        pos = p
        const at = sidebar.visible ? sidebar.dropAt(p) : "\u0000"
        // Its own folder takes nothing
        sidebar.dropPath = note && at !== (note.folder || "") ? at : "\u0000"
    }
    function end() {
        const n = note, to = sidebar.dropPath
        note = null
        sidebar.dropPath = "\u0000"
        if (n && to !== "\u0000") dropped(n.id, to)
    }

    x: pos.x + 12; y: pos.y - height / 2
    z: 10
    visible: note !== null
    width: Math.min(320, ghostText.implicitWidth + 28); height: 34
    radius: 8
    color: c.solid
    border.color: target !== "\u0000" ? c.primary : c.line
    Text {
        id: ghostText
        textFormat: Text.PlainText
        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.note ? root.note.title : ""
        color: root.c.title; font.family: root.c.font; font.pixelSize: 12
    }
}
