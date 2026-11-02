import QtQuick

// What the view on top shows: its rows ({ kind, title, sub, right, mark, data }), its title and the line beside it, and
// what an empty one says. Its own file so the list and the header draw from one description of each view, apart from
// how they draw it (ViewList, ViewHeader).
QtObject {
    id: root
    required property var win

    function year(a) { return a.year ? String(a.year) : "" }
    function fmt(ms) {
        const s = Math.floor(ms / 1000)
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    readonly property var rows: {
        const v = win.nav.view, lib = win.lib, p = win.player, out = []
        const radio = p.radio, results = win.deck.results
        if (v.kind === "shelf")
            for (const a of lib.shelfArtists) out.push({ kind: "artist", title: a.name, right: a.albums + (a.albums === 1 ? " album" : " albums"), data: a, shelf: true, cover: a.id ? "spotify:artist:" + a.id : "" })
        else if (v.kind === "history")
            for (const h of lib.history) out.push({ kind: "album", title: h.name, sub: h.artist, right: lib.when(h.at), data: { uri: h.uri, name: h.name, artist: h.artist }, cover: h.uri })
        else if (v.kind === "curated")
            for (const a of lib.curated) out.push({ kind: "album", title: a.name, sub: a.artist + (a.year ? " · " + a.year : ""), note: a.reason || "", data: a, cover: a.uri, right: lib.heard(a.uri) })
        else if (v.kind === "radio")
            for (const g of lib.genreRows) out.push({ kind: "genre", title: g.name, fav: lib.favorites.indexOf(g.id) >= 0, right: radio && radio.genre === g.id ? "Playing" : "", data: g })
        else if (v.kind === "station" && radio && radio.genre === v.genre.id)
            for (const t of radio.tracks) out.push({ kind: "radiotrack", title: t.title, sub: t.artist + " · " + t.album, data: t, cover: t.album_uri })
        else if (v.kind === "search" && results) {
            for (const a of results.artists) out.push({ kind: "artist", title: a.name, right: "Artist", data: a, shelf: false, cover: "spotify:artist:" + a.id })
            for (const a of results.albums) out.push({ kind: "album", title: a.name, sub: a.artist + (a.year ? " · " + a.year : ""), right: "Album", data: a, cover: a.uri })
            for (const s of results.songs) out.push({ kind: "song", title: s.name, sub: s.artist + " · " + s.album.name, right: fmt(s.duration_ms), data: s, cover: s.album.uri })
        }
        else if (v.kind === "queue") {
            const info = p.info, pendingNext = p.pendingNext
            // What plays now first, so a track taken from the queue doesn't seem to vanish from it
            if (pendingNext) out.push({ kind: "nowplaying", title: pendingNext.title, sub: "Now playing, from the queue", data: info, cover: pendingNext.album_uri || "" })
            else if (info) out.push({ kind: "nowplaying", title: info.title, sub: info.queued ? "Now playing, from the queue" : "Now playing · " + info.artist + " · " + info.album,
                                      data: info, cover: info.album_uri || "" })
            // The coming track is already the top row
            p.queue.forEach((t, i) => (pendingNext && t.uri === pendingNext.uri && i === 0) ? null : out.push({ kind: "queued", title: t.title, sub: t.artist, right: fmt(t.duration_ms), data: t, index: i, cover: t.album_uri || "" }))
        }
        else if (v.kind === "artist" && v.albums)
            for (const a of v.albums) out.push({ kind: "album", title: a.name, sub: year(a), data: a, cover: a.uri })
        else if (v.kind === "album" && v.tracks)
            v.tracks.forEach((t, i) => out.push({ kind: "track", title: t.name, by: t.artist !== v.album.artist ? t.artist : "", right: fmt(t.duration_ms), number: i + 1, data: t }))
        return out
    }
    readonly property string heading: {
        const v = win.nav.view
        if (v.kind === "artist") return v.artist.name
        if (v.kind === "album") return v.album.name
        if (v.kind === "station") return v.genre.name
        return win.nav.sections.find(s => s.id === v.kind).name
    }
    readonly property string subheading: {
        const v = win.nav.view
        // The artist is a link of its own before this
        if (v.kind === "album") return year(v.album) ? (v.album.artist ? "· " : "") + year(v.album) : ""
        if (v.kind === "artist") return v.shelf ? "On your shelf" : "On Spotify"
        if (v.kind === "curated") return win.lib.curated.length ? win.lib.curated.length + " albums picked for you this week" : ""
        if (v.kind === "queue") return win.player.queue.length ? "Plays next, after the current track" : ""
        if (v.kind === "history") return win.lib.history.length ? "What you have played in the last 30 days" : ""
        if (v.kind === "radio") return "A radio for each genre, your favourites first"
        if (v.kind === "station") return "Genre radio"
        return ""
    }
    readonly property string empty: {
        const v = win.nav.view, results = win.deck.results
        if (v.error) return v.error
        if (v.kind === "shelf") return "Your shelf is empty: find an album in Search and press a"
        if (v.kind === "curated") return win.setup.curatedReady ? "No Curated list yet: New list has Claude pick albums from what you play"
                                       : "Albums picked for you, each with a reason: Claude sets it up with you: " + (win.setup.hasApp ? "" : "your own Spotify app, then ") + "your taste, from Last.fm or in your own words"
        if (v.kind === "search") return results && results.error ? results.error : win.deck.searching ? "Searching…" : win.searchField.text.trim().length < 2 ? "Artists, albums and songs on Spotify" : "Nothing found"
        if (v.kind === "queue") return "Nothing queued: e adds an album or a song"
        if (v.kind === "history") return "Nothing yet: the albums you play show up here"
        if (v.kind === "radio") return win.lib.genres.length ? "" : "Loading…"
        if (v.kind === "station") return win.act.radioStarting === v.genre.id ? "Starting the radio…" : "Play starts the radio: songs Spotify picks from the genre's artists"
        if (v.kind === "artist") return v.albums ? "No albums" : "Loading…"
        if (v.kind === "album") return v.tracks ? "No tracks" : "Loading…"
        return ""
    }
    // The album a row stands for, for e and a (a song's or a track's album too)
    function albumOf(row) {
        if (row.kind === "album") return row.data
        if (row.kind === "song") return row.data.album
        if (row.kind === "track") return win.nav.view.album
        if (row.kind === "radiotrack") return { uri: row.data.album_uri, name: row.data.album }
        if (row.kind === "nowplaying" && row.data.album_uri) return { uri: row.data.album_uri, name: row.data.album }
        if (row.kind === "queued" && row.data.album_uri) return { uri: row.data.album_uri, name: "" }
        return null
    }
}
