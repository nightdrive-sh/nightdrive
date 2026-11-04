.pragma library
// The event editor's fields, and what `calendar add` takes from them. Kept apart from the panel so the rules (what an
// event needs) are in one place and the QML only shows them. Days are "YYYY-MM-DD" and times "HH:MM" as text, as
// Dates.js has them: compared as text, no time zone in between. How a day or a time is typed and shown is the
// region's (Settings › Region): the kit's Regional.parse and Regional.format, which the panel calls.

function pad(n) { return (n < 10 ? "0" : "") + n }

function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

// [day, time] minutes after day's time: an hour past 23:30 is the next day
function later(dayText, timeText, minutes) {
    const p = dayText.split("-"), t = timeText.split(":")
    const x = new Date(+p[0], +p[1] - 1, +p[2], +t[0], +t[1] + minutes)
    return [iso(x), pad(x.getHours()) + ":" + pad(x.getMinutes())]
}

// Minutes from (day, time) to (day, time); negative when the second is before
function between(d0, t0, d1, t1) {
    const a = d0.split("-"), b = d1.split("-"), x = t0.split(":"), y = t1.split(":")
    return (new Date(+b[0], +b[1] - 1, +b[2], +y[0], +y[1]) - new Date(+a[0], +a[1] - 1, +a[2], +x[0], +x[1])) / 60000
}

// A new event's fields on dayText: from hour (and minute) when given (a click in the week's hours), else on today the
// next full hour (now is 14:20: 15:00) and on another day 09:00; an hour long
function blank(dayText, now, hour, minute) {
    let start
    if (hour !== undefined) start = pad(hour) + ":" + pad(minute || 0)
    else if (dayText === iso(now)) start = pad(Math.min(now.getHours() + 1, 23)) + ":00"
    else start = "09:00"
    const end = later(dayText, start, 60)
    return { title: "", startDay: dayText, startTime: start, endDay: end[0], endTime: end[1], allDay: false,
             calendar: "", location: "", notes: "", reminder: "none" }
}

// What is wrong with the fields, in words for the panel, or "" when the event can be added. f's days and times are
// already read by Regional.parse and parseTime (an unreadable one is ""); day and time are examples the region's way
// ("5.11.2026", "9:30" or "9:30 AM")
function problem(f, day, time) {
    if (!f.title.trim()) return "An event needs a title."
    if (!f.startDay) return "The first day is written " + day + "."
    if (!f.endDay) return "The last day is written " + day + "."
    if (!f.allDay && (!f.startTime || !f.endTime)) return "A time is written " + time + "."
    if (f.endDay < f.startDay) return "It ends before it starts."
    if (!f.allDay && between(f.startDay, f.startTime, f.endDay, f.endTime) <= 0) return "It ends before it starts."
    if (!f.calendar) return "Pick a calendar for it."
    return ""
}

// The JSON `calendar add` reads on stdin (lib/write.py): an all-day event's end is its last day, as there
function payload(f) {
    const out = { calendar: f.calendar, title: f.title.trim(),
                  start: f.allDay ? f.startDay : f.startDay + "T" + f.startTime,
                  end: f.allDay ? f.endDay : f.endDay + "T" + f.endTime }
    if (f.location.trim()) out.location = f.location.trim()
    if (f.notes.trim()) out.notes = f.notes.trim()
    if (f.reminder !== "none") out.reminder = reminderValue(f.reminder)
    return out
}

// What `calendar edit` reads on stdin (lib/change.py): every field, so an emptied location or notes is cleared there
// (payload leaves them out), and move_to only when the calendar was changed from the one the event was in. The
// reminder only when it was changed (reminderWas, a chip's id): it replaces every alarm the event has (the phone may
// have set two), so an edit of the title alone leaves them be
function edits(f, was, reminderWas) {
    const out = payload(f)
    delete out.calendar
    delete out.reminder
    if (f.reminder !== reminderWas) out.reminder = reminderValue(f.reminder)
    out.location = f.location.trim()
    out.notes = f.notes.trim()
    if (f.calendar !== was) out.move_to = f.calendar
    return out
}

// The editor's Reminder (#2006) as chips: ids are the minutes before the start as text, "none" for none (lib/alarms.py).
// An all-day event starts at its midnight, so its choices are 9:00 on the day (-540) and the day before (900), as the
// phone's; nine is nineAm, the region's way. A reminder the event has that isn't a choice (2 hours, set on the phone)
// is one more chip, so it shows and stays as it is
function reminderLabel(m) {
    if (m === 0) return "At the start"
    if (m % 1440 === 0) return m === 1440 ? "1 day" : (m / 1440) + " days"
    if (m % 60 === 0) return m === 60 ? "1 hour" : (m / 60) + " hours"
    return m + " min"
}
function reminderOptions(allDay, current, nineAm) {
    const out = [{ id: "none", name: "None" }]
    const list = allDay ? [[-540, "On the day, " + nineAm], [900, "The day before, " + nineAm]]
                        : [0, 5, 15, 60, 1440].map(m => [m, reminderLabel(m)])
    for (const x of list) out.push({ id: String(x[0]), name: x[1] })
    if (current !== "none" && !out.some(o => o.id === current))
        out.push({ id: current, name: allDay ? "Its own (" + current + " min)" : reminderLabel(+current) })
    return out
}
// calendar events' reminder (minutes, or null) as a chip's id, and back as the JSON add and edit take
function reminderId(m) { return m === null || m === undefined ? "none" : String(m) }
function reminderValue(id) { return id === "none" ? null : +id }
// The event panel's words for an event's reminder: "15 min before", "at the start", "9:00 the day before"; "" for none
function reminderText(e, nineAm) {
    const m = e.reminder
    if (m === null || m === undefined) return ""
    if (e.all_day && m === -540) return nineAm + " on the day"
    if (e.all_day && m === 900) return nineAm + " the day before"
    return m === 0 ? "at the start" : m < 0 ? reminderLabel(-m) + " after the start" : reminderLabel(m) + " before"
}
