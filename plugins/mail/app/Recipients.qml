import QtQuick
import qs.kit
import "addresses.js" as Addresses

// Who a message in the thread went to (#3716): one of its To, Cc and Bcc under the sender's address, by name and short
// ("Anna, Pekka and 3 more"). A click opens it: each person on a line of their own with the address as the sender's
// shows it, and with Nightdrive Contacts the card's button. Plain text, as the rest of the header (Thread.qml).
Item {
    id: root
    required property QtObject c
    required property var app
    property string label                   // "To", "Cc", "Bcc"
    property string list                    // the header as notmuch gives it
    readonly property var people: Addresses.split(list)
    property bool open: false
    // A header without a name gets the one Contacts has for the address
    function nameOf(p) {
        return p.name !== p.address || !app.book.known(p.address) ? p.name : app.book.names[p.address.toLowerCase()]
    }
    // The labels in one column, as wide as the longest of them
    readonly property int labelWidth: 34
    visible: people.length > 0
    implicitHeight: visible ? Math.max(labelText.implicitHeight, lines.implicitHeight) : 0

    Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.label; color: c.faint; font.family: c.font; font.pixelSize: 12
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.open = !root.open }
    }
    Column {
        id: lines
        x: root.labelWidth
        width: root.width - x
        spacing: 3
        // Closed: the names on one line
        Text {
            visible: !root.open
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: Addresses.summary(root.people.map(p => root.nameOf(p)))
            color: shortHover.hovered ? c.text : c.dim; font.family: c.font; font.pixelSize: 12
            HoverHandler { id: shortHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.open = true }
        }
        // Open: everyone with their address; a click on a name closes it again
        Repeater {
            model: root.open ? root.people : []
            delegate: Item {
                id: person
                required property var modelData
                readonly property bool known: app.book.known(modelData.address)
                readonly property bool hasButton: app.book.available && modelData.address.indexOf("@") > 0
                width: lines.width; height: nameText.implicitHeight
                // The name keeps at least half the line; the address gives way first
                readonly property real room: width - (hasButton ? bookButton.width + 6 : 0)
                Text {
                    id: nameText
                    textFormat: Text.PlainText
                    width: Math.min(implicitWidth, addrText.text ? Math.max(person.room / 2, person.room - addrText.implicitWidth - 8) : person.room)
                    elide: Text.ElideRight
                    text: root.nameOf(person.modelData)
                    color: c.dim; font.family: c.font; font.pixelSize: 12
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.open = false }
                }
                Text {
                    id: addrText
                    textFormat: Text.PlainText
                    anchors.left: nameText.right; anchors.leftMargin: 8; anchors.baseline: nameText.baseline
                    width: Math.max(0, Math.min(implicitWidth, person.room - nameText.width - 8))
                    elide: Text.ElideRight
                    // The name is the address when the header gave no other: then it isn't said twice
                    text: person.modelData.address !== nameText.text ? person.modelData.address : ""
                    color: c.faint; font.family: c.font; font.pixelSize: 12
                }
                AppIconButton {
                    id: bookButton
                    visible: person.hasButton
                    x: (addrText.text ? addrText.x + addrText.width : nameText.width) + 6
                    anchors.verticalCenter: nameText.verticalCenter
                    implicitWidth: 22; implicitHeight: 22
                    c: root.c
                    glyph: person.known ? "contact" : "user-plus"; glyphSize: 13; glyphColor: c.faint
                    tip: person.known ? "Open in Contacts" : "Add to contacts"
                    onClicked: person.known ? app.book.show(person.modelData.address)
                                            : app.book.add(root.nameOf(person.modelData), person.modelData.address)
                }
            }
        }
    }
}
