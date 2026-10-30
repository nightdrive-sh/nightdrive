import QtQuick
import Quickshell
import Quickshell.Io

// Dictation's state, read from outside Voxtype (docs/dictation.md), for DictationToast. Voxtype's own OSD is off
// (config/voxtype/config.toml: [osd] enabled = false), but its daemon still keeps:
// - $XDG_RUNTIME_DIR/voxtype/state: idle, recording, streaming or transcribing, rewritten at each change, and
//   osd_suppressed beside it while a recording started with --no-osd runs;
// - $XDG_RUNTIME_DIR/voxtype/audio.sock: the mic's level frames. Quickshell can't read a Unix socket, so Voxtype's
//   voxtype-audio-bridge turns them into one JSON line each ({"peak":…,"rms":…,"vad":…}). It runs only while dictating.
// Also plays the sound cues, like macOS dictation: rising once the mic is really listening, falling when it stops.
Item {
    id: dictation
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/voxtype"
    readonly property string sounds: Quickshell.env("HOME") + "/.local/share/nightdrive/sounds/dictation/"
    property string daemonState: "idle"
    property bool suppressed: false
    readonly property bool busy: daemonState !== "idle" && daemonState !== ""
    readonly property bool shown: busy && !suppressed
    readonly property bool listening: daemonState === "recording" || daemonState === "streaming"
    readonly property bool transcribing: daemonState === "transcribing"
    // The mic starts with a delay: waiting ("PLEASE WAIT") until the first non-silent frame arrives and 0.35 s has
    // passed, so the woken-up output plays the cue from its very start. After 3 s it's ready regardless.
    property bool audioReady: false
    readonly property bool waiting: listening && !audioReady
    property real listenStart: 0
    signal frame(real peak)

    function play(name) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "file", sounds + name])
    }
    onAudioReadyChanged: if (audioReady && listening) play("listening.wav")
    onListeningChanged: {
        audioReady = false
        listenStart = Date.now()
        if (listening) { readyFallback.restart(); keepAwake.running = true; keepAwakeEnd.stop() }
        else { play("done.wav"); keepAwakeEnd.restart() }
    }

    FileView {
        path: dictation.dir + "/state"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: dictation.daemonState = (text() || "idle").trim()
        onLoadFailed: dictation.daemonState = "idle"
    }
    // Created and removed rather than rewritten: there means hide the toast
    FileView {
        path: dictation.dir + "/osd_suppressed"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: dictation.suppressed = true
        onLoadFailed: dictation.suppressed = false
    }

    Process {
        id: bridge
        // ~/.local/bin, where docs/dictation.md installs it, isn't always in the shell's PATH
        command: ["sh", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec voxtype-audio-bridge 2>/dev/null"]
        running: dictation.busy
        stdout: SplitParser {
            onRead: line => {
                let o
                try { o = JSON.parse(line) } catch (e) { return }
                if (typeof o.peak !== "number") return
                dictation.frame(o.peak)
                if (dictation.listening && o.peak > 0 && Date.now() - dictation.listenStart >= 350)
                    dictation.audioReady = true
            }
        }
    }
    Timer { id: readyFallback; interval: 3000; onTriggered: dictation.audioReady = true }

    // During dictation (and 1.5 s after) silence plays, so the output doesn't go to sleep: otherwise the start of a
    // cue is lost while the device wakes up (ALSA, Bluetooth, the EasyEffects chain).
    Process {
        id: keepAwake
        command: ["sh", "-c", "exec pw-cat --playback --raw --format=s16 --rate=48000 --channels=1 - < /dev/zero"]
    }
    Timer { id: keepAwakeEnd; interval: 1500; onTriggered: keepAwake.running = false }
}
