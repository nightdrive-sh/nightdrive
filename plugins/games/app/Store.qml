import QtQuick
import Quickshell
import Quickshell.Io

// The games, from the core's list (hypr/scripts/games list --json: .desktop games and Steam's library), and starting
// one. Read when the window opens and every 5 s after while it is open, so a Steam download's progress moves and a game
// installed meanwhile shows up without a restart.
Item {
    id: s
    readonly property string cmd: Quickshell.env("HOME") + "/.config/hypr/scripts/games"
    property var games: []        // [{ id, name, source, icon, installed, progress, running, cover, hero, path }]
    property bool loaded: false
    property string error: ""
    signal started(string name, bool running)   // running: it was open already and came forward (#3632)

    function refresh() { if (!listProc.running) listProc.running = true }
    function launch(game) {
        if (!game) return
        launchProc.command = [cmd, "launch", game.id, "--json"]
        launchProc.name = game.name
        launchProc.running = true
    }

    Process {
        id: listProc
        command: [s.cmd, "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const next = JSON.parse(text).games || []
                    // Only when something changed: a new array would rebuild the grid and lose its place
                    if (JSON.stringify(next) !== JSON.stringify(s.games)) s.games = next
                    s.error = ""
                } catch (e) { s.error = "Couldn't read the games list" }
                s.loaded = true
            }
        }
    }
    Process {
        id: launchProc
        property string name: ""
        stdout: StdioCollector { id: launchOut }
        stderr: StdioCollector { id: launchErr }
        onExited: code => {
            let running = false
            try { running = JSON.parse(launchOut.text).running === true } catch (e) {}
            if (code === 0) s.started(name, running)
            else s.error = launchErr.text.trim() || "Couldn't start " + name
        }
    }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: s.refresh() }
    Component.onCompleted: refresh()
}
