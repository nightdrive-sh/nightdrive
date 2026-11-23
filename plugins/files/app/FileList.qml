import QtQuick
import QtQuick.Layouts
import qs.kit

// The list: the columns' titles (a click sorts by one, again turns it round, as s and S do; no line under them, the
// header's is enough), the rows (FileRow) and what an empty folder or filter says. Dropped on its free space, files
// land in the folder on show.
ColumnLayout {
    id: root
    required property QtObject c
    required property var app
    readonly property alias view: list
    spacing: 0

    // Column titles
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        Layout.leftMargin: 12; Layout.rightMargin: 12
        component Title: Text {
            property string field
            property string label
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: (field && root.app.sortBy === field ? (root.app.reversed ? "↓ " : "↑ ") : "") + label
            font.family: root.c.font; font.pixelSize: 11
            color: field && root.app.sortBy === field ? root.c.dim : root.c.faint
            TapHandler { enabled: parent.field !== ""; onTapped: root.app.sortOn(parent.field) }
            HoverHandler { cursorShape: parent.field ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        Title { x: 14; field: root.app.trashShown ? "" : "name"; label: "Name" }
        // The same widths and gaps as FileRow's columns, from the right
        Row {
            anchors.right: parent.right; anchors.rightMargin: 16
            height: parent.height
            spacing: 16
            Item {
                visible: root.app.secondWidth > 0
                width: root.app.secondWidth; height: parent.height
                Title {
                    anchors.right: root.app.trashShown ? undefined : parent.right
                    field: root.app.trashShown ? "" : "size"; label: root.app.trashShown ? "From" : "Size"
                }
            }
            Item {
                visible: root.app.thirdWidth > 0
                width: root.app.thirdWidth; height: parent.height
                Title { anchors.right: parent.right; field: root.app.trashShown ? "" : "modified"; label: root.app.trashShown ? "Deleted" : "Modified" }
            }
        }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 12; Layout.rightMargin: 12
        clip: true
        model: root.app.rows
        currentIndex: root.app.current
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        TouchScroll { view: list }
        spacing: 1
        topMargin: 4
        bottomMargin: 12
        reuseItems: true
        delegate: FileRow { c: root.c; app: root.app }

        DropArea {
            anchors.fill: parent
            z: -1
            enabled: !root.app.trashShown
            keys: ["text/uri-list"]
            onDropped: e => root.app.acts.dropped(e, root.app.path, false)
        }
        // A click on the free space below the rows takes the keys back to the list
        TapHandler { onTapped: root.app.toList() }

        EmptyNote { anchors.centerIn: parent; c: root.c; app: root.app }
    }
}
