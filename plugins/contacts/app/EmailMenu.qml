import QtQuick
import qs

// Send email's addresses, under the button, when the contact has more than one (as the Mac's Contacts asks): each line's
// label and address; ↑ ↓ or the pointer pick, Return or a click sends to it, Esc or a click away leaves it. Focus goes
// back to where it came from (the list or the card), whose keys it takes for as long as it is open.
FocusScope {
    id: root
    required property QtObject c
    property var emails: []             // [{label, value}], from cards.py
    property bool open: false
    property int pick: 0
    property Item back: null            // what had the keys before it opened
    signal chosen(string address)
    visible: open
    implicitWidth: 300; implicitHeight: menu.implicitHeight + 8

    function show(list) {
        emails = list; pick = 0; back = Window.activeFocusItem; open = true
        root.forceActiveFocus()
    }
    function close() {
        open = false
        if (back) back.forceActiveFocus()
    }
    function choose(i) {
        const address = emails[i].value
        close()
        chosen(address)
    }
    Keys.onPressed: e => {
        const k = e.key
        if (k === Qt.Key_Down || k === Qt.Key_J) pick = Math.min(emails.length - 1, pick + 1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) pick = Math.max(0, pick - 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) choose(pick)
        else if (k === Qt.Key_Escape || k === Qt.Key_W) close()
        e.accepted = true     // the list's and the card's keys wait until it closes
    }
    onActiveFocusChanged: if (!activeFocus && open) open = false

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.c.solid
        border.color: root.c.line
        Column {
            id: menu
            x: 4; y: 4
            width: parent.width - 8
            Repeater {
                model: root.emails
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: menu.width; height: 30; radius: 5
                    color: index === root.pick ? root.c.sel : rowHover.hovered ? root.c.hover : "transparent"
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.pick = parent.index }
                    TapHandler { onTapped: root.choose(parent.index) }
                    Text {
                        id: label
                        textFormat: Text.PlainText
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.label || "email"
                        color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
                    }
                    Text {
                        id: address
                        textFormat: Text.PlainText
                        anchors.left: label.right; anchors.leftMargin: 10
                        anchors.right: parent.right; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: parent.modelData.value
                        color: parent.index === root.pick ? root.c.title : root.c.text; font.family: root.c.font; font.pixelSize: 13
                    }
                }
            }
        }
    }
}
