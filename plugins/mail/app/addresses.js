.pragma library
.import "sender.js" as Sender

// A message's To, Cc or Bcc as notmuch gives it (decoded, one string) split into its people, and the short line the
// thread's header shows for them (#3716). A comma inside a quoted name ("Virtanen, Aino" <aino@example.com>) or inside
// <…> doesn't end an address. Tested by addresses_test.py (runs this file in Quickshell).

// The parts between the commas that separate addresses, trimmed, the empty ones left out
function parts(list) {
    const out = []
    let at = 0, quoted = false, angle = false
    for (let i = 0; i <= list.length; i++) {
        const ch = list[i]
        if (i === list.length || ch === "," && !quoted && !angle) {
            const p = list.slice(at, i).trim()
            if (p !== "") out.push(p)
            at = i + 1
        } else if (quoted) {
            if (ch === "\\") i++                    // \" inside a quoted name
            else if (ch === '"') quoted = false
        } else if (ch === '"') quoted = true
        else if (ch === "<") angle = true
        else if (ch === ">") angle = false
    }
    return out
}

// [{ name, address }]: the name as the sender's is read (sender.js), the address "" when the part has none. An empty
// group ("undisclosed-recipients:;") is a name alone.
function split(list) {
    return parts(list || "").map(p => {
        if (/:\s*;$/.test(p)) return { name: p.replace(/:\s*;$/, "").trim(), address: "" }
        const address = Sender.address(p) || (p.indexOf("@") > 0 ? p.replace(/^<|>$/g, "") : "")
        return { name: firstLast(Sender.name(p)), address: address }
    })
}

// "Virtanen, Aino" (Outlook's way) as "Aino Virtanen": in a list joined with commas, the comma read as two people
function firstLast(name) {
    const m = name.match(/^([^,@"]+),\s*([^,@"]+)$/)
    return m ? m[2].trim() + " " + m[1].trim() : name
}

// "Anna, Pekka and Liisa" for three at most, "Anna, Pekka and 3 more" past that: two names always show, and the count
// says how many a click opens
function summary(names) {
    const n = names.length
    if (n <= 1) return names.join("")
    if (n <= 3) return names.slice(0, -1).join(", ") + " and " + names[n - 1]
    return names.slice(0, 2).join(", ") + " and " + (n - 2) + " more"
}
