import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The scale of the host screen each VM's window is on, into its guest (#1630: garage-ctl guest-scale, lib/qemu.sh), so
// a Nightdrive guest's text is as big as the host's, on the Mac's screen at 2 as on an external one at 1.5. Sent when a
// window is first seen and when it is on a screen of another scale; again every RESEND_MS, as the guest keeps it in
// /run, which a reboot inside the same window empties. A guest that doesn't answer yet (booting, no guest agent) is
// tried again every RETRY_MS. One garage-ctl at a time; the overlay's tick keeps Hyprland's lists fresh.
Item {
    id: root

    readonly property int checkMs: 1000
    readonly property int retryMs: 5000
    readonly property int resendMs: 30000
    readonly property string ctl: Quickshell.shellDir + "/../bin/garage-ctl"

    // qemu's pid → { scale, at, ok }: the last one sent, when, and whether the guest took it
    property var sent: ({})

    function check() {
        if (proc.running) return
        const scales = {}
        for (const m of Hyprland.monitors.values) {
            const o = m.lastIpcObject
            if (o && o.scale) scales[m.name] = o.scale
        }
        const now = Date.now(), kept = {}
        let job = null
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject
            if (!o || !o.class || !o.class.startsWith("qemu-system-") || !o.pid || !t.monitor) continue
            const scale = scales[t.monitor.name]
            if (!scale) continue
            const s = sent[o.pid]
            if (s) kept[o.pid] = s
            const due = !s || s.scale !== scale || now - s.at > (s.ok ? resendMs : retryMs)
            if (due && !job) job = { pid: o.pid, scale: scale }
        }
        sent = kept     // a window gone, its VM's qemu with it
        if (!job) return
        proc.job = job
        proc.command = [ctl, "guest-scale", String(job.pid), String(job.scale)]
        proc.running = true
    }

    Process {
        id: proc
        property var job: null
        onExited: code => {
            const s = Object.assign({}, root.sent)
            s[job.pid] = { scale: job.scale, at: Date.now(), ok: code === 0 }
            root.sent = s
        }
    }

    Timer { interval: root.checkMs; running: true; repeat: true; onTriggered: root.check() }
}
