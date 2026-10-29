.pragma library

// Ask Claude's steps in words (AskClaudeSession.qml): a Nightdrive tool's name (mcp__nightdrive__mail_search) as a
// glyph and what it does ("Searching mail"), with the argument that says on what ("Mikko palaveri"). A tool not named
// here gets its area's glyph and its name in words, so a new tool still reads sensibly.

// The glyph for the thinking row: a robot's head while Claude thinks between steps
var THINKING = "bot"

// Areas by the name's start: the longest match wins (home_assistant before home)
var AREAS = {
    mail: "mail", contacts: "user-round", deck: "music", calendar: "calendar", tasks: "list-checks", notes: "notebook-pen",
    appearance: "palette", display: "monitor", sound: "volume-2", network: "wifi", bluetooth: "bluetooth",
    battery: "battery-medium", software: "package", files: "folder", apps: "app-window", windows: "app-window",
    notifications: "bell", docs: "book-open", shortcuts: "keyboard", undo: "undo-2", open: "globe", home_assistant: "house",
    ferry: "send", recent: "history", nightdrive: "info"
}

var LABELS = {
    mail_search: "Searching mail", mail_unread: "Reading unread mail", mail_thread: "Reading a mail", mail_draft: "Drafting a mail",
    mail_send: "Sending a mail", mail_archive: "Archiving mail", mail_delete: "Deleting mail", mail_accounts: "Looking at mail accounts",
    contacts_find: "Looking up a contact", contacts_card: "Reading a contact",
    deck_search: "Searching music", deck_play_album: "Playing an album", deck_play_song: "Playing a song", deck_radio: "Starting a radio",
    deck_queue_album: "Queueing an album", deck_queue_song: "Queueing a song", deck_control: "Controlling playback",
    deck_now_playing: "Checking what's playing", deck_like: "Liking a song",
    notes_create: "Writing a note", battery_status: "Checking the battery", sound_volume: "Setting the volume",
    sound_output: "Choosing the sound output", sound_status: "Checking the sound", display_brightness: "Setting the brightness",
    appearance_wallpaper: "Changing the wallpaper", appearance_theme: "Changing the theme", apps_open: "Opening an app",
    open_address: "Opening a page", docs_search: "Searching Nightdrive's docs", docs_read: "Reading Nightdrive's docs",
    shortcuts: "Looking up keys", software_search: "Searching software", software_install: "Installing", software_remove: "Removing",
    windows_list: "Looking at the windows", windows_focus: "Switching windows", home_assistant_states: "Looking at the home",
    home_assistant_set: "Controlling the home", notifications_send: "Sending a notification",
    notifications_dnd_on: "Turning Do Not Disturb on", notifications_dnd_off: "Turning Do Not Disturb off",
    notifications_recent: "Reading notifications", network_off: "Turning the network off",
    display_scale: "Changing the display's scale", display_resolution: "Changing the resolution", undo_change: "Undoing a change",
    nightdrive_status: "Checking Nightdrive"
}

// The argument worth showing beside the step, in this order
var DETAIL_KEYS = ["query", "q", "text", "title", "name", "subject", "to", "address", "url", "artist", "album", "song", "entity", "app", "id"]

function area(tool) {
    var best = ""
    for (var k in AREAS) if ((tool === k || tool.indexOf(k + "_") === 0) && k.length > best.length) best = k
    return best
}

// { glyph, text } for a tool call; input may still be empty (the call's start) and filled in later
function step(name, input) {
    var tool = name.replace(/^mcp__.+?__/, "")   // the server's name, whatever it was registered as
    var a = area(tool)
    var text = LABELS[tool] || (tool.charAt(0).toUpperCase() + tool.slice(1)).replace(/_/g, " ")
    var detail = ""
    if (input) for (var i = 0; i < DETAIL_KEYS.length && detail === ""; i++) {
        var v = input[DETAIL_KEYS[i]]
        if (typeof v === "string" && v.trim() !== "") detail = v.trim()
        else if (Array.isArray(v) && v.length && typeof v[0] === "string") detail = v.join(", ")
    }
    if (detail.length > 60) detail = detail.slice(0, 60) + "…"
    return { glyph: AREAS[a] || "sparkles", text: detail ? text + ": " + detail : text }
}
