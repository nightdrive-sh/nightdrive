import QtQuick

// Writing: a new message, a reply (or one Claude drafts), a forward or a draft taken up again, in the writing window
// (ComposeWindow.qml), then sending it (Outbox.qml) or saving it in Drafts. Apart from shell.qml, which holds the main
// window; this is the part between the open thread and the writing window.
QtObject {
    required property var win
    required property var composeWin
    required property var outbox
    readonly property var composer: composeWin.composer
    readonly property var nm: win.mailer

    // Writing: mode "new", "reply" (to the sender), "all", "claude" (a reply Claude drafts) or "forward", all on the
    // thread's last message, or "resume" to write on the thread's draft. The thread is the open one, or msgs (a
    // message window's).
    function compose(mode, msgs, fields) {
        const all = msgs || win.messages
        if (composeWin.visible) return
        if (mode === "new") {
            // From the account shown, with its signature under the text
            const f = Object.assign({}, fields || {}, { account: win.account.id })
            if (win.account.signature) f.body = (f.body || "") + "\n\n" + win.account.signature
            composer.start("New message", f); showCompose(); return
        }
        if (mode === "resume") {
            const d = draft(all)
            if (!d) return
            nm.compose(["resume", d.id], r => {
                if (r.error) { win.say(r.error); return }
                composer.start("Draft", r)
                // A reply's draft keeps ⌘⇧C, when the message it answers is here.
                const answers = r.in_reply_to.replace(/[<>\s]/g, "")
                if (answers && all.some(m => m.id === answers)) composer.replyId = answers
                showCompose()
            })
            return
        }
        const last = all.filter(m => !m.draft).pop()
        if (!last) return
        if (mode === "forward") {
            nm.compose(["forward", last.id], r => {
                if (r.error) { win.say(r.error); return }
                composer.start("Forward", r)
                composer.forwardId = last.id
                showCompose()
            })
            return
        }
        nm.compose(["reply", last.id].concat(mode === "reply" ? [] : ["all"]), r => {
            if (r.error) { win.say(r.error); return }
            composer.start(mode === "reply" ? "Reply to sender" : "Reply", r)
            composer.replyId = last.id
            showCompose()
            if (mode === "claude") composer.rewrite()
        })
    }
    // mailto:a@b?cc=…&subject=…&body=… as the writing window's fields (RFC 6068)
    function mailtoFields(url) {
        const m = url.replace(/^mailto:/i, "").split("?")
        const f = { to: decodeURIComponent(m[0] || "") }
        for (const kv of (m[1] || "").split("&")) {
            const i = kv.indexOf("="), k = kv.slice(0, i).toLowerCase()
            if (i > 0 && ["to", "cc", "subject", "body"].indexOf(k) >= 0) {
                const v = decodeURIComponent(kv.slice(i + 1).replace(/\+/g, " "))
                f[k] = k === "to" && f.to ? f.to + ", " + v : v
            }
        }
        return f
    }
    // The addresses to complete from are read again each time, so the newest are there.
    function showCompose() {
        composeWin.opening = true; composeWin.visible = true
        win.book.load()
        nm.addresses(list => composer.book = win.book.merge(list.filter(a => !win.accounts.some(x => x.address === a.address))))
    }
    // The open thread's draft, newest first, if it has one.
    function draft(msgs) { return (msgs || win.messages).filter(m => m.draft).pop() }


    // Claude writes the reply (Compose.qml asks): the desktop's Claude writes card opens in the middle of the writing
    // window and runs compose.py through `nightmail claude-draft`: the thread up to the message answered with the
    // draft, or the selected text alone. Its Enter comes back through claudeAnswer().
    function suggest(request) {
        nm.nightmail(["ask-claude", composeWin.title, JSON.stringify(request)],
                     t => { if (t.trim()) { try { composer.failed = true; composer.status = JSON.parse(t).error } catch (e) {} } })
    }

    // Send closes the writing window at once; the message goes in the background (Outbox.qml).
    function sendMail(f) {
        outbox.send(f, composer.heading, composer.replyId, composer.forwardId)
        composeWin.done = true; composeWin.visible = false
    }

    // ⌘S, or closing a message saved before: the copy in Drafts is replaced with this one.
    function saveDraft(f, close) {
        if (close) { composeWin.done = true; composeWin.visible = false }
        nm.compose(["draft", JSON.stringify(f)], r => {
            if (r.error) { composer.failed = true; composer.status = r.error; if (close) composeWin.visible = true; return }
            if (!close) { composer.draftId = r.id; composer.failed = false; composer.status = "Saved in Drafts" }
            win.reload(true)
            if (close) composeEnded()
        })
    }
    function dismissCompose() { composeWin.done = true; composeWin.visible = false; composeEnded() }
    // The writing window is closed, and its draft saved: Mail started for it alone quits with it, once what it
    // sends has gone (or failed and waits in Drafts).
    function composeEnded() { if (!win.visible && !composeWin.visible && !outbox.jobs.length) Qt.quit() }
}
