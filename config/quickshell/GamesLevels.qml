import QtQuick
import Quickshell
import Quickshell.Io

// The launcher's Games (#3530): the games on this computer, from hypr/scripts/games (.desktop files with
// Categories=Game, and Steam's library), Enter starts one. A light first version of a games app, until there are enough
// games for covers: the controller's Xbox button opens this page (hypr/scripts/gamepad-home), and while it is open the
// controller moves in it over IPC ("games" below): the d-pad and the left stick up and down, A plays, B closes.
// Its row at the root shows only when there are games; the root search finds Steam's games too (the .desktop ones are
// apps there already). Launcher.qml asks it like its other level files (levels, titles, parents, items, activate,
// footer, entered).
Item {
    id: g
    property var launcher: null

    readonly property string cmd: Quickshell.env("HOME") + "/.config/hypr/scripts/games"
    property var games: []                  // [{ id, name, source, icon, installed, progress, path }] (games list --json)

    readonly property var levels: ["games"]
    readonly property var titles: ({ games: "Games" })
    readonly property var parents: ({})
    readonly property var rootRow: games.length ? [{ kind: "nav", name: "Games", glyph: "gamepad-2", target: "games",
                                                     summary: String(games.length), extra: "play steam controller xbox gamepad pelit" }] : []

    function gameItem(x) {
        const steam = x.source === "steam"
        return { kind: "game", name: x.name, id: x.id, glyph: x.icon ? undefined : "gamepad-2", iconFile: x.icon || undefined,
                 summary: !x.installed ? "downloading " + x.progress + " %" : steam ? "Steam" : "" }
    }
    function footer(level, query) {
        if (level !== "games") return ""
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind !== "game") return ""
        // The keys show as chips, Enter's as ↵; the controller's A and B as letters
        return cur.summary && cur.summary.indexOf("downloading") === 0 ? "Enter: open in Steam, which goes on downloading  ·  A: the same  ·  B: close"
                                                                         : "Enter: play  ·  A: play  ·  B: close"
    }
    function opened() { listProc.running = true }
    function entered(level) { if (level === "games") listProc.running = true }
    function shiftActivate(it) {}

    function items(level, q) {
        if (level !== "games") return []
        if (!games.length) return [{ kind: "note", name: "No games yet. Games you install, from Steam or as apps, show here." }]
        return { all: games.map(x => ({ item: gameItem(x), text: x.name })) }
    }
    // The root search: Steam's games (a .desktop game is found as an app already)
    function rootRows() {
        return games.filter(x => x.source === "steam").map(x => ({ item: Object.assign(gameItem(x), { from: "Games", summary: undefined }),
                                                                  text: x.name, extra: "game play steam" }))
    }

    function activate(it) {
        if (it.kind !== "game") return false
        launcher.open = false
        Quickshell.execDetached([cmd, "launch", it.id])
        return true
    }

    Process {
        id: listProc
        command: [g.cmd, "list", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { g.games = JSON.parse(text).games || [] } catch (e) { g.games = [] } } }
    }
    // The list is read once at start too, so the root's Games row is there the first time the launcher opens
    Component.onCompleted: listProc.running = true

    readonly property bool showing: launcher !== null && launcher.open && launcher.level === "games"
    // `qs ipc call games …`: the controller (hypr/scripts/gamepad-home). It sends the moves only after its Xbox button
    // opened this page, and asks state() to know when to give the controller back to the game.
    IpcHandler {
        target: "games"
        // The Xbox button: opens Games, or closes it when it is open. "open" | "closed"
        function home(): string {
            if (g.showing) { g.launcher.open = false; return "closed" }
            g.launcher.open = true
            g.launcher.go("games")
            g.launcher.keyLevel = "games"   // Esc and B close the launcher from here, as from a level a key opened
            return "open"
        }
        // up | down | a | b: "ok", or "" when Games isn't open (the button is the game's then)
        function pad(button: string): string {
            if (!g.showing) return ""
            const L = g.launcher
            if (button === "up") L.step(-1)
            else if (button === "down") L.step(1)
            else if (button === "a") L.activate(L.results[L.selIndex])
            else if (button === "b") L.open = false
            return g.showing ? "ok" : ""
        }
        // "open" while Games is showing, else ""
        function state(): string { return g.showing ? "open" : "" }
    }
}
