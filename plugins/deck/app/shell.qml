import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Deck's window: the shelf, Curated, genre radio, Spotify search and the queue, with the player along the bottom. The music plays in
// `deck serve` (or a Deck in a terminal), which this only talks to: `deck ctl` for commands, its state file for what plays,
// and Deck's own files for the shelf and Curated. Closing the window leaves the music playing.
ShellRoot {
    id: shell
    FloatingWindow {
        id: win
        title: "Deck"
        implicitWidth: 1080
        implicitHeight: 700
        color: c.bg
        onClosed: Qt.quit()

        // The look, as Mail's: the apps' kit (kit/AppLook.qml)
        AppLook { id: c }

        readonly property string home: Quickshell.env("HOME")
        readonly property string deckBin: home + "/.local/bin/deck"
        readonly property string runtime: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/deck"
        readonly property int searchDelay: 450      // ms after typing stops before Spotify is asked
        readonly property int settleTime: 1500      // ms a pressed button's look waits for Deck's state to catch up
        readonly property int headerHeight: 62      // the view's title bar, a line under it whatever it holds; the sidebar's title beside it
        readonly property int listGap: 12           // from the line to the first row, and to the sidebar's first section
        readonly property int listTop: headerHeight + 1 + listGap

        // --- What Deck says: the playing track and the queue (state.json, written on every change) ---
        property var info: null
        property bool alive: false                  // a Deck is running (the file's pid lives)
        property real updatedMs: 0
        property real nowMs: Date.now()
        property var optimistic: ({})               // { playing, liked } until Deck's state catches up
        readonly property bool playing: optimistic.playing !== undefined ? optimistic.playing : (info !== null && info.playing)
        readonly property var liked: optimistic.liked !== undefined ? optimistic.liked : (info ? info.liked : null)
        readonly property real duration: info ? info.duration_ms : 0
        readonly property real position: {
            if (!info) return 0
            let p = info.position_ms
            if (info.playing) p += nowMs - updatedMs
            return Math.max(0, Math.min(duration, p))
        }
        readonly property var queue: info && info.queue ? info.queue : []
        readonly property var radio: info && info.radio ? info.radio : null
        // Deck's latest error (a failed search, an empty station…): shown on the note line when it changes
        readonly property string deckError: info && info.error ? info.error : ""
        onDeckErrorChanged: if (deckError !== "") { showNote(deckError, true); radioStarting = "" }

        FileView {
            id: stateFile
            path: win.runtime + "/state.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: {
                try {
                    const j = JSON.parse(text())
                    win.info = j.info
                    win.updatedMs = j.updated_ms
                    win.nowMs = Date.now()
                    alivePid.command = ["test", "-d", "/proc/" + j.pid]
                    alivePid.running = true
                } catch (e) { win.info = null; win.alive = false }
            }
            onLoadFailed: { win.info = null; win.alive = false }
        }
        // A Deck killed without cleaning up leaves its file behind: the pid tells.
        Process { id: alivePid; onExited: code => { win.alive = code === 0; if (code !== 0) win.info = null } }
        Timer { interval: 3000; repeat: true; running: true; onTriggered: stateFile.reload() }
        Timer { interval: 250; repeat: true; running: win.playing; onTriggered: win.nowMs = Date.now() }
        Timer { id: settle; interval: win.settleTime; onTriggered: win.optimistic = ({}) }

        function ctl(args) {
            Quickshell.execDetached([deckBin, "ctl"].concat(args))
            settle.restart()
        }
        function togglePlay() { if (info) { optimistic = Object.assign({}, optimistic, { playing: !playing }); ctl(["toggle"]) } }
        function toggleLike() {
            if (liked === null || liked === undefined) return
            optimistic = Object.assign({}, optimistic, { liked: !liked })
            ctl(["like"])
        }
        // A jump in the track: shown at once, then Deck's state catches up
        function seek(fraction) {
            if (!info || duration <= 0) return
            const ms = Math.round(Math.max(0, Math.min(1, fraction)) * duration)
            info = Object.assign({}, info, { position_ms: ms })
            updatedMs = Date.now(); nowMs = updatedMs
            ctl(["seek", String(ms)])
        }
        // Next takes the queue's first track, which leaves the queue at once, but Deck tells the new track only once the
        // player has it: until then the queue's top row shows the track that is coming
        property var pendingNext: null
        Timer { id: pendingWait; interval: 5000; onTriggered: win.pendingNext = null }
        onInfoChanged: if (pendingNext && info && info.track_uri === pendingNext.uri) pendingNext = null
        function next() {
            if (queue.length) { pendingNext = queue[0]; pendingWait.restart() }
            ctl(["next"])
        }
        function startDeck() { Quickshell.execDetached([home + "/.local/bin/deck-window", "player"]) }

        // --- Deck's own files: the shelf and Curated ---
        property var shelf: []
        property var curated: []
        FileView {
            path: win.home + "/.config/deck/shelf.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: { try { win.shelf = JSON.parse(text()) } catch (e) { win.shelf = [] } }
        }
        FileView {
            path: win.home + "/.config/deck/curated.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: { try { win.curated = JSON.parse(text()).albums || [] } catch (e) { win.curated = [] } }
        }
        // What Deck's config has: your own Spotify app (likes, search without the shared limits, and Curated, which finds
        // its albums through it), and Curated's taste: Last.fm (your history there) or, without it, a few lines of your
        // own (taste.md). Until both are there, Deck's setup with Claude is offered for what is missing.
        property bool hasApp: false
        property bool hasLastfm: false
        property bool hasNotes: false
        readonly property bool curatedReady: hasApp && (hasLastfm || hasNotes)
        property bool configRead: false
        FileView {
            path: win.home + "/.config/deck/config.toml"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: {
                const t = text()
                win.hasApp = /^\s*client_id\s*=\s*"[^"]+"/m.test(t)
                win.hasLastfm = /^\s*lastfm_api_key\s*=\s*"[^"]+"/m.test(t) && /^\s*lastfm_user\s*=\s*"[^"]+"/m.test(t)
                win.configRead = true
            }
            onLoadFailed: { win.hasApp = false; win.hasLastfm = false; win.configRead = true }
        }
        FileView {
            path: win.home + "/.config/deck/taste.md"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: win.hasNotes = text().trim() !== ""
            onLoadFailed: win.hasNotes = false
        }
        // The window's own: whether its first start's offer to set up Deck was put aside
        property var prefs: ({})
        property bool prefsRead: false
        FileView {
            id: prefsFile
            path: win.home + "/.config/deck/window.json"
            printErrors: false
            onLoaded: { try { win.prefs = JSON.parse(text()) } catch (e) { win.prefs = {} } win.prefsRead = true }
            onLoadFailed: win.prefsRead = true
        }
        // What you have listened to in Deck: a track halfway counts, an album with half its tracks is listened
        property var listened: ({})
        FileView {
            path: win.home + "/.local/state/deck/listened.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: { try { win.listened = JSON.parse(text()) } catch (e) { win.listened = {} } }
        }
        // What you have played lately, album by album, newest first (Deck keeps 30 days)
        property var history: []
        FileView {
            path: win.home + "/.local/state/deck/history.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: { try { win.history = JSON.parse(text()) } catch (e) { win.history = [] } }
        }
        // When: today's with its time, then yesterday, a weekday this week, and a date before that
        function when(at) {
            const d = new Date(at * 1000), now = new Date()
            const day = x => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
            const days = Math.round((day(now) - day(d)) / 86400000)
            if (days === 0) return "Today " + Qt.formatTime(d, "hh:mm")
            if (days === 1) return "Yesterday"
            if (days < 7) return Qt.formatDate(d, "dddd")
            return Qt.formatDate(d, "ddd d MMM")
        }
        function heard(uri) {
            const l = listened[uri]
            if (!l) return ""
            if (l.listened) return "Listened"
            return l.played && l.played.length && l.tracks ? l.played.length + " of " + l.tracks : ""
        }
        readonly property var curatedUris: {
            const s = {}
            for (const a of curated) s[a.uri] = true
            return s
        }
        // Not for me: out of Curated, into its history as rejected, which the next list learns from (loosely: no more
        // records like it)
        function notForMe(album) {
            ctl(["curated-reject", album.uri])
            note = "Not for me: " + album.name
        }
        // Album covers and artists' pictures by URI: the image's address from Spotify's oEmbed (no sign-in needed), asked
        // once per album or artist when a row shows it. The addresses are kept in covers.json, so a cover shows at once the next time; the images
        // themselves aren't kept (Spotify's CDN serves them, as to its own apps).
        property var covers: ({})
        property bool coversLoaded: false
        property var coversAsked: ({})              // this session's oEmbed requests: one per album
        FileView {
            id: coversFile
            path: win.home + "/.cache/deck/covers.json"
            printErrors: false
            onLoaded: { try { win.covers = JSON.parse(text()) } catch (e) {} win.coversLoaded = true }
            onLoadFailed: win.coversLoaded = true
        }
        Timer { id: coversSave; interval: 1000; onTriggered: coversFile.setText(JSON.stringify(win.covers) + "\n") }
        function cover(uri) {
            if (covers[uri]) return covers[uri]
            if (!coversLoaded || coversAsked[uri]) return ""
            coversAsked[uri] = true
            const [, kind, id] = uri.split(":")
            const req = new XMLHttpRequest()
            req.onreadystatechange = () => {
                if (req.readyState !== XMLHttpRequest.DONE || req.status !== 200) return
                try {
                    const url = JSON.parse(req.responseText).thumbnail_url
                    if (!url) return
                    const c = Object.assign({}, covers); c[uri] = url; covers = c
                    coversSave.restart()
                } catch (e) {}
            }
            req.open("GET", "https://open.spotify.com/oembed?url=https://open.spotify.com/" + kind + "/" + id)
            req.send()
            return ""
        }

        // A new Curated list (`deck curate`: Claude Code, a few minutes, on your Claude plan). It runs on its own, so
        // closing the window doesn't stop it; the list shows up when curated.json changes.
        property bool curating: false
        property bool curateAsk: false              // the button's first press asks, the second runs it
        property string curateLine: ""              // the run's latest line in its log
        readonly property string curateLog: home + "/.cache/deck/curate.log"
        function curate() {
            curateAsk = false
            Quickshell.execDetached(["setsid", "-f", deckBin, "curate"])
            curating = true
            curateLine = "Starting Claude…"
        }
        // Setting up Deck with Claude (`deck-window setup`, which asks only for what is missing): offered at the first start
        // (setupPanel) until it is done or put aside, and by Curated's button until it is done
        property bool setupStarted: false
        readonly property bool setupOffer: configRead && prefsRead && setupStateRead && !curatedReady && !prefs.setupDismissed
                                           && (!setupElsewhere || setupStarted)
        // Started elsewhere (Welcome to Nightdrive, the plugin's page: claude-setup marks it in setup.json), the setup isn't
        // offered again at the first start; Curated's button still offers it until it is done
        property bool setupElsewhere: false
        property bool setupStateRead: false
        FileView {
            path: win.home + "/.local/state/nightdrive/setup.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: {
                try { win.setupElsewhere = (JSON.parse(text()).tasks || {}).deck === "started" } catch (e) { win.setupElsewhere = false }
                win.setupStateRead = true
            }
            onLoadFailed: win.setupStateRead = true
        }
        function startSetup() { setupStarted = true; Quickshell.execDetached([home + "/.local/bin/deck-window", "setup"]) }
        function dismissSetup() {
            prefs = Object.assign({}, prefs, { setupDismissed: true })
            prefsFile.setText(JSON.stringify(prefs) + "\n")
            list.forceActiveFocus()
        }
        // Set up while the window is open: Curated, for its New list
        onCuratedReadyChanged: if (curatedReady && setupStarted) pickSection("curated")
        Process {
            id: curateCheck
            // A run (this one, or the weekly one) is going: its latest log line; then "done" and the last line
            command: ["sh", "-c", 'pgrep -f "^[^ ]*deck curate$" >/dev/null && echo run || echo done; tail -n 1 "$1" | cut -c 22-', "sh", win.curateLog]
            stdout: StdioCollector {
                onStreamFinished: {
                    const [state, ...rest] = text.split("\n")
                    const line = rest.join(" ").trim()
                    if (state === "run") { win.curating = true; win.curateLine = line || "Starting Claude…"; return }
                    if (!win.curating) return
                    win.curating = false
                    win.note = /failed/.test(line) ? "Curated failed: " + line.replace(/^=== curate: failed: /, "") : "A new Curated list"
                }
            }
        }
        Timer { interval: 2000; repeat: true; running: true; triggeredOnStart: true; onTriggered: curateCheck.running = true }

        // Genres for the radio: Deck's catalog and your own (`deck genre list`, once), favourites first as on Deck's home
        property var genres: []
        property var favorites: []
        // Deck keeps the names in lowercase; here each word starts with a capital, as the window's other titles (Indie Rock)
        function genreName(name) { return name.replace(/(^|[\s-])(\S)/g, (m, sep, ch) => sep + ch.toUpperCase()) }
        Component.onCompleted: run(["genre", "list"], text => genres = JSON.parse(text).map(g => ({ id: g.id, name: genreName(g.name) })), err => {})
        FileView {
            path: win.home + "/.config/deck/genres.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: { try { win.favorites = JSON.parse(text()).favorites || [] } catch (e) { win.favorites = [] } }
            onLoadFailed: win.favorites = []
        }
        readonly property var genreRows: {
            const fav = favorites.map(id => genres.find(g => g.id === id)).filter(g => g)
            return fav.concat(genres.filter(g => favorites.indexOf(g.id) < 0))
        }

        readonly property var shelfUris: {
            const s = {}
            for (const a of shelf) s[a.uri] = true
            return s
        }
        // Sorted as Deck sorts them: a leading "The" and accents aside
        function sortName(name) { return name.replace(/^the\s+/i, "") }
        readonly property var shelfArtists: {
            const by = {}
            for (const a of shelf) {
                const id = a.artist_id || a.artist
                if (!by[id]) by[id] = { id: a.artist_id, name: a.artist, albums: 0 }
                by[id].albums++
            }
            return Object.values(by).sort((x, y) => sortName(x.name).localeCompare(sortName(y.name), undefined, { sensitivity: "base" }))
        }

        // --- Where you are: a section (the sidebar) and the views opened in it, Esc goes back ---
        readonly property var sections: [
            { id: "shelf", name: "Shelf", glyph: "library" },
            { id: "curated", name: "Curated", glyph: "sparkles" },
            { id: "radio", name: "Radio", glyph: "radio" },
            { id: "search", name: "Search", glyph: "search" },
            { id: "queue", name: "Queue", glyph: "list-music" },
            { id: "history", name: "History", glyph: "history" }
        ]
        property string section: "shelf"
        property var stack: [{ kind: "shelf" }]
        property var cursors: [0]                    // the selected row in each view of the stack below the top one
        // The selected row: kept by hand, because the list's own goes back to the top whenever its rows are made anew
        // (each change of Deck's state does that in the queue)
        property int cursor: 0
        readonly property var view: stack[stack.length - 1]
        // Narrow windows: below onePaneMax the sidebar and the view take turns, as Mail's list and thread: Esc or the back
        // arrow at a section's own view shows the sections, a click or Enter on one its view. ⌘B shows and hides the
        // sidebar, in a wide window too. Below playerMin the player keeps to the controls and the track.
        readonly property int onePaneMax: 720
        readonly property int playerMin: 900
        readonly property bool onePane: width < onePaneMax
        readonly property bool narrowPlayer: width < playerMin
        property var sidebarChoice: null            // ⌘B's, in a wide window
        property bool sectionsOpen: false           // in one pane: the sections show instead of the view
        property string sectionCursor: "shelf"      // the section the keys point at while they show
        readonly property bool sidebarShown: onePane ? sectionsOpen : sidebarChoice !== null ? sidebarChoice : true
        onOnePaneChanged: sectionsOpen = false
        function openSections() { sectionCursor = section; sectionsOpen = true; list.forceActiveFocus() }
        function stepCursor(d) {
            const i = sections.findIndex(s => s.id === sectionCursor) + d
            if (i >= 0 && i < sections.length) sectionCursor = sections[i].id
        }
        function toggleSidebar() {
            if (!onePane) sidebarChoice = !sidebarShown
            else if (sectionsOpen) sectionsOpen = false
            else openSections()
        }
        // A key while the sections show: whether it was theirs
        function sectionKey(k) {
            if (k === Qt.Key_Down || k === Qt.Key_J) stepCursor(1)
            else if (k === Qt.Key_Up || k === Qt.Key_K) stepCursor(-1)
            else if (k === Qt.Key_Home) sectionCursor = sections[0].id
            else if (k === Qt.Key_End) sectionCursor = sections[sections.length - 1].id
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) pickSection(sectionCursor)
            else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) sectionsOpen = false
            else return [Qt.Key_P, Qt.Key_E, Qt.Key_A, Qt.Key_D, Qt.Key_Delete, Qt.Key_F].indexOf(k) >= 0
            return true
        }
        function moveTo(i) { cursor = Math.max(0, Math.min(i, rows.length - 1)); list.currentIndex = cursor }
        function pickSection(id) {
            sectionsOpen = false
            section = id
            cursor = 0
            stack = [{ kind: id }]
            cursors = []
            if (id === "search") searchField.forceActiveFocus()
            else list.forceActiveFocus()
        }
        function push(v) {
            sectionsOpen = false
            cursors = cursors.concat([cursor])
            cursor = 0
            stack = stack.concat([v])
            list.forceActiveFocus()
        }
        function back() {
            if (stack.length < 2 && onePane) { openSections(); return }
            if (stack.length < 2) { if (section === "search") searchField.forceActiveFocus(); return }
            cursor = cursors[cursors.length - 1]
            cursors = cursors.slice(0, -1)
            stack = stack.slice(0, -1)
        }
        // A view whose data arrives later is updated in place, if it is still in the stack
        function update(v, fields) {
            const i = stack.indexOf(v)
            if (i < 0) return
            const s = stack.slice(); s[i] = Object.assign({}, v, fields); stack = s
        }

        function openArtist(artist, fromShelf) {
            const v = { kind: "artist", artist: artist, shelf: fromShelf, albums: null }
            if (fromShelf) v.albums = shelf.filter(a => (a.artist_id || a.artist) === (artist.id || artist.name)).sort((x, y) => (x.year || 0) - (y.year || 0))
            push(v)
            if (!fromShelf) run(["artist-albums", "--json", artist.id], text => update(v, { albums: JSON.parse(text) }), err => update(v, { albums: [], error: err }))
        }
        // An album's artist, from the album's view: all their albums on Spotify (yours marked with the shelf's icon), or
        // only your shelf's when Deck knows no id for the artist
        function artistOnShelf(album) { return shelf.some(a => (a.artist_id || a.artist) === (album.artist_id || album.artist)) }
        function openAlbumArtist() {
            const a = view.album
            openArtist({ id: a.artist_id, name: a.artist }, !a.artist_id)
        }
        function openAlbum(album, from) {
            const v = { kind: "album", album: album, tracks: null, from: from || "" }
            push(v)
            run(["album-tracks", "--json", album.uri], text => {
                const j = JSON.parse(text)
                update(v, { tracks: j.tracks, album: Object.assign({}, j.album, album) })
            }, err => update(v, { tracks: [], error: err }))
        }

        // n, or a click on the player's cover: what plays, in the section you are in (Esc comes back): its album, or the
        // radio's genre
        function openPlaying() {
            if (!info) return
            if (info.album_uri) {
                if (view.kind === "album" && view.album.uri === info.album_uri) return
                openAlbum({ uri: info.album_uri, name: info.album, artist: info.artist })
            } else if (radio) {
                if (view.kind === "station" && view.genre.id === radio.genre) return
                const g = genres.find(g => g.id === radio.genre) || { id: radio.genre, name: genreName(radio.name) }
                push({ kind: "station", genre: g })
            }
        }

        // --- Deck's JSON commands (search, an artist's albums, an album's tracks), one process each ---
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
            runner.createObject(win, { command: [deckBin].concat(args), done: done, failed: failed, running: true })
        }

        property var results: null                   // { query, artists, albums, songs, error }
        property bool searching: false
        Timer { id: searchTimer; interval: win.searchDelay; onTriggered: win.search() }
        function search() {
            const q = searchField.text.trim()
            if (q.length < 2) { results = null; return }
            searching = true
            run(["search", "--json", q], text => {
                const r = JSON.parse(text)
                if (searchField.text.trim() === q) { results = { query: q, artists: r.artists, albums: r.albums, songs: r.songs, error: "" }; searching = false }
            }, e => { results = { query: q, artists: [], albums: [], songs: [], error: e }; searching = false })
        }

        // --- The rows of the view on top: { kind, title, sub, right, mark, data } ---
        function year(a) { return a.year ? String(a.year) : "" }
        function fmt(ms) {
            const s = Math.floor(ms / 1000)
            return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
        }
        readonly property var rows: {
            const v = view, out = []
            if (v.kind === "shelf")
                for (const a of shelfArtists) out.push({ kind: "artist", title: a.name, right: a.albums + (a.albums === 1 ? " album" : " albums"), data: a, shelf: true, cover: a.id ? "spotify:artist:" + a.id : "" })
            else if (v.kind === "history")
                for (const h of history) out.push({ kind: "album", title: h.name, sub: h.artist, right: when(h.at), data: { uri: h.uri, name: h.name, artist: h.artist }, cover: h.uri })
            else if (v.kind === "curated")
                for (const a of curated) out.push({ kind: "album", title: a.name, sub: a.artist + (a.year ? " · " + a.year : ""), note: a.reason || "", data: a, cover: a.uri, right: heard(a.uri) })
            else if (v.kind === "radio")
                for (const g of genreRows) out.push({ kind: "genre", title: g.name, fav: favorites.indexOf(g.id) >= 0, right: radio && radio.genre === g.id ? "Playing" : "", data: g })
            else if (v.kind === "station" && radio && radio.genre === v.genre.id)
                for (const t of radio.tracks) out.push({ kind: "radiotrack", title: t.title, sub: t.artist + " · " + t.album, data: t, cover: t.album_uri })
            else if (v.kind === "search" && results) {
                for (const a of results.artists) out.push({ kind: "artist", title: a.name, right: "Artist", data: a, shelf: false, cover: "spotify:artist:" + a.id })
                for (const a of results.albums) out.push({ kind: "album", title: a.name, sub: a.artist + (a.year ? " · " + a.year : ""), right: "Album", data: a, cover: a.uri })
                for (const s of results.songs) out.push({ kind: "song", title: s.name, sub: s.artist + " · " + s.album.name, right: fmt(s.duration_ms), data: s, cover: s.album.uri })
            }
            else if (v.kind === "queue") {
                // What plays now first, so a track taken from the queue doesn't seem to vanish from it
                if (pendingNext) out.push({ kind: "nowplaying", title: pendingNext.title, sub: "Now playing, from the queue", data: info, cover: pendingNext.album_uri || "" })
                else if (info) out.push({ kind: "nowplaying", title: info.title, sub: info.queued ? "Now playing, from the queue" : "Now playing · " + info.artist + " · " + info.album,
                                          data: info, cover: info.album_uri || "" })
                // The coming track is already the top row
                queue.forEach((t, i) => (pendingNext && t.uri === pendingNext.uri && i === 0) ? null : out.push({ kind: "queued", title: t.title, sub: t.artist, right: fmt(t.duration_ms), data: t, index: i, cover: t.album_uri || "" }))
            }
            else if (v.kind === "artist" && v.albums)
                for (const a of v.albums) out.push({ kind: "album", title: a.name, sub: year(a), data: a, cover: a.uri })
            else if (v.kind === "album" && v.tracks)
                v.tracks.forEach((t, i) => out.push({ kind: "track", title: t.name, by: t.artist !== v.album.artist ? t.artist : "", right: fmt(t.duration_ms), number: i + 1, data: t }))
            return out
        }
        readonly property string heading: {
            const v = view
            if (v.kind === "artist") return v.artist.name
            if (v.kind === "album") return v.album.name
            if (v.kind === "station") return v.genre.name
            return sections.find(s => s.id === v.kind).name
        }
        readonly property string subheading: {
            const v = view
            // The artist is a link of its own before this
            if (v.kind === "album") return year(v.album) ? (v.album.artist ? "· " : "") + year(v.album) : ""
            if (v.kind === "artist") return v.shelf ? "On your shelf" : "On Spotify"
            if (v.kind === "curated") return curating ? curateLine : curated.length ? curated.length + " albums picked for you this week" : ""
            if (v.kind === "queue") return queue.length ? "Plays next, after the current track" : ""
            if (v.kind === "history") return history.length ? "What you have played in the last 30 days" : ""
            if (v.kind === "radio") return "A radio for each genre, your favourites first"
            if (v.kind === "station") return "Genre radio"
            return ""
        }
        readonly property string empty: {
            const v = view
            if (v.error) return v.error
            if (v.kind === "shelf") return "Your shelf is empty: find an album in Search and press a"
            if (v.kind === "curated") return curatedReady ? "No Curated list yet: New list has Claude pick albums from what you play"
                                           : "Albums picked for you, each with a reason: Claude sets it up with you: " + (hasApp ? "" : "your own Spotify app, then ") + "your taste, from Last.fm or in your own words"
            if (v.kind === "search") return results && results.error ? results.error : searching ? "Searching…" : searchField.text.trim().length < 2 ? "Artists, albums and songs on Spotify" : "Nothing found"
            if (v.kind === "queue") return "Nothing queued: e adds an album or a song"
            if (v.kind === "history") return "Nothing yet: the albums you play show up here"
            if (v.kind === "radio") return genres.length ? "" : "Loading…"
            if (v.kind === "station") return radioStarting === v.genre.id ? "Starting the radio…" : "Play starts the radio: songs Spotify picks from the genre's artists"
            if (v.kind === "artist") return v.albums ? "No albums" : "Loading…"
            if (v.kind === "album") return v.tracks ? "No tracks" : "Loading…"
            return ""
        }
        // The album a row stands for, for e and a (a song's or a track's album too)
        function albumOf(row) {
            if (row.kind === "album") return row.data
            if (row.kind === "song") return row.data.album
            if (row.kind === "track") return view.album
            if (row.kind === "radiotrack") return { uri: row.data.album_uri, name: row.data.album }
            if (row.kind === "nowplaying" && row.data.album_uri) return { uri: row.data.album_uri, name: row.data.album }
            if (row.kind === "queued" && row.data.album_uri) return { uri: row.data.album_uri, name: "" }
            return null
        }

        // --- What the keys and clicks do ---
        function activate(row) {
            if (!row) return
            if (row.kind === "artist") openArtist(row.data, row.shelf)
            else if (row.kind === "album") openAlbum(row.data, view.kind)
            // A genre opens to its Play button, as an album does: picking one doesn't stop the music
            else if (row.kind === "genre") push({ kind: "station", genre: row.data })
            else if (row.kind === "nowplaying") openPlaying()
            else if (row.kind === "track") ctl(["play-song", row.data.uri, view.album.uri])
            else if (row.kind === "song") ctl(["play-song", row.data.uri, row.data.album.uri])
        }
        function play(row) {
            const a = row && albumOf(row)
            if (row && (row.kind === "track" || row.kind === "song")) activate(row)
            else if (row && row.kind === "genre") playRadio(row.data)
            else if (view.kind === "station" && (!row || row.kind === "radiotrack")) playRadio(view.genre)
            else if (a) ctl(["play-album", a.uri])
        }
        // A genre's radio: Deck fetches a station first, so the view says it is starting until the radio plays
        property string radioStarting: ""
        Timer { id: radioWait; interval: 20000; onTriggered: win.radioStarting = "" }
        onRadioChanged: if (radio && radio.genre === radioStarting) radioStarting = ""
        function playRadio(g) {
            if (radio && radio.genre === g.id) return
            radioStarting = g.id
            radioWait.restart()
            ctl(["radio", g.id])
        }
        function genreRow(g) { return { kind: "genre", title: g.name, fav: favorites.indexOf(g.id) >= 0, data: g } }
        // Pick for me: Deck draws an album from the shelf or Curated that hasn't played in this round
        function pick(from) {
            ctl(from ? ["pick", from] : ["pick"])
            note = "Picking an album…"
        }
        function enqueue(row) {
            if (!row) return
            if (row.kind === "track") ctl(["queue-song", row.data.uri, view.album.uri])
            else if (row.kind === "song") ctl(["queue-song", row.data.uri, row.data.album.uri])
            else if (row.kind === "album") ctl(["queue-album", row.data.uri])
            else if (row.kind === "radiotrack") ctl(["queue-song", row.data.uri, row.data.album_uri])
            else return
            note = "Queued: " + row.title
        }
        function shelve(row) {
            const a = row ? albumOf(row) : view.kind === "album" ? view.album : null
            if (!a) return
            const on = !!shelfUris[a.uri]
            ctl([on ? "shelf-remove" : "shelf-add", a.uri])
            note = (on ? "Taken off the shelf: " : "On the shelf: ") + (a.name || "the album")
        }
        // d: out of the queue, or out of Curated (Deck keeps it in Curated's history, so it isn't suggested again)
        function remove(row) {
            if (!row) return
            if (row.kind === "queued") ctl(["unqueue", String(row.index)])
            else if (row.kind === "album" && view.kind === "curated") notForMe(row.data)
            else if (view.kind === "album" && curatedUris[view.album.uri]) { notForMe(view.album); back() }
        }
        function favorite(row) {
            if (!row || row.kind !== "genre") return
            ctl([row.fav ? "favorite-remove" : "favorite-add", row.data.id])
            note = (row.fav ? "Not a favourite: " : "A favourite: ") + row.title
        }

        // A quiet line for what just happened; Deck's errors in the danger colour, and longer
        property string note: ""
        property bool noteDanger: false
        onNoteChanged: { noteDanger = false; if (note !== "") { noteTimer.interval = 3000; noteTimer.restart() } }
        Timer { id: noteTimer; onTriggered: win.note = "" }
        function showNote(text, danger) {
            note = ""
            note = text
            noteDanger = danger
            if (danger) { noteTimer.interval = 8000; noteTimer.restart() }
        }

        // `deck-window search QUERY` (the launcher's "Search Spotify" row)
        IpcHandler {
            target: "deck"
            function search(query: string): void {
                win.pickSection("search")
                searchField.text = query
                win.search()
            }
            function section(id: string): void { win.pickSection(id) }
            // A genre's view (its Play button), by Deck's id
            function radio(id: string): void {
                const g = win.genres.find(g => g.id === id)
                if (!g) return
                win.pickSection("radio")
                win.push({ kind: "station", genre: g })
            }
        }

        // ⌘F and / search, ⌘1–6 the sections; Ctrl+Q closes the window (the music plays on). ⌘Q, Hyprland's, quits the player
        // too (plugins/deck/quit-commands)
        Shortcut { sequences: ["Ctrl+F", "/"]; onActivated: win.pickSection("search") }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.toggleSidebar() }
        Shortcut { sequences: ["Ctrl+1", "Meta+1"]; onActivated: win.pickSection("shelf") }
        Shortcut { sequences: ["Ctrl+2", "Meta+2"]; onActivated: win.pickSection("curated") }
        Shortcut { sequences: ["Ctrl+3", "Meta+3"]; onActivated: win.pickSection("radio") }
        Shortcut { sequences: ["Ctrl+4", "Meta+4"]; onActivated: win.pickSection("search") }
        Shortcut { sequences: ["Ctrl+5", "Meta+5"]; onActivated: win.pickSection("queue") }
        Shortcut { sequences: ["Ctrl+6", "Meta+6"]; onActivated: win.pickSection("history") }
        // Ctrl+↑ ↓ the previous and next section, as Mail's folders
        function stepSection(d) {
            const i = sections.findIndex(s => s.id === section) + d
            if (i >= 0 && i < sections.length) pickSection(sections[i].id)
        }
        Shortcut { sequence: "Ctrl+Up"; onActivated: win.stepSection(-1) }
        Shortcut { sequence: "Ctrl+Down"; onActivated: win.stepSection(1) }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            // ? and Ctrl+? show the keys, as in Mail (KeySheet.qml)
            Keys.onPressed: e => sheet.pressed(e)

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Sections: the title level with the view's, the first section level with the first row. In one pane, the
                // whole width while they show.
                AppSidebar {
                    visible: win.sidebarShown
                    Layout.preferredWidth: win.onePane ? -1 : 196
                    Layout.fillWidth: win.onePane
                    c: win.look
                    title: "Deck"
                    headerHeight: win.headerHeight
                    contentTop: win.listTop
                    Repeater {
                        model: win.sections
                        delegate: AppNavRow {
                            required property var modelData
                            c: win.look
                            glyph: modelData.glyph
                            label: modelData.name
                            selected: (win.sectionsOpen ? win.sectionCursor : win.section) === modelData.id
                            count: modelData.id === "queue" && win.queue.length ? win.queue.length
                                 : modelData.id === "curated" && win.curated.length ? win.curated.length : ""
                            onClicked: win.pickSection(modelData.id)
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // The view. While the sections show in one pane it is there at no width: its list keeps the keyboard, so
                // the arrows move in the sections and Space and the rest go on working
                ColumnLayout {
                    Layout.preferredWidth: win.sectionsOpen ? 0 : -1
                    Layout.fillWidth: !win.sectionsOpen
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0

                    // Its title (with the way back), or the search field: as high whatever it holds, with a line under it, so the
                    // first row stays put. Over the list, so its buttons' tips aren't drawn under the first row.
                    Item {
                        z: 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: win.headerHeight
                        ColumnLayout {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 28
                                Layout.rightMargin: 28
                                // As high as the tallest it holds (an album's cover, the buttons), so it centres in the bar
                                Layout.preferredHeight: win.onePane ? 40 : 30
                                spacing: 10
                                // The way back: a button the size of the album buttons, its arrow where the title starts
                                // in a section's own view. In one pane a finger's size, and in a section's own view too,
                                // to the sections.
                                AppIconButton {
                                    visible: win.stack.length > 1 || win.onePane
                                    Layout.leftMargin: win.onePane ? -16 : -8
                                    implicitWidth: win.onePane ? 40 : 30; implicitHeight: win.onePane ? 40 : 28; radius: win.onePane ? 8 : 7
                                    c: win.look
                                    glyph: "arrow-left"; glyphSize: win.onePane ? 17 : 16
                                    tip: win.stack.length > 1 ? "Back" : "Sections"; keys: "Esc"
                                    onClicked: win.back()
                                }
                                // As high as the title's row, so the field sits where the title does
                                AppSearchField {
                                    id: searchField
                                    Layout.fillWidth: true
                                    visible: win.view.kind === "search"
                                    c: win.look
                                    placeholder: "Search Spotify"
                                    onEdited: searchTimer.restart()
                                    onReturnPressed: { searchTimer.stop(); win.search(); list.forceActiveFocus() }
                                    onDownPressed: list.forceActiveFocus()
                                    onEscapePressed: { if (text) { text = ""; win.results = null } else if (win.onePane) win.openSections(); else list.forceActiveFocus() }
                                }
                                // The album's cover, a little taller than the line
                                Image {
                                    visible: win.view.kind === "album"
                                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                                    sourceSize: Qt.size(64, 64)
                                    fillMode: Image.PreserveAspectCrop
                                    source: win.view.kind === "album" ? win.cover(win.view.album.uri) : ""
                                    Rectangle { anchors.fill: parent; color: c.hover; visible: parent.status !== Image.Ready }
                                }
                                Text {
                                    visible: win.view.kind !== "search"
                                    Layout.maximumWidth: implicitWidth
                                    // Narrow, the title is the last to give way
                                    Layout.minimumWidth: Math.min(implicitWidth, 160)
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: win.heading; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.DemiBold
                                }
                                // An album's artist: a click opens the artist's albums
                                Text {
                                    id: albumArtist
                                    readonly property bool linked: win.view.kind === "album" && (!!win.view.album.artist_id || win.artistOnShelf(win.view.album))
                                    visible: win.view.kind === "album" && !!win.view.album.artist
                                    Layout.alignment: Qt.AlignBaseline
                                    Layout.leftMargin: 10
                                    // Its own width (a long name at most this much); the year after it takes the rest
                                    Layout.preferredWidth: Math.min(implicitWidth, 320)
                                    elide: Text.ElideRight
                                    text: visible ? win.view.album.artist : ""
                                    color: arh.hovered && linked ? c.text : c.dim; font.family: c.font; font.pixelSize: 12
                                    font.underline: arh.hovered && linked
                                    HoverHandler { id: arh; enabled: albumArtist.linked; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { enabled: albumArtist.linked; onTapped: win.openAlbumArtist() }
                                    Tip { y: parent.height + 8; c: win.look; text: "Open the artist"; hovered: arh.hovered }
                                }
                                // What it is, quieter on the same line (the album's year, how many Curated has)
                                Text {
                                    visible: win.view.kind !== "search"
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignBaseline
                                    Layout.leftMargin: albumArtist.visible ? -4 : 10      // after the artist, a space's width (the row's spacing is 10)
                                    elide: Text.ElideRight
                                    text: win.subheading; color: c.dim; font.family: c.font; font.pixelSize: 12
                                }
                                // An album's own buttons, as Curated's New list: play it, queue it, shelve it. The tip tells the key.
                                Repeater {
                                    model: win.view.kind === "shelf" && win.shelf.length ? [
                                        { glyph: "dices", label: "Pick for me", tip: "An album you haven't played in a while", keys: "r", act: () => win.pick("shelf") }
                                    ] : win.view.kind === "queue" ? (win.queue.length === 0 ? [] : [
                                        // The queue plays when its first track does: Next takes it
                                        win.info && win.info.queued
                                            ? { glyph: "check", label: "Playing", tip: "The queue plays", keys: "", act: () => {} }
                                            : { glyph: "play", label: "Play", tip: "Play the queue now", keys: "", act: () => win.next() },
                                        { glyph: "trash-2", label: "Empty queue", tip: "Take everything off the queue", keys: "", act: () => { win.ctl(["queue-clear"]); win.note = "The queue is empty" } }
                                    ]) : win.view.kind === "station" ? [
                                        win.radio && win.radio.genre === win.view.genre.id
                                            ? { glyph: "check", label: "Playing", tip: "The radio plays", keys: "", act: () => {} }
                                            : { glyph: "play", label: "Play", tip: "Play the radio", keys: "p", act: () => win.playRadio(win.view.genre) },
                                        win.favorites.indexOf(win.view.genre.id) >= 0
                                            ? { glyph: "star", on: true, label: "Favourite", tip: "Not a favourite", keys: "f", act: () => win.favorite(win.genreRow(win.view.genre)) }
                                            : { glyph: "star", label: "Favourite", tip: "A favourite genre, on Deck's home", keys: "f", act: () => win.favorite(win.genreRow(win.view.genre)) }
                                    ] : win.view.kind === "album" ? [
                                        // While this album plays the button pauses it, and resumes it when paused, so a press shows
                                        win.info && win.info.album_uri === win.view.album.uri
                                            ? (win.playing ? { glyph: "pause", label: "Pause", tip: "Pause the album", keys: "Space", act: () => win.togglePlay() }
                                                           : { glyph: "play", label: "Resume", tip: "Go on with the album", keys: "Space", act: () => win.togglePlay() })
                                            : { glyph: "play", label: "Play", tip: "Play the album", keys: "p", act: () => win.ctl(["play-album", win.view.album.uri]) },
                                        { glyph: "list-plus", label: "Queue", tip: "Queue the album", keys: "e", act: () => { win.ctl(["queue-album", win.view.album.uri]); win.note = "Queued: " + win.view.album.name } },
                                        win.shelfUris[win.view.album.uri]
                                            ? { glyph: "check", label: "On the shelf", tip: "Take it off the shelf", keys: "a", act: () => win.shelve(null) }
                                            : { glyph: "library", label: "Shelf", tip: "Put it on the shelf", keys: "a", act: () => win.shelve(null) }
                                    ].concat(win.curatedUris[win.view.album.uri] ? [
                                        // A Curated suggestion: out of the list, and the next one learns from it
                                        { glyph: "thumbs-down", label: "Not for me", tip: "Out of Curated: no more like it", keys: "d", act: () => { win.notForMe(win.view.album); win.back() } }
                                    ] : []) : []
                                    // In one pane the glyphs alone, the tip saying what each does
                                    delegate: AppButton {
                                        required property var modelData
                                        c: win.look
                                        glyph: modelData.glyph; label: win.onePane ? "" : modelData.label
                                        on: !!modelData.on || modelData.glyph === "check"
                                        tip: win.onePane ? modelData.label + ": " + modelData.tip : modelData.tip; keys: modelData.keys
                                        onClicked: modelData.act()
                                    }
                                }
                                // Curated: a new list by Claude. The first press says what it does, the second does it.
                                Text {
                                    visible: win.view.kind === "curated" && win.curateAsk
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: implicitWidth
                                    elide: Text.ElideRight
                                    text: "Claude picks new albums in a few minutes, on your Claude plan"
                                    color: c.dim; font.family: c.font; font.pixelSize: 12
                                }
                                Repeater {
                                    model: win.view.kind !== "curated" || win.curating ? []
                                         : !win.curatedReady ? [{ label: win.setupStarted ? "Open Claude again" : "Set up with Claude", glyph: "sparkles", strong: true, act: () => win.startSetup() }]
                                         : win.curateAsk ? [{ label: "Make it", glyph: "sparkles", strong: true, act: () => win.curate() },
                                                            { label: "Cancel", glyph: "", strong: false, act: () => win.curateAsk = false }]
                                         : (win.curated.length ? [{ label: "Pick for me", glyph: "dices", strong: false, tip: "An album you haven't played in a while", keys: "r", act: () => win.pick("curated") }] : [])
                                           .concat([{ label: "New list", glyph: "refresh-cw", strong: false, tip: "Claude picks new albums", act: () => win.curateAsk = true }])
                                    // The one to press keeps its label in one pane, the others are their glyphs
                                    delegate: AppButton {
                                        required property var modelData
                                        c: win.look
                                        glyph: modelData.glyph; label: win.onePane && !modelData.strong && modelData.glyph ? "" : modelData.label
                                        tip: win.onePane && modelData.tip ? modelData.label + ": " + modelData.tip : ""; keys: modelData.keys || ""
                                        strong: modelData.strong
                                        onClicked: modelData.act()
                                    }
                                }
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: c.divider }

                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        clip: true
                        focus: true
                        model: win.rows
                        onModelChanged: currentIndex = Math.max(0, Math.min(win.cursor, count - 1))
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 0
                        spacing: 2
                        // Inside the list, so rows scroll up to the line
                        topMargin: win.listGap
                        bottomMargin: 12
                        TouchScroll { view: list }
                        readonly property var row: win.rows[currentIndex]
                        // The track numbers' column: as wide as the longest number here (12 tracks: two digits), or the
                        // playing track's note
                        TextMetrics { id: numberMetrics; font.family: c.font; font.pixelSize: 11; text: String(list.count) }
                        readonly property real leadWidth: Math.max(Math.ceil(numberMetrics.advanceWidth), 14)
                        Keys.onPressed: e => {
                            const k = e.key
                            if (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier)) return
                            // The list takes most keys before they reach the sheet: any but ? closes it here
                            if (sheet.shown && k !== Qt.Key_Question && sheet.modifierKeys.indexOf(k) < 0) sheet.shown = false
                            // The sections on show (one pane): the keys move in them and Enter opens one; the player's keys
                            // work as ever, and what acts on a row of the view out of sight does nothing
                            if (win.sectionsOpen && win.sectionKey(k)) { e.accepted = true; return }
                            if (k === Qt.Key_Down || k === Qt.Key_J) win.moveTo(currentIndex + 1)
                            else if (k === Qt.Key_Up || k === Qt.Key_K) {
                                if (currentIndex > 0) win.moveTo(currentIndex - 1)
                                else if (win.view.kind === "search") searchField.forceActiveFocus()
                            }
                            else if (k === Qt.Key_Return || k === Qt.Key_Enter) win.activate(row)
                            else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) win.back()
                            else if (k === Qt.Key_Space) win.togglePlay()
                            else if (k === Qt.Key_Left) win.ctl(["previous"])
                            else if (k === Qt.Key_Right) win.next()
                            else if (k === Qt.Key_P) win.play(row)
                            else if (k === Qt.Key_E) win.enqueue(row)
                            else if (k === Qt.Key_A) win.shelve(row)
                            else if (k === Qt.Key_L) win.toggleLike()
                            else if (k === Qt.Key_D || k === Qt.Key_Delete) win.remove(row)
                            else if (k === Qt.Key_F) win.favorite(win.view.kind === "station" ? win.genreRow(win.view.genre) : row)
                            else if (k === Qt.Key_O) outputs.visible = !outputs.visible
                            else if (k === Qt.Key_N) win.openPlaying()
                            else if (k === Qt.Key_R) win.pick(win.section === "curated" ? "curated" : win.section === "shelf" ? "shelf" : "")
                            else if (k === Qt.Key_Comma) win.seek((win.position - 10000) / win.duration)
                            else if (k === Qt.Key_Period) win.seek((win.position + 10000) / win.duration)
                            else if (k === Qt.Key_Question) sheet.shown = !sheet.shown
                            else if (k === Qt.Key_Home) win.moveTo(0)
                            else if (k === Qt.Key_End) win.moveTo(count - 1)
                            else return
                            e.accepted = true
                        }
                        delegate: AppRow {
                            id: r
                            required property var modelData
                            required property int index
                            readonly property bool current: index === list.currentIndex
                            // The playing track, or the album it plays from
                            readonly property bool now: win.info !== null && (
                                modelData.kind === "nowplaying" ||
                                (modelData.kind === "track" || modelData.kind === "song" || modelData.kind === "radiotrack") && modelData.data.uri === win.info.track_uri
                                || modelData.kind === "album" && modelData.data.uri === win.info.album_uri
                                || modelData.kind === "genre" && win.radio !== null && win.radio.genre === modelData.data.id)
                            // An album on your shelf has the shelf's icon (Deck's green ●); a favourite genre has a star
                            readonly property bool dotted: modelData.kind === "album" && win.view.kind !== "shelf" && !!win.shelfUris[modelData.data.uri]
                            // A cover beside a reason (Curated) is as tall as the texts; beside a line or two, a small one
                            readonly property bool tall: !!modelData.cover && !!modelData.note
                            implicitHeight: Math.max(body.implicitHeight, art.visible ? art.height : 0) + 20
                            c: win.look
                            selected: current && list.activeFocus
                            marked: current
                            TapHandler {
                                // An artist, an album or a genre opens with one click (only browsing: Esc comes back); a song plays
                                // with two, so picking one doesn't stop the music
                                onTapped: {
                                    win.moveTo(r.index); list.forceActiveFocus()
                                    if (["artist", "album", "genre"].indexOf(r.modelData.kind) >= 0) win.activate(r.modelData)
                                }
                                onDoubleTapped: if (["artist", "album", "genre"].indexOf(r.modelData.kind) < 0) win.activate(r.modelData)
                            }
                            Text {
                                id: lead
                                x: 14; width: list.leadWidth
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                visible: (r.modelData.number !== undefined || r.now) && r.modelData.cover === undefined
                                text: r.now ? Icons.g("music") : r.modelData.number || ""
                                font.family: r.now ? Icons.family : c.font; font.pixelSize: r.now ? 13 : 11
                                color: r.now ? c.primary : c.faint
                            }
                            // An album's cover (Curated's as tall as the texts beside it with a two-line reason, its top at
                            // theirs: a selected row's longer reason runs on below it)
                            // (From the fonts, not the texts' heights: those hang on the width, which hangs on the cover)
                            FontMetrics { id: titleMetrics; font: titleText.font }
                            FontMetrics { id: subMetrics; font: subText.font }
                            FontMetrics { id: noteMetrics; font: noteText.font }
                            Image {
                                id: art
                                visible: r.modelData.cover !== undefined
                                x: 12
                                anchors.top: r.tall ? body.top : undefined
                                anchors.verticalCenter: r.tall ? undefined : parent.verticalCenter
                                height: r.tall ? Math.ceil(titleMetrics.height) + Math.ceil(subMetrics.height) + subText.bottomPadding + 2 * Math.ceil(noteMetrics.height * noteText.lineHeight) + 2 * body.spacing
                                               : 36
                                width: height
                                sourceSize: Qt.size(128, 128)
                                fillMode: Image.PreserveAspectCrop
                                source: r.modelData.cover ? win.cover(r.modelData.cover) : ""
                                Rectangle { anchors.fill: parent; color: c.hover; visible: parent.status !== Image.Ready }
                            }
                            Column {
                                id: body
                                anchors.left: art.visible ? art.right : lead.visible ? lead.right : parent.left
                                anchors.leftMargin: art.visible ? (r.tall ? 17 : 14) : lead.visible ? 14 : 16
                                anchors.right: right.left; anchors.rightMargin: 16
                                // Beside a tall cover from the top, so a one-line reason doesn't leave the cover hanging below
                                anchors.top: r.tall ? parent.top : undefined
                                anchors.topMargin: 10
                                anchors.verticalCenter: r.tall ? undefined : parent.verticalCenter
                                spacing: 3
                                Row {
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        id: titleText
                                        width: Math.min(implicitWidth, parent.width - (dot.visible ? dot.implicitWidth + 8 : 0) - (star.visible ? star.implicitWidth + 8 : 0) - (byText.visible ? Math.min(byText.implicitWidth, parent.width / 3) : 0))
                                        elide: Text.ElideRight
                                        text: r.modelData.title
                                        font.family: c.font; font.pixelSize: 13
                                        color: r.now ? c.accent : c.title
                                    }
                                    // A track's own artists, when not the album's: after its name, as quiet as a second line
                                    Text {
                                        id: byText
                                        visible: !!r.modelData.by
                                        anchors.baseline: titleText.baseline
                                        width: Math.min(implicitWidth, parent.width - titleText.width - parent.spacing)
                                        elide: Text.ElideRight
                                        text: "– " + (r.modelData.by || "")
                                        font.family: c.font; font.pixelSize: 12; color: c.dim
                                    }
                                    // On your shelf: the shelf's icon, as the player's button by the playing album
                                    Text {
                                        id: dot
                                        visible: r.dotted
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Icons.g("library"); font.family: Icons.family; font.pixelSize: 12
                                        color: c.primary
                                    }
                                    Text {
                                        id: star
                                        visible: !!r.modelData.fav
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Icons.g("star"); font.family: Icons.family; font.pixelSize: 12
                                        color: c.primary
                                    }
                                }
                                Text {
                                    id: subText
                                    visible: !!r.modelData.sub
                                    bottomPadding: r.modelData.note ? 5 : 0     // a little air before the reason
                                    width: parent.width; elide: Text.ElideRight
                                    text: r.modelData.sub || ""
                                    font.family: c.font; font.pixelSize: 12; color: c.dim
                                }
                                Text {
                                    id: noteText
                                    visible: !!r.modelData.note
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: r.current ? 6 : 2
                                    elide: Text.ElideRight
                                    text: r.modelData.note || ""
                                    font.family: c.font; font.pixelSize: 11; color: c.faint; lineHeight: 1.2
                                }
                            }
                            // On the right: a duration or a year, or for the queue's playing track the note the album's
                            // list shows on the left
                            Text {
                                id: right
                                anchors.right: parent.right; anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property bool note: r.modelData.kind === "nowplaying"
                                text: note ? Icons.g("music") : r.modelData.right || ""
                                font.family: note ? Icons.family : c.font; font.pixelSize: note ? 13 : 11
                                // A Curated album you have listened to, in the theme's colour
                                color: note || r.modelData.right === "Listened" ? c.primary : c.faint
                            }
                        }
                        // An empty view: what it is in light text ("Nothing yet"), and what to do below it, quieter (the
                        // part of win.empty after its first ": ")
                        Column {
                            id: emptyNote
                            readonly property int cut: win.empty.indexOf(": ")
                            visible: list.count === 0
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 48, 420)
                            spacing: 6
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: emptyNote.cut < 0 ? win.empty : win.empty.slice(0, emptyNote.cut)
                                color: c.text; font.family: c.font; font.pixelSize: 13
                            }
                            Text {
                                visible: emptyNote.cut >= 0
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: emptyNote.cut < 0 ? "" : win.empty.slice(emptyNote.cut + 2).replace(/^./, ch => ch.toUpperCase())
                                color: c.faint; font.family: c.font; font.pixelSize: 12
                            }
                        }
                    }
                }
            }

            // The player
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: c.divider }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 28
                    spacing: 16
                    Item {
                        Layout.preferredWidth: 60; Layout.preferredHeight: 60
                        Image {
                            id: cover
                            anchors.fill: parent
                            sourceSize: Qt.size(120, 120)
                            fillMode: Image.PreserveAspectCrop
                            source: win.info && win.info.cover ? win.info.cover : ""
                            visible: source !== "" && status === Image.Ready
                        }
                        HoverHandler { id: cvh; enabled: !!win.info; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: !!win.info; onTapped: win.openPlaying() }
                        Tip { y: -height - 10; c: win.look; text: win.info && win.info.album_uri ? "Open the album" : "Open the radio"; keys: "n"; hovered: cvh.hovered }
                        Rectangle {
                            anchors.fill: parent; radius: 6
                            visible: !cover.visible
                            color: c.hover
                            Text { anchors.centerIn: parent; text: Icons.g("disc-3"); color: c.dim; font.family: Icons.family; font.pixelSize: 24 }
                        }
                    }
                    // A narrow player gives the track what the controls leave, and the note its second line
                    Column {
                        Layout.preferredWidth: win.narrowPlayer ? 1 : 260
                        Layout.fillWidth: win.narrowPlayer
                        // Room before the playhead's time, so a long album name doesn't run up to it
                        Layout.rightMargin: 16
                        spacing: 3
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: win.info ? win.info.title : win.alive ? "Nothing playing" : "Deck isn't running"
                            color: win.info ? c.accent : c.dim; font.family: c.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Row {
                            width: parent.width
                            visible: !!win.info && !playerNote.visible
                            spacing: 8
                            Text {
                                width: Math.min(implicitWidth, parent.width - (shelfButton.visible ? shelfButton.width + 8 : 0))
                                elide: Text.ElideRight
                                text: win.info ? win.info.artist + " · " + win.info.album : ""
                                color: c.dim; font.family: c.font; font.pixelSize: 12
                            }
                            // The playing album on the shelf, or off it: by the album's name, so it doesn't read as the
                            // heart's (which is the track's). Not for a radio track: Deck knows no album for it.
                            Text {
                                id: shelfButton
                                readonly property string uri: win.info && win.info.album_uri ? win.info.album_uri : ""
                                readonly property bool on: !!win.shelfUris[uri]
                                anchors.verticalCenter: parent.verticalCenter
                                visible: uri !== ""
                                text: Icons.g("library")
                                color: on || sbh.hovered ? c.primary : c.faint
                                font.family: Icons.family; font.pixelSize: 14
                                HoverHandler { id: sbh; cursorShape: Qt.PointingHandCursor }
                                Tip { x: (parent.width - width) / 2; y: -height - 10; c: win.look; text: shelfButton.on ? "Take the album off the shelf" : "Put the album on the shelf"; hovered: sbh.hovered }
                                TapHandler {
                                    onTapped: {
                                        win.ctl([shelfButton.on ? "shelf-remove" : "shelf-add", shelfButton.uri])
                                        win.note = (shelfButton.on ? "Taken off the shelf: " : "On the shelf: ") + win.info.album
                                    }
                                }
                            }
                        }
                        Text {
                            id: playerNote
                            visible: win.narrowPlayer && win.note !== ""
                            width: parent.width; elide: Text.ElideRight
                            text: win.note
                            color: win.noteDanger ? c.danger : c.dim; font.family: c.font; font.pixelSize: 11
                        }
                        Text {
                            visible: !win.alive && !playerNote.visible
                            text: "Start Deck"
                            color: sth.hovered ? c.primary : c.text; font.family: c.font; font.pixelSize: 12
                            HoverHandler { id: sth; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: win.startDeck() }
                        }
                    }
                    // Controls over the playhead; a click or a drag on the bar jumps
                    ColumnLayout {
                        Layout.fillWidth: !win.narrowPlayer
                        Layout.preferredWidth: win.narrowPlayer ? 170 : -1
                        spacing: 8
                        opacity: win.info ? 1 : 0.35
                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 26
                            Repeater {
                                model: [
                                    { glyph: "skip-back", size: 18, act: "previous", tip: "Previous track", keys: "←" },
                                    { glyph: "play", size: 24, act: "toggle", tip: "Play, pause", keys: "Space" },
                                    { glyph: "skip-forward", size: 18, act: "next", tip: "Next track", keys: "→" }
                                ]
                                delegate: Text {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Icons.g(modelData.act === "toggle" ? (win.playing ? "pause" : "play") : modelData.glyph)
                                    color: ch.hovered ? c.primary : c.text
                                    font.family: Icons.family; font.pixelSize: modelData.size
                                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                                    Tip { x: (parent.width - width) / 2; y: -height - 10; c: win.look; text: modelData.tip; keys: modelData.keys; hovered: ch.hovered }
                                    TapHandler { onTapped: modelData.act === "toggle" ? win.togglePlay() : modelData.act === "next" ? win.next() : win.ctl([modelData.act]) }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text { text: win.fmt(bar.dragAt >= 0 ? bar.dragAt * win.duration : win.position); color: c.faint; font.family: c.font; font.pixelSize: 10 }
                            // The bar stays 3 px; what takes the pointer is taller, so it is easy to hit
                            Item {
                                id: bar
                                Layout.fillWidth: true; implicitHeight: 16
                                property real dragAt: -1          // while dragging: where it will jump, 0–1
                                readonly property real shown: dragAt >= 0 ? dragAt : win.duration > 0 ? win.position / win.duration : 0
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: seekArea.containsMouse || bar.dragAt >= 0 ? 5 : 3; radius: height / 2
                                    color: c.line
                                    Rectangle { width: parent.width * bar.shown; height: parent.height; radius: parent.radius; color: c.primary }
                                }
                                MouseArea {
                                    id: seekArea
                                    anchors.fill: parent
                                    enabled: !!win.info && win.duration > 0
                                    hoverEnabled: true
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onPressed: m => bar.dragAt = Math.max(0, Math.min(1, m.x / width))
                                    onPositionChanged: m => { if (pressed) bar.dragAt = Math.max(0, Math.min(1, m.x / width)) }
                                    onReleased: { win.seek(bar.dragAt); bar.dragAt = -1 }
                                    onCanceled: bar.dragAt = -1
                                }
                            }
                            Text { text: win.fmt(win.duration); color: c.faint; font.family: c.font; font.pixelSize: 10 }
                        }
                    }
                    Item {
                        Layout.preferredWidth: win.narrowPlayer ? speaker.width + (heart.visible ? 18 + heart.width : 0) : 260
                        Layout.fillHeight: true
                        Text {
                            visible: !win.narrowPlayer
                            anchors.right: speaker.left; anchors.rightMargin: 18
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                            text: win.note
                            color: win.noteDanger ? c.danger : c.dim; font.family: c.font; font.pixelSize: 11
                        }
                        // Where the sound goes: the same list as the Sound menu's
                        Text {
                            id: speaker
                            anchors.right: heart.visible ? heart.left : parent.right; anchors.rightMargin: heart.visible ? 18 : 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: Icons.g("speaker")
                            color: outputs.visible || oh.hovered ? c.primary : c.dim
                            font.family: Icons.family; font.pixelSize: 18
                            HoverHandler { id: oh; cursorShape: Qt.PointingHandCursor }
                            // Ending at the button's right edge, as the heart's: the window's edge is near
                            Tip { x: parent.width - width; y: -height - 10; c: win.look; text: "Where the sound plays"; keys: "o"; hovered: oh.hovered && !outputs.visible }
                            TapHandler { onTapped: outputs.visible = !outputs.visible }
                        }
                        Text {
                            id: heart
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            visible: win.liked !== null && win.liked !== undefined
                            text: Icons.g("heart")
                            color: win.liked ? c.primary : lh.hovered ? c.primary : c.dim
                            font.family: Icons.family; font.pixelSize: 18
                            HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
                            Tip { x: parent.width - width; y: -height - 10; c: win.look; text: win.liked ? "Unlike the track" : "Like the track"; keys: "l"; hovered: lh.hovered }
                            TapHandler { onTapped: win.toggleLike() }
                        }
                    }
                }
            }
        }

        readonly property QtObject look: c
        readonly property var keyHelp: [
            { title: "Browse", keys: [["↑ ↓  j k", "Move"], ["⏎", "Open, or play a song"], ["Esc  ⌫", "Back; at a section, narrow: the sections"], ["⌘1 … ⌘6", "Shelf, Curated, Radio, Search, Queue, History"], ["Ctrl ↑ ↓", "Previous, next section"], ["⌘B", "Show or hide the sections"], ["⌘F  /", "Search Spotify"], ["n", "What plays: its album or radio"], ["r", "Pick for me: an album you haven't played lately"],
                                      ["f", "A favourite genre, or not"], ["d", "Out of the queue; Not for me in Curated"]] },
            { title: "Play", keys: [["Space", "Play, pause"], ["← →", "Previous, next track"], [", .", "Back, ahead 10 seconds"], ["p", "Play the album, song or radio"], ["e", "Queue the album or song"], ["a", "On the shelf, or off it"],
                                    ["l", "Like the playing track"], ["o", "Where the sound plays"], ["?  Ctrl ?", "These keys"]] }
        ]
        KeySheet { id: sheet; c: win.look; groups: win.keyHelp }

        // The first start: Deck plays as it is; your own Spotify app and Last.fm make the rest work. Enter (or the button)
        // opens Claude Code in a terminal to set up what is missing (`deck-window setup`); Esc or a click outside puts it
        // aside, and Curated's own button offers it again.
        AppPanel {
            id: setupPanel
            visible: win.setupOffer
            c: win.look
            onVisibleChanged: if (visible) forceActiveFocus()
            onOutsideTapped: win.dismissSetup()
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.startSetup()
                else if (e.key === Qt.Key_Escape) win.dismissSetup()
                e.accepted = true
            }
            Text { text: win.hasApp ? "Curated: albums picked for you" : "Set up Deck"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
            Text {
                width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2; color: c.text; font.family: c.font; font.pixelSize: 12
                text: win.setupStarted
                    ? "Claude opens in a terminal and goes through it with you. When it's done, Curated's New list makes your first list here."
                    : win.hasApp
                    ? "Deck plays your Spotify as it is. Curated adds a list of albums you haven't heard, each with a reason why it is there for you, picked by Claude from your Last.fm listening history, or without it, from what you tell about your taste and play in Deck. Claude can set it up with you in a terminal, a step at a time."
                    : "Deck plays your Spotify as it is. Two things make the rest work: your own Spotify app (free, a couple of minutes), for likes, search without Spotify's shared limits and Curated; and your taste, for Curated: a list of albums you haven't heard, each with a reason, picked by Claude from your Last.fm history or from what you tell it. Claude can set them up with you in a terminal, a step at a time. You sign in to Spotify only in your browser."
            }
            Row {
                spacing: 28
                AppKeyAction {
                    c: win.look
                    keys: "⏎"; label: win.setupStarted ? "Open Claude again" : "Set up with Claude"; color: c.primary; hoverColor: c.title
                    onClicked: win.startSetup()
                }
                AppKeyAction {
                    c: win.look
                    keys: "esc"; label: win.setupStarted ? "Close" : "Not now"
                    onClicked: win.dismissSetup()
                }
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap; color: c.faint; font.family: c.font; font.pixelSize: 11
                text: "Later: Curated (⌘2) has the same button. To do it yourself: Deck's README, " + (win.hasApp ? "" : "Create your own Spotify app and ") + "Setting up Curated."
            }
        }

        // The sound outputs, just above the speaker button. A click anywhere else, on the button too, or Esc closes them.
        Item {
            id: outputs
            anchors.fill: parent
            visible: false
            // Where the button is, taken when the list opens (the window may have been resized since)
            property point at: Qt.point(0, 0)
            onVisibleChanged: {
                if (visible) at = speaker.mapToItem(outputs, speaker.width / 2, 0)
                else list.forceActiveFocus()
            }
            // Over everything, so the click that closes the list doesn't also reach what is under it
            MouseArea { anchors.fill: parent; onClicked: outputs.visible = false }
            Rectangle {
                width: 320
                height: outCol.implicitHeight + 26
                x: Math.min(outputs.at.x + 28 - width, parent.width - width - 12)
                y: outputs.at.y - height - 12
                radius: 10
                // The window's own colour, a step darker, so the list stands out from what is under it
                color: Qt.darker(c.solid, 1.05)
                border.color: c.line
                // Clicks between the rows stay on the list
                MouseArea { anchors.fill: parent }
                Column {
                    id: outCol
                    x: 10; y: 14
                    width: parent.width - 20
                    spacing: 8
                    Text { leftPadding: 10; text: "Sound output"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                    OutputList { active: outputs.visible; width: parent.width }
                }
            }
            Shortcut { enabled: outputs.visible; sequence: "Escape"; onActivated: outputs.visible = false }
        }
    }
}
