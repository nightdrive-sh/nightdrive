import QtQuick
import QtQuick.Layouts
import qs.kit

// The folders, with each one's unread count (✓ under the pointer marks them all read, and in Spam and Trash a bin beside
// it empties them), the accounts at the foot and the fetch and outbox signs by the title. Apart from shell.qml, which
// places it first in the window's row.
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
    bottomMargin: 0     // the account bar's line reaches the foot (AppAccountBar)
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
            // Under the pointer, the unread count gives way to ✓: mark all read. In Spam and Trash the bin beside it
            // empties the folder (it asks first), so the two lie side by side, the bin outermost.
            AppIconButton {
                id: emptyButton
                readonly property string dir: folderRow.modelData.dir
                visible: folderRow.hovered && (dir === "Spam" || dir === "Trash")
                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                c: win.look
                glyph: "trash-2"
                hoverColor: c.sel       // as ✓ beside it: the confirm panel is the warning
                tip: "Empty " + dir; keys: "⌘⇧⌫"; tipSide: "right"
                onClicked: ops.emptyDir(dir)
            }
            AppIconButton {
                id: readButton
                visible: folderRow.hovered && win.unreadCounts[folderRow.index] > 0
                anchors.right: emptyButton.visible ? emptyButton.left : parent.right
                anchors.rightMargin: emptyButton.visible ? 2 : 6
                anchors.verticalCenter: parent.verticalCenter
                c: win.look
                glyph: "check-check"
                hoverColor: c.sel
                tip: "Mark all read"; keys: "⇧U"; tipSide: "right"
                onClicked: { ops.markAllRead(folderRow.index); win.list.forceActiveFocus() }
            }
        }
    }
    Item { Layout.fillHeight: true }
    AppAccountBar {
        c: win.look
        accounts: win.accounts     // compose.py accounts: their addresses
        current: win.acct
        counts: win.inboxUnread    // the inboxes' unread threads
        onPicked: i => { win.pickAccount(i); win.list.forceActiveFocus() }
    }

    // At the title's right: Settings' gear, only while the pointer is on the line (⌘, and launcher › Settings › Apps ›
    // Mail open Settings too, so it needn't take room all the time), a spinner while mail is fetched (FetchWatch.qml)
    // and the sending badge (SendStatus.qml)
    titleItems: [
        AppIconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: sidebar.titleHovered
            implicitWidth: 22       // a narrow sidebar (168 px) has just room for "Mail█", the gear and "Not sent"
            c: win.look
            glyph: "settings"; glyphColor: c.faint
            tip: "Settings"; keys: "⌘,"; tipAlign: "right"
            onClicked: sidebar.settings()
        },
        Spinner {
            anchors.verticalCenter: parent.verticalCenter
            c: win.look
            running: sidebar.fetching
            tip: "Fetching mail"; tipAlign: "right"
        },
        SendStatus {
            anchors.verticalCenter: parent.verticalCenter
            c: win.look; outbox: sidebar.outbox
            frame: sidebar      // its card starts at the sidebar's left
        }
    ]

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
