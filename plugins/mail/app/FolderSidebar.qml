import QtQuick
import QtQuick.Layouts
import qs.kit

// The folders, with each one's unread count (✓ under the pointer marks them all read), the accounts at the foot and the
// fetch and outbox signs by the title. Apart from shell.qml, which places it first in the window's row.
//
// The title's line and the search's are as high (headerHeight) and as far from the top, so the first
// folder and the first message line up.
AppSidebar {
    id: sidebar
    required property var win
    required property var ops           // Actions.qml
    required property var panes
    required property var outbox
    required property bool fetching
    signal settings()
    Layout.preferredWidth: win.width < 900 ? 168 : 208
    z: 1        // a folder's tip lies over the list
    visible: win.showFolders
    c: win.look
    title: "Mail"
    headerHeight: 2 * 18 + win.headerHeight
    contentTop: 18 + win.headerHeight + win.headerGap
    bottomMargin: 0     // the account bar's line reaches the foot (AccountBar.qml)
    Repeater {
        id: folderRows
        model: win.folders
        // The same glyphs as the reading pane's buttons
        delegate: AppNavRow {
            id: folderRow
            required property var modelData
            required property int index
            c: win.look
            glyph: modelData.glyph
            label: modelData.name
            selected: index === win.folder
            dropTarget: index === ops.dropFolder
            count: !readButton.visible && win.unreadCounts[index] > 0 ? win.unreadCounts[index] : ""
            countColor: c.dim
            active: panes.at === "folders"     // Tab's (Panes.qml)
            onClicked: win.pickFolder(index)
            // Under the pointer, the unread count gives way to ✓: mark all read
            AppIconButton {
                id: readButton
                visible: folderRow.hovered && win.unreadCounts[folderRow.index] > 0
                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                c: win.look
                glyph: "check-check"
                hoverColor: c.sel
                tip: "Mark all read"; keys: "⇧U"; tipSide: "right"
                onClicked: { ops.markAllRead(folderRow.index); win.list.forceActiveFocus() }
            }
        }
    }
    Item { Layout.fillHeight: true }
    AccountBar {
        c: win.look
        accounts: win.accounts
        current: win.acct
        unread: win.inboxUnread
        onPicked: i => { win.pickAccount(i); win.list.forceActiveFocus() }
    }
    SidebarHead {
        parent: sidebar     // over the sidebar's title, outside its column
        c: win.look; outbox: sidebar.outbox
        fetching: sidebar.fetching
        headerHeight: sidebar.headerHeight
        onSettings: sidebar.settings()
    }

    // The folder under a thread dragged from the list (pos in the window), if takes(i) says it takes it, else -1
    function dropAt(pos, takes) {
        let at = -1
        for (let i = 0; i < win.folders.length; i++) {
            const f = folderRows.itemAt(i)
            if (f && takes(i) && f.contains(f.mapFromItem(null, pos.x, pos.y))) at = i
        }
        return at
    }
}
