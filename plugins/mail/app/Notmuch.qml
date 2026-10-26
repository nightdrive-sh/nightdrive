import QtQuick
import Quickshell
import Quickshell.Io

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

    // Threads matching the query, newest first.
    function search(query, done) {
        json(["search", "--format=json", "--limit=500", query],
             t => JSON.parse(t).map(x => Object.assign(x, { subject: oneLine(x.subject) })), [], done)
    }

    // Some senders fold a header with stray spaces or end it in line breaks, which keeps a Text from eliding it.
    function oneLine(s) {
        return (s || "").replace(/\s+/g, " ").trim()
    }

    // The thread's messages in order, each { from, to, date, subject, tags, body } with the body as plain text.
    function show(thread, done) {
        json(["show", "--format=json", "--include-html", "--entire-thread=true", "thread:" + thread],
             t => { const out = []; flatten(JSON.parse(t), out); return out }, [], done)
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

    // Deletes a query's messages in Trash for good (lib/erase.py); done gets { erased } or { error }.
    readonly property string eraser: composer.replace(/compose\.py$/, "erase.py")
    function erase(query, from, done) {
        proc.createObject(nm, { command: ["python3", eraser, query].concat(from), done: t => {
            let r
            try { r = JSON.parse(t) } catch (e) { r = { error: t.trim() || "No answer from erase.py" } }
            done(r)
        } })
    }

    // An attachment of a message being read (lib/parts.py): "open" copies it where it can be opened from, "save" to
    // the downloads folder. done gets { path } or { error }.
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

    // notmuch nests a thread as [[message, [replies]]]; walk it in reading order.
    function flatten(node, out) {
        if (!Array.isArray(node)) return
        for (const n of node) {
            if (Array.isArray(n) && n.length === 2 && n[0] && n[0].headers) {
                out.push(message(n[0]))
                flatten(n[1], out)
            } else {
                flatten(n, out)
            }
        }
    }

    function message(m) {
        const parts = { plain: "", html: "", files: [] }
        collect(m.body || [], parts, "")
        return {
            id: m.id,
            from: m.headers.From || "",
            to: m.headers.To || "",
            subject: oneLine(m.headers.Subject),
            timestamp: m.timestamp,
            tags: m.tags || [],
            draft: (m.filename || []).some(f => /\/Drafts\/(cur|new)\//.test(f)),
            body: (parts.plain !== "" ? plainText(parts.plain) : htmlToText(parts.html)).replace(/^\s+|\s+$/g, ""),
            html: parts.html !== "" ? safeHtml(parts.html) : "",
            files: parts.files      // attachments: { part, name, size } (size in bytes, or -1)
        }
    }

    // The first plain and HTML text, and the attachments: parts sent as attachments or with a file name. Pictures an
    // HTML text points at (in multipart/related, with a Content-ID) belong to the HTML and are left out.
    function collect(list, parts, parent) {
        for (const part of list) {
            const type = (part["content-type"] || "").toLowerCase()
            if (Array.isArray(part.content)) { collect(part.content, parts, type); continue }
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
