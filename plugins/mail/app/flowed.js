.pragma library

// A format=flowed plain text (RFC 3676) put back into paragraphs for reading (#3321). Such a text is wrapped at about
// 72 columns, and a line that goes on in the next one ends in a space (a "soft" break); the read view would otherwise
// show it in short, ragged lines. Lines are joined only when the part's own header says format=flowed (lib/flowed.py
// reads it, as notmuch's JSON leaves Content-Type's parameters out): a text without it, a newsletter's made from HTML
// too, keeps its line breaks, as joining by guesswork breaks lists, addresses and code.
// Tested by flowed_test.py (runs this file in Quickshell).

// Worth asking the header about: a line that ends in a space and goes on in a next one with text. "-- " alone is a
// signature's separator, never a soft break.
function maybe(t) {
    const lines = t.replace(/\r/g, "").split("\n")
    for (let i = 0; i + 1 < lines.length; i++)
        if (lines[i].length > 1 && lines[i].endsWith(" ") && lines[i] !== "-- " && lines[i + 1] !== "") return true
    return false
}

// RFC 3676 4.2: each line's quote depth is its leading ">"s, then one space after them is stuffing and goes. A line
// ending in a space flows into the next of the same depth (with delsp, that space was added by the sender's wrap and
// goes too); "-- " never flows, and a soft break before a change of depth counts as hard. A quoted paragraph comes
// back as ">" per level and a space, the way the read view shows quotes.
function unflow(t, delsp) {
    const out = []
    let open = false, depth = -1
    for (const raw of t.replace(/\r/g, "").split("\n")) {
        const d = raw.match(/^>*/)[0].length
        let line = raw.slice(d)
        if (line.startsWith(" ")) line = line.slice(1)
        const soft = line.endsWith(" ") && line !== "-- "
        if (soft && delsp) line = line.slice(0, -1)
        if (open && d === depth) out[out.length - 1] += line
        else out.push(d > 0 ? ">".repeat(d) + (line !== "" ? " " + line : "") : line)
        open = soft
        depth = d
    }
    return out.join("\n")
}
