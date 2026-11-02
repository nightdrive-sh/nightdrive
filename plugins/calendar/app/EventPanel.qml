import QtQuick
import qs.kit
import "Dates.js" as Dates

// An event, opened from a view: its title, when, where, its calendar and notes. Read only for now: editing (#2002) and
// deleting (#2003) come here next; until then `calendar delete`, or Claude. Esc, Enter or a click outside close it.
AppPanel {
    id: root
    property var event: null
    signal closed()
    visible: false
    cardWidth: Math.min(520, width - 24)     // a narrow window (#2025): the card fits in it
    spacing: 14

    function show(e) { event = e; visible = true; forceActiveFocus() }
    function close() { visible = false; closed() }
    onOutsideTapped: close()
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) close()
        e.accepted = true
    }

    // Plain text throughout: an event can come from anyone (an invitation, a shared calendar)
    Text {
        textFormat: Text.PlainText
        width: parent.width; wrapMode: Text.Wrap
        text: root.event ? root.event.title : ""
        color: c.title; font.family: c.font; font.pixelSize: 16; font.weight: Font.Medium
    }
    Text {
        textFormat: Text.PlainText
        width: parent.width; wrapMode: Text.Wrap
        text: root.event ? Dates.span(root.event) + (root.event.recurring ? "  ·  repeats" : "") : ""
        color: c.text; font.family: c.font; font.pixelSize: 12
    }
    Text {
        textFormat: Text.PlainText
        visible: !!(root.event && root.event.location)
        width: parent.width; wrapMode: Text.Wrap
        text: root.event ? root.event.location : ""
        color: c.dim; font.family: c.font; font.pixelSize: 12
    }
    Row {
        spacing: 8
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4
            color: root.event ? root.event.color : "transparent"
        }
        Text {
            textFormat: Text.PlainText
            text: root.event ? root.event.calendar_name : ""
            color: c.dim; font.family: c.font; font.pixelSize: 12
        }
    }
    Text {
        textFormat: Text.PlainText
        visible: !!(root.event && root.event.notes)
        width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2
        maximumLineCount: 16; elide: Text.ElideRight
        text: root.event ? root.event.notes : ""
        color: c.body; font.family: c.font; font.pixelSize: 12
    }
}
