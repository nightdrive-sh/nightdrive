import QtQuick
import Quickshell.Io

// Plays the picked recording. Quickshell has no QtMultimedia here, so ffmpeg plays it into PipeWire (its pulse output,
// named Recorder in the Sound menu's apps), from position on (-ss): pause stops it and keeps the place, play starts it
// again from there, and a seek while playing starts it again at the new place. The position runs on a clock from the
// start, as ffmpeg plays in real time. A new path (another recording picked, a rename) stops it.
Item {
    id: pl
    property string path: ""
    property string title: ""                 // the stream's name in the Sound menu
    property real duration: 0
    property real position: 0                 // seconds
    property bool playing: false
    readonly property real progress: duration > 0 ? Math.min(1, position / duration) : 0

    property real startPos: 0
    property real startedAt: 0
    property bool restart: false              // the process ending is a seek's: start again at position
    readonly property real step: 5            // seconds ← and → move

    function play() {
        if (!path) return
        if (position >= duration - 0.05) position = 0
        startPos = position
        proc.command = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-ss", startPos.toFixed(2),
                        "-i", path, "-vn", "-f", "pulse", "-name", "Recorder", "-stream_name", title || "Recording",
                        "default"]
        startedAt = Date.now()
        playing = true
        proc.running = true
    }
    function pause() {
        if (!playing) return
        tick()
        playing = false
        restart = false
        proc.running = false
    }
    function toggle() { if (playing) pause(); else play() }
    function seek(t) {
        position = Math.max(0, Math.min(duration, t))
        if (!playing) return
        if (proc.running) { restart = true; proc.running = false }
        else play()
    }
    function skip(d) { seek((playing ? now() : position) + d) }
    function stop() { pause(); position = 0 }
    function now() { return Math.min(duration, startPos + (Date.now() - startedAt) / 1000) }
    function tick() { if (playing) position = now() }

    onPathChanged: stop()
    Component.onDestruction: proc.running = false

    Timer { interval: 100; repeat: true; running: pl.playing && !pl.restart; onTriggered: pl.tick() }

    signal failed(string text)
    Process {
        id: proc
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (pl.restart) { pl.restart = false; pl.play(); return }
            if (!pl.playing) return               // paused: it was stopped
            pl.playing = false                    // the end, or ffmpeg failed
            if (code !== 0 && err.text.trim()) pl.failed("Can't play: " + err.text.trim().split("\n").pop())
            else pl.position = 0
        }
    }
}
