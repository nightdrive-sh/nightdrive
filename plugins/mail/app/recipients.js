.pragma library

// To and Cc while they are typed: where the address being written starts, for the completions (#3593).
// A comma inside a quoted name ("Virtanen, Aino" <aino@example.com>) or inside <…> doesn't end an address, so the
// last comma that counts is found by walking the text, not with lastIndexOf(","). Otherwise typing after such a name
// searched for "Aino" <aino@…> and a completion replaced the name's second half. The backend parses the whole list
// with Python's getaddresses (lib/recipients.py). Tested by recipients_test.py (runs this file in Quickshell).

// Index of the last comma that separates addresses, or -1.
function lastComma(text) {
    let at = -1, quoted = false, angle = false
    for (let i = 0; i < text.length; i++) {
        const ch = text[i]
        if (quoted) {
            if (ch === "\\") i++                    // \" inside a quoted name
            else if (ch === '"') quoted = false
        } else if (ch === '"') quoted = true
        else if (ch === "<") angle = true
        else if (ch === ">") angle = false
        else if (ch === "," && !angle) at = i
    }
    return at
}

// The text before the address being typed, its comma included ("" for the first address).
function before(text) { return text.slice(0, lastComma(text) + 1) }

// The address being typed, as the completions search for it: no spaces around it, an opening quote left out.
function typed(text) { return text.slice(lastComma(text) + 1).trim().replace(/^"/, "").toLowerCase() }
