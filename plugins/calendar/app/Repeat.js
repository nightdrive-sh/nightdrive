.pragma library
// A recurring event's repeat in the window (#2009): the editor's Repeat chips and Until, what `calendar add` and
// `calendar edit` take from them, and the event panel's words for it. The rules themselves are lib/repeat.py's; an
// event's repeat comes from `calendar events` as { every, interval, days, until, count, simple, text } (or null).

// The choices, as repeat.py's words: [id, chip's name, every, interval, days]
const CHOICES = [["none", "Never"], ["daily", "Every day", "day", 1, []],
                 ["weekdays", "Weekdays", "week", 1, ["MO", "TU", "WE", "TH", "FR"]],
                 ["weekly", "Every week", "week", 1, []], ["biweekly", "Every 2 weeks", "week", 2, []],
                 ["monthly", "Every month", "month", 1, []], ["yearly", "Every year", "year", 1, []]]
const DAY_NAMES = { MO: "Mon", TU: "Tue", WE: "Wed", TH: "Thu", FR: "Fri", SA: "Sat", SU: "Sun" }

// An event's repeat as a chip's id: "none", one of the choices, or "own" for a rule they don't say (the second
// Tuesday, ten times), which the editor keeps as it is. Weekly on one day is "weekly": the phone writes its start's
// day in the rule
function id(r) {
    if (!r) return "none"
    if (!r.simple || r.count) return "own"
    const days = (r.days || []).join(",")
    for (const c of CHOICES.slice(1)) {
        if (c[2] !== r.every || c[3] !== r.interval) continue
        if (days === c[4].join(",") || (c[2] === "week" && c[4].length === 0 && r.days.length <= 1)) return c[0]
    }
    return "own"
}

// The chips: the choices, and the event's own rule when it has one, so it shows and stays
function options(current, r) {
    const out = CHOICES.map(c => ({ id: c[0], name: c[1] }))
    if (current === "own") out.push({ id: "own", name: r ? words(r) : "Its own" })
    return out
}

// What add and edit take as repeat: null, a word, or the word's rule with its last day (until, "YYYY-MM-DD")
function value(chip, until) {
    if (chip === "none") return null
    const c = CHOICES.find(x => x[0] === chip)
    if (!until) return chip
    return { every: c[2], interval: c[3], days: c[4], until: until }
}

// "Every 2 weeks on Mon, Thu": the rule without its end
function words(r) {
    if (!r.simple) return r.text
    if (r.every === "week" && r.interval === 1 && (r.days || []).join(",") === "MO,TU,WE,TH,FR") return "Every weekday"
    let out = r.interval === 1 ? "Every " + r.every : "Every " + r.interval + " " + r.every + "s"
    if (r.days && r.days.length) out += " on " + r.days.map(d => DAY_NAMES[d]).join(", ")
    return out
}

// The event panel's line: its rule and end, the day the region's way (R is the kit's Regional); "Repeating" when the
// event is one time of a series whose rule isn't here
function text(r, R) {
    if (!r) return "Repeating"
    return words(r) + (r.until ? ", until " + R.format(r.until, "short") : "") + (r.count ? ", " + r.count + " times" : "")
}
