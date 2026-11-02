import QtQuick
import Quickshell.Io

// Deck's own files, read and watched: the shelf, Curated, what you have listened to and played lately, and the genres
// for the radio with your favourites. Its own file so the views and the actions share one copy of them, and what is
// worked out from them (the shelf's artists, which albums are where) is worked out once.
Item {
    id: root
    required property var win

    property var shelf: []
    property var curated: []
    FileView {
        path: root.win.home + "/.config/deck/shelf.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.shelf = JSON.parse(text()) } catch (e) { root.shelf = [] } }
    }
    FileView {
        path: root.win.home + "/.config/deck/curated.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.curated = JSON.parse(text()).albums || [] } catch (e) { root.curated = [] } }
    }
    // What you have listened to in Deck: a track halfway counts, an album with half its tracks is listened
    property var listened: ({})
    FileView {
        path: root.win.home + "/.local/state/deck/listened.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.listened = JSON.parse(text()) } catch (e) { root.listened = {} } }
    }
    // What you have played lately, album by album, newest first (Deck keeps 30 days)
    property var history: []
    FileView {
        path: root.win.home + "/.local/state/deck/history.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.history = JSON.parse(text()) } catch (e) { root.history = [] } }
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

    // Genres for the radio: Deck's catalog and your own (`deck genre list`, once), favourites first as on Deck's home
    property var genres: []
    property var favorites: []
    // Deck keeps the names in lowercase; here each word starts with a capital, as the window's other titles (Indie Rock)
    function genreName(name) { return name.replace(/(^|[\s-])(\S)/g, (m, sep, ch) => sep + ch.toUpperCase()) }
    Component.onCompleted: win.deck.run(["genre", "list"], text => genres = JSON.parse(text).map(g => ({ id: g.id, name: genreName(g.name) })), err => {})
    FileView {
        path: root.win.home + "/.config/deck/genres.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.favorites = JSON.parse(text()).favorites || [] } catch (e) { root.favorites = [] } }
        onLoadFailed: root.favorites = []
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
}
