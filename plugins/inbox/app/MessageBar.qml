import QtQuick
import qs.kit

// The bar over the open message, as Notes' over a note: Archive (or, in the archive, back to the inbox), Unread and
// Delete, the names shown while they all fit, else the glyphs alone with their tips. In one pane a back button to the
// list first. As high as the sidebars' headers, so the line under it runs on under their titles and the search.
Item {
    id: root
    required property QtObject c
    property bool onePane: false
    property var message: null           // Store.message
    property int margin: 40
    signal back()
    signal archive()
    signal toggleRead()
    signal remove()
    height: 62
    readonly property var actions: !message ? [] : [
        message.archived
            ? { id: "archive", glyph: "archive-restore", label: "Back to Inbox", strong: true, tip: "Back to the inbox", keys: "e" }
            : { id: "archive", glyph: "archive", label: "Archive", strong: true, tip: "Done with it: to the archive", keys: "e" },
        message.read
            ? { id: "read", glyph: "mail", label: "Unread", tip: "Mark unread", keys: "u" }
            : { id: "read", glyph: "mail-open", label: "Read", tip: "Mark read", keys: "u" },
        { id: "delete", glyph: "trash-2", label: "Delete", tip: "Delete for good", keys: "Del" }
    ]
    function act(id) {
        if (id === "archive") archive()
        else if (id === "read") toggleRead()
        else if (id === "delete") remove()
    }
    readonly property real start: onePane ? backButton.x + backButton.width + 8 : margin - 10
    readonly property bool labels: fullRow.implicitWidth + 14 <= width - start

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.c.divider }

    // Measured with their names, as Notes' bar is
    Row {
        id: fullRow
        visible: false
        spacing: 2
        Repeater { model: root.actions; delegate: AppBarButton { required property var modelData; c: root.c; glyph: modelData.glyph; label: modelData.label } }
    }
    AppIconButton {
        id: backButton
        visible: root.onePane
        anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
        c: root.c; glyph: "arrow-left"; tip: "The messages"; keys: "Esc"; tipAlign: "left"
        onClicked: root.back()
    }
    Row {
        x: root.onePane ? Math.max(root.start, (root.width - width) / 2) : root.start
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Repeater {
            model: root.actions
            delegate: AppBarButton {
                required property var modelData
                c: root.c; glyph: modelData.glyph; label: modelData.label; compact: !root.labels; strong: !!modelData.strong
                tip: modelData.tip; keys: modelData.keys
                onClicked: root.act(modelData.id)
            }
        }
    }
}
