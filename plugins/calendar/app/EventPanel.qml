import QtQuick
import qs.kit
import "Dates.js" as Dates
import "Form.js" as Form

// An event, opened from a view: its title, when, where, its calendar and notes, with Edit (e), which opens it in the
// editor, and Delete (Del, ⌫), which asks first (EventDelete). A recurring event has neither (its date line says
// Repeating: editing the series is #2009); one in a read-only calendar says why instead. Esc, Enter or a click outside
// close it.
AppPanel {
    id: root
    required property var app           // the window: its calendars, to tell a read-only one
    property var event: null
    readonly property bool readOnly: {
        if (!event) return false
        const cal = app.calendars.find(x => x.id === event.calendar)
        return !cal || cal.read_only
    }
    // No Edit or Delete here: change.py and write.py refuse the same ones. A recurring one gets no hint (#2109):
    // "Repeating" in its date line says enough
    readonly property bool fixed: !!event && (event.recurring || readOnly)
    signal closed()
    signal editRequested(var event)
    signal deleteRequested(var event)
    visible: false
    cardWidth: Math.min(520, width - 24)     // a narrow window (#2025): the card fits in it
    spacing: 14

    function show(e) { event = e; visible = true; forceActiveFocus() }
    function close() { visible = false; closed() }
    function edit() { if (event && !fixed) { const e = event; close(); editRequested(e) } }
    function remove() { if (event && !fixed) { const e = event; close(); deleteRequested(e) } }
    onOutsideTapped: close()
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) close()
        else if (e.key === Qt.Key_E) edit()
        else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) remove()
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
        text: root.event ? Dates.span(root.event, Regional) + (root.event.recurring ? "  ·  Repeating" : "") : ""
        color: c.text; font.family: c.font; font.pixelSize: 12
    }
    // Its reminder (#2006), when it has one: what the notification will say, and when
    Text {
        readonly property string said: root.event ? Form.reminderText(root.event, Regional.time("09:00")) : ""
        textFormat: Text.PlainText
        visible: said !== ""
        width: parent.width; wrapMode: Text.Wrap
        text: "Reminder " + said
        color: c.dim; font.family: c.font; font.pixelSize: 12
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
    // Why there is no Edit or Delete, in the hint's colour
    Text {
        textFormat: Text.PlainText
        visible: root.readOnly
        width: parent.width; wrapMode: Text.Wrap
        text: "Its calendar is read only here."
        color: c.dim; font.family: c.font; font.pixelSize: 12; font.italic: true
    }
    // The answers, right as the editor's. A Flow, so in a narrow card they go on two lines rather than out of it
    Flow {
        width: parent.width
        spacing: 10
        layoutDirection: Qt.RightToLeft
        AppPanelButton { c: root.c; keys: ["Esc"]; label: "Close"; onClicked: root.close() }
        AppPanelButton { c: root.c; keys: ["e"]; label: "Edit"; visible: !root.fixed; onClicked: root.edit() }
        AppPanelButton { c: root.c; keys: ["Del"]; label: "Delete"; visible: !root.fixed; onClicked: root.remove() }
    }
}
