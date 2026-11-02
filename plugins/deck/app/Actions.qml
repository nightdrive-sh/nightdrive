import QtQuick

// What the keys and clicks do to a row or the view (open, play, queue, shelve, take out, a favourite), and the note
// that says what just happened (the window's AppToast). Its own file so the list's keys, the header's buttons and the player act the
// same way, through one set of functions.
Item {
    id: root
    required property var win
    readonly property var nav: win.nav
    readonly property var player: win.player

    function activate(row) {
        if (!row) return
        if (row.kind === "artist") nav.openArtist(row.data, row.shelf)
        else if (row.kind === "album") nav.openAlbum(row.data, nav.view.kind)
        // A genre opens to its Play button, as an album does: picking one doesn't stop the music
        else if (row.kind === "genre") nav.push({ kind: "station", genre: row.data })
        else if (row.kind === "nowplaying") nav.openPlaying()
        else if (row.kind === "track") player.ctl(["play-song", row.data.uri, nav.view.album.uri])
        else if (row.kind === "song") player.ctl(["play-song", row.data.uri, row.data.album.uri])
    }
    function play(row) {
        const a = row && win.page.albumOf(row)
        if (row && (row.kind === "track" || row.kind === "song")) activate(row)
        else if (row && row.kind === "genre") playRadio(row.data)
        else if (nav.view.kind === "station" && (!row || row.kind === "radiotrack")) playRadio(nav.view.genre)
        else if (a) player.ctl(["play-album", a.uri])
    }
    // A genre's radio: Deck fetches a station first, so the view says it is starting until the radio plays
    property string radioStarting: ""
    Timer { id: radioWait; interval: 20000; onTriggered: root.radioStarting = "" }
    Connections {
        target: root.player
        function onRadioChanged() { if (root.player.radio && root.player.radio.genre === root.radioStarting) root.radioStarting = "" }
    }
    function playRadio(g) {
        if (player.radio && player.radio.genre === g.id) return
        radioStarting = g.id
        radioWait.restart()
        player.ctl(["radio", g.id])
    }
    function genreRow(g) { return { kind: "genre", title: g.name, fav: win.lib.favorites.indexOf(g.id) >= 0, data: g } }
    // Pick for me: Deck draws an album from the shelf or Curated that hasn't played in this round
    function pick(from) {
        player.ctl(from ? ["pick", from] : ["pick"])
        note = "Picking an album…"
    }
    function enqueue(row) {
        if (!row) return
        if (row.kind === "track") player.ctl(["queue-song", row.data.uri, nav.view.album.uri])
        else if (row.kind === "song") player.ctl(["queue-song", row.data.uri, row.data.album.uri])
        else if (row.kind === "album") player.ctl(["queue-album", row.data.uri])
        else if (row.kind === "radiotrack") player.ctl(["queue-song", row.data.uri, row.data.album_uri])
        else return
        note = "Queued: " + row.title
    }
    function shelve(row) {
        const a = row ? win.page.albumOf(row) : nav.view.kind === "album" ? nav.view.album : null
        if (!a) return
        const on = !!win.lib.shelfUris[a.uri]
        player.ctl([on ? "shelf-remove" : "shelf-add", a.uri])
        note = (on ? "Taken off the shelf: " : "On the shelf: ") + (a.name || "the album")
    }
    // Not for me: out of Curated, into its history as rejected, which the next list learns from (loosely: no more
    // records like it)
    function notForMe(album) {
        player.ctl(["curated-reject", album.uri])
        note = "Not for me: " + album.name
    }
    // d: out of the queue, or out of Curated (Deck keeps it in Curated's history, so it isn't suggested again)
    function remove(row) {
        if (!row) return
        if (row.kind === "queued") player.ctl(["unqueue", String(row.index)])
        else if (row.kind === "album" && nav.view.kind === "curated") notForMe(row.data)
        else if (nav.view.kind === "album" && win.lib.curatedUris[nav.view.album.uri]) { notForMe(nav.view.album); nav.back() }
    }
    function favorite(row) {
        if (!row || row.kind !== "genre") return
        player.ctl([row.fav ? "favorite-remove" : "favorite-add", row.data.id])
        note = (row.fav ? "Not a favourite: " : "A favourite: ") + row.title
    }

    // What just happened, in the window's toast at the top (it was a line in the player bar, easily missed). act.note =
    // "…" is the short way the callers have; it empties itself at once, so the same note again shows again. Deck's
    // errors come through showNote(text, true): in the danger colour, and longer.
    property string note: ""
    onNoteChanged: if (note !== "") { showNote(note, false); note = "" }
    function showNote(text, danger) { win.toast.show(text, danger ? { danger: true } : { duration: 3000 }) }
}
