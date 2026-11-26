import QtQuick

// Where you are: a section (the sidebar) and the views opened in it, Esc goes back. Also how the window shares its width
// between the sections and the view, and what the keys do while they are on the sections. Its own file so the views and
// the keys ask one place where they are, apart from what is shown there (Rows.qml).
QtObject {
    id: root
    required property var win

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
    readonly property bool onePane: win.width < onePaneMax
    readonly property bool narrowPlayer: win.width < playerMin
    property var sidebarChoice: null            // ⌘B's, in a wide window
    property bool sectionsOpen: false           // in one pane: the sections show instead of the view
    property string sectionCursor: "shelf"      // the section the keys point at while they show
    // Two panes: Tab takes the keys to the sections beside the view, as in one pane (sectionKey), and back
    property bool sectionsKeyed: false
    function tabSections() {
        if (onePane) toggleSidebar()
        else if (sectionsKeyed) sectionsKeyed = false
        else if (sidebarShown) { sectionCursor = section; sectionsKeyed = true }
    }
    readonly property bool sidebarShown: onePane ? sectionsOpen : sidebarChoice !== null ? sidebarChoice : true
    onOnePaneChanged: sectionsOpen = false
    function openSections() { sectionCursor = section; sectionsOpen = true; win.list.forceActiveFocus() }
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
        else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) { sectionsOpen = false; sectionsKeyed = false }
        // Out of sight in one pane, the view's row isn't acted on; beside the sections (Tab) it is
        else return sectionsOpen && [Qt.Key_P, Qt.Key_E, Qt.Key_A, Qt.Key_D, Qt.Key_Delete, Qt.Key_F].indexOf(k) >= 0
        return true
    }
    function moveTo(i) { cursor = Math.max(0, Math.min(i, win.page.rows.length - 1)); win.list.currentIndex = cursor }
    function pickSection(id) {
        sectionsOpen = false
        sectionsKeyed = false
        section = id
        cursor = 0
        stack = [{ kind: id }]
        cursors = []
        if (id === "search") win.searchField.forceActiveFocus()
        else win.list.forceActiveFocus()
    }
    function push(v) {
        sectionsOpen = false
        cursors = cursors.concat([cursor])
        cursor = 0
        stack = stack.concat([v])
        win.list.forceActiveFocus()
    }
    function back() {
        if (stack.length < 2 && onePane) { openSections(); return }
        if (stack.length < 2) { if (section === "search") win.searchField.forceActiveFocus(); return }
        cursor = cursors[cursors.length - 1]
        cursors = cursors.slice(0, -1)
        stack = stack.slice(0, -1)
    }
    // Ctrl+↑ ↓ the previous and next section, as Mail's folders
    function stepSection(d) {
        const i = sections.findIndex(s => s.id === section) + d
        if (i >= 0 && i < sections.length) pickSection(sections[i].id)
    }
    // A view whose data arrives later is updated in place, if it is still in the stack
    function update(v, fields) {
        const i = stack.indexOf(v)
        if (i < 0) return
        const s = stack.slice(); s[i] = Object.assign({}, v, fields); stack = s
    }

    function openArtist(artist, fromShelf) {
        const v = { kind: "artist", artist: artist, shelf: fromShelf, albums: null }
        if (fromShelf) v.albums = win.lib.shelf.filter(a => (a.artist_id || a.artist) === (artist.id || artist.name)).sort((x, y) => (x.year || 0) - (y.year || 0))
        push(v)
        if (!fromShelf) win.deck.run(["artist-albums", "--json", artist.id], text => update(v, { albums: JSON.parse(text) }), err => update(v, { albums: [], error: err }))
    }
    // An album's artist, from the album's view: all their albums on Spotify (yours marked with the shelf's icon), or
    // only your shelf's when Deck knows no id for the artist
    function artistOnShelf(album) { return win.lib.shelf.some(a => (a.artist_id || a.artist) === (album.artist_id || album.artist)) }
    function openAlbumArtist() {
        const a = view.album
        openArtist({ id: a.artist_id, name: a.artist }, !a.artist_id)
    }
    function openAlbum(album, from) {
        const v = { kind: "album", album: album, tracks: null, from: from || "" }
        push(v)
        win.deck.run(["album-tracks", "--json", album.uri], text => {
            const j = JSON.parse(text)
            update(v, { tracks: j.tracks, album: Object.assign({}, j.album, album) })
        }, err => update(v, { tracks: [], error: err }))
    }

    // n, or a click on the player's cover: what plays, in the section you are in (Esc comes back): its album, or the
    // radio's genre
    function openPlaying() {
        const info = win.player.info, radio = win.player.radio
        if (!info) return
        if (info.album_uri) {
            if (view.kind === "album" && view.album.uri === info.album_uri) return
            openAlbum({ uri: info.album_uri, name: info.album, artist: info.artist })
        } else if (radio) {
            if (view.kind === "station" && view.genre.id === radio.genre) return
            const g = win.lib.genres.find(g => g.id === radio.genre) || { id: radio.genre, name: win.lib.genreName(radio.name) }
            push({ kind: "station", genre: g })
        }
    }
}
