import QtQuick
import Quickshell.Io
import qs
import qs.kit
import "Form.js" as Form
import "kit/Dates.js" as KitDates

// A new event, or one being changed, in a panel over the window: its title, first and last day with the times (or all
// day), the calendar it goes in, where and notes. Saved by `calendar add` (lib/write.py) or `calendar edit`
// (lib/change.py), which write it here and sync it up at once; the panel waits for that, so what went wrong (the server,
// a calendar gone) is said here, where it can still be fixed. ⏎ in a field or Ctrl+⏎ saves, Esc leaves it.
AppPanel {
    id: root
    required property var app           // the window: calendars, command, today
    property string error: ""
    property bool busy: false
    property int duration: 60           // minutes from start to end, kept when the start moves
    property string lastCalendar: ""    // the one used last, picked again for the next event
    property var editing: null          // the event being changed (calendar events' JSON), null for a new one
    readonly property int timeWidth: Regional.h24 ? 72 : 88   // "12:30 PM" needs more than "12:30"
    readonly property var writable: app.calendars.filter(x => !x.read_only)
    signal saved(var event, bool edited) // calendar add's or edit's JSON: uid, calendar_name, title, when, synced…
    signal closed()
    visible: false
    // As wide as the window lets it (#2025: every panel works in a narrow window): 600, or the window less a margin
    cardWidth: Math.min(600, width - 24)
    spacing: height < 700 ? 10 : 14     // a low window: less air, so the card fits

    // dayText "YYYY-MM-DD"; hour and minute when the event starts at a clicked time
    function open(dayText, hour, minute) {
        const f = Form.blank(dayText, new Date(), hour, minute)
        editing = null
        title.text = ""
        startDay.text = showDay(f.startDay); startTime.text = showTime(f.startTime)
        endDay.text = showDay(f.endDay); endTime.text = showTime(f.endTime)
        allDay.on = false
        location.text = ""; notes.text = ""
        duration = 60
        picker.picked = writable.some(x => x.id === lastCalendar) ? lastCalendar : (writable.length ? writable[0].id : "")
        error = ""
        visible = true
        title.input.forceActiveFocus()
    }
    // An event of calendar events, its fields as they are: an all-day event's end is its last day there, as here
    function edit(e) {
        editing = e
        title.text = e.title
        allDay.on = e.all_day
        startDay.text = showDay(e.start.slice(0, 10)); startTime.text = e.all_day ? "" : showTime(e.start.slice(11, 16))
        endDay.text = showDay(e.end.slice(0, 10)); endTime.text = e.all_day ? "" : showTime(e.end.slice(11, 16))
        location.text = e.location || ""; notes.text = e.notes || ""
        duration = e.all_day ? Form.between(e.start.slice(0, 10), "00:00", e.end.slice(0, 10), "00:00")
                             : Form.between(e.start.slice(0, 10), e.start.slice(11, 16), e.end.slice(0, 10), e.end.slice(11, 16))
        picker.picked = e.calendar
        error = ""
        visible = true
        title.input.forceActiveFocus()
    }
    function close() { if (!busy) { visible = false; closed() } }

    // The days and times are shown and typed the region's way (Settings › Region: 5.11.2026 14:30, 11/5/2026 2:30 PM)
    // and kept as Form.js has them ("YYYY-MM-DD", "HH:MM"): the kit's Regional writes and reads them
    function showDay(iso) { return iso ? Regional.format(iso, "short") : "" }
    function showTime(hhmm) { return hhmm ? Regional.time(hhmm) : "" }
    // A day typed without its year (5.11.) is in the start's year, the start's in this one
    function readDay(text) { return Regional.parse(text, Regional.parse(startDay.text) || app.today) }
    // The fields as Form.js reads them, each day and time normalised ("" when unreadable)
    function fields() {
        return { title: title.text, startDay: readDay(startDay.text), startTime: Regional.parseTime(startTime.text),
                 endDay: readDay(endDay.text), endTime: Regional.parseTime(endTime.text), allDay: allDay.on,
                 calendar: picker.picked, location: location.text, notes: notes.text }
    }
    // A day or time field left: shown the way it was read, so "930" becomes 09:30 and "5.11." 5.11.2026 before the eyes
    function tidyDay(field) { const v = readDay(field.text); if (v) field.text = showDay(v) }
    function tidyTime(field) { const v = Regional.parseTime(field.text); if (v) field.text = showTime(v) }
    // The region changed while the panel is open (Settings › Region): the days typed the old way are read that way and
    // shown the new way, or 5.11.2026 would turn into May 11 in the US
    property string shownRegion: Regional.key
    Connections {
        target: Regional
        function onKeyChanged() {
            const was = Regional.table[root.shownRegion]
            root.shownRegion = Regional.key
            if (!root.visible || !was) return
            const base = KitDates.parse(startDay.text, was, root.app.today) || root.app.today
            for (const f of [startDay, endDay]) { const v = KitDates.parse(f.text, was, base); if (v) f.text = root.showDay(v) }
            for (const f of [startTime, endTime]) { const v = Regional.parseTime(f.text); if (v) f.text = root.showTime(v) }
        }
    }
    // The start moved: the end moves with it, the length kept. Without this an event moved to the afternoon would end
    // in the morning, before it starts
    function startMoved() {
        tidyDay(startDay); tidyTime(startTime)
        const f = fields()
        if (!f.startDay || (!f.allDay && !f.startTime)) return
        const end = Form.later(f.startDay, f.allDay ? "00:00" : f.startTime, duration)
        endDay.text = showDay(end[0])
        if (!f.allDay) endTime.text = showTime(end[1])
    }
    function endMoved() {
        tidyDay(endDay); tidyTime(endTime)
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
        const f = fields()
        duration = allDay.on && f.startDay && f.endDay ? Form.between(f.startDay, "00:00", f.endDay, "00:00") : 60
        if (!allDay.on) startMoved()
    }

    function save() {
        if (busy) return
        tidyDay(startDay); tidyDay(endDay); tidyTime(startTime); tidyTime(endTime)
        const f = fields()
        error = Form.problem(f, Regional.example, Regional.h24 ? "9:30 or 0930" : "9:30 AM or 2pm")
        if (error) {
            if (!f.title.trim()) title.input.forceActiveFocus()    // the one field everyone forgets: the keys go there
            return
        }
        busy = true
        if (editing) {
            writer.command = [app.command, "edit", "--json", editing.calendar, editing.uid]
            writer.input = JSON.stringify(Form.edits(f, editing.calendar))
        } else {
            lastCalendar = f.calendar
            writer.command = [app.command, "add", "--json"]
            writer.input = JSON.stringify(Form.payload(f))
        }
        writer.running = true
    }

    // calendar add or edit --json, the event on stdin: no option parsing to trip over a title that starts with "--"
    Process {
        id: writer
        property string input: ""
        stdinEnabled: true
        onStarted: { write(input); stdinEnabled = false }   // the end of stdin ends its read
        stdout: StdioCollector { id: writeOut }
        stderr: StdioCollector { id: writeErr }
        onExited: code => {
            root.busy = false
            stdinEnabled = true
            let result = null
            if (code === 0) try { result = JSON.parse(writeOut.text) } catch (e) {}
            if (!result) {
                // write.py's own words (sys.exit), the last line: the rest is a traceback, if anything
                root.error = writeErr.text.trim().split("\n").pop()
                             || (root.editing ? "The event wasn't changed" : "The event wasn't added") + ": calendar log says why."
                return
            }
            const edited = !!root.editing
            root.close()
            root.saved(result, edited)
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
        text: root.editing ? "Edit event" : "New event"
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
    // The first day and time, the last day and time: an all-day event hides the times. A day is typed or picked from
    // the kit's month grid (a click, or ↓). A Flow, so in a narrow panel
    // Ends goes under Starts rather than out of the card
    Flow {
        width: parent.width
        spacing: 14
        Row {
            spacing: 8
            AppDatePicker { id: startDay; c: root.c; width: 136; label: "Starts"; base: root.app.today
                            onPicked: root.startMoved(); onAccepted: root.save(); onEscaped: root.close() }
            AppField { id: startTime; c: root.c; width: root.timeWidth; visible: !allDay.on; label: "at"; onAccepted: root.save(); onEscaped: root.close() }
        }
        Row {
            spacing: 8
            AppDatePicker { id: endDay; c: root.c; width: 136; label: "Ends"; base: startDay.day || root.app.today
                            onPicked: root.endMoved(); onAccepted: root.save(); onEscaped: root.close() }
            AppField { id: endTime; c: root.c; width: root.timeWidth; visible: !allDay.on; label: "at"; onAccepted: root.save(); onEscaped: root.close() }
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
        AppPanelButton { c: root.c; keys: ["Ctrl", "Enter"]; strong: true
                         label: root.editing ? (root.busy ? "Saving…" : "Save") : (root.busy ? "Adding…" : "Add"); onClicked: root.save() }
    }
}
