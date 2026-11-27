import QtQuick
import Quickshell
import Quickshell.Io
import "blanks.js" as Blanks
import "flowed.js" as Flowed
import "order.js" as Order

// The only part that talks to notmuch, and the only Quickshell import besides the window:
// a later native host replaces this file and keeps the same functions.
QtObject {
    id: nm

    readonly property Component proc: Component {
        Process {
            id: p
            property var done: null
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    if (p.done) p.done(text)
                    p.destroy()
                }
            }
        }
    }

    function run(args, done) {
        proc.createObject(nm, { command: ["notmuch"].concat(args), done: done })
    }

    // A read that comes back with no JSON is tried again (tries times, retryMs apart): while notmuch new indexes a big
    // sync, or a tag is written, a reader can fail (Xapian's DatabaseModifiedError) and print nothing. Then parse(t)
    // throws, and done gets fallback only after the last try.
    readonly property int tries: 4
    readonly property int retryMs: 400
    readonly property Component later: Component { Timer { running: true; onTriggered: destroy() } }
    function json(args, parse, fallback, done, left) {
        run(args, t => {
            let v
            try { v = parse(t) } catch (e) {
                if ((left ?? tries) > 1) {
                    const timer = later.createObject(nm, { interval: retryMs })
                    timer.triggered.connect(() => json(args, parse, fallback, done, (left ?? tries) - 1))
                } else {
                    console.warn("notmuch " + args[0] + " failed: " + e + (t.trim() === "" ? " (no output)" : ""))
                    done(fallback)
                }
                return
            }
            done(v)
        })
    }

    // Threads matching the query, newest first, each with attachments: true when a message in it has a file attached.
    function search(query, done) {
        json(["search", "--format=json", "--limit=500", query],
             t => JSON.parse(t).map(x => Object.assign(x, { subject: oneLine(x.subject), authors: authors(x.authors) })),
             [], rows => attachments(rows, done))
    }

    // notmuch tags a message "attachment" when a part of it is sent as one (signature and other inline pictures
    // aren't), but an invitation's invite.ics is one too: a message whose only files are calendar ones doesn't count,
    // unless a PDF (an agenda) came with it. The same query is in lib/browse.py (FILES), for `nightmail search`.
    readonly property string files: "tag:attachment and not ((mimetype:application/ics or mimetype:text/calendar)"
                                    + " and not mimetype:application/pdf)"
    // Only the threads already tagged are asked about (a few dozen ids, ~25 ms), so a folder of thousands costs the
    // same. If notmuch can't answer, the tag alone decides.
    function attachments(rows, done) {
        const maybe = rows.filter(r => r.tags.indexOf("attachment") >= 0)
        for (const r of rows) r.attachments = false
        if (!maybe.length) { done(rows); return }
        json(["search", "--format=json", "--output=threads",
              "(" + maybe.map(r => "thread:" + r.thread).join(" or ") + ") and " + files],
             t => JSON.parse(t), null, ids => {
                 for (const r of maybe) r.attachments = !ids || ids.indexOf(r.thread) >= 0
                 done(rows)
             })
    }

    // notmuch lists the authors of the messages the query matched, then "| " and the rest's (e.g. your own reply in
    // Sent): the list shows them all as one list, each name once.
    function authors(s) {
        const names = []
        for (const n of (s || "").split(/\s*[,|]\s*/))
            if (n && names.indexOf(n) < 0) names.push(n)
        return names.join(", ")
    }

    // Some senders fold a header with stray spaces or end it in line breaks, which keeps a Text from eliding it.
    function oneLine(s) {
        return (s || "").replace(/\s+/g, " ").trim()
    }

    // The thread's messages by date, oldest first and without deleted drafts (order.js), each { from, to, cc, bcc, date,
    // subject, tags, body } with the body as plain text.
    function show(thread, done) {
        json(["show", "--format=json", "--include-html", "--entire-thread=true", "thread:" + thread],
             t => { const out = []; flatten(JSON.parse(t), out); return Order.order(out) }, [], list => unflow(list, done))
    }

    // A format=flowed text's paragraphs joined (flowed.js, #3321). notmuch's JSON leaves Content-Type's parameters
    // out, so lib/flowed.py reads the header from the file, for the messages whose text looks flowed (a line ending
    // in a space goes on in the next): most mail isn't asked about. If it can't answer, the lines stay as they are.
    readonly property string flowReader: composer.replace(/compose\.py$/, "flowed.py")
    function unflow(list, done) {
        const maybe = list.filter(m => m.flowable)
        for (const m of list) delete m.flowable
        if (!maybe.length) { done(list); return }
        // (reduce, not flatMap: Qt's engine has no flatMap)
        const pairs = maybe.reduce((a, m) => a.concat([m.id, m.file]), [])
        proc.createObject(nm, { command: ["python3", flowReader].concat(pairs), done: t => {
            let r = {}
            try { r = JSON.parse(t) } catch (e) {}
            for (const m of maybe)
                if (r[m.id] !== undefined) m.body = Blanks.tidy(plainText(Flowed.unflow(m.plain, r[m.id])))
            for (const m of maybe) { delete m.plain; delete m.file }
            done(list)
        } })
    }

    // Mail's own command (bin/nightmail), e.g. for Claude's card: its output as text.
    function nightmail(args, done) {
        proc.createObject(nm, { command: [Quickshell.shellDir + "/../bin/nightmail"].concat(args), done: done })
    }

    // The writing side (lib/compose.py): every command answers with one JSON object.
    // lib/ is beside Mail's config (app/), where Qt.resolvedUrl doesn't reach: Quickshell keeps URLs inside the config
    readonly property string composer: Quickshell.shellDir + "/../lib/compose.py"
    function compose(args, done) {
        proc.createObject(nm, { command: ["python3", composer].concat(args), done: t => {
            let r
            try { r = JSON.parse(t) } catch (e) { r = { error: t.trim() || "No answer from compose.py" } }
            done(r)
        } })
    }

    // Moves a query's messages to a folder of their account (lib/move.py), e.g. "Trash".
    readonly property string mover: composer.replace(/compose\.py$/, "move.py")
    // from: the folders the files may move from ("account/INBOX"); a message's files elsewhere stay
    function move(folder, query, from, done) {
        proc.createObject(nm, { command: ["python3", mover, folder, query].concat(from), done: t => {
            let r
            try { r = JSON.parse(t) } catch (e) { r = { error: t.trim() } }
            if (done) done(r)
        } })
    }

    // Deletes a query's messages in Trash (or folder: "Spam") for good (lib/erase.py); done gets { erased } or { error }.
    readonly property string eraser: composer.replace(/compose\.py$/, "erase.py")
    function erase(query, from, done, folder) {
        proc.createObject(nm, { command: ["python3", eraser, "--folder", folder || "Trash", query].concat(from), done: t => {
            let r
            try { r = JSON.parse(t) } catch (e) { r = { error: t.trim() || "No answer from erase.py" } }
            done(r)
        } })
    }

    // An attachment of a message being read (lib/parts.py): "open" copies it where it can be opened from, "save" to
    // the downloads folder (never over a file there: "name (2).pdf"). done gets { path } or { error }.
    readonly property string parter: composer.replace(/compose\.py$/, "parts.py")
    function part(cmd, msgid, part, name, done) {
        proc.createObject(nm, { command: ["python3", parter, cmd, msgid, String(part), name], done: t => {
            let r
            try { r = JSON.parse(t) } catch (e) { r = { error: t.trim() || "No answer from parts.py" } }
            done(r)
        } })
    }

    // The message's HTML as a page for the browser, with nothing in it that loads from the network; done gets
    // { path } or { error }.
    function page(msgid, done) {
        proc.createObject(nm, { command: ["python3", parter, "html", msgid], done: t => {
            let r
            try { r = JSON.parse(t) } catch (e) { r = { error: t.trim() || "No answer from parts.py" } }
            done(r)
        } })
    }

    // All of a message's attachments ({ part, name }) to the downloads folder; done gets { paths } or { error }.
    function saveAll(msgid, files, done) {
        const pairs = files.reduce((a, f) => a.concat([String(f.part), f.name]), [])
        proc.createObject(nm, { command: ["python3", parter, "save-all", msgid].concat(pairs), done: t => {
            let r
            try { r = JSON.parse(t) } catch (e) { r = { error: t.trim() || "No answer from parts.py" } }
            done(r)
        } })
    }

    // Show in folder: the folder the saved files are in, with them picked, in the file manager (parts.py show)
    function showSaved(paths) { proc.createObject(nm, { command: ["python3", parter, "show"].concat(paths), done: t => {} }) }

    // Files to attach, from the desktop's file picker; done gets their paths (none when cancelled).
    function pick(done) {
        proc.createObject(nm, { command: ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Attach files"],
                                done: t => done(t.split("\n").filter(p => p !== "")) })
    }

    // Everyone in the mail, for completing To and Cc: { name, address, nameAddr }, the most written with first.
    function addresses(done) {
        run(["address", "--format=json", "--output=sender", "--output=recipients", "--output=count", "--deduplicate=address", "*"], t => {
            let list = []
            try { list = JSON.parse(t) } catch (e) {}
            done(list.filter(a => a.address.indexOf("@") > 0)
                     .sort((a, b) => b.count - a.count)
                     .map(a => ({ name: a.name, address: a.address, nameAddr: a["name-addr"] })))
        })
    }

    function tag(changes, query, done) {
        run(["tag"].concat(changes, ["--", query]), () => { if (done) done() })
    }

    // notmuch nests a thread as [[message, [replies]]]; walk it in the tree's order (show() then sorts it by date).
    // parent: the message a reply answers (its In-Reply-To), for twins.js
    function flatten(node, out, parent) {
        if (!Array.isArray(node)) return
        for (const n of node) {
            if (Array.isArray(n) && n.length === 2 && n[0] && n[0].headers) {
                out.push(message(n[0], parent || ""))
                flatten(n[1], out, n[0].id)
            } else {
                flatten(n, out, parent)
            }
        }
    }

    function message(m, parent) {
        const parts = { plain: "", html: "", files: [], invite: false }
        collect(m.body || [], parts, "")
        const file = Array.isArray(m.filename) ? m.filename[0] : m.filename
        const flowable = parts.plain !== "" && !!file && Flowed.maybe(parts.plain)
        return {
            id: m.id,
            from: m.headers.From || "",
            to: m.headers.To || "",
            // Who else it went to (Recipients.qml); Bcc only where the copy kept it, as a sent message's may
            cc: m.headers.Cc || "",
            bcc: m.headers.Bcc || "",
            subject: oneLine(m.headers.Subject),
            timestamp: m.timestamp,
            tags: m.tags || [],
            parent: parent || "",
            draft: (m.filename || []).some(f => /\/Drafts\/(cur|new)\//.test(f)),
            sent: (m.filename || []).some(f => /\/Sent\/(cur|new)\//.test(f)),
            gone: Order.deletedDraft(m.tags, m.filename),   // for order(), which leaves it out and takes this off
            // Blank lines tidied for reading (blanks.js): a newsletter's runs of empty and NBSP lines become one
            body: Blanks.tidy(parts.plain !== "" ? plainText(parts.plain) : htmlToText(parts.html)),
            html: parts.html !== "" ? safeHtml(parts.html) : "",
            files: parts.files,     // attachments: { part, name, size } (size in bytes, or -1)
            invite: parts.invite,   // a calendar invitation in it: Invitation.qml reads it by Calendar
            // For unflow() only, which takes them off: the raw text and its file, when it may be format=flowed
            flowable: flowable,
            plain: flowable ? parts.plain : undefined,
            file: flowable ? file : undefined
        }
    }

    // The first plain and HTML text, and the attachments: parts sent as attachments or with a file name. Pictures an
    // HTML text points at (in multipart/related, with a Content-ID) belong to the HTML and are left out.
    function collect(list, parts, parent) {
        for (const part of list) {
            const type = (part["content-type"] || "").toLowerCase()
            if (Array.isArray(part.content)) { collect(part.content, parts, type); continue }
            // An invitation's own text/calendar part (in multipart/alternative, no file name), or an .ics attached
            if (type === "text/calendar" || type === "application/ics" || /\.ics$/i.test(part.filename || "")) parts.invite = true
            if (part["content-disposition"] === "attachment" || part.filename && type.indexOf("text/") !== 0) {
                if (parent === "multipart/related" && part["content-id"] && part["content-disposition"] !== "attachment") continue
                parts.files.push({ part: part.id, name: part.filename || "attachment", size: part["content-length"] || (part.content || "").length || -1 })
            }
            else if (type === "text/plain" && parts.plain === "") parts.plain = part.content || ""
            else if (type === "text/html" && parts.html === "") parts.html = part.content || ""
            else if (part.filename) parts.files.push({ part: part.id, name: part.filename, size: part["content-length"] || -1 })
        }
    }

    // HTML for Qt's rich text: no scripts, styles or head, and nothing that loads from the sender's server (and tells
    // it the message was opened). Qt fetches <img>, a background="…" and CSS url(…) from the network, so those go, in
    // any quoting (as an attribute: ?src= in a link stays); an image keeps its alt text. Again until nothing changes: a
    // tag split by another (<im<img>g src=…>) forms once the inner one goes.
    function safeHtml(h) {
        for (let was = ""; was !== h;) {
            was = h
            h = h.replace(/<(style|script|head|title)\b[\s\S]*?<\/\1\s*>/gi, "")
                 .replace(/<img\b[^>]*?\balt\s*=\s*"([^"]+)"[^>]*>/gi, "[$1]")
                 .replace(/<\/?(img|style|script|link|meta|base)\b[^>]*>/gi, "")
                 .replace(/(^|[\s"'])(src|srcset|background)\s*=\s*("[^"]*"|'[^']*'|[^\s>]*)/gi, "$1")
                 .replace(/(^|[\s"'])style\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi, (m, s, v) => s + 'style="' + safeStyle(/^["']/.test(v) ? v.slice(1, -1) : v) + '"')
                 .replace(/url\s*\(/gi, "none(")
        }
        return h
    }
    // A style attribute without the declarations that load something. Qt reads the value with its entities
    // (&#117;rl( is url(), and CSS has \75 escapes of its own), so they are read first, and written back escaped.
    function safeStyle(v) {
        const loads = d => /url\s*\(|image|@import/i.test(d.replace(/\/\*[\s\S]*?\*\//g, "")
            .replace(/\\([0-9a-f]{1,6})\s?/gi, (m, x) => entity("#x" + x) ?? "").replace(/\\/g, ""))
        return v.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+\d*);?/gi, (m, e) => entity(e) ?? m)
                .split(";").filter(d => !loads(d)).join(";")
                .replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    // The same HTML for a dark page: the sender's text and background colours go, so the text takes the window's own
    // light colour; links get the accent.
    function darken(h, link) {
        return h.replace(/\s(bgcolor|color|background)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi, "")
                .replace(/\sstyle\s*=\s*"([^"]*)"/gi, (m, css) =>
                    ' style="' + css.replace(/(^|;)\s*(color|background(-color|-image)?)\s*:[^;]*/gi, "$1") + '"')
                .replace(/<a\b/gi, '<a style="color:' + link + '"')
    }

    // Enough to read an HTML-only message as text; a real renderer comes later.
    function htmlToText(h) {
        return h.replace(/<(style|script|head)[\s\S]*?<\/\1>/gi, "")
                .replace(/<br\s*\/?>/gi, "\n")
                .replace(/<\/(p|div|tr|h\d|li)>/gi, "\n\n")
                .replace(/<[^>]+>/g, "")
                .replace(/&(#x[0-9a-f]+|#\d+|[a-z]+\d*);/gi, (m, e) => entity(e) ?? m)
                .replace(/\n{3,}/g, "\n\n").trim()
    }
    // Some senders put HTML's entities in the plain part too ("Hei&nbsp;Jari", "viel&auml;"). One that only HTML writes
    // (&nbsp;, a letter, a numbered character) shows the part came out of HTML, and then the entities are read; a plain
    // text that only has &amp; or &lt; may be quoting HTML on purpose, so it stays as it is.
    function plainText(t) {
        if (!/&(nbsp|[a-z]+(uml|acute|grave|ring|circ|tilde|cedil|slash)|#x?[0-9a-f]+);/i.test(t)) return t
        return t.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+\d*);/gi, (m, e) => entity(e) ?? m)
    }
    // &#228; &#xE4; &auml; → ä: every numbered character, and the named ones mail most often has
    readonly property var entities: ({ nbsp: " ", amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", auml: "ä", Auml: "Ä",
        ouml: "ö", Ouml: "Ö", aring: "å", Aring: "Å", uuml: "ü", Uuml: "Ü", eacute: "é", Eacute: "É", egrave: "è", agrave: "à",
        aacute: "á", oacute: "ó", iacute: "í", uacute: "ú", ccedil: "ç", ntilde: "ñ", oslash: "ø", Oslash: "Ø", aelig: "æ",
        AElig: "Æ", szlig: "ß", euro: "€", pound: "£", copy: "©", reg: "®", trade: "™", hellip: "…", ndash: "–", mdash: "—",
        lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”", laquo: "«", raquo: "»", bull: "•", middot: "·", deg: "°", times: "×",
        shy: "", zwnj: "", zwj: "" })
    function entity(e) {
        if (e[0] !== "#") return entities[e]
        const n = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)
        return n > 0 && n <= 0x10ffff ? String.fromCodePoint(n) : undefined
    }
}
