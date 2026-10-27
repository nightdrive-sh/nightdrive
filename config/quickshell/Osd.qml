import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Toast at the top: volume, screen or keyboard brightness, do not disturb and mic mute.
// The keybinding runs:  qs ipc call osd volume | brightness | kbd | dnd | mic
// (called only after wpctl / brightnessctl / the dnd toggle, so this just reads the current state).
// A volume key also ticks (hypr/scripts/sounds event volume: off in Settings › Notifications › System sounds), at the
// new level, so you hear how loud it is; not when it's muted.
Scope {
    id: osd
    property real volume: 0
    property bool muted: false
    property real brightness: 0
    property string mode: "volume"      // "volume" | "brightness" | "kbd" | "dnd" | "mic"
    property bool dnd: false
    property bool micMuted: false
    property string micLabel: ""
    readonly property bool textMode: mode === "dnd" || mode === "mic"
    readonly property real level: mode === "volume" ? volume : brightness

    IpcHandler {
        target: "osd"
        function volume(): void { osd.mode = "volume"; readProc.running = true }
        function brightness(): void { osd.mode = "brightness"; brightProc.command = ["brightnessctl", "-m"]; brightProc.running = true }
        function dnd(on: bool): void { osd.mode = "dnd"; osd.dnd = on; win.visible = true; hide.restart() }
        function mic(): void { osd.mode = "mic"; osd.micLabel = ""; micProc.running = true }
        function micblocked(): void { osd.mode = "mic"; osd.micMuted = true; osd.micLabel = "Unable to listen - mic muted"; win.visible = true; hide.restart() }   // F5 with the mic muted
        function kbd(): void { osd.mode = "kbd"; brightProc.command = ["brightnessctl", "-d", "*kbd_backlight*", "-m"]; brightProc.running = true }
    }

    Sh {
        id: readProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        onResult: text => {
            const m = text.match(/([\d.]+)/)
            osd.volume = m ? parseFloat(m[1]) : 0
            osd.muted = text.indexOf("[MUTED]") >= 0
            if (!osd.muted && osd.volume > 0)
                Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "event", "volume"])
            win.visible = true
            hide.restart()
        }
    }
    Sh {
        id: micProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        onResult: text => {
            osd.micMuted = text.indexOf("[MUTED]") >= 0
            win.visible = true
            hide.restart()
        }
    }
    Sh {
        id: brightProc
        command: ["brightnessctl", "-m"]
        onResult: text => {
            const m = text.match(/,(\d+)%/)
            osd.brightness = m ? parseInt(m[1]) / 100 : 0
            win.visible = true
            hide.restart()
        }
    }
    Timer { id: hide; interval: 1500; onTriggered: win.visible = false }

    PanelWindow {
        id: win
        visible: false
        anchors { top: true }
        margins { top: Theme.barHeight + 8 }
        implicitWidth: osd.mode === "mic" && osd.micLabel !== "" ? 350 : 280   // the long "Unable to listen" text needs a wider card
        implicitHeight: 48
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}          // clicks pass through the toast

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Theme.bg
            border { color: Theme.border; width: 1 }

            Text {
                id: ico
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                text: Icons.g(osd.mode === "mic" ? (osd.micMuted ? "mic-off" : "mic") : osd.mode === "dnd" ? (osd.dnd ? "bell-off" : "bell") : osd.mode === "brightness" ? "sun" : osd.mode === "kbd" ? "keyboard" : osd.muted || osd.volume <= 0 ? "volume-x" : osd.volume < 0.34 ? "volume" : osd.volume < 0.67 ? "volume-1" : "volume-2")
                font { family: Icons.family; pixelSize: 18 }
                color: osd.mode === "volume" && osd.muted ? Theme.dim : Theme.accent
            }
            Rectangle {
                id: track
                visible: !osd.textMode
                anchors { left: ico.right; leftMargin: 14; right: pct.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                height: 6; radius: 3
                color: Theme.hover
                Rectangle {
                    width: parent.width * Math.min(1, osd.level)
                    height: parent.height; radius: 3
                    color: osd.mode === "volume" && osd.muted ? Theme.off : Theme.primary
                }
            }
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
                visible: osd.textMode
                text: (osd.mode === "mic" ? (osd.micLabel !== "" ? osd.micLabel : (osd.micMuted ? "Mic off" : "Mic on"))
                                          : (osd.dnd ? "Do not disturb on" : "Notifications on")).toUpperCase()
                color: Theme.primary
                font { family: Theme.font; pixelSize: 12; letterSpacing: 0.6 }
            }
            Text {
                id: pct
                visible: !osd.textMode
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                readonly property bool isMuted: osd.mode === "volume" && osd.muted
                width: isMuted ? 52 : 38; horizontalAlignment: Text.AlignRight
                text: isMuted ? "MUTED" : Math.round(osd.level * 100) + "%"
                color: isMuted ? Theme.primary : Theme.text
                font { family: Theme.font; pixelSize: 12; letterSpacing: isMuted ? 0.6 : 0 }
            }
        }
    }
}
