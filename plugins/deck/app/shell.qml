import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Deck's window: the shelf, Curated, genre radio, Spotify search and the queue, with the player along the bottom. The music plays in
// `deck serve` (or a Deck in a terminal), which this only talks to: `deck ctl` for commands, its state file for what plays,
// and Deck's own files for the shelf and Curated. Closing the window leaves the music playing.
// This file only puts the window together: what it knows and does is in the parts below (Player, Library, Navigation…),
// what it shows in ViewHeader, ViewList, PlayerBar and the panels, each a file of its own.
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
        readonly property int headerHeight: 62      // the view's title bar, a line under it whatever it holds; the sidebar's title beside it
        readonly property int listGap: 12           // from the line to the first row, and to the sidebar's first section
        readonly property int listTop: headerHeight + 1 + listGap

        // The window's parts, each in its own file; they reach each other through the window (win.player, win.nav…)
        readonly property Player player: Player { win: win }               // what plays, `deck ctl`
        readonly property Library lib: Library { win: win }                // the shelf, Curated, history, genres
        readonly property Covers covers: Covers { win: win }               // covers' addresses from Spotify
        readonly property CurateSetup setup: CurateSetup { win: win }      // Deck's config, its setup, a new Curated list
        readonly property Navigation nav: Navigation { win: win }          // the section and the views opened in it
        readonly property Commands deck: Commands { win: win }             // Deck's JSON commands and the search
        readonly property Rows page: Rows { win: win }                     // the rows and titles of the view on top
        readonly property Actions act: Actions { win: win }                // what the keys and clicks do, the note line
        readonly property Item list: viewList
        readonly property Item searchField: viewHeader.searchField
        readonly property Item outputs: outputsPopup
        readonly property Item sheet: keySheet

        // `deck-window search QUERY` (the launcher's "Search Spotify" row)
        IpcHandler {
            target: "deck"
            function search(query: string): void {
                win.nav.pickSection("search")
                win.searchField.text = query
                win.deck.search()
            }
            function section(id: string): void { win.nav.pickSection(id) }
            // A genre's view (its Play button), by Deck's id
            function radio(id: string): void {
                const g = win.lib.genres.find(g => g.id === id)
                if (!g) return
                win.nav.pickSection("radio")
                win.nav.push({ kind: "station", genre: g })
            }
        }

        // ⌘F and / search, ⌘1–6 the sections; Ctrl+Q closes the window (the music plays on). ⌘Q, Hyprland's, quits the player
        // too (plugins/deck/quit-commands)
        Shortcut { sequences: ["Ctrl+F", "/"]; onActivated: win.nav.pickSection("search") }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.nav.toggleSidebar() }
        Shortcut { sequences: ["Ctrl+1", "Meta+1"]; onActivated: win.nav.pickSection("shelf") }
        Shortcut { sequences: ["Ctrl+2", "Meta+2"]; onActivated: win.nav.pickSection("curated") }
        Shortcut { sequences: ["Ctrl+3", "Meta+3"]; onActivated: win.nav.pickSection("radio") }
        Shortcut { sequences: ["Ctrl+4", "Meta+4"]; onActivated: win.nav.pickSection("search") }
        Shortcut { sequences: ["Ctrl+5", "Meta+5"]; onActivated: win.nav.pickSection("queue") }
        Shortcut { sequences: ["Ctrl+6", "Meta+6"]; onActivated: win.nav.pickSection("history") }
        // Ctrl+↑ ↓ the previous and next section, as Mail's folders
        Shortcut { sequence: "Ctrl+Up"; onActivated: win.nav.stepSection(-1) }
        Shortcut { sequence: "Ctrl+Down"; onActivated: win.nav.stepSection(1) }

        ColumnLayout {
            id: content          // what a panel turns off while it shows (AppPanel.behind)
            anchors.fill: parent
            spacing: 0
            // ? and Ctrl+? show the keys, as in Mail (KeySheet.qml)
            Keys.onPressed: e => keySheet.pressed(e)
            AppPointer { c: win.look }      // the pointer hides the keys' frame

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Sections: the title level with the view's, the first section level with the first row. In one pane, the
                // whole width while they show.
                AppSidebar {
                    visible: win.nav.sidebarShown
                    Layout.preferredWidth: win.nav.onePane ? -1 : 196
                    Layout.fillWidth: win.nav.onePane
                    c: win.look
                    title: "Deck"
                    headerHeight: win.headerHeight
                    contentTop: win.listTop
                    Repeater {
                        model: win.nav.sections
                        delegate: AppNavRow {
                            required property var modelData
                            c: win.look
                            glyph: modelData.glyph
                            label: modelData.name
                            selected: (win.nav.sectionsOpen || win.nav.sectionsKeyed ? win.nav.sectionCursor : win.nav.section) === modelData.id
                            active: win.nav.sectionsOpen || win.nav.sectionsKeyed      // the kit's frame: the keys are here
                            count: modelData.id === "queue" && win.player.queue.length ? win.player.queue.length
                                 : modelData.id === "curated" && win.lib.curated.length ? win.lib.curated.length : ""
                            onClicked: win.nav.pickSection(modelData.id)
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // The view. While the sections show in one pane it is there at no width: its list keeps the keyboard, so
                // the arrows move in the sections and Space and the rest go on working
                ColumnLayout {
                    Layout.preferredWidth: win.nav.sectionsOpen ? 0 : -1
                    Layout.fillWidth: !win.nav.sectionsOpen
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0

                    ViewHeader {
                        id: viewHeader
                        win: win
                        Layout.fillWidth: true
                        Layout.preferredHeight: win.headerHeight
                    }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: c.divider }
                    ViewList {
                        id: viewList
                        win: win
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: c.divider }
            PlayerBar {
                id: playerBar
                win: win
                Layout.fillWidth: true
                Layout.preferredHeight: 92
            }
        }

        readonly property QtObject look: c
        readonly property var keyHelp: [
            { title: "Browse", keys: [["↑ ↓  j k", "Move"], ["⏎", "Open, or play a song"], ["Esc  ⌫", "Back; at a section, narrow: the sections"], ["⌘1 … ⌘6", "Shelf, Curated, Radio, Search, Queue, History"], ["Ctrl ↑ ↓", "Previous, next section"], ["Tab ⇧Tab", "To the sections, and back"], ["⌘B", "Show or hide the sections"], ["⌘F  /", "Search Spotify"], ["n", "What plays: its album or radio"], ["r", "Pick for me: an album you haven't played lately"],
                                      ["f", "A favourite genre, or not"], ["d", "Out of the queue; Not for me in Curated"]] },
            { title: "Play", keys: [["Space", "Play, pause"], ["← →", "Previous, next track"], [", .", "Back, ahead 10 seconds"], ["p", "Play the album, song or radio"], ["e", "Queue the album or song"], ["a", "On the shelf, or off it"],
                                    ["l", "Like the playing track"], ["o", "Where the sound plays"], ["?  Ctrl ?", "These keys"]] }
        ]
        KeySheet { id: keySheet; c: win.look; groups: win.keyHelp }

        SetupPanel {
            behind: content
            win: win
            visible: win.setup.setupOffer
        }

        CuratePanel {
            id: curatePanel
            behind: content
            visible: win.setup.curateAsk
            c: win.look
            onAnswered: yes => {
                if (yes) win.setup.curate()
                else win.setup.curateAsk = false
                win.list.forceActiveFocus()
            }
        }

        OutputsPopup {
            id: outputsPopup
            win: win
            speaker: playerBar.speaker
            anchors.fill: parent
        }
    }
}
