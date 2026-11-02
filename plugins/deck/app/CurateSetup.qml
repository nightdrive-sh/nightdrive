import QtQuick
import Quickshell
import Quickshell.Io

// What Deck's config has, the offer to set it up with Claude, and a new Curated list being made. Its own file because
// these hang together (Curated needs the setup, the setup is offered until Curated can work) and apart from the views.
Item {
    id: root
    required property var win

    // Your own Spotify app (likes, search without the shared limits, and Curated, which finds its albums through it),
    // and Curated's taste: Last.fm (your history there) or, without it, a few lines of your own (taste.md). Until both
    // are there, Deck's setup with Claude is offered for what is missing.
    property bool hasApp: false
    property bool hasLastfm: false
    property bool hasNotes: false
    readonly property bool curatedReady: hasApp && (hasLastfm || hasNotes)
    property bool configRead: false
    FileView {
        path: root.win.home + "/.config/deck/config.toml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const t = text()
            root.hasApp = /^\s*client_id\s*=\s*"[^"]+"/m.test(t)
            root.hasLastfm = /^\s*lastfm_api_key\s*=\s*"[^"]+"/m.test(t) && /^\s*lastfm_user\s*=\s*"[^"]+"/m.test(t)
            root.configRead = true
        }
        onLoadFailed: { root.hasApp = false; root.hasLastfm = false; root.configRead = true }
    }
    FileView {
        path: root.win.home + "/.config/deck/taste.md"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.hasNotes = text().trim() !== ""
        onLoadFailed: root.hasNotes = false
    }
    // The window's own: whether its first start's offer to set up Deck was put aside
    property var prefs: ({})
    property bool prefsRead: false
    FileView {
        id: prefsFile
        path: root.win.home + "/.config/deck/window.json"
        printErrors: false
        onLoaded: { try { root.prefs = JSON.parse(text()) } catch (e) { root.prefs = {} } root.prefsRead = true }
        onLoadFailed: root.prefsRead = true
    }

    // A new Curated list (`deck curate`: Claude Code, a few minutes, on your Claude plan). It runs on its own, so
    // closing the window doesn't stop it; the list shows up when curated.json changes.
    property bool curating: false
    property bool curateAsk: false              // New list asks first (curatePanel)
    readonly property string curateLog: win.home + "/.cache/deck/curate.log"
    function curate() {
        curateAsk = false
        Quickshell.execDetached(["setsid", "-f", win.deckBin, "curate"])
        curating = true
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
        path: root.win.home + "/.local/state/nightdrive/setup.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.setupElsewhere = (JSON.parse(text()).tasks || {}).deck === "started" } catch (e) { root.setupElsewhere = false }
            root.setupStateRead = true
        }
        onLoadFailed: root.setupStateRead = true
    }
    function startSetup() { setupStarted = true; Quickshell.execDetached([win.home + "/.local/bin/deck-window", "setup"]) }
    function dismissSetup() {
        prefs = Object.assign({}, prefs, { setupDismissed: true })
        prefsFile.setText(JSON.stringify(prefs) + "\n")
        win.list.forceActiveFocus()
    }
    // Set up while the window is open: Curated, for its New list
    onCuratedReadyChanged: if (curatedReady && setupStarted) win.nav.pickSection("curated")
    Process {
        id: curateCheck
        // A run (this one, or the weekly one) is going; then "done" and the log's last line, for a failure
        command: ["sh", "-c", 'pgrep -f "^[^ ]*deck curate$" >/dev/null && echo run || echo done; tail -n 1 "$1" | cut -c 22-', "sh", root.curateLog]
        stdout: StdioCollector {
            onStreamFinished: {
                const [state, ...rest] = text.split("\n")
                const line = rest.join(" ").trim()
                if (state === "run") { root.curating = true; return }
                if (!root.curating) return
                root.curating = false
                root.win.act.note = /failed/.test(line) ? "Curated failed: " + line.replace(/^=== curate: failed: /, "") : "A new Curated list"
            }
        }
    }
    Timer { interval: 2000; repeat: true; running: true; triggeredOnStart: true; onTriggered: curateCheck.running = true }
}
