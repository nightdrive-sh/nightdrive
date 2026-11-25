.pragma library

// The text a thread or a message is dragged out of Mail as (OutDrag.qml, #3611): a line each, which a terminal pastes
// as it is. Dropped in Claude Code, the line says what the mail is and how to read it: Claude reads it with its
// mail_thread tool, so Settings › Claude › Access decides what it may read, as when it finds the mail itself (a path
// to the message's file would have let it read past that, and changes as the message is read or archived).
//     Mail: "Lunch on Friday" – Maija Meikäläinen, 25.11.2026 (thread:0000000000001a2b, read it with mail_thread)
// The subject and the names are the sender's words going into the user's prompt: each stays on its one line, without
// control or direction characters, its double quotes made single so the quoted subject ends where it seems to, and
// cut short. Tested by refs_test.py (runs this file in Quickshell).

const SUBJECT = 80
const NAMES = 60
// C0 and C1 controls, line and paragraph separators, zero-width and bidirectional marks: a subject can't break the
// line or turn its text around on screen. Built from a string with the escapes spelled out: a U+2028 in a regex
// literal is a line break to Qt's lexer, and the literal ends there.
const HIDDEN = new RegExp("[\\u0000-\\u001f\\u007f-\\u009f\\u200b-\\u200f\\u2028-\\u202e\\u2060-\\u206f\\ufeff]+", "g")

function clean(s, max) {
    const t = String(s || "").replace(HIDDEN, " ").replace(/\s+/g, " ").trim().replace(/"/g, "'")
    const chars = Array.from(t)                  // by characters, so an emoji isn't cut in half
    return chars.length > max ? chars.slice(0, max - 1).join("").replace(/\s+$/, "") + "…" : t
}

function line(subject, who, day, ref) {
    return "Mail: \"" + (clean(subject, SUBJECT) || "(no subject)") + "\" – " + (clean(who, NAMES) || "(unknown sender)")
        + (day ? ", " + day : "") + " (" + ref + ", read it with mail_thread)"
}

// A thread of the list (notmuch search's: thread, subject, authors with "|" before the ones the search didn't match)
function thread(t, day) {
    return line(t.subject, String(t.authors || "").replace(/\s*\|\s*/g, ", "), day, "thread:" + t.thread)
}

// One message of an open thread, by its Message-ID, which mail_thread takes as it is; who is the sender's name
function message(m, who, day) {
    return line(m.subject, who, day, "message " + m.id)
}

// The drag's text: one line ends in a space, for the words that follow it; several end each in a newline
function text(lines) {
    return lines.length > 1 ? lines.join("\n") + "\n" : lines.length ? lines[0] + " " : ""
}
