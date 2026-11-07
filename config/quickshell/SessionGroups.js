.pragma library
// The sessions bar's order (SessionsBar.qml): a session that opened others with `nightdrive ask` (a project manager,
// say) leads a group of them, the ones it opened right after it, joined by a line; the groups and the sessions
// nobody here opened in the order of their workspaces, with a dot between each group or lone session. Nothing is named: a lead is a session with
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

// Whether s led a group before, though its openings have all closed: kept = { addrs: { address: true }, names: [name…] }
// (Claude.qml remembers them), so a project manager stays a lead (its bot, its place, Hyper ↑/↓) while it has no sessions running
function wasLead(s, kept) {
    return !!kept && (!!(kept.addrs || {})[s.address] || (!!s.name && (kept.names || []).indexOf(s.name) >= 0))
}

// [{ lead: session, members: [session…] }] for the groups (a lead kept from before with none), then [session…] for the
// rest; each by age, oldest first, so chips keep their places as sessions come and go
function arrange(sessions, kept) {
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
        if (kids.has(r) || wasLead(r, kept)) groups.push({ lead: r, members: below(r) })
        else rest.push(r)
    }
    return { groups: groups, rest: rest, leads: new Set(kids.keys()) }   // leads: the ones with openings now
}

// Whether a opened b, however far down (so making b a's opener would close a loop)
function opens(a, b, all) {
    for (let x = openerOf(b, all), n = 0; x && n < all.length; x = openerOf(x, all), n++)
        if (x === a) return true
    return false
}

// The bar's row: { kind: "chip", session, lead } and { kind: "dot" }.
// Its units, a group or a lone session, go by workspace (a group by its lead's; ws: Claude.qml), so the bar reads like
// the workspaces; on one workspace the groups first, each by age
function row(sessions, kept) {
    const a = arrange(sessions, kept)
    const units = a.groups.map((g, i) => ({ s: g.lead, g: g, i: i }))
                   .concat(a.rest.map((s, i) => ({ s: s, g: null, i: a.groups.length + i })))
    units.sort((x, y) => (x.s.ws || 0) - (y.s.ws || 0) || x.i - y.i)
    const out = []
    for (const u of units) {
        if (out.length) out.push({ kind: "dot" })
        out.push({ kind: "chip", session: u.s, lead: !!u.g })
        if (u.g) for (const m of u.g.members) out.push({ kind: "chip", session: m, lead: a.leads.has(m) })
    }
    return out
}

// A lead's chip leaves out a trailing "Project Manager" or "PM": the bot icon and the border already say it (the
// hover card keeps the whole name)
function shortName(name) {
    return String(name || "").replace(/\s+(project\s+manager|pm)\s*$/i, "") || name
}
