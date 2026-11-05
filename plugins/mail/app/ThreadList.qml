import QtQuick
import QtQuick.Layouts
import qs.kit

// The thread list's column: the search, the list (ThreadRow.qml, its keys in ListKeys.qml), Empty Trash (or Spam) and
// the quiet line for what just happened. Apart from shell.qml, which places it between the folders and the open thread.
//
// In one pane it fills the window, and while the thread shows it is there at no width: it keeps the keyboard, so j k
// and the rest go on working from the thread.
Rectangle {
    id: root
    required property var win
    required property var ops           // Actions.qml
    required property var writer        // Writing.qml
    required property var panes
    required property var sheet
    required property var reader
    readonly property QtObject c: win.look
    readonly property alias list: list
    readonly property alias search: search
    ListKeys { id: keys; win: root.win; ops: root.ops; writer: root.writer; panes: root.panes; sheet: root.sheet; reader: root.reader }
    Layout.preferredWidth: win.onePane ? (win.readerOpen ? 0 : -1) : Math.max(250, Math.min(370, win.width * 0.3 - 30))
    Layout.fillWidth: win.onePane && !win.readerOpen
    Layout.fillHeight: true
    clip: true
    color: "transparent"
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        AppSearchField {
            id: search
            Layout.fillWidth: true
            Layout.margins: 28
            Layout.topMargin: 16    // centred between the window's top and the line below
            // Held to the line's height, so the glyph doesn't push the list down
            Layout.preferredHeight: win.headerHeight
            Layout.bottomMargin: 0
            c: win.look
            pixelSize: 13
            onEdited: searchDelay.restart()
            onEscapePressed: { text = ""; win.reload(false); list.forceActiveFocus() }
            onReturnPressed: list.forceActiveFocus()
            onDownPressed: list.forceActiveFocus()
            Timer { id: searchDelay; interval: 150; onTriggered: win.reload(false) }
        }
        // Under the search, level with the line under the thread's buttons (the last pixel of Thread.barHeight)
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: reader.barHeight - 1 - search.Layout.topMargin - win.headerHeight
            Layout.preferredHeight: 1
            color: c.divider
        }
        ListView {
            id: list
            Layout.fillWidth: true
            // The view itself is inset: ListView places its delegates at x 0.
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.fillHeight: true
            clip: true
            model: win.threads
            currentIndex: win.current
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            TouchScroll { view: list }
            spacing: 2
            // The rest of the gap under the search, so the first message is level with the first folder
            topMargin: 18 + win.headerHeight + win.headerGap - reader.barHeight
            bottomMargin: 12
            focus: true
            Keys.onPressed: e => keys.pressed(e)
            delegate: ThreadRow { win: root.win; ops: root.ops; writer: root.writer; panes: root.panes }
            Text {
                visible: win.threads.length === 0
                anchors.centerIn: parent
                text: "Nothing here"; color: c.faint; font.family: c.font; font.pixelSize: 12
            }
        }
        // In Trash or Spam: emptying it, which asks first
        AppKeyAction {
            readonly property string dir: win.folders[win.folder].dir
            Layout.leftMargin: 28
            Layout.topMargin: 8
            Layout.bottomMargin: 24
            visible: (dir === "Trash" || dir === "Spam") && win.threads.length > 0
            c: win.look
            keys: "⌘⇧⌫"; label: "Empty " + dir; hoverColor: c.danger
            onClicked: ops.emptyFolder()
        }
    }
    Rectangle { visible: !win.onePane; anchors.right: parent.right; width: 1; height: parent.height; color: c.divider }
}
