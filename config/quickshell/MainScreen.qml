pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The main screen, for what belongs on one screen and not the focused one: the sessions bar and the notifications
// (#3741). It is the Main display of the Displays window (the "main" line of arrangementFile, arrangement.lua), else
// the one with workspace 1 (where everything comes back to, virtual-display.lua), else the first external one (it has
// 1–9, display.lua), never a virtual one (a tablet over VNC). Workspace 1 alone wasn't enough: empty and not shown,
// Hyprland drops it, and the bar went to the first screen, the laptop's (#3294).
// It follows the file and the screens: unplugged, the Main display gives way to the next in that order, the laptop's
// own screen when it is the only one left.
Singleton {
    id: ms
    readonly property string arrangementFile: Quickshell.env("HOME") + "/.local/state/nightdrive/arrangement"
    property string mainKey: ""   // "desc:<make model serial>" for an external display, else an output's name

    FileView {
        path: ms.arrangementFile; watchChanges: true; onFileChanged: reload(); printErrors: false
        onLoaded: {
            const m = text().split("\n").map(l => l.match(/^main (.+)$/)).filter(m => m)
            ms.mainKey = m.length ? m[m.length - 1][1].trim() : ""   // the last one wins, as in arrangement.lua
        }
        onLoadFailed: ms.mainKey = ""
    }

    readonly property var screen: {
        const real = Quickshell.screens.filter(s => !s.name.startsWith("HEADLESS-"))
        const byName = n => n ? real.find(s => s.name === n) || null : null
        let s = null
        if (mainKey.startsWith("desc:")) {
            // An external display goes by its description, which only Hyprland's monitor object carries
            const mon = Hyprland.monitors.values.find(m => m.lastIpcObject
                                                          && "desc:" + m.lastIpcObject.description === mainKey)
            s = byName(mon ? mon.name : "")
        } else s = byName(mainKey)
        const w1 = Hyprland.workspaces.values.find(w => w.id === 1)
        return s || byName(w1 && w1.monitor ? w1.monitor.name : "")
            || real.find(s => !/^(eDP|LVDS|DSI)-/.test(s.name)) || real[0] || Quickshell.screens[0] || null
    }
    readonly property string name: screen ? screen.name : ""
}
