import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The host's clipboard into a VM as its window gets the keyboard (#3117), as UTM and Parallels share theirs: copy on the
// host, click the VM, paste there. garage-ctl clip-auto (lib/clip.sh) does the rest, quietly: only a VM whose setting
// allows it (on unless turned off in its Settings), only text, not a password manager's, and only when the clipboard has
// changed since it last went to that VM. The text never passes through here.
Item {
    id: root

    readonly property string ctl: Quickshell.shellDir + "/../bin/garage-ctl"
    readonly property int retryMs: 300      // a window's details not in yet: Hyprland's list is refreshed meanwhile
    property int retries: 0
    property int queued: 0                  // a VM's pid that got the keyboard while one call still ran

    function focused() {
        const t = Hyprland.activeToplevel
        const o = t && t.lastIpcObject
        if (!t) return
        if (!o || !o.class) {
            // Just opened: its class and pid come with the next refresh
            if (retries++ < 5) { Hyprland.refreshToplevels(); retry.restart() }
            return
        }
        retries = 0
        if (!o.class.startsWith("qemu-system-") || !o.pid) return
        if (proc.running) { queued = o.pid; return }
        send(o.pid)
    }

    function send(pid) {
        proc.command = [ctl, "clip-auto", String(pid)]
        proc.running = true
    }

    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root.retries = 0; root.focused() }
    }
    Timer { id: retry; interval: root.retryMs; onTriggered: root.focused() }

    Process {
        id: proc
        onExited: if (root.queued) { const p = root.queued; root.queued = 0; root.send(p) }
    }
}
