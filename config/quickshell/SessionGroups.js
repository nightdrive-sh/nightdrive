.pragma library
// The sessions bar's order (SessionsBar.qml): a session that opened others with `nightdrive ask` (a project manager,
// say) leads a group of them, the ones it opened right after it, joined by a line; groups first, then the sessions
// nobody here opened, with a dot between each group or lone session. Nothing is named: a lead is a session with
// openings, whatever it's called.
// claude-sessions gives each session its opener's PID and name (terminal-or-claude records them); the PID finds it while
// it runs, the name once it has been restarted (a new PID: claude --resume, a reboot).

// The session s was opened by, among all, or null
function openerOf(s, all) {
    if (s.openerPid) {
        const o = all.find(x => x.pid === s.openerPid && x.address !== s.address)
        if (o) return o
    }
    if (s.openerName) return all.find(x => x.name === s.openerName && x.address !== s.address) || null
    return null
}

// [{ lead: session, members: [session…] }] for the groups, then [session…] for the rest; each by age, oldest first,
// so chips keep their places as sessions come and go
function arrange(sessions) {
    const byAge = sessions.slice().sort((a, b) => a.started - b.started || (a.address < b.address ? -1 : 1))
    const kids = new Map()      // opener → [sessions it opened]
    const roots = []
    for (const s of byAge) {
        const o = openerOf(s, byAge)
        if (o && !opens(s, o, byAge)) {   // a loop (two sessions with each other's name) would hide both
            if (!kids.has(o)) kids.set(o, [])
            kids.get(o).push(s)
        } else roots.push(s)
    }
    // A group: its lead and everything below it, depth first (a session opened by one of the lead's sessions follows it)
    // (a loop, not flatMap: QML's JavaScript engine has none)
    const below = s => {
        let out = []
        for (const k of kids.get(s) || []) out = out.concat([k], below(k))
        return out
    }
    const groups = [], rest = []
    for (const r of roots) {
        if (kids.has(r)) groups.push({ lead: r, members: below(r) })
        else rest.push(r)
    }
    return { groups: groups, rest: rest, leads: new Set(kids.keys()) }
}

// Whether a opened b, however far down (so making b a's opener would close a loop)
function opens(a, b, all) {
    for (let x = openerOf(b, all), n = 0; x && n < all.length; x = openerOf(x, all), n++)
        if (x === a) return true
    return false
}

// The bar's row: { kind: "chip", session, lead, linked } (linked: joined to the chip before it) and { kind: "dot" }
function row(sessions) {
    const a = arrange(sessions)
    const out = []
    const sep = () => { if (out.length) out.push({ kind: "dot" }) }
    for (const g of a.groups) {
        sep()
        out.push({ kind: "chip", session: g.lead, lead: true, linked: false })
        for (const m of g.members) out.push({ kind: "chip", session: m, lead: a.leads.has(m), linked: true })
    }
    for (const s of a.rest) { sep(); out.push({ kind: "chip", session: s, lead: false, linked: false }) }
    return out
}

// A lead's chip leaves out a trailing "Project Manager" or "PM": the bot icon and the border already say it (the
// hover card keeps the whole name)
function shortName(name) {
    return String(name || "").replace(/\s+(project\s+manager|pm)\s*$/i, "") || name
}
