import QtQuick
import Quickshell.Io

// Deck's JSON commands (search, an artist's albums, an album's tracks, the genres), one process each, and the Spotify
// search that runs on them as you type. Its own file so the views ask Deck one way, with its errors in plain words.
Item {
    id: root
    required property var win

    readonly property int searchDelay: 450      // ms after typing stops before Spotify is asked

    Component {
        id: runner
        Process {
            property var done
            property var failed
            stdout: StdioCollector { id: out }
            stderr: StdioCollector { id: err }
            onExited: code => {
                try {
                    if (code !== 0) throw new Error(err.text.trim().split("\n").pop() || "Deck didn't answer")
                    done(out.text)
                } catch (e) { failed(String(e.message || e).replace(/^deck: /, "")) }
                destroy()
            }
        }
    }
    function run(args, done, failed) {
        runner.createObject(root, { command: [win.deckBin].concat(args), done: done, failed: failed, running: true })
    }

    property var results: null                   // { query, artists, albums, songs, error }
    property bool searching: false
    Timer { id: searchTimer; interval: root.searchDelay; onTriggered: root.search() }
    function searchLater() { searchTimer.restart() }
    function searchNow() { searchTimer.stop(); search() }
    function search() {
        const q = win.searchField.text.trim()
        if (q.length < 2) { results = null; return }
        searching = true
        run(["search", "--json", q], text => {
            const r = JSON.parse(text)
            if (win.searchField.text.trim() === q) { results = { query: q, artists: r.artists, albums: r.albums, songs: r.songs, error: "" }; searching = false }
        }, e => { results = { query: q, artists: [], albums: [], songs: [], error: e }; searching = false })
    }
}
