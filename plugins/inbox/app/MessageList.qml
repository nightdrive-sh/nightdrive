import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// The messages, newest first, beside the sidebar: the search field (/, ⌘F), then a row each, its title and when it came
// over who sent it, with a paperclip and a count when it has files. An unread one has a dot and a brighter title, so
// what is new stands apart without a list of its own (the sidebar's Unread is that list). A click opens one; in a narrow
// window the list takes the whole width while it shows (shell.qml's onePane). While the sidebar is hidden its title is
// what the list shows (Inbox, Archive, a project), with a button to show the sidebar.
AppSidebar {
    id: root
    required property QtObject store
    readonly property alias field: field
    signal searchDone(bool clear)        // ⏎ or ↓ in the field: to the messages; Esc (clear): the search ended
    property bool active: false          // the keys move between the messages: the open one has the kit's frame
    property bool navShown: true
    signal picked(string id)
    signal showNav()
    title: navShown ? "" : store.scopeName
    contentTop: navShown ? 16 : headerHeight + 13
    headerLine: true                     // the line under the message's bar runs on under the search
    titleItems: AppIconButton {
        visible: !root.navShown
        c: root.c; glyph: "folder-tree"; tip: "Inbox, archive and senders"; keys: "f"; tipAlign: "right"
        onClicked: root.showNav()
    }

    // The region's way (Settings › Region): the time today, Yesterday, the weekday this week, then the day
    function when(iso) { return Regional.relative(new Date(iso)) }

    AppSearchField {
        id: field
        Layout.fillWidth: true
        Layout.leftMargin: 28; Layout.rightMargin: 20
        Layout.bottomMargin: root.navShown ? 29 : 10    // beside the sidebar, its first message level with Inbox
        c: root.c
        pixelSize: 13
        placeholder: "Search " + root.store.scopeName.toLowerCase()
        onEdited: searchDelay.restart()
        onReturnPressed: { root.store.setSearch(text); root.searchDone(false) }
        onDownPressed: root.searchDone(false)
        onEscapePressed: root.searchDone(true)
    }
    // The command is asked again as the words are typed, a moment after the last key
    Timer { id: searchDelay; interval: 250; onTriggered: root.store.setSearch(field.text) }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        clip: true
        spacing: 2
        model: root.store.messages
        currentIndex: root.store.index
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        boundsBehavior: Flickable.StopAtBounds

        delegate: AppRow {
            id: row
            required property var modelData
            required property int index
            readonly property bool unread: !modelData.read
            implicitHeight: 54
            c: root.c
            selected: index === root.store.index
            active: root.active
            TapHandler { onTapped: root.picked(row.modelData.id) }
            // The unread dot, in the theme's colour, in the margin before the title
            Rectangle {
                visible: row.unread
                x: 6; y: 15
                width: 6; height: 6; radius: 3
                color: root.c.primary
            }
            Column {
                anchors.left: parent.left; anchors.leftMargin: 18
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Item {
                    width: parent.width; height: titleText.implicitHeight
                    // Plain text: a title is a sender's data, which Qt would read as HTML if it held a tag
                    Text {
                        id: titleText
                        textFormat: Text.PlainText
                        anchors.left: parent.left; anchors.right: dateText.left; anchors.rightMargin: 8
                        elide: Text.ElideRight
                        text: row.modelData.title
                        font.family: root.c.font; font.pixelSize: 13
                        font.weight: row.unread ? Font.DemiBold : Font.Normal
                        color: row.selected || row.unread ? root.c.title : root.c.dim
                    }
                    Text {
                        id: dateText
                        anchors.right: parent.right; anchors.baseline: titleText.baseline
                        text: root.when(row.modelData.updated || row.modelData.at)
                        font.family: root.c.font; font.pixelSize: 11
                        color: row.unread ? root.c.primary : root.c.faint
                    }
                }
                Item {
                    width: parent.width; height: fromText.implicitHeight
                    Text {
                        id: fromText
                        textFormat: Text.PlainText
                        anchors.left: parent.left; anchors.right: extras.left; anchors.rightMargin: 8
                        elide: Text.ElideRight
                        text: row.modelData.sender.short
                        font.family: root.c.font; font.pixelSize: 11; color: root.c.faint
                    }
                    // Files and buttons it has, as glyphs: what is in it before it is opened
                    Row {
                        id: extras
                        anchors.right: parent.right; anchors.verticalCenter: fromText.verticalCenter
                        spacing: 6
                        Text {
                            visible: row.modelData.attachments > 0
                            text: Icons.g("paperclip") + " " + row.modelData.attachments
                            font.family: Icons.family; font.pixelSize: 11; color: root.c.faint
                        }
                        Text {
                            visible: row.modelData.actions > 0
                            text: Icons.g("square-mouse-pointer")
                            font.family: Icons.family; font.pixelSize: 11; color: root.c.faint
                        }
                    }
                }
            }
        }
        Text {
            visible: root.store.loaded && !root.store.messages.length
            anchors.horizontalCenter: parent.horizontalCenter; y: 24
            width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.store.error ? root.store.error
                : root.store.search.trim() ? "No message has " + root.store.search.trim()
                : root.store.view === "archive" ? "Nothing archived yet."
                : root.store.view === "unread" ? "Nothing unread."
                : "Nothing here yet."
            font.family: root.c.font; font.pixelSize: 12; color: root.store.error ? root.c.danger : root.c.faint
        }
    }
}
