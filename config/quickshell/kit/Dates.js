.pragma library
// Dates and times written the region's way (Settings › Region, regions.json), and read back as people type them.
// Pure functions: the region is handed in as its entry of regions.json ({ order, short, day, medium, long, time,
// weekStart }); apps call them through the Regional singleton, which knows the current one (Regional.format(d, "short")).
// The names are always English, as the language is: Qt.formatDate would take them from the locale (LC_TIME fi_FI gives
// "marraskuu"), so the patterns are filled in here. Days travel as "YYYY-MM-DD" and times as "HH:MM", local, as text:
// that is what the apps store and compare, and what parse gives back (the date picker, #2035, builds on the same).

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                "November", "December"]
const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

function pad(n) { return (n < 10 ? "0" : "") + n }

// A Date's day as "YYYY-MM-DD", in local time
function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

// A Date from a Date, "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM" (local); null when it is none of them
function toDate(v) {
    if (v instanceof Date) return v
    const m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?/.exec(v || "")
    return m ? new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0)) : null
}

// The month's and weekday's English names, whole or in three letters
function monthName(m, short) { return short ? MONTHS[m].slice(0, 3) : MONTHS[m] }
function dayName(wd, short) { return short ? DAYS[wd].slice(0, 3) : DAYS[wd] }

// d by pattern: d dd M MM MMM MMMM yy yyyy ddd dddd H HH h hh mm AP ap; anything else is copied as it is
function pattern(v, p) {
    const d = toDate(v)
    if (!d) return ""
    const h = d.getHours()
    return p.replace(/dddd|ddd|dd|d|MMMM|MMM|MM|M|yyyy|yy|HH|H|hh|h|mm|AP|ap/g, t => {
        switch (t) {
        case "d": return "" + d.getDate()
        case "dd": return pad(d.getDate())
        case "ddd": return dayName(d.getDay(), true)
        case "dddd": return dayName(d.getDay(), false)
        case "M": return "" + (d.getMonth() + 1)
        case "MM": return pad(d.getMonth() + 1)
        case "MMM": return monthName(d.getMonth(), true)
        case "MMMM": return monthName(d.getMonth(), false)
        case "yy": return pad(d.getFullYear() % 100)
        case "yyyy": return "" + d.getFullYear()
        case "H": return "" + h
        case "HH": return pad(h)
        case "h": return "" + ((h + 11) % 12 + 1)
        case "hh": return pad((h + 11) % 12 + 1)
        case "mm": return pad(d.getMinutes())
        case "AP": return h < 12 ? "AM" : "PM"
        case "ap": return h < 12 ? "am" : "pm"
        }
        return t
    })
}

// The kinds an app asks for, by the region:
//   short  3.11.2026 · 11/3/2026 · 2026-11-03     (a field, a list's column)
//   day    3.11. · 11/3                            (a day of this year, where room is short)
//   medium 3 Nov 2026 · Nov 3, 2026
//   long   Tue 3 November 2026 · Tue, November 3, 2026
//   time   14:30 · 2:30 PM
//   month  November 2026 (the same everywhere)
// An unknown kind is taken as a pattern of its own
function format(v, kind, r) {
    if (kind === "month") return pattern(v, "MMMM yyyy")
    return pattern(v, r && r[kind] ? r[kind] : kind)
}

// A time as "HH:MM" written the region's way: "14:30" → "2:30 PM" in the US
function time(hhmm, r) {
    const m = /^(\d{1,2}):(\d{2})/.exec(hhmm || "")
    return m ? pattern(new Date(2000, 0, 1, +m[1], +m[2]), r ? r.time : "HH:mm") : ""
}

