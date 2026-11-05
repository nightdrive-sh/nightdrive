import QtQuick
import Quickshell
import Quickshell.Io

// What the window shows, as the recorder command gives it: the recording being made (`recorder status --json`), the
// recordings in the folder (`recorder list --json`, newest first) and the microphone picked (`recorder config --json`).
// The commands that change something (record, pause, save, new, the mic) run here too, and print the state after them,
// so the window follows at once; a change from elsewhere (a key, the top bar, Claude) comes as `ipc refresh`
// (bin/recorder's changed), and the status is read again every few seconds all the same.
Item {
    id: store
    // The plugin's own command, by its path: the compositor's PATH may not have ~/.local/bin
    readonly property string command: Quickshell.shellDir + "/../bin/recorder"

    // --- The recording being made ---
    property string state: "idle"              // idle, recording, paused
    property string name: ""
    property string recMic: ""                 // the mic it records from ("" the default input)
    property real elapsedAt: 0                 // its seconds when the status was read…
    property real readAt: 0                    // …and when, so the clock runs on between two reads
    property real now: Date.now()
    readonly property bool idle: state === "idle"
    readonly property bool recording: state === "recording"
    readonly property real elapsed: recording ? elapsedAt + Math.max(0, now - readAt) / 1000 : elapsedAt
    Timer { interval: 250; repeat: true; running: store.recording; onTriggered: store.now = Date.now() }

    function clock(seconds) {
        const s = Math.floor(seconds), two = n => (n < 10 ? "0" : "") + n
        return s >= 3600 ? Math.floor(s / 3600) + ":" + two(Math.floor(s / 60) % 60) + ":" + two(s % 60)
                         : Math.floor(s / 60) + ":" + two(s % 60)
    }
    function applyStatus(st) {
        if (!st || !st.state) return
        state = st.state
        name = st.name || ""
        recMic = st.mic || ""
        elapsedAt = st.elapsed || 0
        readAt = now = Date.now()
    }

    // --- The recordings ---
    property var recordings: []                // { name, path, duration, size, modified, transcript, exports }
    property string folder: ""
    property bool loaded: false
    property string error: ""
    property string picked: ""                 // the picked recording's name
    readonly property int index: recordings.findIndex(r => r.name === picked)
    readonly property var current: index >= 0 ? recordings[index] : null
    function step(d) {
        if (!recordings.length) return
        picked = recordings[Math.max(0, Math.min(recordings.length - 1, (index < 0 ? -1 : index) + d))].name
    }
    function pickAt(i) { if (i >= 0 && i < recordings.length) picked = recordings[i].name }

    // --- The microphone picked: Settings' mic, which a new recording takes ---
    property string mic: ""

    // --- Reading ---
    function refresh() { status.again(); lister.again() }
    // Quickshell has no folder watcher: the list is read again every few seconds too (Files, a sync, a terminal)
    Timer { interval: store.idle ? 5000 : 2000; repeat: true; running: true; onTriggered: status.again() }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: lister.again() }
    Component.onCompleted: { refresh(); settings.running = true }

    Reader {
        id: status
        command: [store.command, "status", "--json"]
        onRead: data => store.applyStatus(data)
    }
    Reader {
        id: lister
        command: [store.command, "list", "--json"]
        onRead: data => {
            store.folder = data.folder || ""
            store.recordings = data.recordings || []
            store.loaded = true
            store.error = ""
            // The one picked stays picked; gone (trashed, renamed elsewhere), the newest
            if (store.index < 0) store.picked = store.recordings.length ? store.recordings[0].name : ""
        }
        onFailed: text => store.error = text
    }
    Process {
        id: settings
        command: [store.command, "config", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { store.mic = JSON.parse(text).mic || "" } catch (e) {} } }
    }

    // --- Changing: one command at a time, the state after it applied; failed gets the command's own words ---
    signal failed(string text)
    signal saved(string name)                  // a recording was saved (Save, New): the window picks it
    property var queue: []
    readonly property bool busy: runner.running
    function run(args) { queue = queue.concat([args]); next() }
    function next() {
        if (runner.running || !queue.length) return
        runner.command = [store.command].concat(queue[0]).concat(["--json"])
        queue = queue.slice(1)
        runner.running = true
    }
    function record() { run(mic ? ["record", "--mic", mic] : ["record"]) }
    function pause() { run(["pause"]) }
    function toggle() { if (idle || state === "paused") record(); else pause() }
    function save() { if (!idle) run(["save"]) }
    function newOne() { if (idle) record(); else run(mic ? ["new", "--mic", mic] : ["new"]) }
    // A mic picked while idle or paused: Settings' mic, and a paused recording goes on from it
    function pickMic(node) {
        mic = node
        run(["config", "mic", node])
    }
    Process {
        id: runner
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (code !== 0) store.failed(err.text.trim() || "recorder failed")
            else {
                try {
                    const st = JSON.parse(out.text)
                    if (st.state) store.applyStatus(st)
                    // saved: the recording save wrote ({ name, … }), null when nothing was heard
                    if (st.saved) { store.picked = st.saved.name; store.saved(st.saved.name) }
                    else if ("saved" in st) store.failed("Nothing was heard, so nothing was saved.")
                } catch (e) {}
                lister.again()
            }
            store.next()
        }
    }
}
