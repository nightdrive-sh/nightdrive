import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs

// "Resizing…" over a VM's window while its screen catches up with the window's new size (#1599). qemu tells the guest a
// second after the window's last change of size (ui/console.c: SDL's dpy_set_ui_info always waits), and SDL stretches
// the old picture over the window until the guest has switched (lib/qemu.sh: screen_args), so that second is covered.
// Nothing says when the guest is done, nor whether it follows at all (KDE might not), so the cover goes by time: HOLD_MS
// after the last change seen. Hyprland has no event for a window's change of size, so qemu's windows are looked at
// every POLL_MS while one shows, every IDLE_MS otherwise. Started by `garage-ctl start` (one for all VMs: flock), it
// quits once no VM's window has been there for QUIT_MS. A window's first size, as it opens, isn't covered.
ShellRoot {
    id: root

    readonly property int pollMs: 100
    readonly property int idleMs: 1000
    readonly property int holdMs: 1300    // qemu's second, and the guest's switch
    readonly property int quitMs: 10000

    // address → { w, h, until }: the size last seen, and until when it is covered
    property var seen: ({})
    // The covers to draw: [{ address, monitor, x, y, w, h }], x and y on its monitor
    property var covers: []
    property bool anyShown: false
    property real lastVm: Date.now()

    function tick() {
        const now = Date.now()
        const mons = {}, showing = {}
        // The workspaces that show: each monitor's, and the special one open over it. Not a hidden special one: a VM's
        // window hidden in special:bg (garage-ctl hide) changes size there unseen, and isn't polled for
        for (const m of Hyprland.monitors.values) {
            mons[m.name] = m
            const o = m.lastIpcObject
            if (o && o.activeWorkspace) showing[o.activeWorkspace.name] = true
            if (o && o.specialWorkspace && o.specialWorkspace.name) showing[o.specialWorkspace.name] = true
        }
        const next = {}, list = []
        let shown = false
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject
            if (!o || !o.class || !o.class.startsWith("qemu-system-") || !o.size) continue
            const prev = seen[t.address]
            let until = prev ? prev.until : 0
            if (prev && (prev.w !== o.size[0] || prev.h !== o.size[1])) until = now + holdMs
            next[t.address] = { w: o.size[0], h: o.size[1], until: until }
            const ws = t.workspace
            const visible = ws && (ws.active || !!showing[ws.name])
            shown = shown || visible
            const m = t.monitor && mons[t.monitor.name]
            if (visible && m && until > now)
                list.push({ address: t.address, monitor: m.name, x: o.at[0] - m.x, y: o.at[1] - m.y, w: o.size[0], h: o.size[1] })
        }
        seen = next
        covers = list
        anyShown = shown
        if (Object.keys(next).length) lastVm = now
        else if (now - lastVm > quitMs) Qt.quit()
        // For the next tick: the answer comes back asynchronously
        Hyprland.refreshToplevels()
        Hyprland.refreshMonitors()
    }

    Timer {
        running: true
        repeat: true
        interval: root.anyShown || root.covers.length ? root.pollMs : root.idleMs
        triggeredOnStart: true
        onTriggered: root.tick()
    }

    // One layer over each screen, always there (transparent, clicks pass through), so a cover shows in the very frame it
    // is needed, without a layer opening first
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "nightdrive-garage-resizing"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}

            Repeater {
                model: root.covers.filter(c => c.monitor === modelData.name)
                Rectangle {
                    required property var modelData
                    x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                    color: Theme.bg
                    Text {
                        anchors.centerIn: parent
                        text: "Resizing…"
                        color: Theme.dim
                        font { family: Theme.font; pixelSize: 15 }
                    }
                }
            }
        }
    }
}
