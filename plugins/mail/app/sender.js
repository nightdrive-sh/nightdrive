.pragma library

// A From header as notmuch gives it ("Name" <addr>, Name <addr>, <addr> or addr) split into the name and the address.
// The address is the <…> at the end, not the first one: a name may hold text that looks like a tag ("Bob <b>x</b>"
// <bob@example.com>), and taking the first <…> showed "b" as the address and cut the name short.

// The address in the trailing <…>, or "" when there is none (a bare address: callers fall back to the header).
function address(from) {
    const m = from.match(/<([^<>]*)>\s*$/)
    return m ? m[1].trim() : ""
}

// The name before that <…>, unquoted ("Quote \"Q\" Person" → Quote "Q" Person). Without a name, the address itself.
function name(from) {
    const m = from.match(/^(.*?)\s*<[^<>]*>\s*$/)
    let n = m ? m[1].trim() : ""
    if (/^".*"$/.test(n)) n = n.slice(1, -1).replace(/\\(.)/g, "$1").trim()
    return n !== "" ? n : (m ? address(from) : from.trim())
}
