import QtQuick
import Quickshell.Io
import qs
import qs.kit
import "Form.js" as Form

// A new event, in a panel over the window: its title, first and last day with the times (or all day), the calendar it
// goes in, where and notes. Saved by `calendar add` (lib/write.py), which writes it here and syncs it up at once; the
// panel waits for that, so what went wrong (the server, a calendar gone) is said here, where it can still be fixed.
// ⏎ in a field or Ctrl+⏎ adds it, Esc leaves it. Editing an existing event comes next (#2002), in this same panel.
AppPanel {
    id: root
    required property var app           // the window: calendars, command, today
    property string error: ""
    property bool busy: false
    property int duration: 60           // minutes from start to end, kept when the start moves
    property string lastCalendar: ""    // the one used last, picked again for the next event
    readonly property var writable: app.calendars.filter(x => !x.read_only)
    signal added(var event)             // calendar add's JSON: uid, calendar_name, title, start, when, synced…
    signal closed()
    visible: false
    // As wide as the window lets it (#2025: every panel works in a narrow window): 600, or the window less a margin
    cardWidth: Math.min(600, width - 24)
    spacing: height < 700 ? 10 : 14     // a low window: less air, so the card fits

    // dayText "YYYY-MM-DD"; hour and minute when the event starts at a clicked time
    function open(dayText, hour, minute) {
        const f = Form.blank(dayText, new Date(), hour, minute)
        title.text = ""
        startDay.text = f.startDay; startTime.text = f.startTime
        endDay.text = f.endDay; endTime.text = f.endTime
        allDay.on = false
        location.text = ""; notes.text = ""
        duration = 60
        picker.picked = writable.some(x => x.id === lastCalendar) ? lastCalendar : (writable.length ? writable[0].id : "")
        error = ""
        visible = true
        title.input.forceActiveFocus()
    }
    function close() { if (!busy) { visible = false; closed() } }

    // The fields as Form.js reads them, each day and time normalised ("" when unreadable)
    function fields() {
        const base = startDay.text
        return { title: title.text, startDay: Form.day(startDay.text, base), startTime: Form.time(startTime.text),
                 endDay: Form.day(endDay.text, base), endTime: Form.time(endTime.text), allDay: allDay.on,
                 calendar: picker.picked, location: location.text, notes: notes.text }
    }
    // A day or time field left: shown the way it was read, so "930" becomes 09:30 before the eyes
    function tidy(field, read) { const v = read(field.text); if (v) field.text = v }
    // The start moved: the end moves with it, the length kept. Without this an event moved to the afternoon would end
    // in the morning, before it starts
    function startMoved() {
        tidy(startDay, t => Form.day(t, startDay.text)); tidy(startTime, Form.time)
        const f = fields()
        if (!f.startDay || (!f.allDay && !f.startTime)) return
        const end = Form.later(f.startDay, f.allDay ? "00:00" : f.startTime, duration)
        endDay.text = end[0]
        if (!f.allDay) endTime.text = end[1]
    }
    function endMoved() {
        tidy(endDay, t => Form.day(t, startDay.text)); tidy(endTime, Form.time)
        const f = fields()
        if (!f.startDay || !f.endDay) return
        const m = f.allDay ? Form.between(f.startDay, "00:00", f.endDay, "00:00")
                           : (f.startTime && f.endTime ? Form.between(f.startDay, f.startTime, f.endDay, f.endTime) : -1)
        if (m >= 0) duration = m
    }
    function entered(field) { if (field.input.activeFocus) field.input.selectAll() }
    function toggleAllDay() {
        allDay.on = !allDay.on
        // All day keeps the days; back to times, an hour from the start's time
        duration = allDay.on ? Form.between(startDay.text, "00:00", endDay.text, "00:00") : 60
        if (!allDay.on) startMoved()
    }

    function save() {
        if (busy) return
        tidy(startDay, t => Form.day(t, startDay.text)); tidy(endDay, t => Form.day(t, startDay.text))
        tidy(startTime, Form.time); tidy(endTime, Form.time)
        const f = fields()
        error = Form.problem(f)
        if (error) {
            if (!f.title.trim()) title.input.forceActiveFocus()    // the one field everyone forgets: the keys go there
            return
        }
        lastCalendar = f.calendar
        adder.input = JSON.stringify(Form.payload(f))
        busy = true
        adder.running = true
    }

    // calendar add --json, the event on stdin: no option parsing to trip over a title that starts with "--"
    Process {
        id: adder
        property string input: ""
        command: [root.app.command, "add", "--json"]
        stdinEnabled: true
        onStarted: { write(input); stdinEnabled = false }   // the end of stdin ends its read
        stdout: StdioCollector { id: addOut }
        stderr: StdioCollector { id: addErr }
        onExited: code => {
            root.busy = false
            stdinEnabled = true
            let result = null
            if (code === 0) try { result = JSON.parse(addOut.text) } catch (e) {}
            if (!result) {
                // write.py's own words (sys.exit), the last line: the rest is a traceback, if anything
                root.error = addErr.text.trim().split("\n").pop() || "The event wasn't added: calendar log says why."
                return
            }
            root.close()
            root.added(result)
        }
    }

    onOutsideTapped: close()
    Keys.onPressed: e => {
        const ctrl = e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
        if (e.key === Qt.Key_Escape) close()
        else if (ctrl && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_S)) save()
        else return
        e.accepted = true
    }

    Text {
        text: "New event"
        color: root.c.title; font.family: root.c.font; font.pixelSize: 16; font.weight: Font.Medium
    }
    AppField {
        id: title
        c: root.c
        width: parent.width
        label: "Title"
        onAccepted: root.save()
        onEscaped: root.close()
    }
    // The first day and time, the last day and time: an all-day event hides the times. A Flow, so in a narrow panel
    // Ends goes under Starts rather than out of the card
    Flow {
        width: parent.width
        spacing: 14
        Row {
            spacing: 8
            AppField { id: startDay; c: root.c; width: 136; label: "Starts"; onAccepted: root.save(); onEscaped: root.close() }
            AppField { id: startTime; c: root.c; width: 72; visible: !allDay.on; label: "at"; onAccepted: root.save(); onEscaped: root.close() }
        }
        Row {
            spacing: 8
            AppField { id: endDay; c: root.c; width: 136; label: "Ends"; onAccepted: root.save(); onEscaped: root.close() }
            AppField { id: endTime; c: root.c; width: 72; visible: !allDay.on; label: "at"; onAccepted: root.save(); onEscaped: root.close() }
        }
    }
    // A day or time field: picked whole when the keys come to it, so typing replaces it (9:00 → 1430, not 9:001430);
    // left (Tab, a click elsewhere), tidied, and the end follows the start
    Connections { target: startDay.input; function onActiveFocusChanged() { root.entered(startDay) } function onEditingFinished() { root.startMoved() } }
    Connections { target: startTime.input; function onActiveFocusChanged() { root.entered(startTime) } function onEditingFinished() { root.startMoved() } }
    Connections { target: endDay.input; function onActiveFocusChanged() { root.entered(endDay) } function onEditingFinished() { root.endMoved() } }
    Connections { target: endTime.input; function onActiveFocusChanged() { root.entered(endTime) } function onEditingFinished() { root.endMoved() } }
    // All day: a box to tick, Space with the keys on it
    Item {
        id: allDay
        property bool on: false
        activeFocusOnTab: true
        width: dayRow.implicitWidth; height: 22
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Space) root.toggleAllDay()
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.save()
            else return
            e.accepted = true
        }
        TapHandler { onTapped: { root.toggleAllDay(); allDay.forceActiveFocus() } }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Row {
            id: dayRow
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                width: 16; height: 16; radius: 4
                color: allDay.on ? root.c.sel : "transparent"
                border.color: allDay.activeFocus ? root.c.primary : root.c.line
                Text {
                    anchors.centerIn: parent
                    visible: allDay.on
                    text: Icons.g("check"); font.family: Icons.family; font.pixelSize: 11
                    color: root.c.title
                }
            }
            Text { text: "All day"; color: root.c.text; font.family: root.c.font; font.pixelSize: 13 }
        }
    }
    CalendarPicker {
        id: picker
        c: root.c
        width: parent.width
        calendars: root.writable
        onAccepted: root.save()
        onEscaped: root.close()
    }
    AppField {
        id: location
        c: root.c
        width: parent.width
        label: "Location"
        onAccepted: root.save()
        onEscaped: root.close()
    }
    NotesField {
        id: notes
        c: root.c
        width: parent.width
        boxHeight: root.height < 700 ? 50 : 74     // a low window: the card must fit; the notes scroll with the cursor
        onSave: root.save()
        onEscaped: root.close()
    }
    // What stops it, in the danger colour: a field to fix, or the server's answer
    Text {
        textFormat: Text.PlainText
        visible: root.error !== ""
        width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
        text: root.error
        color: root.c.danger; font.family: root.c.font; font.pixelSize: 12
    }
    Row {
        anchors.right: parent.right
        spacing: 10
        AppPanelButton { c: root.c; keys: ["Esc"]; label: "Cancel"; onClicked: root.close() }
        AppPanelButton { c: root.c; keys: ["Ctrl", "Enter"]; label: root.busy ? "Adding…" : "Add"; strong: true; onClicked: root.save() }
    }
}
