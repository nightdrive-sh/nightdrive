import QtQuick
import Quickshell.Io
import qs
import qs.kit

// A new task, or a change to one, in a panel over the window: its title, the day and time it is due (either may stay
// empty), the list it goes in, Important and a note. Saved by `cli.py add --stdin` or `cli.py edit --stdin`, the same
// code Claude's and the command's changes run, so what a due may look like is decided in one place (lib/when.py); the
// panel only shows how it reads it, as it is typed ("930" → 9:30, "2pm" → 2:00 PM), and what went wrong. The day is the kit's
// AppDatePicker: typed the region's way (5.11.2026, 11/5/2026) or picked from its month grid, and sent on as ISO, so
// lib/when.py needn't know the region; a word it reads itself (today, fri, +3d) goes as typed. ⏎ in a one-line field or
// Ctrl+⏎ saves, Esc leaves it. An edit sends only the fields that were changed: one left alone (a low priority, a due
// another app wrote in its own zone) stays exactly as the file has it.
AppPanel {
    id: root
    required property var app           // the window: lists, helper
    property string error: ""
    property bool busy: false
    property string lastList: ""        // the list used last, picked again when the view isn't a list
    property string reading: ""         // the due as cli.py reads the two fields, the region's way: "Fri 6.11. 9:30"
    property bool unreadable: false
    // With no list yet, the one the first task makes (store.DEFAULT)
    readonly property var options: app.lists.length ? app.lists.map(l => ({ id: l.id, name: l.name })) : [{ id: "", name: "Tasks" }]
    property var editing: null          // the task being changed (the window's row of it), null for a new one
    property var before: ({})           // the fields as they were opened, to tell what was changed
    signal added(var task)              // cli.py's row of it: id, title, list, due_label…
    signal edited(var task)
    signal closed()
    visible: false
    // Narrower with the window: a card wider than it would be cut at both sides
    cardWidth: Math.min(560, app.width - 24)
    spacing: 14

    // listId: the list the window shows, if it shows one; day: what the day field starts with ("today" in Today)
    function open(listId, day) {
        editing = null
        const has = id => options.some(o => o.id === id)
        fill({ title: "", day: day || "", time: "", important: false, note: "",
               list: has(listId) ? listId : has(lastList) ? lastList : options[0].id })
    }
    // task: a row of the window's (id, title, due, list_id, priority, note)
    function edit(task) {
        editing = task
        const due = task.due || ""
        // The time as the region writes it ("2:30 PM" in the US), which when.py reads back as it does 14:30
        fill({ title: task.title, day: due ? Regional.format(due.slice(0, 10), "short") : "", time: Regional.time(due.slice(11, 16)),
               important: task.priority === "high", note: task.note, list: task.list_id })
    }
    function fill(f) {
        before = f
        title.text = f.title; dayField.text = f.day; timeField.text = f.time
        important.on = f.important; note.text = f.note; lists.picked = f.list
        error = ""
        visible = true
        readDue()
        title.input.forceActiveFocus()
    }
    // The day as cli.py gets it: ISO when the picker reads it as a day (the region's 11/5 isn't when.py's 11.5.),
    // else the words as typed (today, fri, +3d), which when.py reads, or says why it can't
    function dayValue() { return dayField.day || dayField.text }
    function close() { if (!busy) { visible = false; closed() } }

    // How the due fields read, a moment after the typing stops: one python start per pause, not per key
    function readDue() { reader.running = false; pause.restart() }
    Timer { id: pause; interval: 250; onTriggered: if (root.visible) reader.running = true }
    Process {
        id: reader
        command: ["python3", root.app.helper, "when", "--json", "--day", root.dayValue(), "--time", timeField.text]
        stdout: StdioCollector { id: readOut }
        stderr: StdioCollector { id: readErr }
        onExited: code => {
            let d = null
            if (code === 0) try { d = JSON.parse(readOut.text) } catch (e) {}
            root.unreadable = !d
            // cli.py reads, the window writes: the same label as the task's row will show (shell.qml dueLabel)
            root.reading = d ? (d.due ? "Due " + root.app.dueLabel(d.due) : "No due date") : readErr.text.trim().split("\n").pop()
        }
    }

    function save() {
        if (busy) return
        if (!title.text.trim()) {
            error = "A task needs a title."
            title.input.forceActiveFocus()   // the one field everyone forgets: the keys go there
            return
        }
        const out = editing ? changes() : { title: title.text.trim(), day: dayValue(), time: timeField.text,
                                            note: note.text.trim(), priority: important.on ? "high" : "normal" }
        if (!editing && lists.picked) out.list = lists.picked
        if (editing && Object.keys(out).length === 1) { close(); return }   // nothing changed: nothing to write
        lastList = lists.picked
        saver.input = JSON.stringify(out)
        saver.command = ["python3", app.helper, editing ? "edit" : "add", "--json", "--stdin"]
        busy = true
        saver.running = true
    }
    // An edit's JSON: the id, and only what differs from how it was opened
    function changes() {
        const out = { id: editing.id }
        if (title.text.trim() !== before.title.trim()) out.title = title.text.trim()
        if (dayField.text !== before.day || timeField.text !== before.time) { out.day = dayValue(); out.time = timeField.text }
        if (lists.picked !== before.list) out.list = lists.picked
        if (important.on !== before.important) out.priority = important.on ? "high" : "normal"
        if (note.text.trim() !== before.note.trim()) out.note = note.text.trim()
        return out
    }

    // The task as JSON on stdin: no option parsing to trip over a title that starts with "--"
    Process {
        id: saver
        property string input: ""
        stdinEnabled: true
        onStarted: { write(input); stdinEnabled = false }   // the end of stdin ends its read
        stdout: StdioCollector { id: addOut }
        stderr: StdioCollector { id: addErr }
        onExited: code => {
            root.busy = false
            stdinEnabled = true
            let task = null
            if (code === 0) try { task = JSON.parse(addOut.text) } catch (e) {}
            if (!task) {
                // cli.py's own words (sys.exit), the last line: the rest is a traceback, if anything
                root.error = addErr.text.trim().split("\n").pop()
                          || (root.editing ? "The change wasn't saved" : "The task wasn't added") + ": tasks log says why."
                return
            }
            const was = root.editing
            root.close()
            if (was) root.edited(task)
            else root.added(task)
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
        text: root.editing ? "Edit task" : "New task"
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
    // The day and the time, and how they read: the words are the ones the task will show. A Flow, so in a narrow
    // window the reading goes under the fields rather than being cut to nothing. The day's month grid opens on a click
    // into it, its calendar glyph or ↓, and is drawn over the window, so the panel doesn't cut it
    Flow {
        width: parent.width
        spacing: 8
        AppDatePicker {
            id: dayField
            c: root.c; width: 180            // the hint's example, ISO's the longest: "today, fri, 2026-11-05"
            base: root.app.today
            label: "Due"; hint: "today, fri, " + Regional.example
            onTextChanged: root.readDue()
            onAccepted: root.save(); onEscaped: root.close()
        }
        AppField {
            id: timeField
            c: root.c; width: 86
            label: "at"; hint: Regional.h24 ? "930" : "2pm"   // what's quickest to type; either is read anywhere
            onTextChanged: root.readDue()
            onAccepted: root.save(); onEscaped: root.close()
        }
        Item {
            width: Math.min(reading.implicitWidth, title.width)
            // Level with the fields' boxes beside them; on a line of its own (y > 0), only its own height
            height: y > 0 ? reading.implicitHeight : dayField.height
            Text {
                id: reading
                textFormat: Text.PlainText
                anchors.bottom: parent.bottom; bottomPadding: 8; leftPadding: 8
                width: parent.width
                elide: Text.ElideRight
                text: root.reading
                color: root.unreadable ? root.c.danger : root.c.dim; font.family: root.c.font; font.pixelSize: 12
            }
        }
    }
    // Picked whole when the keys come to it, so typing replaces it ("today" → "fri", not "todayfri")
    Connections { target: dayField.input; function onActiveFocusChanged() { if (dayField.input.activeFocus) dayField.input.selectAll() } }
    Connections { target: timeField.input; function onActiveFocusChanged() { if (timeField.input.activeFocus) timeField.input.selectAll() } }
    AppChips {
        id: lists
        c: root.c
        width: parent.width
        label: "List"
        options: root.options
        onAccepted: root.save()
        onEscaped: root.close()
    }
    AppCheck { id: important; c: root.c; label: "Important"; onAccepted: root.save() }
    AppTextArea {
        id: note
        c: root.c
        width: parent.width
        label: "Note"
        onSave: root.save()
        onEscaped: root.close()
    }
    // What stops it, in the danger colour: the title, a due that can't be read
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
        AppPanelButton { c: root.c; keys: ["Ctrl", "Enter"]; label: root.editing ? (root.busy ? "Saving…" : "Save") : root.busy ? "Adding…" : "Add"; strong: true; onClicked: root.save() }
    }
}
