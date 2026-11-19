import QtQuick
import Quickshell
import Quickshell.Io
import qs.kit

// The message's sound files (ogg, wav, mp3, m4a, flac, opus), a row each with a play button, the length and a thin bar
// of the place in it (SoundRow). They play here, through the kit's AppAudio: one at a time, so playing another stops the
// one before. A session leaves a few to compare (A, B, C), so the keys go quickly from one to the next: p plays or
// pauses the current one, ← → play the one before or after from its start (shell.qml). The lengths come from ffprobe
// when the message shows. The copy button at a row's end copies the file's name (to tell a session which one won); a
// click on a row elsewhere than its buttons opens the file in its app, as before.
Column {
    id: root
    required property QtObject c
    property var files: []                    // the message's attachments that are sound
    property int current: 0                   // the row p and ← → start from
    property var lengths: ({})                // path → seconds, from ffprobe
    readonly property bool any: files.length > 0
    signal notice(string text, bool danger)  // for the window's toast: a copied name, a sound that can't play
    spacing: 2

    function clock(s) {
        s = Math.max(0, Math.round(s || 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    function isLoaded(i) { return i === current && !!files[i] && player.path === files[i].path }
    // The row's file from its start, or on from where it was paused; a second press pauses it
    function play(i) {
        const f = files[i]
        if (!f) return
        if (isLoaded(i)) return player.toggle()
        current = i
        player.path = f.path                  // AppAudio stops the one before and starts at 0
        player.title = f.name
        player.duration = lengths[f.path] || 0
        player.play()
    }
    function toggle() { play(Math.min(current, files.length - 1)) }
    function step(d) {
        if (!files.length) return             // not `any`: its binding hasn't caught up with files here
        const i = Math.max(0, Math.min(files.length - 1, current + d))
        if (i === current && isLoaded(i)) { player.seek(0); if (!player.playing) player.play(); return }
        play(i)
    }

    // The store reads the messages again when one changes (opening one marks it read): the same files keep playing
    property string shown: ""
    onFilesChanged: load()
    Component.onCompleted: load()             // a message shown as the window opens: no change comes for it
    function load() {
        const key = files.map(f => f.path).join("\n")
        if (key === shown) return
        shown = key
        player.path = ""                      // another message: what played stops
        current = 0
        lengths = ({})
        probe.running = false
        if (!files.length) return             // not `any`: its binding hasn't caught up with files here
        const paths = files.map(f => f.path)
        probe.paths = paths
        probe.command = ["sh", "-c",
            'for f; do ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null || echo; done',
            "sh"].concat(paths)
        probe.running = true
    }

    AppAudio {
        id: player
        app: "Inbox"
        onFailed: text => root.notice(text, true)
    }
    Process {
        id: probe
        property var paths: []
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n"), got = {}
                probe.paths.forEach((p, i) => { const s = parseFloat(lines[i]); if (s > 0) got[p] = s })
                root.lengths = got
                // One started before its length was known gets it now
                if (got[player.path] && !player.duration) player.duration = got[player.path]
            }
        }
    }

    Repeater {
        model: root.files
        delegate: SoundRow {
            required property var modelData
            required property int index
            width: root.width
            c: root.c
            name: modelData.name
            length: root.lengths[modelData.path] || 0
            loaded: root.isLoaded(index)
            playing: loaded && player.playing
            position: loaded ? player.position : 0
            progress: loaded ? player.progress : 0
            clock: root.clock
            onPlay: root.play(index)
            onOpen: Qt.openUrlExternally("file://" + modelData.path)
            onCopy: { Quickshell.execDetached(["wl-copy", modelData.name]); root.notice("Copied " + modelData.name, false) }
        }
    }
}