// A day as typed → "YYYY-MM-DD", or "" when it isn't a day of the calendar (31.11. isn't). Always read: ISO 2026-11-05.
// Then by the region's order (dmy 5.11.2026, 5/11/26; mdy 11/5/2026), with . / - or a space between, and without the
// year (5.11., 11/5; read in the order of the region's day) the year of base ("YYYY-MM-DD", else this year). A two-digit year is this century's
function parse(text, r, base) {
    const t = (text || "").trim().replace(/\.$/, "")
    let y, mo, d, m
    if ((m = /^(\d{4})[-./ ](\d{1,2})[-./ ](\d{1,2})$/.exec(t))) { y = +m[1]; mo = +m[2]; d = +m[3] }
    else if ((m = /^(\d{1,2})[-./ ](\d{1,2})(?:[-./ ](\d{2}|\d{4}))?$/.exec(t))) {
        // Without the year, the order of the region's own day (ISO's MM-dd is month first, Sweden's d/M not)
        const us = r && (m[3] ? r.order === "mdy" : /^M/.test(r.day))
        mo = us ? +m[1] : +m[2]
        d = us ? +m[2] : +m[1]
        y = m[3] ? (m[3].length === 2 ? 2000 + +m[3] : +m[3]) : +(base || iso(new Date())).slice(0, 4)
    } else return ""
    const x = new Date(y, mo - 1, d)
    return x.getFullYear() === y && x.getMonth() === mo - 1 && x.getDate() === d ? iso(x) : ""
}

// A time as typed → "HH:MM", or "" when it isn't one: "9", "930", "9:30", "09.30", and with am/pm "2:30 pm", "2pm"
// (in any region: a US user's 14:30 is read too). Without the colon it is still read, as quick typing is the point
function parseTime(text) {
    const m = /^(\d{1,2})(?:[:.]?(\d{2}))?\s*([ap])?\.?m?\.?$/i.exec((text || "").trim())
    if (!m) return ""
    let h = +m[1]
    const min = m[2] ? +m[2] : 0
    if (m[3]) {
        if (h < 1 || h > 12) return ""
        h = h % 12 + (m[3].toLowerCase() === "p" ? 12 : 0)
    }
    return h > 23 || min > 59 ? "" : pad(h) + ":" + pad(min)
}

// Two days as one span, the year written once: "2 – 8 Nov 2026", "30 Nov – 6 Dec 2026", "Nov 2 – 8, 2026" in the US;
// short leaves the year out ("2 – 8 Nov"). Days of different years are each written whole
function range(a, b, r, short) {
    const x = toDate(a), y = toDate(b)
    if (!x || !y) return ""
    const us = r && r.order === "mdy"
    const yr = short ? "" : (us ? ", yyyy" : " yyyy")
    if (x.getFullYear() !== y.getFullYear())
        return pattern(x, us ? "MMM d, yyyy" : "d MMM yyyy") + " – " + pattern(y, us ? "MMM d, yyyy" : "d MMM yyyy")
    if (x.getMonth() === y.getMonth())
        return us ? pattern(x, "MMM d") + " – " + pattern(y, "d" + yr) : pattern(x, "d") + " – " + pattern(y, "d MMM" + yr)
    return us ? pattern(x, "MMM d") + " – " + pattern(y, "MMM d" + yr) : pattern(x, "d MMM") + " – " + pattern(y, "d MMM" + yr)
}

// When something happened, as a list shows it beside a mail or a note: the time today ("9:30", "2:30 PM"), Yesterday,
// the weekday within the week ("Tue"), the day this year ("28.10.", "10/28"), else the whole date ("28.10.2025").
// By calendar days, not hours, so last night at 23:50 is Yesterday at 00:10. now is for tests; the apps leave it out
function relative(v, r, now) {
    const d = toDate(v)
    if (!d) return ""
    const n = now || new Date()
    const days = Math.round((new Date(n.getFullYear(), n.getMonth(), n.getDate())
                             - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000)
    if (days === 0) return pattern(d, r ? r.time : "HH:mm")
    if (days === 1) return "Yesterday"
    if (days > 1 && days < 7) return dayName(d.getDay(), true)
    return format(d, d.getFullYear() === n.getFullYear() ? "day" : "short", r)
}

// What a field's hint says to type: "5.11.2026", "11/5/2026"
function example(r) { return format(new Date(2026, 10, 5), "short", r) }

// The first day of d's week (0 Sunday, 1 Monday: the region's weekStart)
function weekStart(d, r) {
    const ws = r ? r.weekStart : 1
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() - (d.getDay() - ws + 7) % 7)
}

// The weekdays in the week's order, as numbers of Date.getDay(): [1 … 6, 0] or [0 … 6]
function weekdays(r) {
    const ws = r ? r.weekStart : 1
    const out = []
    for (let i = 0; i < 7; i++) out.push((ws + i) % 7)
    return out
}
