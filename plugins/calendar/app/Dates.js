.pragma library
// Days and times for Calendar's views. The events come from `calendar events` with local times as text,
// "YYYY-MM-DDTHH:MM", or days, "YYYY-MM-DD" (an all-day event's end is its last day), and are compared as such: the
// same text sorts and compares as the time it is, with no time zone to go wrong in between.

function pad(n) { return (n < 10 ? "0" : "") + n }

// A Date's day as "YYYY-MM-DD", in local time
function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

// "YYYY-MM-DD" (or the day of "YYYY-MM-DDTHH:MM") to a local Date at midnight
function parse(text) {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(text || "")
    return m ? new Date(+m[1], +m[2] - 1, +m[3]) : new Date()
}

function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }

// The Monday of d's week (weeks start on Monday, as the top bar's calendar)
function monday(d) { return addDays(d, -((d.getDay() + 6) % 7)) }

// ISO 8601 week number
function week(d) {
    const t = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 3 - (d.getDay() + 6) % 7)
    const first = new Date(t.getFullYear(), 0, 4)
    return 1 + Math.round(((t - first) / 86400000 - 3 + (first.getDay() + 6) % 7) / 7)
}

// The month view's 42 days: six weeks from the Monday on or before the 1st
function monthDays(year, month) {
    const start = monday(new Date(year, month, 1))
    const out = []
    for (let i = 0; i < 42; i++) out.push(addDays(start, i))
    return out
}

// The day an event ends on: an all-day event's end is its last day already; a timed one ending at 00:00 ends the day
// before (a party till midnight isn't on the next day too)
function lastDay(e) {
    if (e.all_day) return e.end.slice(0, 10)
    if (e.end.slice(11) === "00:00" && e.end.slice(0, 10) > e.start.slice(0, 10)) return iso(addDays(parse(e.end), -1))
    return e.end.slice(0, 10)
}

// Whether the event is on day ("YYYY-MM-DD")
function onDay(e, day) { return e.start.slice(0, 10) <= day && lastDay(e) >= day }

// An event that fills the day's top row in the week view: all day, or over more than one day
function spansDays(e) { return e.all_day || lastDay(e) > e.start.slice(0, 10) }

// Minutes from midnight of "YYYY-MM-DDTHH:MM" on day: 0 if it began before, 24 * 60 if it ends after
function minutes(text, day) {
    if (text.slice(0, 10) < day) return 0
    if (text.slice(0, 10) > day) return 24 * 60
    return +text.slice(11, 13) * 60 + +text.slice(14, 16)
}

// "14:30", or "" for an all-day event
function time(e) { return e.all_day ? "" : e.start.slice(11, 16) }

// The event's when, in words: "Thu 29 October, 14:00 – 15:00", "29 – 31 October", "All day"
function span(e) {
    const s = parse(e.start), l = parse(lastDay(e))
    const date = d => Qt.formatDate(d, "ddd d MMMM yyyy")
    if (e.all_day)
        return iso(s) === iso(l) ? date(s) + ", all day" : date(s) + " – " + date(l)
    const t0 = e.start.slice(11, 16), t1 = e.end.slice(11, 16)
    return e.start.slice(0, 10) === e.end.slice(0, 10) ? date(s) + ", " + t0 + " – " + t1
        : date(s) + " " + t0 + " – " + date(parse(e.end)) + " " + t1
}
