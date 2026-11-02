import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// The view's own buttons at the right of its title bar: the shelf's Pick for me, the queue's, a station's, an album's,
// and Curated's (a new list by Claude, or its setup). Its own file because each view has its own set, and the header
// only has to place them. Out of the header's layout while it has none, so no gap is left for it.
RowLayout {
    id: root
    required property var win
    readonly property var nav: win.nav
    readonly property var player: win.player
    readonly property var lib: win.lib
    readonly property var setup: win.setup
    readonly property var act: win.act
    spacing: 10
    // Repeater.count rather than the layout's own width: an invisible layout has no width to tell
    visible: buttons.count > 0 || curated.count > 0 || busy.shown

    // An album's own buttons, as Curated's New list: play it, queue it, shelve it. The tip tells the key.
    Repeater {
        id: buttons
        model: root.nav.view.kind === "shelf" && root.lib.shelf.length ? [
            { glyph: "dices", label: "Pick for me", tip: "An album you haven't played in a while", keys: "r", act: () => root.act.pick("shelf") }
        ] : root.nav.view.kind === "queue" ? (root.player.queue.length === 0 ? [] : [
            // The queue plays when its first track does: Next takes it
            root.player.info && root.player.info.queued
                ? { glyph: "check", label: "Playing", tip: "The queue plays", keys: "", act: () => {} }
                : { glyph: "play", label: "Play", tip: "Play the queue now", keys: "", act: () => root.player.next() },
            { glyph: "trash-2", label: "Empty queue", tip: "Take everything off the queue", keys: "", act: () => { root.player.ctl(["queue-clear"]); root.act.note = "The queue is empty" } }
        ]) : root.nav.view.kind === "station" ? [
            root.player.radio && root.player.radio.genre === root.nav.view.genre.id
                ? { glyph: "check", label: "Playing", tip: "The radio plays", keys: "", act: () => {} }
                : { glyph: "play", label: "Play", tip: "Play the radio", keys: "p", act: () => root.act.playRadio(root.nav.view.genre) },
            root.lib.favorites.indexOf(root.nav.view.genre.id) >= 0
                ? { glyph: "star", on: true, label: "Favourite", tip: "Not a favourite", keys: "f", act: () => root.act.favorite(root.act.genreRow(root.nav.view.genre)) }
                : { glyph: "star", label: "Favourite", tip: "A favourite genre, on Deck's home", keys: "f", act: () => root.act.favorite(root.act.genreRow(root.nav.view.genre)) }
        ] : root.nav.view.kind === "album" ? [
            // While this album plays the button pauses it, and resumes it when paused, so a press shows
            root.player.info && root.player.info.album_uri === root.nav.view.album.uri
                ? (root.player.playing ? { glyph: "pause", label: "Pause", tip: "Pause the album", keys: "Space", act: () => root.player.togglePlay() }
                                       : { glyph: "play", label: "Resume", tip: "Go on with the album", keys: "Space", act: () => root.player.togglePlay() })
                : { glyph: "play", label: "Play", tip: "Play the album", keys: "p", act: () => root.player.ctl(["play-album", root.nav.view.album.uri]) },
            { glyph: "list-plus", label: "Queue", tip: "Queue the album", keys: "e", act: () => { root.player.ctl(["queue-album", root.nav.view.album.uri]); root.act.note = "Queued: " + root.nav.view.album.name } },
            root.lib.shelfUris[root.nav.view.album.uri]
                ? { glyph: "check", label: "Shelf", tip: "On the shelf: take it off", keys: "a", act: () => root.act.shelve(null) }
                : { glyph: "library", label: "Shelf", tip: "Put it on the shelf", keys: "a", act: () => root.act.shelve(null) }
        ].concat(root.lib.curatedUris[root.nav.view.album.uri] ? [
            // A Curated suggestion: out of the list, and the next one learns from it
            { glyph: "thumbs-down", label: "Not for me", tip: "Out of Curated: no more like it", keys: "d", act: () => { root.act.notForMe(root.nav.view.album); root.nav.back() } }
        ] : []) : []
        // In one pane the glyphs alone, the tip saying what each does
        delegate: AppButton {
            required property var modelData
            c: root.win.look
            glyph: modelData.glyph; label: root.nav.onePane ? "" : modelData.label
            on: !!modelData.on || modelData.glyph === "check"
            tip: root.nav.onePane ? modelData.label + ": " + modelData.tip : modelData.tip; keys: modelData.keys
            onClicked: modelData.act()
        }
    }
    // Curated: a new list by Claude, asked first in curatePanel
    Repeater {
        id: curated
        model: root.nav.view.kind !== "curated" || root.setup.curating ? []
             : !root.setup.curatedReady ? [{ label: root.setup.setupStarted ? "Open Claude again" : "Set up with Claude", glyph: "sparkles", strong: true, act: () => root.setup.startSetup() }]
             : (root.lib.curated.length ? [{ label: "Pick for me", glyph: "dices", strong: false, tip: "An album you haven't played in a while", keys: "r", act: () => root.act.pick("curated") }] : [])
               .concat([{ label: "New list", glyph: "refresh-cw", strong: false, tip: "Claude picks new albums", act: () => root.setup.curateAsk = true }])
        // The one to press keeps its label in one pane, the others are their glyphs
        delegate: AppButton {
            required property var modelData
            c: root.win.look
            glyph: modelData.glyph; label: root.nav.onePane && !modelData.strong && modelData.glyph ? "" : modelData.label
            tip: root.nav.onePane && modelData.tip ? modelData.label + ": " + modelData.tip : ""; keys: modelData.keys || ""
            strong: modelData.strong
            onClicked: modelData.act()
        }
    }
    // While a new list is being made, in place of its buttons: what goes on in plain words, not the
    // run's log lines, which meant nothing here
    Row {
        id: busy
        readonly property bool shown: root.nav.view.kind === "curated" && root.setup.curating
        visible: shown
        spacing: 10
        BusyDots { anchors.verticalCenter: parent.verticalCenter }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Claude is looking for albums…"
            color: root.win.look.dim; font.family: root.win.look.font; font.pixelSize: 12
        }
    }
}
