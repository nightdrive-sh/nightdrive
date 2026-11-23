import QtQuick
import Quickshell.Io

// Plays one sound file (Recorder's recordings, Inbox's attachments). Quickshell has no QtMultimedia here, so ffmpeg plays
// it into PipeWire (its pulse output, named after the app in the Sound menu's apps), from position on (-ss, below): pause stops
// it and keeps the place, play starts it again from there, and a seek while playing starts it again at the new place.
// The position runs on a clock from the start, as ffmpeg plays in real time. A new path (another file, a rename) stops it.
//
// ffmpeg's pulse output throws away what is still in the server's buffer when it closes (a flush, not a drain): with the
// default buffer of ~2 s, every file lost its last 2 s (#3332). So the buffer has a set length (bufferMs) and the sound
// ends in a little more silence than that (padSeconds): what is thrown away is only silence, and ffmpeg ends about when
// the sound has played. Pause still stops at once, as the flush is what it wants. audio_test.py measures it.
Item {
    id: pl
    property string path: ""
    property string app: "Nightdrive"         // the app's name in the Sound menu
    property string title: ""                 // the stream's name there
    property real duration: 0
    property real position: 0                 // seconds
    property bool playing: false
    readonly property real progress: duration > 0 ? Math.min(1, position / duration) : 0

    property real startPos: 0
    property real startedAt: 0
    property bool restart: false              // the process ending is a seek's: start again at position
    readonly property real step: 5            // seconds ← and → move
    readonly property int bufferMs: 1000      // the pulse stream's buffer, thrown away at the end (above)
    readonly property real padSeconds: 1.5    // silence after the sound, more than bufferMs

    // ffmpeg's arguments to play `file` from `from` seconds on
    function command(file, from) {
        // -ss after -i: decoded from the start and dropped up to there. Before -i it seeks in the file instead, which in
        // an Ogg with a video stream beside the sound (a cover picture) skipped all of the sound (#3216)
        return ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-i", file,
                "-ss", from.toFixed(2), "-vn", "-af", "apad=pad_dur=" + padSeconds,
                "-f", "pulse", "-buffer_duration", String(bufferMs), "-name", app, "-stream_name", title || app,
                "default"]
    }

    function play() {
        if (!path) return
        if (position >= duration - 0.05) position = 0
        startPos = position
        // Another file while one still plays (Inbox's next sound): the one before ends first, and its end starts this
        if (proc.running) { restart = true; playing = true; proc.running = false; return }
        proc.command = command(path, startPos)
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
