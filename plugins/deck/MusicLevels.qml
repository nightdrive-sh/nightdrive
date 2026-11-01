import QtQuick
import Quickshell
import qs

// Deck's part of the launcher (plugin-parts lists it while Deck is on): Music at the root, with Album Shelf and Curated
// from Deck's files and Search Spotify through Deck's own client (an artist's albums too); Enter on an album plays it.
// The root search finds the shelf's and Curated's albums (rootRows). The player row above the search field (topRow):
// play/pause, the track, next and like; ↑ from the list's first row selects it, and Ctrl+Space plays or pauses anywhere.
// Launcher.qml asks it like its own level files (levels, titles, parents, items, activate, footer, entered).
Item {
    id: m
    property var launcher: null               // Launcher.qml sets it once the file is loaded

    readonly property var rootItems: [{ kind: "nav", name: "Music", glyph: "disc-3", target: "music" }]

    property var albums: []                   // Deck's shelf and Curated albums [{ uri, name, artist, year, list }]
    property var spotify: null                // Music › Search: { query, artists, albums, songs, error } (deck search --json)
    property var artist: ({ id: "", name: "", albums: null })   // Music › Search › an artist's albums

    readonly property string bin: Quickshell.env("HOME") + "/.local/bin"   // deck, and deck-ctl and deck-window (bin/ here)
    readonly property var levels: ["music", "shelf", "curated", "musicsearch", "artist"]
    readonly property var titles: ({ music: "Music", shelf: "Music › Album Shelf", curated: "Music › Curated", musicsearch: "Music › Search",
                                     artist: "Music › " + artist.name })
    readonly property var parents: ({ shelf: "music", curated: "music", musicsearch: "music", artist: "musicsearch" })

    function footer(level, query) { return level === "shelf" || level === "curated" ? "Enter: play in Deck" : "" }
    // Shelf, Curated and the player's state are read on every open; a Spotify search is only kept while the launcher is open
    function opened() { spotify = null; musicProc.running = true; deckProc.running = true }
    function entered(level) {}
    function shiftActivate(it) {}

    // An album row: the album's name with ARTIST below it (small, theme colour), the year on the right; an artist's own
    // album list leaves the artist out
    function albumItem(a, withArtist = true) {
        return { kind: "album", name: a.name, artist: withArtist && a.artist ? a.artist : "", summary: a.year ? String(a.year) : "", glyph: "disc-3", uri: a.uri }
    }
    // Settings › Launcher › Include Deck artists, albums and songs (off by default: the search shows no Deck rows then).
    // On: the shelf's and Curated's albums and their artists among the hits, and after them a row that searches Spotify
    // for what was typed. Spotify is asked only when that row is picked, never while typing.
    function rootTail(q) {
        if (!launcher.prefs.deck || launcher.query.trim().length < 2) return []
        return [searchRow(launcher.query.trim())]
    }
    // A song row: the song with ARTIST · ALBUM below it, the length on the right
    function songItem(s) {
        return { kind: "spotifysong", name: s.name, glyph: "music", uri: s.uri, album: s.album.uri,
                 artist: s.artist + " · " + s.album.name, summary: duration(s.duration_ms) }
    }

    // The root search's album rows ("fm-84" → Atlas) and their artists (opening one lists its albums on Spotify), with the
    // MUSIC tag on the right; only when Deck is in the search (Settings › Launcher)
    function rootRows() { return launcher.prefs.deck ? localRows() : [] }
    // The shelf's and Curated's artists (opening one lists its albums on Spotify) and albums, as search rows
    function localRows() {
        const artists = []
        for (const a of albums) if (a.artist_id && !artists.some(x => x.id === a.artist_id)) artists.push({ id: a.artist_id, name: a.artist })
        return artists.map(a => ({ item: { kind: "spotifyartist", name: a.name, glyph: "mic-vocal", id: a.id, from: "Music" }, text: a.name }))
            .concat(albums.map(a => ({ item: Object.assign(albumItem(a), { summary: undefined, from: "Music" }), text: a.name, extra: a.artist })))
    }
    // Search Spotify for what was typed: opens Music › Search Spotify with it (Spotify is asked only then). A fixed name,
    // as Ask Claude's row has: the typed words are already in the field above it (Dashboard #1919)
    function searchRow(text) {
        return { kind: "spotifysearch", name: "Search Spotify", glyph: "search", value: text, from: "Music",
                 footer: "Enter: search Spotify" }
    }

    // 3:45
    function duration(ms) { const s = Math.round((ms || 0) / 1000); return s > 0 ? Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") : "" }

    function items(level, q) {
        const hint = launcher.hint
        if (level === "music") {
            const count = list => albums.filter(a => a.list === list).length
            const navs = [{ kind: "nav", name: "Album Shelf", glyph: "library-big", target: "shelf", summary: String(count("shelf")) },
                          { kind: "nav", name: "Curated", glyph: "sparkles", target: "curated", summary: String(count("curated")) },
                          { kind: "nav", name: "Search Spotify", glyph: "search", target: "musicsearch", summary: "in Deck" }]
                .map(r => ({ item: r, text: r.name }))
            // Typing here finds the shelf's and Curated's artists and albums, whatever Settings › Launcher says (this is
            // Deck's own level), and offers the same words to Spotify after them
            if (q === "") return { all: navs }
            return { all: navs.concat(localRows()), tail: [searchRow(launcher.query.trim())] }
        }
        if (level === "musicsearch") {
            // Results come from `deck search --json` a moment after typing stops; going back from an artist shows them again
            const typed = launcher.query.trim()
            const shown = typed !== "" ? typed : (spotify ? spotify.query : "")
            if (shown === "") return hint("Type an artist, album or song")
            const inDeck = { kind: "decksearch", name: "Open “" + shown + "” in Deck", glyph: "external-link", value: shown }
            if (!spotify || spotify.query !== shown) return hint("Searching Spotify…")
            if (spotify.error) return hint(spotify.error).concat([inDeck])
            const artists = spotify.artists.slice(0, 4).map(a => ({ kind: "spotifyartist", name: a.name, glyph: "mic-vocal", id: a.id, chevron: true }))
            const found = spotify.albums.map(a => albumItem(a))
            // A song plays its album from that song (deck ctl play-song), as Enter on a song in Deck does
            const songs = spotify.songs.slice(0, 6).map(songItem)
            if (artists.length + found.length + songs.length === 0) return hint("Nothing found on Spotify").concat([inDeck])
            return (artists.length ? [{ kind: "header", name: "Artists" }].concat(artists) : [])
                .concat(found.length ? [{ kind: "header", name: "Albums" }].concat(found) : [],
                        songs.length ? [{ kind: "header", name: "Songs" }].concat(songs) : [], [inDeck])
        }
        if (level === "artist") {
            if (artist.albums === null) return hint("Loading albums…")
            if (artist.albums.length === 0) return hint("No albums found")
            return { all: artist.albums.map(a => ({ item: albumItem(a, false), text: a.name, extra: String(a.year || "") })) }
        }
        if (level === "shelf" || level === "curated") {
            const list = albums.filter(a => a.list === level)
            if (list.length === 0) return hint(level === "shelf" ? "The shelf is empty: add albums in Deck with a"
                                                                : "No Curated list yet: `deck curate` suggests albums based on what you play")
            return { all: list.map(a => ({ item: albumItem(a), text: a.name, extra: a.artist + " " + (a.year || "") })) }
        }
        return []
    }

    // Albums also come from the root search, so these work on any level
    function activate(it) {
        const l = launcher
        if (it.kind === "album") { l.open = false; Quickshell.execDetached([bin + "/deck-ctl", "play-album", it.uri]); return true }
        if (it.kind === "spotifysong") { l.open = false; Quickshell.execDetached([bin + "/deck-ctl", "play-song", it.uri, it.album]); return true }
        if (it.kind === "spotifyartist") {
            artist = { id: it.id, name: it.name, albums: null }
            artistProc.environment = { "ID": it.id }
            artistProc.running = true
            l.go("artist")
            return true
        }
        if (it.kind === "spotifysearch") { l.goSearch("musicsearch", it.value); return true }
        if (it.kind === "decksearch") { l.open = false; Quickshell.execDetached([bin + "/deck-ctl", "search", it.value]); return true }
        return false
    }

    // Deck's shelf (sorted by artist and year, like in Deck) and the Curated list
    Sh {
        id: musicProc
        script: 'd="$HOME/.config/deck"; s=$(cat "$d/shelf.json" 2>/dev/null || echo "[]"); c=$(cat "$d/curated.json" 2>/dev/null || echo "{}")
jq -cn --argjson s "$s" --argjson c "$c" \'[($s | sort_by((.artist | ascii_downcase), .year) | .[] | {uri, name, artist, artist_id, year, list: "shelf"}),
  ($c.albums // [] | .[] | {uri, name, artist, artist_id, year, list: "curated"})]\''
        onResult: text => { try { m.albums = JSON.parse(text) } catch (e) { m.albums = [] } }
    }
    // Music › Search: Spotify through Deck's own client (needs client_id in Deck's config.toml); one request after typing pauses
    Connections {
        target: m.launcher
        function onQueryChanged() { if (m.launcher.level === "musicsearch" && m.launcher.query.trim() !== "") spotifyDelay.restart() }
    }
    Timer { id: spotifyDelay; interval: 450; onTriggered: m.searchSpotify() }
    function searchSpotify() {
        const q = launcher.query.trim()
        if (q.length < 2 || spotifyProc.running) return
        spotifyProc.environment = { "Q": q }
        spotifyProc.running = true
    }
    Sh {
        id: spotifyProc
        script: '"$HOME/.local/bin/deck" search --json "$Q"'
        onResult: text => {
            const q = spotifyProc.environment.Q
            try {
                if (spotifyProc.exitCode !== 0) throw new Error(text.trim().split("\n").pop() || "Search failed")
                const r = JSON.parse(text)
                m.spotify = { query: q, artists: r.artists || [], albums: r.albums || [], songs: r.songs || [], error: "" }
            } catch (e) { m.spotify = { query: q, artists: [], albums: [], songs: [], error: String(e.message || e).replace(/^deck: /, "") } }
            const l = m.launcher
            if (l.level === "musicsearch" && l.query.trim() !== "" && l.query.trim() !== q) m.searchSpotify()   // typed on meanwhile
        }
    }
    Sh {
        id: artistProc
        script: '"$HOME/.local/bin/deck" artist-albums --json "$ID"'
        onResult: text => {
            let albums = []
            try { albums = JSON.parse(text) } catch (e) {}
            if (m.artist.id === artistProc.environment.ID) m.artist = Object.assign({}, m.artist, { albums: albums })
        }
    }

    // --- The player row ---
    property var info: null                   // Deck's playback state (state.json): null = not playing / not running
    property bool alive: false                // Deck's helper process is running
    property var override: ({})               // pending local changes (playing, liked)
    readonly property bool playing: override.playing !== undefined ? override.playing : (info !== null && info.playing)
    readonly property var liked: override.liked !== undefined ? override.liked : (info ? info.liked : null)
    readonly property string deckBin: bin + "/deck"

    // Keys while the player row is selected. Returns true if the key was handled.
    function topKey(event) {
        const k = event.key
        const ctrl = event.modifiers & Qt.ControlModifier
        if (k === Qt.Key_Down || (ctrl && (k === Qt.Key_N || k === Qt.Key_J))) { launcher.topFocused = false; return true }
        if (k === Qt.Key_Up) return true
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { topPress(); return true }
        if (k === Qt.Key_Right) { if (info !== null) ctl("next"); return true }
        if (k === Qt.Key_Left) { if (info !== null) ctl("previous"); return true }
        if (ctrl && k === Qt.Key_L) { if (info !== null) ctl("like"); return true }
        if (k === Qt.Key_Escape || k === Qt.Key_Backspace) return false
        if (event.text !== "" && !ctrl) launcher.topFocused = false      // typing returns to the search
        return false
    }
    // Play (Ctrl+Space anywhere): something playing → play/pause; nothing playing → start / bring up Deck
    function topPress() { if (info === null) launchDeck(); else ctl("toggle") }
    function launchDeck() {
        launcher.open = false
        Quickshell.execDetached([bin + "/deck-window"])
    }
    function ctl(cmd) {
        if (cmd === "toggle") override = Object.assign({}, override, { playing: !playing })
        if (cmd === "like" && liked !== null && liked !== undefined) override = Object.assign({}, override, { liked: !liked })
        Quickshell.execDetached([deckBin, "ctl", cmd])
        settle.restart()
    }
    Timer { id: settle; interval: 1000; onTriggered: { m.override = ({}); deckProc.running = true } }
    Timer { interval: 1500; repeat: true; running: m.launcher !== null && m.launcher.open; onTriggered: deckProc.running = true }
    Sh {
        id: deckProc
        script: 'f="$XDG_RUNTIME_DIR/deck/state.json"; [ -s "$f" ] || exit 3; pid=$(jq -r .pid "$f"); [ -d "/proc/$pid" ] || exit 4; cat "$f"'
        onResult: text => {
            if (deckProc.exitCode !== 0) { m.alive = false; m.info = null; return }
            try { m.info = JSON.parse(text).info; m.alive = true } catch (e) { m.alive = false; m.info = null }
        }
    }

    // Play/pause, track, next, like. Not playing → play starts Deck
    readonly property Component topRow: Rectangle {
        implicitHeight: 40
        radius: 10
        color: m.launcher.topFocused ? Theme.sel : "transparent"

        Text {
            id: playBtn
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: Icons.g(m.playing ? "pause" : "play")
            color: (playArea.containsMouse || m.launcher.topFocused) ? Theme.accent : (m.info === null ? Theme.dim : Theme.text)
            font { family: Icons.familyMedium; pixelSize: 19 }
            MouseArea { cursorShape: Qt.PointingHandCursor; id: playArea; anchors { fill: parent; margins: -8 } hoverEnabled: true; onClicked: m.topPress() }
        }
        Text {
            anchors { left: playBtn.right; leftMargin: 16; right: nextBtn.visible ? nextBtn.left : parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: m.info ? (m.info.title + "  —  " + m.info.artist)
                         : (m.alive ? "Deck — nothing playing" : "Deck — not running (press play to start)")
            color: m.info === null ? Theme.dim : (m.playing ? Theme.accent : Theme.text)
            font { family: Theme.font; pixelSize: m.launcher.fontSize - 3; weight: m.launcher.fontWeight }
        }
        Text {
            id: nextBtn
            visible: m.info !== null
            anchors { right: heartBtn.visible ? heartBtn.left : parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: Icons.g("skip-forward")
            color: nextArea.containsMouse ? Theme.accent : Theme.text
            font { family: Icons.familyMedium; pixelSize: 17 }
            MouseArea { cursorShape: Qt.PointingHandCursor; id: nextArea; anchors { fill: parent; margins: -8 } hoverEnabled: true; onClicked: m.ctl("next") }
        }
        Text {
            id: heartBtn
            visible: m.liked !== null && m.liked !== undefined
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: Icons.g("heart")
            color: m.liked ? Theme.primary : (heartArea.containsMouse ? Theme.accent : Theme.dim)
            font { family: Icons.familyMedium; pixelSize: 17 }
            MouseArea { cursorShape: Qt.PointingHandCursor; id: heartArea; anchors { fill: parent; margins: -8 } hoverEnabled: true; onClicked: m.ctl("like") }
        }
    }
}
