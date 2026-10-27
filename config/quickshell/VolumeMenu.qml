import QtQuick
import Quickshell
import Quickshell.Io

// Sound: volume, mute and output selection, plus microphone volume, mute and selection.
// Uses wpctl and pw-dump (Quickshell's Pipewire module doesn't work with Pipewire 1.6).
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 10

    property real volume: 0
    property bool muted: false
    property real pending: -1
    property real micVolume: 0
    property bool micMuted: false
    property real micPending: -1
    property real micLevel: 0
    // The meter's scale in dBFS, measured on the MacBook's mic (asahi-audio's chain adds ~45 dB): a quiet room peaks
    // around -46, speech around -32 (loud -15). Other mics sit lower in silence, so this suits them too.
    readonly property int micFloorDb: -45
    readonly property int micTopDb: -10
    signal close()

    function refresh() { volProc.running = true; micProc.running = true }
    function setVolume(v) {
        volume = v; pending = v
        if (!apply.running) apply.start()
    }
    function toggleMute() {
        muted = !muted
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        soon.start()
    }
    function setMicVolume(v) {
        micVolume = v; micPending = v
        if (!micApply.running) micApply.start()
    }
    function toggleMicMute() {
        micMuted = !micMuted
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"])
        soon.start()
    }
    Component.onCompleted: refresh()

    Timer { interval: 1000; repeat: true; running: true; onTriggered: m.refresh() }
    Timer { id: soon; interval: 150; onTriggered: m.refresh() }
    Timer {
        id: apply; interval: 60
        onTriggered: {
            if (m.pending >= 0) {
                Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", m.pending.toFixed(2)])
                m.pending = -1
            }
        }
    }

    Timer {
        id: micApply; interval: 60
        onTriggered: {
            if (m.micPending >= 0) {
                Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", m.micPending.toFixed(2)])
                m.micPending = -1
            }
        }
    }
    // Input level meter for the mic slider. The menu is loaded only while open, so the mic is recorded only then.
    // The stream follows the default source and sees its volume, so the meter shows what apps get.
    // Peak per 50 ms block on a dB scale (micFloorDb..micTopDb -> 0..1); the first block is a start-up click, so it's
    // skipped. --raw: without it pw-record writes an AU file to stdout (a header and big-endian samples), read here as
    // noise near 0 dB.
    Process {
        running: true
        command: ["python3", "-I", "-c", `
import array, math, subprocess, sys
lo, hi = float(sys.argv[1]), float(sys.argv[2])
p = subprocess.Popen(["pw-record", "--raw", "--rate", "16000", "--channels", "1", "--format", "s16", "--latency", "50ms",
                      "-P", "{ node.name = nightdrive-mic-meter, media.name = \\"Mic level meter\\" }", "-"],
                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
p.stdout.read(1600)
while (b := p.stdout.read(1600)) and len(b) == 1600:
    peak = max(map(abs, array.array("h", b))) / 32768
    print(round(max(0, min(1, (20 * math.log10(peak) - lo) / (hi - lo))) if peak > 0 else 0, 3), flush=True)
`, String(m.micFloorDb), String(m.micTopDb)]
        stdout: SplitParser {
            // fast attack, slower fall so the line doesn't flicker
            onRead: line => { const v = parseFloat(line); if (!isNaN(v)) m.micLevel = Math.max(v, m.micLevel * 0.75) }
        }
    }
    Sh {
        id: micProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        onResult: text => {
            if (micSlider.pressed || m.micPending >= 0) return
            const r = text.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
            if (r) { m.micVolume = parseFloat(r[1]); m.micMuted = !!r[2] }
        }
    }
    Sh {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        onResult: text => {
            if (slider.pressed || m.pending >= 0) return
            const r = text.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
            if (r) { m.volume = parseFloat(r[1]); m.muted = !!r[2] }
        }
    }
    MenuHeader { width: parent.width; title: "Sound"; showToggle: true; checked: !m.muted; onToggled: m.toggleMute() }   // toggle on = sound on

    Row {
        width: parent.width
        spacing: 12
        Text {
            id: volIcon
            width: 22
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: Icons.g(m.muted || m.volume === 0 ? "volume-x" : m.volume < 0.34 ? "volume" : m.volume < 0.67 ? "volume-1" : "volume-2")
            color: m.muted ? Theme.dim : Theme.text
            font { family: Icons.family; pixelSize: 18 }
            MouseArea { cursorShape: Qt.PointingHandCursor; anchors { fill: parent; margins: -6 } onClicked: m.toggleMute() }
        }
        Slider {
            id: slider
            width: parent.width - volIcon.width - pct.width - 24
            anchors.verticalCenter: parent.verticalCenter
            value: m.volume
            dimmed: m.muted
            onMoved: v => m.setVolume(v)
        }
        Text {
            id: pct
            width: 44
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: Math.round(m.volume * 100) + "%"
            color: Theme.text
            font { family: Theme.font; pixelSize: 13 }
        }
    }

    MenuSection { apart: true; title: "Output" }

    OutputList { width: parent.width }

    MenuHeader { width: parent.width; apart: true; title: "Microphone"; showToggle: true; checked: !m.micMuted; onToggled: m.toggleMicMute() }

    Row {
        width: parent.width
        spacing: 12
        Text {
            id: micIcon
            width: 22
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: Icons.g(m.micMuted ? "mic-off" : "mic")
            color: m.micMuted ? Theme.dim : Theme.text
            font { family: Icons.family; pixelSize: 18 }
            MouseArea { cursorShape: Qt.PointingHandCursor; anchors { fill: parent; margins: -6 } onClicked: m.toggleMicMute() }
        }
        Slider {
            id: micSlider
            width: parent.width - micIcon.width - micPct.width - 24
            anchors.verticalCenter: parent.verticalCenter
            value: m.micVolume
            level: m.micMuted ? 0 : m.micLevel
            dimmed: m.micMuted
            onMoved: v => m.setMicVolume(v)
        }
        Text {
            id: micPct
            width: 44
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: Math.round(m.micVolume * 100) + "%"
            color: Theme.text
            font { family: Theme.font; pixelSize: 13 }
        }
    }

    MenuSection { apart: true; title: "Input source" }

    OutputList { width: parent.width; kind: "source" }

    MenuButton {
        width: parent.width
        gap: 10   // no divider above it: the room sets it apart
        icon: "settings"
        label: "Sound settings…"
        onClicked: { Quickshell.execDetached(["pavucontrol"]); m.close() }
    }
}
