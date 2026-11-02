import QtQuick
import Quickshell
import Quickshell.Io

// What Deck says: the playing track and the queue, from its state file (state.json, written on every change), and the
// commands that change them (`deck ctl`). Its own file so the window's views read one place for what plays; a pressed
// button looks pressed at once (optimistic) until Deck's state catches up.
Item {
    id: root
    required property var win

    readonly property int settleTime: 1500      // ms a pressed button's look waits for Deck's state to catch up

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
    onDeckErrorChanged: if (deckError !== "") { win.act.showNote(deckError, true); win.act.radioStarting = "" }

    FileView {
        id: stateFile
        path: root.win.runtime + "/state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text())
                root.info = j.info
                root.updatedMs = j.updated_ms
                root.nowMs = Date.now()
                alivePid.command = ["test", "-d", "/proc/" + j.pid]
                alivePid.running = true
            } catch (e) { root.info = null; root.alive = false }
        }
        onLoadFailed: { root.info = null; root.alive = false }
    }
    // A Deck killed without cleaning up leaves its file behind: the pid tells.
    Process { id: alivePid; onExited: code => { root.alive = code === 0; if (code !== 0) root.info = null } }
    Timer { interval: 3000; repeat: true; running: true; onTriggered: stateFile.reload() }
    Timer { interval: 250; repeat: true; running: root.playing; onTriggered: root.nowMs = Date.now() }
    Timer { id: settle; interval: root.settleTime; onTriggered: root.optimistic = ({}) }

    function ctl(args) {
        Quickshell.execDetached([win.deckBin, "ctl"].concat(args))
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
    Timer { id: pendingWait; interval: 5000; onTriggered: root.pendingNext = null }
    onInfoChanged: if (pendingNext && info && info.track_uri === pendingNext.uri) pendingNext = null
    function next() {
        if (queue.length) { pendingNext = queue[0]; pendingWait.restart() }
        ctl(["next"])
    }
    function startDeck() { Quickshell.execDetached([win.home + "/.local/bin/deck-window", "player"]) }
}
