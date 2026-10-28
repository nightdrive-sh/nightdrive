.pragma library
.import "EmojiNames.js" as Names

// Emoji shortcodes in a notification's text as the emoji: Slack's (and Discord's, Mattermost's) web notifications send
// ":thumbsup:" and ":+1::skin-tone-2:" as such. Only names in the table change, so a workspace's own emoji (":partyparrot:")
// and text that merely has colons in it (10:30:15) stay as they are. A skin tone is its own name (a modifier) that
// follows the emoji, so it falls into place.
// Split at the colons rather than a /:name:/g regex, which would eat the colon a stray one ("Re:x:smile:") shares.
function replace(text) {
    if (!text || text.indexOf(":") < 0) return text
    const parts = text.split(":")
    let out = parts[0]
    for (let i = 1; i < parts.length; i++) {
        if (i < parts.length - 1 && Names.names.hasOwnProperty(parts[i])) out += Names.names[parts[i]] + parts[++i]
        else out += ":" + parts[i]
    }
    return out
}
