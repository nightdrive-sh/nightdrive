.pragma library
// Notifications as the popups and the menu show them (#1982): an app's notifications in one stack, newest on top, and
// a pinned one (critical, or hint x-nightdrive-pin: Claude's permission requests) on its own, never in a stack.
// A row is Notifs.qml's history row: app, group (its stack's key), pinned, uid.

// The stack a row goes in: its app, or the app and the sender's own group (hint x-nightdrive-group: Claude's sessions
// apart from its changes). A newline joins them, as in a row's tag, so no app's name can be mistaken for one.
function key(app, group) { return group ? app + "\n" + group : app }

// The stack's name in its header: "Claude · sessions"
function label(k) { return String(k || "").replace("\n", " · ") }

// rows (newest first) → units [{ key, pinned, rows }]: each pinned one that alone(row) says is still pending on its own,
// first, then a stack per group, in the order of their newest row
function units(rows, alone) {
    const pins = [], stacks = [], at = {}
    for (const r of rows) {
        if (r.pinned && alone(r)) { pins.push({ key: "pin\n" + r.uid, pinned: true, rows: [r] }); continue }
        const k = r.group || r.app || ""
        if (at[k] === undefined) { at[k] = stacks.length; stacks.push({ key: k, pinned: false, rows: [] }) }
        stacks[at[k]].rows.push(r)
    }
    return pins.concat(stacks)
}

// The popups to keep (newest first, items { uid, entry }): at most `max` units on screen and `perStack` cards in a
// stack; the oldest go first (into the history only), a pinned one never
function trim(popups, max, perStack) {
    const us = units(popups.map(p => p.entry), r => true)
    const keep = {}
    let room = Math.max(0, max - us.filter(u => u.pinned).length)
    for (const u of us) {
        if (!u.pinned && room-- <= 0) continue
        for (const r of u.pinned ? u.rows : u.rows.slice(0, perStack)) keep[r.uid] = true
    }
    return popups.filter(p => keep[p.uid])
}
