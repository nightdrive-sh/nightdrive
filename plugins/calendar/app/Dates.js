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

// The first day of d's week: ws 1 Monday, 0 Sunday (Settings › Region, Regional.weekStart)
function weekFirst(d, ws) { return addDays(d, -((d.getDay() - ws + 7) % 7)) }

// The ISO 8601 week number of a week that starts on first: its Monday's, so a week from Sunday has the number of the
// Monday after (the US has no week numbers of its own in use)
function weekNumber(first) { return week(addDays(first, (8 - first.getDay()) % 7)) }

// ISO 8601 week number
function week(d) {
    const t = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 3 - (d.getDay() + 6) % 7)
    const first = new Date(t.getFullYear(), 0, 4)
    return 1 + Math.round(((t - first) / 86400000 - 3 + (first.getDay() + 6) % 7) / 7)
}

// The month view's 42 days: six weeks from the week's first day on or before the 1st
function monthDays(year, month, ws) {
    const start = weekFirst(new Date(year, month, 1), ws)
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

// "14:30" as it is stored, or "" for an all-day event; Regional.time writes it the region's way
function time(e) { return e.all_day ? "" : e.start.slice(11, 16) }

// The event's when, in words, the region's way (R is the kit's Regional): "Thu 29 October 2026, 14:00 – 15:00",
// "Thu, October 29, 2026, 2:00 PM – 3:00 PM", "Thu 29 October 2026, all day"
function span(e, R) {
    const s = parse(e.start), l = parse(lastDay(e))
    const date = d => R.format(d, "long")
    if (e.all_day)
        return iso(s) === iso(l) ? date(s) + ", all day" : date(s) + " – " + date(l)
    const t0 = R.time(e.start.slice(11, 16)), t1 = R.time(e.end.slice(11, 16))
    return e.start.slice(0, 10) === e.end.slice(0, 10) ? date(s) + ", " + t0 + " – " + t1
        : date(s) + " " + t0 + " – " + date(parse(e.end)) + " " + t1
}

// A day's heading in a list of days (the agenda, a search's results): Today, Tomorrow, Yesterday, else its weekday and
// date, the year only when it isn't this one's: "Thu 5 November", "Thu, November 5"; "Mon 3 May 2027". R is the kit's
// Regional, today "YYYY-MM-DD"
function heading(day, today, R) {
    const d = parse(day), t = parse(today)
    const n = Math.round((d - t) / 86400000)
    if (n === 0) return "Today"
    if (n === 1) return "Tomorrow"
    if (n === -1) return R.relative(d)      // the kit's own word for it: "Yesterday"
    const long = R.format(d, "long")
    return d.getFullYear() === t.getFullYear() ? long.replace(/,? \d{4}$/, "") : long
}

// What an agenda row says of the event's time on day: "all day", the start ("9:30"; with end, "9:30 – 10:30"), and on a
// later day of an event that began before it "until 14:00" (or all day, when it goes on past this day too)
function when(e, day, R, withEnd) {
    if (e.all_day) return "all day"
    const s = e.start.slice(0, 10), last = lastDay(e)
    if (s < day) return last > day ? "all day" : "until " + R.time(e.end.slice(11, 16))
    const t = R.time(e.start.slice(11, 16))
    return withEnd && last === day ? t + " – " + R.time(e.end.slice(11, 16)) : t
}
