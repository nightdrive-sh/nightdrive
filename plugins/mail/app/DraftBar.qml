import QtQuick
import qs.kit
import "twins.js" as Twins

// Under a draft in the thread: Continue writing (this draft, in the writing window), and when the draft has a twin
// (twins.js: another draft answering the same message, or a reply to it already sent, #3625) a warning saying so, with
// Move to Trash, as the draft left behind is usually the one not to send. ⌘Z brings it back (Actions.trashDraft).
Column {
    id: bar
    required property QtObject c
    required property var app           // fullDate
    required property var msg           // the draft
    required property var messages      // its thread
    signal resume()
    signal trash()
    spacing: 8

    readonly property string warning: Twins.warning(Twins.twins(messages, msg.parent, msg.id), ts => app.fullDate(ts))

    Text {
        visible: bar.warning !== ""
        width: Math.min(implicitWidth, bar.parent ? bar.parent.width : implicitWidth)
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: bar.warning
        color: bar.c.danger
        font.family: bar.c.font; font.pixelSize: 12
    }
    Row {
        spacing: 8
        DraftButton { c: bar.c; label: "Continue writing"; keys: "⏎"; onClicked: bar.resume() }
        DraftButton { c: bar.c; visible: bar.warning !== ""; label: "Move to Trash"; onClicked: bar.trash() }
    }

    // An inline component doesn't see this file's ids: the look comes in as c
    component DraftButton: Rectangle {
        id: button
        required property QtObject c
        property string label
        property string keys: ""
        signal clicked()
        implicitWidth: row.implicitWidth + 28
        implicitHeight: 34
        radius: 8
        color: hover.hovered ? button.c.hover : "transparent"
        border.color: button.c.line
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: button.clicked() }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            KeyCap { visible: button.keys !== ""; anchors.verticalCenter: parent.verticalCenter; c: button.c; keys: button.keys }
            Text { anchors.verticalCenter: parent.verticalCenter; text: button.label; color: button.c.accent; font.family: button.c.font; font.pixelSize: 12 }
        }
    }
}
