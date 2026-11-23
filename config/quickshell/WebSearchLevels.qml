import QtQuick
import Quickshell

// The launcher's "Open in Browser" row (Dashboard #2836): when the root search finds nothing, the row after Ask
// Claude's opens what was typed in the default browser: an address as it is, anything else as a search with the
// browser's own default engine. hypr/scripts/web-search decides which and finds the engine (xdg-open can't search).
// A fixed name, as Ask Claude's and Search Spotify's rows have: the words are already in the field above it.
Item {
    id: w
    property var launcher: null

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    // No level of its own
    readonly property var levels: []
    readonly property var titles: ({})
    readonly property var parents: ({})

    function opened() {}
    function entered(level) {}
    function items(level, q) { return [] }
    function footer(level, query) { return "" }

    // After the hits: only when there are none (rows after the hits whatever was typed, such as Search Spotify, and the
    // Ask Claude row aren't hits), so a search that finds something keeps its rows as they were
    function tailRows(query, results) {
        const q = query.trim()
        if (q === "" || results.some(r => !r.tail && r.kind !== "askclaude")) return []
        return [{ kind: "websearch", name: "Open in Browser", glyph: "globe", value: q, tail: true,
                  footer: "Enter: open the address, or search for it in the browser" }]
    }

    function activate(it) {
        if (it.kind !== "websearch") return false
        launcher.open = false
        Quickshell.execDetached([scripts + "/web-search", it.value])
        return true
    }
}
