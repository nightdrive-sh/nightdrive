import QtQuick
import QtQuick.Layouts
import qs.kit

// The sidebar: the notes, newest first, each with its title and when it was saved over its first line of text. A click
// opens one; in a narrow window the list takes the whole width while it shows (shell.qml's onePane).
AppSidebar {
    id: root
    required property QtObject store
    property bool active: false          // the keys move between the notes: the open one has the kit's frame
    property bool showNew: false         // one pane: the note's header, where New is, doesn't show beside the list
    signal picked(string id)
    signal newNote()
    title: "Notes"
    titleItems: AppIconButton {
        visible: root.showNew
        c: root.c; glyph: "plus"; tip: "New note"; keys: "n"; tipAlign: "right"
        onClicked: root.newNote()
    }

    // "14:05" today, "Tue" this week, "28 Oct" this year, else "28 Oct 2025"
    function when(iso) {
        const d = new Date(iso), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm")
        if (now - d < 6 * 86400000) return Qt.formatDate(d, "ddd")
        return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy")
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        clip: true
        spacing: 2
        model: root.store.notes
        currentIndex: root.store.index
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        boundsBehavior: Flickable.StopAtBounds

        delegate: AppRow {
            id: row
            required property var modelData
            required property int index
            implicitHeight: 52
            c: root.c
            selected: index === root.store.index
            active: root.active
            TapHandler { onTapped: root.picked(row.modelData.id) }
            Column {
                anchors.left: parent.left; anchors.leftMargin: 14
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Item {
                    width: parent.width; height: titleText.implicitHeight
                    // Plain text: a title is the user's (or Claude's) data, which Qt would read as HTML if it held a tag
                    Text {
                        id: titleText
                        textFormat: Text.PlainText
                        anchors.left: parent.left; anchors.right: dateText.left; anchors.rightMargin: 8
                        elide: Text.ElideRight
                        text: row.modelData.title
                        font.family: root.c.font; font.pixelSize: 13
                        color: row.selected ? root.c.title : root.c.text
                    }
                    Text {
                        id: dateText
                        anchors.right: parent.right; anchors.baseline: titleText.baseline
                        text: root.when(row.modelData.modified)
                        font.family: root.c.font; font.pixelSize: 11; color: root.c.faint
                    }
                }
                Text {
                    textFormat: Text.PlainText
                    width: parent.width; elide: Text.ElideRight
                    text: row.modelData.excerpt || " "
                    font.family: root.c.font; font.pixelSize: 11; color: root.c.faint
                }
            }
        }
    }
}
