import QtQuick
import Quickshell
import "Format.js" as Format

// What the keys, the header's buttons and a drop ask of Files, over Ops (the changes) and Clip (the clipboard): each
// takes the marked files, or the picked one when none is marked (app.selection()), asks a name in the prompt when it
// needs one, and the confirm before what can't be undone (deleting from the trash). changed() hears every result and
// picks what a change made, so a pasted or new file is the one picked after.
QtObject {
    id: root
    required property var app             // the window
    required property var prompt          // AppPrompt
    required property var confirm         // AppConfirm, its answered() wired to answered() here

    function copy(isCut) {
        if (app.trashShown) return
        app.clip.copy(app.selection(), isCut)
        if (isCut) app.marks = ({})
    }
    function paste() { if (!app.trashShown) app.clip.paste(app.path) }
    function trashPicked() {
        const ps = app.selection()
        if (ps.length && !app.trashShown) { trashPaths(ps); app.marks = ({}) }
    }
    // To the trash at once, but asked first when home's own folders (Documents…), the sidebar's or home's hidden ones
    // (.config, .local…) are among them: one d away, a running desktop's settings went with no word. Home itself, the
    // folders above it and the trash are refused by lib/trash.py whatever asks.
    function kept(p) {
        const d = app.places.data
        const name = Format.base(p)
        return d.standard.indexOf(p) >= 0 || d.pinned.some(e => e.path === p) || d.bookmarks.some(e => e.path === p)
            || (Format.parent(p) === app.home && name.startsWith("."))
    }
    function trashPaths(ps) {
        const ask = ps.filter(kept)
        if (!ask.length) { app.ops.trash(ps); return }
        pending = () => app.ops.trash(ps)
        confirm.question = ps.length === 1 ? "Move “" + Format.base(ps[0]) + "” to the trash?" : "Move " + ps.length + " items to the trash?"
        confirm.detail = (ps.length === 1 ? "It is" : "Among them, " + ask.map(Format.base).join(", ") + (ask.length === 1 ? " is" : " are"))
                       + " one of home's own folders or the sidebar's. Undo or the trash puts " + (ps.length === 1 ? "it" : "them") + " back."
        confirm.action = "Move to Trash"
        confirm.visible = true
    }

    // r / F2: the name with its stem picked, so typing keeps ".pdf"
    function askRename() {
        const f = app.picked
        if (!f || app.trashShown) return
        const dot = f.dir ? -1 : f.name.lastIndexOf(".")
        prompt.ask("Rename", f.name, name => { if (name && name !== f.name) app.ops.rename(f.path, name) }, dot > 0 ? dot : -1)
    }
    // a: a file, or a folder when the name ends in "/"; ⌘⇧N and the header's button: a folder
    function askNew(isDir) {
        if (app.trashShown) return
        prompt.ask(isDir ? "New folder" : "New file (end with / for a folder)", isDir ? "New folder" : "", name => {
            if (!name) return
            const dir = isDir || name.endsWith("/")
            app.ops.create(app.path, dir ? name.replace(/\/+$/, "") : name, dir)
        })
    }
    // ⌘L: a folder by its path; ~ is home
    function askGo() {
        prompt.ask("Go to folder", app.tilde(app.path), p => {
            if (!p) return
            const full = p === "~" ? app.home : p.startsWith("~/") ? app.home + p.slice(1) : p
            app.go(full.length > 1 ? full.replace(/\/+$/, "") : full, "")
        })
    }

    // b, ⌘D: the picked folder among the bookmarks, or out of them; with a file picked, the folder on show
    function toggleBookmark() {
        if (app.trashShown) return
        const p = app.picked && app.picked.dir ? app.picked.path : app.path
        const on = !app.places.bookmarked(p)
        app.ops.run([on ? "bookmark" : "unbookmark", p], (d, why) => {
            app.say(d ? (on ? "Bookmarked " : "Bookmark removed: ") + Format.base(p) : why, !d)
            app.manager.placesChanged()
        })
    }
    // The sidebar's ✕ on one of its folders: out of its group, with Undo putting it back where it was
    function removePlace(entry) {
        const own = entry.kind === "place"
        const group = own ? app.places.pinnedRows : app.places.bookmarkRows
        const next = group[group.findIndex(e => e.path === entry.path) + 1]
        app.ops.run([own ? "unpin" : "unbookmark", entry.path], (d, why) => {
            app.manager.placesChanged()
            if (!d) { app.say(why, true); return }
            app.offer("Removed " + entry.name, () => movePlace(entry.path, own ? "places" : "bookmarks", next ? next.path : ""))
        })
    }
    // A sidebar folder dragged to another place: to group ("places" or "bookmarks"), before another of it or at its end
    function movePlace(path, group, before) {
        app.ops.run(["place-move", path, "--to", group, "--before", before], (d, why) => {
            if (!d) app.say(why, true)
            app.manager.placesChanged()
        })
    }
    function unmount(entry) {
        app.ops.run(["unmount", entry.path], (d, why) => {
            app.say(d ? entry.name + " can be taken out" : why, !d)
            if (d && (app.path === entry.path || app.path.startsWith(entry.path + "/"))) app.go(app.home, "")
            app.places.refresh()
        })
    }
    function mount(entry, then) {
        app.say("Mounting " + entry.name + "…")
        app.ops.run(["mount", entry.device], (d, why) => {
            if (!d) { app.say(why, true); return }
            app.places.refresh()
            then(d.path)
        })
    }

    // The trash's: u puts back, d deletes for good after asking, ⌘⇧⌫ and Empty empty it after asking
    function restorePicked() {
        const ids = app.selectionIds()
        if (ids.length) { app.ops.restore(ids); app.marks = ({}) }
    }
    property var pending: null
    function askDelete() {
        const ids = app.selectionIds()
        if (!ids.length) return
        pending = () => app.ops.remove(ids)
        confirm.question = ids.length === 1 ? "Delete “" + app.picked.name + "” for good?" : "Delete " + ids.length + " items for good?"
        confirm.detail = "It can't be put back."
        confirm.action = "Delete"
        confirm.visible = true
    }
    function askEmpty() {
        pending = () => app.ops.empty()
        confirm.question = "Empty the trash?"
        confirm.detail = "Everything in it is deleted for good."
        confirm.action = "Empty"
        confirm.visible = true
    }
    function answered(ok) {
        confirm.visible = false
        const run = pending
        pending = null
        if (ok && run) run()
        app.toList()
    }

    // Files dropped on the list, a folder or a sidebar row: moved when they come from this window (and not to where
    // they are), else copied; dropped on the trash, trashed
    function dropped(e, into, toTrash) {
        const ps = (e.urls || []).map(u => Format.path(u)).filter(p => p)
        if (!ps.length) return
        e.accept(Qt.CopyAction)
        if (toTrash) { trashPaths(ps); return }
        if (ps.indexOf(into) >= 0) return
        if (app.drag.ours(e)) app.ops.move(ps, into)
        else app.ops.copy(ps, into)
    }

    // A change's result: pick what it made here, and read again what it may have moved
    function changed(d) {
        if (d) {
            const made = d.made || (d.moved || []).map(m => m[0]) || []
            const here = (d.restored || []).concat(made).find(p => Format.parent(p) === app.path)
            if (here) app.keep = here
        }
        app.places.refresh()
        if (app.trashShown) app.loadTrash()
    }
}
