import QtQuick
import Quickshell.Io

// The window's two sizes (Jari, 5.11.2026): while a recording is made, a low wide strip (STRIP_W × STRIP_H) that
// stays out of the way; otherwise tall, with the recordings under the strip. A Wayland window can't resize itself once
// Hyprland has placed it, so the size is asked of Hyprland (hl.dsp.window.resize on this window, found by Quickshell's
// pid: the shell's $PPID). The tall size the user gave it is kept for the way back; one that would then reach past the
// screen's bottom (the strip was moved down) is centred. A window tiled with ⌘⇧T is left alone: the layout sizes it.
// The first size is hyprland.lua's rule (TALL_W × TALL_H there too).
QtObject {
    id: ws
    readonly property int stripW: 560
    readonly property int stripH: 88
    readonly property int tallW: 720
    readonly property int tallH: 520
    property bool strip: false
    property int keptW: tallW                  // the tall size, as it was when the window became the strip
    property int keptH: tallH
    onStripChanged: apply()
    function apply() {
        if (resizer.running) { again = true; return }
        resizer.command = ["bash", "-c", ws.script, "_", strip ? "strip" : "tall",
                           String(strip ? stripW : keptW), String(strip ? stripH : keptH)]
        resizer.running = true
    }
    property bool again: false

    // Prints the window's size before the change ("W H"), so the tall one is kept. Waits up to 2 s for the window to be
    // mapped: the first apply comes as the window loads.
    readonly property string script: '
command -v hyprctl >/dev/null || exit 0
for _ in $(seq 20); do
  read -r addr w h floating mon x y < <(hyprctl -j clients | jq -r --argjson pid "$PPID" \
    \'[.[] | select(.pid == $pid and .title == "Recorder")] | first // empty
      | "\\(.address) \\(.size[0]) \\(.size[1]) \\(.floating) \\(.monitor) \\(.at[0]) \\(.at[1])"\')
  [[ -n $addr ]] && break
  sleep 0.1
done
[[ -n $addr && $floating == true ]] || exit 0
echo "$w $h"
hyprctl dispatch "hl.dsp.window.resize({ x = $2, y = $3, exact = true, window = \\"address:$addr\\" })" >/dev/null
if [[ $1 == tall ]]; then
  bottom=$(hyprctl -j monitors | jq --argjson id "$mon" \'.[] | select(.id == $id) | .y + (.height / .scale)\')
  (( y + $3 > ${bottom%.*} )) && hyprctl dispatch "hl.dsp.window.center({ window = \\"address:$addr\\" })" >/dev/null
fi
exit 0'

    property Process resizer: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim().split(" ").map(Number)
                // The size before becoming the strip is the tall one to come back to (not a strip's own size)
                if (ws.strip && s.length === 2 && s[1] > ws.stripH + 40) { ws.keptW = s[0]; ws.keptH = s[1] }
            }
        }
        onExited: if (ws.again) { ws.again = false; ws.apply() }
    }
}
