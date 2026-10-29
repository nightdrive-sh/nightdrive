// What the Access window says about each choice, in plain words: the user decides what Claude may do from these, so
// they say what happens and what leaves the computer, without tools or classes (Dashboard #1831: "very, very clear").
// The areas' own words ("searches and reads your mail…") come from config/mcp/areas.py through `nightdrive mcp access`.
.pragma library

const RIGHTS = ["read", "modify", "delete"]
const RIGHT_NAMES = { read: "Read", modify: "Modify", delete: "Delete" }
const VALUE_NAMES = { allow: "Allow", ask: "Ask", no: "No" }
const LEVELS = [
    { id: "strict", name: "Strict", about: "Only Nightdrive's docs and status: Claude explains how things work." },
    { id: "normal", name: "Normal", about: "Reading what is private (mail, people, calendar, notes, notifications, "
        + "the screen) asks you each time; the rest is allowed. Changes come with Undo; deleting asks." },
    { id: "open", name: "Open", about: "Everything allowed. Sending, devices and installing still ask each time." }
]

// The menu's line under each choice
const CHOICES = {
    read: { allow: "Claude reads it when it needs to. What it reads goes to Anthropic with the answer.",
            ask: "A card on your screen asks before each read, and shows what Claude is looking for.",
            no: "Claude doesn't see it at all." },
    modify: { allow: "At once, with a notification that undoes it.",
              ask: "A card on your screen asks before each change, and shows exactly what it is.",
              no: "Claude can't change anything here." },
    delete: { allow: "At once, to the trash, with a notification that undoes it.",
              ask: "A card on your screen asks before each one, and shows what goes.",
              no: "Claude can't delete anything here." }
}
// Where every tool of the right has consequences (sending, devices, installing), Allow isn't offered
const ALWAYS_ASKS = "Sending, devices and installing always ask: the card is what stops a mail Claude read from "
    + "making it act."

function choiceText(right, value, consequential) {
    if (value === "ask" && consequential) return "A card on your screen asks before each one, and shows exactly what it is."
    return CHOICES[right][value]
}

// "Asks you each time", "Allowed, with Undo", "No": the state of one right, as the row's sentence starts
function state(right, r) {
    const v = r.value
    const asks = r.tools.filter(t => t.asks)
    if (v === "no") return "No"
    if (v === "ask" || asks.length === r.tools.length) return "Asks you each time"
    return right === "read" ? "Allowed" : r.tools.some(t => t.undo) ? "Allowed, with Undo" : "Allowed"
}

// One line per right for the picked row: "Read · Asks you each time: Claude searches and reads your mail…"
// plus which tools ask whatever the choice ("Send a draft always asks")
function lines(area) {
    const out = []
    for (const right of RIGHTS) {
        const r = area.rights[right]
        if (!r) continue
        let text = RIGHT_NAMES[right] + " · " + state(right, r) + (r.words ? ": Claude " + r.words + "." : ".")
        const asks = r.tools.filter(t => t.asks)
        if (r.value === "allow" && asks.length && asks.length < r.tools.length)
            text += " Always asks: " + asks.map(t => t.title.toLowerCase()).join(", ") + "."
        if (right === "read" && r.value !== "no") text += " What Claude reads goes to Anthropic."
        out.push(text)
    }
    return out
}
