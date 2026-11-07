import QtQuick
import Quickshell
import qs
import qs.kit

// A message's calendar invitation (an .ics: a meeting, a ticket's journey), as a card under its header in Thread.qml,
// when Nightdrive Calendar is installed: what it is, when (the region's way), where and from whom, and what it does to
// the calendar. A new one goes in with Add to calendar into the calendar picked; one already there opens in Calendar,
// an update (a newer version, METHOD:REQUEST) waits for Update, a cancellation (METHOD:CANCEL) for Remove: nothing
// changes in a calendar without a press. Reading and writing are `nightmail invitation` (lib/invitation.py), by
// `calendar invite`, which reads the stranger's file as data; its texts show here as plain text. Answering the
// organiser is InviteAnswer.qml's.
Rectangle {
    id: root
    required property QtObject c
    required property var app
    required property var msg            // the message: { id, invite (it has a calendar part) … }
    property var info: null              // `calendar invite --json`: title, start, end, state, existing, calendars …
    property bool busy: false
    property string failed: ""
    // In a narrow pane the buttons keep their glyphs, and say what they do as a tip
    readonly property bool narrow: width < 400
    readonly property string calendarCommand: Quickshell.shellDir + "/../../calendar/bin/calendar"
    readonly property var ex: info ? info.existing : null
    readonly property bool canWrite: ex !== null && !ex.read_only
    readonly property string state_: info ? info.state : ""
    // Which buttons: worked out here, as a child's visible reads false while its row is hidden
    readonly property bool showAdd: state_ === "new" && info.calendars.length > 0
    readonly property bool showUpdate: state_ === "changed" && canWrite
    readonly property bool showRemove: state_ === "cancelled" && canWrite

    visible: msg.invite === true && info !== null && info.state !== "reply"
    implicitHeight: col.implicitHeight + 24
    radius: 10
    color: "transparent"
    border.color: c.line

    function load() {
        if (!msg.invite) return
        app.mailer.nightmail(["invitation", msg.id], t => {
            let r
            try { r = JSON.parse(t) } catch (e) { r = { error: "No answer from Calendar" } }
            // No Calendar, or no invitation after all: no card. Another failure shows in it.
            if (r.calendar === false || r.invitation === false) { info = null; return }
            if (r.error) { failed = r.error; if (!info) info = { state: "error", title: "Invitation", calendars: [] }; return }
            failed = ""
            info = r
            const ids = r.calendars.map(x => x.id)
            if (ids.indexOf(app.inviteCalendar) < 0) app.inviteCalendar = ids.length ? ids[0] : ""
        })
    }
    Component.onCompleted: load()
    onMsgChanged: { info = null; failed = ""; load() }

    // done(r): the caller's look at the answer (InviteAnswer keeps the one sent), before the card reads it again
    function act(args, doing, done) {
        busy = true
        app.say(doing)
        app.mailer.nightmail(["invitation", msg.id].concat(args), t => {
            busy = false
            let r
            try { r = JSON.parse(t) } catch (e) { r = { error: "No answer from Calendar" } }
            app.say(r.error || r.said + (r.note ? ". " + r.note : ""))
            if (r.error) failed = r.error
            if (done) done(r)
            load()
        })
    }
    function openInCalendar() {
        Quickshell.execDetached([calendarCommand, "open-event", ex.calendar, info.uid, (info.occurrence || ex.start).slice(0, 10)])
    }

    // "Tue 10 November 2026, 10:00 – 11:00", "Fri 13 November 2026, all day", over days with both days
    function when(i) {
        if (!i || !i.start) return ""
        const day = s => Regional.format(s.slice(0, 10), "long")
        if (i.all_day) return i.start === i.end ? day(i.start) + ", all day" : day(i.start) + " – " + day(i.end)
        const t = s => Regional.time(s.slice(11, 16))
        return i.start.slice(0, 10) === i.end.slice(0, 10) ? day(i.start) + ", " + t(i.start) + " – " + t(i.end)
            : day(i.start) + " " + t(i.start) + " – " + day(i.end) + " " + t(i.end)
    }
    readonly property string said: {
        if (!info) return ""
        const where = ex ? ex.calendar_name : ""
        const changes = (info.changes || []).map(x => x === "place" ? "the place" : "the " + x).join(", ")
        switch (info.state) {
        case "added": return "In " + where + (ex.read_only ? " (read only here)" : "")
        case "changed": return "Changed" + (changes ? ": " + changes : "") + ". " + where + " has the earlier version."
        case "older": return where + " has a newer version of it."
        case "cancelled": return "Cancelled. It is still in " + where + "."
        case "gone": return "Cancelled, and not in your calendars."
        case "new": return info.calendars.length ? "" : "No calendar here takes new events."
        }
        return ""
    }

    Column {
        id: col
        x: 14; y: 12
        width: root.width - 28
        spacing: 4
        Row {
            width: parent.width
            spacing: 8
            Text {
                id: glyph
                anchors.top: parent.top; anchors.topMargin: 2
                text: Icons.g(root.info && root.info.method === "CANCEL" ? "calendar-x" : "calendar")
                font.family: Icons.family; font.pixelSize: 14
                color: root.info && root.info.method === "CANCEL" ? c.danger : c.accent
            }
            Text {
                width: parent.width - glyph.width - 8
                textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                text: root.info ? root.info.title : ""
                color: c.title; font.family: c.font; font.pixelSize: 14; font.weight: Font.DemiBold
            }
        }
        Text {
            width: parent.width; visible: text !== ""
            textFormat: Text.PlainText; wrapMode: Text.Wrap
            text: root.when(root.info) + (root.info && root.info.recurring ? "  ·  Repeating" : "")
            color: c.text; font.family: c.font; font.pixelSize: 12
        }
        Text {
            width: parent.width; visible: text !== ""
            textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            text: root.info && root.info.location ? root.info.location : ""
            color: c.text; font.family: c.font; font.pixelSize: 12
        }
        Text {
            width: parent.width; visible: text !== ""
            textFormat: Text.PlainText; elide: Text.ElideRight
            text: {
                const o = root.info ? root.info.organizer : null
                return o ? "From " + (o.name || o.address) + (o.name && o.address ? "  " + o.address : "") : ""
            }
            color: c.faint; font.family: c.font; font.pixelSize: 12
        }
        Text {
            width: parent.width; visible: text !== ""
            textFormat: Text.PlainText; wrapMode: Text.Wrap
            text: root.failed || root.said
            color: root.failed || root.info && root.info.state === "cancelled" ? c.danger
                 : root.info && root.info.state === "changed" ? c.accent : c.dim
            font.family: c.font; font.pixelSize: 12
        }
        Item { width: 1; height: 6; visible: root.showAdd || root.ex !== null }
        // Which calendar a new one goes in: the ones that take events, as Calendar's editor shows them; the pick stays
        // for the next invitation
        AppChips {
            width: parent.width
            visible: root.info !== null && root.info.state === "new" && root.info.calendars.length > 1
            c: root.c
            options: root.info ? root.info.calendars : []
            picked: root.app.inviteCalendar
            onPickedChanged: root.app.inviteCalendar = picked
        }
        Flow {
            id: actions
            width: parent.width
            spacing: 8
            visible: root.showAdd || root.showUpdate || root.showRemove || root.ex !== null
            AppButton {
                id: add
                visible: root.showAdd
                c: root.c; strong: true; glyph: "calendar-plus"
                label: root.busy ? "Adding…" : root.narrow ? "Add" : "Add to calendar"
                tip: "Add it to the calendar picked"; tipAlign: "left"
                onClicked: if (!root.busy) root.act(["--add", root.app.inviteCalendar], "Adding to the calendar…")
            }
            AppButton {
                id: update
                visible: root.showUpdate
                c: root.c; strong: true; glyph: "calendar-sync"
                label: root.busy ? "Updating…" : root.narrow ? "Update" : "Update in " + (root.ex ? root.ex.calendar_name : "")
                tip: "Change the event in your calendar as the invitation has it"; tipAlign: "left"
                onClicked: if (!root.busy) root.act(["--add", root.ex.calendar], "Updating the event…")
            }
            AppButton {
                id: remove
                visible: root.showRemove
                c: root.c; strong: true; glyph: "calendar-minus"
                label: root.busy ? "Removing…" : root.narrow ? "Remove" : "Remove from " + (root.ex ? root.ex.calendar_name : "")
                tip: "Take the cancelled event out of your calendar, and its server"; tipAlign: "left"
                onClicked: if (!root.busy) root.act(["--remove"], "Removing the event…")
            }
            AppButton {
                id: open
                visible: root.ex !== null
                c: root.c; glyph: "external-link"
                label: root.narrow ? "" : "Open in Calendar"
                tip: "Open in Calendar"; tipAlign: "left"
                onClicked: root.openInCalendar()
            }
        }
        // Accept, Maybe, Decline: a mail to the organiser, on a press (#2130)
        Item { width: 1; height: 6; visible: answer.visible }
        InviteAnswer { id: answer; width: parent.width; c: root.c; card: root }
    }
}
