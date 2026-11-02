.pragma library
// The event editor's fields as people type them, and what `calendar add` takes from them. Kept apart from the panel so
// the rules (what a time or a day may look like, what an event needs) are in one place and the QML only shows them.
// Days are "YYYY-MM-DD" and times "HH:MM" as text, as Dates.js has them: compared as text, no time zone in between.

function pad(n) { return (n < 10 ? "0" : "") + n }

function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

// A time as typed: "9", "930", "9:30", "09.30" → "09:30"; "" when it isn't one. Without the colon it is still read,
// as the fields are small and quick typing is the point
function time(text) {
    const m = /^(\d{1,2})(?:[:.]?(\d{2}))?$/.exec((text || "").trim())
    if (!m) return ""
    const h = +m[1], min = m[2] ? +m[2] : 0
    return h > 23 || min > 59 ? "" : pad(h) + ":" + pad(min)
}

// A day as typed: "2026-11-05", or the Finnish way "5.11.2026" and "5.11." (the year of base, "YYYY-MM-DD") → ISO;
// "" when it isn't a day of the calendar (31.11. isn't)
function day(text, base) {
    const t = (text || "").trim()
    let y, mo, d, m
    if ((m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(t))) { y = +m[1]; mo = +m[2]; d = +m[3] }
    else if ((m = /^(\d{1,2})\.(\d{1,2})\.?(\d{4})?$/.exec(t))) { d = +m[1]; mo = +m[2]; y = m[3] ? +m[3] : +(base || iso(new Date())).slice(0, 4) }
    else return ""
    const x = new Date(y, mo - 1, d)
    return x.getFullYear() === y && x.getMonth() === mo - 1 && x.getDate() === d ? iso(x) : ""
}

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
// already normalised by day() and time() (an unreadable one is "")
function problem(f) {
    if (!f.title.trim()) return "An event needs a title."
    if (!f.startDay) return "The first day is 2026-11-05 or 5.11.2026."
    if (!f.endDay) return "The last day is 2026-11-05 or 5.11.2026."
    if (!f.allDay && (!f.startTime || !f.endTime)) return "A time is 9:30 or 0930."
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
