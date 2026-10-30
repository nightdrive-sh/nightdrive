// Voxtype OSD, Nightdrive's version: replaces the original OsdSurface.qml (copied to ~/.local/share/voxtype/quickshell/).
// Same look as the other toasts (Osd.qml: 10 px radius, dark card without a border, violet UPPERCASE text):
//   mic icon | equalizer (stationary bars growing up and down from the center line) | state (LISTENING / TRANSCRIBING)
// Keeps the original interface: daemonState, osdSuppressed, audio (frameReceived), style (unused).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: panel

    property string daemonState: "idle"      // idle / recording / streaming / transcribing
    property bool osdSuppressed: false
    property var audio: null
    property var style: null

    readonly property bool listening: daemonState === "recording" || daemonState === "streaming"
    readonly property bool transcribing: daemonState === "transcribing"
    // The microphone starts with a delay: "PLEASE WAIT" until the first non-silent audio frame arrives (and 0.35 s has passed), then "LISTENING".
    // Without the audio bridge there's no waiting. Fallback: LISTENING after 3 s regardless.
    property bool audioReady: false
    // Sound cues like macOS dictation: rising when the mic is actually listening (LISTENING), falling when recording ends.
    // During dictation (and for 1.5 s after) silence is played so the output doesn't go to sleep: otherwise the start
    // of the cue gets lost while the device wakes up (ALSA, Bluetooth, the EasyEffects chain).
    // The .wav files sit next to this file (link.sh links them into ~/.local/share/voxtype/quickshell/ too)
    function sound(name) { return decodeURIComponent(Qt.resolvedUrl(name).toString().replace(/^file:\/\//, "")) }
    onAudioReadyChanged: if (audioReady && listening) Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "file", sound("listening.wav")])
    readonly property bool waiting: listening && !audioReady && audio !== null
    property real listenStart: 0
    onListeningChanged: {
        audioReady = false
        listenStart = Date.now()
        if (listening) { readyFallback.restart(); keepAwake.running = true; keepAwakeEnd.stop() }
        else { Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "file", sound("done.wav")]); keepAwakeEnd.restart() }
    }
    Process {
        id: keepAwake
        command: ["sh", "-c", "exec pw-cat --playback --raw --format=s16 --rate=48000 --channels=1 - < /dev/zero"]
    }
    Timer { id: keepAwakeEnd; interval: 1500; onTriggered: keepAwake.running = false }
    Timer { id: readyFallback; interval: 3000; onTriggered: panel.audioReady = true }

    // Colours (same as in the Quickshell menus; theme colour from ~/.cache/nightdrive/theme.json, hypr/scripts/theme)
    property var themeC: ({})
    FileView {
        path: Quickshell.env("HOME") + "/.cache/nightdrive/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { panel.themeC = JSON.parse(text()) } catch (e) {} }
    }
    readonly property color cBg: "#0b0b0d"
    readonly property color cViolet: themeC.primary || "#c071eb"
    readonly property color cAccent: themeC.accent || "#e0bff2"
    readonly property color cDim: themeC.dim || "#9486a3"

    readonly property int cols: 24
    property var levels: []          // bar heights 0..1
    property real framePeak: 0
    property int scan: 0

    visible: !osdSuppressed && daemonState !== "idle" && daemonState !== ""
    anchors { top: true }
    margins { top: 37 + 8 }          // below the top bar, like the other toasts
    implicitWidth: 16 + ico.implicitWidth + 14 + meter.implicitWidth + 12 + 88 + 16   // the card adapts to its content
    implicitHeight: 48
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "voxtype-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}                  // clicks pass through

    function resetMeter() {
        levels = new Array(cols).fill(0)
        framePeak = 0
        scan = 0
    }
    onVisibleChanged: if (visible) resetMeter()
    Component.onCompleted: resetMeter()

    Connections {
        target: panel.audio
        enabled: panel.audio !== null
        function onFrameReceived(peak, rms, vad, tsMs) {
            panel.framePeak = Math.max(panel.framePeak, peak)
            // wait at least 0.35 s so the woken-up output can play the cue from its very start
            if (panel.listening && peak > 0 && Date.now() - panel.listenStart >= 350) panel.audioReady = true
        }
        function onDisconnected() { panel.resetMeter() }
    }

    // Equalizer style: stationary bars that jump with the audio level (tallest in the middle).
    // The audio source only provides the level (no frequency spectrum), so the variation between bars is random.
    // Timer ~14 Hz: a bar rises instantly and falls more slowly.
    Timer {
        interval: 70; repeat: true; running: panel.visible
        onTriggered: {
            if (panel.transcribing) { panel.scan = (panel.scan + 1) % (panel.cols * 2 - 2); return }
            const level = Math.min(1, Math.pow(panel.framePeak, 0.5))
            const h = panel.levels.slice()
            const mid = (panel.cols - 1) / 2
            for (let i = 0; i < panel.cols; i++) {
                const d = (i - mid) / (panel.cols / 3.4)
                const env = 0.35 + 0.65 * Math.exp(-d * d)
                const target = level < 0.10 ? 0 : Math.min(1, level * env * (0.55 + 0.45 * Math.random()) * 1.5)
                h[i] = target > h[i] ? target : h[i] * 0.72 + target * 0.28
            }
            panel.levels = h
            panel.framePeak = 0
        }
    }

    readonly property int scanPos: scan < cols ? scan : (cols * 2 - 2 - scan)

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: panel.cBg

        Text {
            id: ico
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: String.fromCodePoint(0xE118)       // Lucide "mic"
            font { family: "lucide"; pixelSize: 18 }
            color: panel.waiting ? panel.cDim : panel.cAccent
            SequentialAnimation on opacity {
                running: panel.listening && !panel.waiting; loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: 700 }
                NumberAnimation { to: 1.0; duration: 700 }
            }
        }
        // Equalizer: bars grow up and down from the center line
        Row {
            id: meter
            anchors { left: ico.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 2
            Repeater {
                model: panel.cols
                Item {
                    required property int index
                    width: 3; height: 30
                    readonly property real amount: panel.transcribing
                        ? (index === panel.scanPos ? 1.0 : (Math.abs(index - panel.scanPos) === 1 ? 0.45 : 0))
                        : (panel.levels[index] || 0)
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: Math.max(2, parent.amount * parent.height)
                        radius: 1
                        color: panel.transcribing ? panel.cDim : panel.cViolet
                        Behavior on height { NumberAnimation { duration: 60 } }
                    }
                }
            }
        }
        Text {
            anchors { left: meter.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: panel.transcribing ? "TRANSCRIBING" : panel.waiting ? "PLEASE WAIT" : "LISTENING"
            color: panel.waiting ? panel.cDim : panel.cViolet
            font { family: "JetBrains Mono"; pixelSize: 10; letterSpacing: 0.6 }
        }
    }
}
