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
             calendar: "", location: "", notes: "" }
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
    return out
}

// What `calendar edit` reads on stdin (lib/change.py): every field, so an emptied location or notes is cleared there
// (payload leaves them out), and move_to only when the calendar was changed from the one the event was in
function edits(f, was) {
    const out = payload(f)
    delete out.calendar
    out.location = f.location.trim()
    out.notes = f.notes.trim()
    if (f.calendar !== was) out.move_to = f.calendar
    return out
}
