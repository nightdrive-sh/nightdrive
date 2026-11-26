import QtQuick
import Quickshell
import Quickshell.Io

// What Access › Apps and files' list (the folders Claude can use, Dashboard #1849) offers to tick: home's own folders
// by their English names, where xdg-user-dir has them (Downloads may be ~/Lataukset), the folders at the top of home,
// and home whole. Read when the panel opens (refresh), as `nightdrive files folders --json` of this checkout.
QtObject {
    id: folders
    required property string nd         // the window's nightdrive (Store.nd)
    readonly property string home: Quickshell.env("HOME") || ""   // for ~ in the labels
    property var rows: []               // [{item, path}]
    readonly property var items: rows.map(r => r.item)

    function refresh() { if (!reader.running) reader.running = true }

    // An entry as the list shows it: a home folder with where it really is, ~ as what it means
    function label(item) {
        if (item === "~") return "Your whole home (hidden files never)"
        const r = rows.find(x => x.item === item)
        if (!r || item.startsWith("~")) return item
        const shown = r.path.startsWith(home + "/") ? "~" + r.path.slice(home.length) : r.path
        return shown === "~/" + item ? item : item + "  (" + shown + ")"
    }

    property Process reader: Process {
        command: [folders.nd, "files", "folders", "--json"]
        stdout: StdioCollector {
            onStreamFinished: { try { folders.rows = JSON.parse(text) } catch (e) { folders.rows = [] } }
        }
    }
}
