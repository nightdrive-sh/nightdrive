.pragma library
// Which tasks a view shows, in what order and under which headings: pure functions over cli.py's rows, so the window
// (shell.qml) only hands them the tasks and draws what comes back. view is { kind, id }: today, upcoming, list, done
// or search (every list, by the words typed).
// o: { today: "YYYY-MM-DD", query, lists: [{ id, name }], doneMax, dayLabel(day) } (dayLabel: the region's heading)

var UPCOMING_DAYS = 7     // Upcoming's day-by-day headings, Today included; what comes after is under Later

function words(query) { return (query || "").toLowerCase().split(/\s+/).filter(function (w) { return w }) }

// Every word in the title or the note, as `tasks list --query` (cli.py) and Claude's search find them
function matches(t, ws) {
    var text = (t.title + "\n" + (t.note || "")).toLowerCase()
    return ws.every(function (w) { return text.indexOf(w) >= 0 })
}

function days(today, day) { return Math.round((new Date(day + "T12:00") - new Date(today + "T12:00")) / 86400000) }

function dueToday(t, today) { return !!t.due && t.due.slice(0, 10) <= today }

// Late ones together at the top (a timed one from this morning sorts after today's all-day ones otherwise)
function lateFirst(rows) {
    return rows.filter(function (t) { return t.overdue }).concat(rows.filter(function (t) { return !t.overdue }))
}

function newestDone(tasks, max) {
    return tasks.filter(function (t) { return t.done })
        .sort(function (a, b) { return (b.completed || "").localeCompare(a.completed || "") }).slice(0, max)
}

function section(t, kind, o) {
    if (kind === "today") return t.overdue ? "Overdue" : "Today"
    if (kind === "upcoming") {
        if (t.overdue) return "Overdue"
        var day = t.due.slice(0, 10)
        return days(o.today, day) < UPCOMING_DAYS ? o.dayLabel(day) : "Later"
    }
    if (kind === "search") return t.done ? "Done" : t.list
    return ""
}

// The rows a view shows, each with its heading in `section` (ListView's sections need them together)
function rows(tasks, view, o) {
    var kind = view.kind, out
    if (kind === "done") out = newestDone(tasks, o.doneMax)
    else if (kind === "search") {
        // The open ones by list, in the sidebar's order (soonest first within one), then the newest done
        var ws = words(o.query)
        if (!ws.length) return []
        var found = tasks.filter(function (t) { return matches(t, ws) })
        var open = found.filter(function (t) { return !t.done })
        var order = o.lists.map(function (l) { return l.id })
        out = order.reduce(function (acc, id) { return acc.concat(open.filter(function (t) { return t.list_id === id })) }, [])
        out = out.concat(newestDone(found, o.doneMax))
    } else {
        out = tasks.filter(function (t) { return !t.done })
        if (kind === "today") out = lateFirst(out.filter(function (t) { return dueToday(t, o.today) }))
        else if (kind === "upcoming") out = lateFirst(out.filter(function (t) { return !!t.due }))
        else out = out.filter(function (t) { return t.list_id === view.id })
    }
    return out.map(function (t) { return Object.assign({}, t, { section: section(t, kind, o) }) })
}

// Whether a task (cli.py's row of it, after a change) shows in the view: if not, the toast says where it went
function shows(t, view, o) {
    switch (view.kind) {
    case "list": return view.id === t.list_id
    case "today": return dueToday(t, o.today) && !t.done
    case "upcoming": return !!t.due && !t.done
    case "search": return matches(t, words(o.query))
    default: return t.done
    }
}
