import QtQuick
import QtQuick.Layouts
import qs.kit

// The sidebar: the search field (/, ⌘F), then the notes, newest first, each with its title and when it was saved over its
// first line of text; while a search is on, the notes it found, each over the first line where the words are. A click
// opens one; in a narrow window the list takes the whole width while it shows (shell.qml's onePane). Its title is the
// folder or tag picked (NavSidebar.qml), and while that sidebar is hidden a button by it shows it. A row dragged sideways
// goes to a folder there (NoteDrag.qml).
AppSidebar {
    id: root
    required property QtObject store
    required property QtObject search    // NoteSearch
    readonly property alias field: field
    signal searchDone(bool clear)        // ⏎ or ↓ in the field: to the notes found; Esc (clear): the search ended
    property bool active: false          // the keys move between the notes: the open one has the kit's frame
    property bool showNew: false         // one pane: the note's header, where New is, doesn't show beside the list
    property bool navShown: true         // the folders and tags beside it
    required property QtObject drag      // NoteDrag
    signal picked(string id)
    signal newNote()
    signal showNav()
    // Beside the folders, the one picked shows there, and the search field takes the title's line; without them the
    // title says which folder or tag the list is
    title: navShown ? "" : store.scopeName
    contentTop: navShown ? 16 : headerHeight + 13
    headerLine: true                     // the line under the note's header runs on under the search (or the title)
    titleItems: [
        AppIconButton {
            visible: !root.navShown
            c: root.c; glyph: "folder-tree"; tip: "Folders and tags"; keys: "f"; tipAlign: "right"
            onClicked: root.showNav()
        },
        AppIconButton {
            visible: root.showNew
            c: root.c; glyph: "plus"; tip: "New note"; keys: "n"; tipAlign: "right"
            onClicked: root.newNote()
        }
    ]

    // The region's way (Settings › Region): "14:05" today, Yesterday, "Tue" this week, "28.10." this year, else the whole date
    function when(iso) { return Regional.relative(new Date(iso)) }

    AppSearchField {
        id: field
        Layout.fillWidth: true
        Layout.leftMargin: 28; Layout.rightMargin: 20
        Layout.bottomMargin: root.navShown ? 29 : 10    // beside the folders, its first note level with All notes
        c: root.c
        pixelSize: 13
        placeholder: "Search notes"
        onEdited: root.search.query = text
        onReturnPressed: root.searchDone(false)
        onDownPressed: root.searchDone(false)
        onEscapePressed: root.searchDone(true)
    }
    // The search's count, or why it found nothing
    Text {
        visible: root.search.active && !!root.search.found && (root.search.found.length > 0 || root.search.error !== "")
        Layout.fillWidth: true
        Layout.leftMargin: 28; Layout.rightMargin: 20; Layout.bottomMargin: 6
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: !root.search.found ? "" : root.search.error
            || (root.store.shown.length === 1 ? "1 note" : root.store.shown.length + " notes")
        font.family: root.c.font; font.pixelSize: 11
        color: root.search.error ? root.c.danger : root.c.faint
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        clip: true
        spacing: 2
        model: root.store.shown
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
            // Dragged (towards the folders) it moves; the wheel still scrolls the list
            DragHandler {
                target: null
                grabPermissions: PointerHandler.TakeOverForbidden
                cursorShape: Qt.ClosedHandCursor
                onActiveChanged: if (active) root.drag.start(row.modelData); else root.drag.end()
                onCentroidChanged: if (active) root.drag.over(centroid.scenePosition)
            }
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
                    // Found: the first line with the words, without its list, quote or heading mark
                    text: (row.modelData.lines && row.modelData.lines.length
                           ? row.modelData.lines[0].replace(/^([-*+>]|\d+[.)]|#{1,6})\s+(\[[ xX]\]\s+)?/, "")
                           : row.modelData.excerpt) || " "
                    font.family: root.c.font; font.pixelSize: 11; color: root.c.faint
                }
            }
        }
        // A folder or tag with no notes (a new folder, or a search that found none in it)
        Text {
            visible: root.store.loaded && !root.store.shown.length && root.store.notes.length > 0
                     && !(root.search.active && root.search.found !== null && !root.search.found.length)
            anchors.horizontalCenter: parent.horizontalCenter; y: 24
            width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.search.active ? "None of them in " + root.store.scopeName
                : root.store.scopeTag ? "No note has " + root.store.scopeName
                : "No notes in " + root.store.scopeName + " yet.\nNew (n) writes one here; drag one here from All notes."
            font.family: root.c.font; font.pixelSize: 12; font.weight: Font.Normal; color: root.c.faint
        }
        Text {
            visible: root.search.active && root.search.found !== null && !root.search.found.length && !root.search.error
            anchors.horizontalCenter: parent.horizontalCenter; y: 24
            width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: "No note has " + root.search.query.trim()
            font.family: root.c.font; font.pixelSize: 12; color: root.c.faint
        }
    }
}
