import QtQuick

// The writing window's message is saved in Drafts while it is written (#3660): a few seconds after typing stops, and
// at least every half minute while it doesn't, so a crash or Quickshell's reload (Mail runs from ~/dotfiles, and a
// save there reloads it) loses little. Nothing here takes the keyboard or waits on the typing: an edit only restarts
// a timer, and the save runs in the background (lib/compose.py).
// Every save replaces the copy before it (draft_id), so one message has one draft (#3625). Saves go one at a time,
// this window's own (⌘S, closing) too, through write(): a save started before the last one answered would replace
// the copy before that, and leave two. Send and throwing away wait for a save under way with after(), to act on the
// newest copy.
Item {
    id: auto
    required property var composer      // Compose.qml
    required property var mailer        // Notmuch.qml
    readonly property int pause: 5000   // ms after the last edit
    readonly property int most: 30000   // ms at most between an edit and its save

    property bool on: false             // while the window is open
    property bool busy: false           // a save under way
    property bool gone: false           // the draft left Drafts elsewhere (sent, thrown away, replaced by Claude)
    property int session: 0             // one per opening of the window: a late answer doesn't touch the next message
    property string saved: ""           // the fields as last saved (or as opened), draft_id left out
    property var waiting: []            // after()'s, until the save answers
    property string lastId: ""          // the copy the last save made, for which opening, and whether it was a save
    property int lastSession: 0         // while writing
    property bool lastAuto: false
    signal first()                      // a message's first copy: the main window's list shows it
    signal failed(string error)

    function snap() { const f = composer.fields(); delete f.draft_id; return JSON.stringify(f) }
    // The window opens on a message (Writing.qml has filled it): what it holds now is nothing new.
    function begin() {
        session++; saved = snap(); gone = false; composer.autoSaved = false; on = true
        quiet.stop(); due.stop()
    }
    function end() { on = false; quiet.stop(); due.stop() }
    function edited() {
        if (!on || gone) return
        quiet.restart()
        if (!due.running) due.start()
    }
    Timer { id: quiet; interval: auto.pause; onTriggered: auto.save() }
    Timer { id: due; interval: auto.most; onTriggered: auto.save() }

    function save() {
        quiet.stop(); due.stop()
        if (!on || gone) return
        if (busy) { quiet.restart(); return }
        if (snap() === saved || composer.draftId === "" && composer.untouched()) return
        const f = composer.fields(); f.autosave = true
        const firstCopy = composer.draftId === ""
        write(f, r => {
            if (r.gone) { gone = true; failed(r.error); return }
            if (r.error) { failed(r.error); return }
            if (firstCopy) first()
        })
    }

    // A save of f, replacing the copy it names (or the newest, when one was under way). done(r) gets compose.py's
    // answer, after the window's fields know the new copy.
    function write(f, done) {
        const s = session
        after(id => {
            if (id) f.draft_id = id
            const mine = !!f.autosave, before = f.draft_id || ""
            const shown = Object.assign({}, f); delete shown.draft_id; delete shown.autosave
            busy = true
            mailer.compose(["draft", JSON.stringify(f)], r => {
                busy = false
                lastId = r.error ? "" : r.id; lastSession = s; lastAuto = mine
                if (!r.error && s === session) {
                    composer.draftId = r.id; saved = JSON.stringify(shown); gone = false
                    // A copy only this file saved is still the writer's to throw away; one they saved is kept.
                    composer.autoSaved = mine && (composer.autoSaved || before === "")
                }
                done(r)
                flush()
            })
        })
    }
    // fn(id, auto) at once, or once the save under way answers: id is the copy it made ("" when none or it failed),
    // auto whether it was a save while writing. Only a copy of the message open when after() was called counts: the
    // window may have closed and opened on another meanwhile.
    function after(fn) {
        if (!busy) { fn("", false); return }
        const s = session
        waiting = waiting.concat([{ s: s, fn: fn }])
    }
    function flush() {
        while (!busy && waiting.length) {
            const w = waiting[0]; waiting = waiting.slice(1)
            const mine = w.s === lastSession
            w.fn(mine ? lastId : "", mine && lastAuto)
        }
    }

    Connections { target: auto.composer.to; function onTextChanged() { auto.edited() } }
    Connections { target: auto.composer.cc; function onTextChanged() { auto.edited() } }
    Connections { target: auto.composer.subject; function onTextChanged() { auto.edited() } }
    Connections { target: auto.composer.bodyEdit; function onTextChanged() { auto.edited() } }
    Connections {
        target: auto.composer
        function onAttachmentsChanged() { auto.edited() }
        function onAccountChanged() { auto.edited() }
    }
}
