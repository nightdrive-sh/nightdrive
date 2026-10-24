// Polkit password prompt (hyprpolkitagent): asking is true while its window is open. The launcher and the bar's menus
// are overlay layers with the keyboard, which no window can get above, so they step aside (hide, keeping their place)
// meanwhile; otherwise the prompt opened under them unseen and timed out. Every prompt counts: pkexec, systemd,
// firewalld, 1Password's system unlock.
import QtQuick
import Quickshell
import Quickshell.Hyprland

Scope {
    id: watch
    readonly property string agentClass: "hyprpolkitagent"
    readonly property bool asking: addresses.length > 0
    property var addresses: []          // the open prompts' window addresses (one per request; a retry may open another)

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow") {
                // ADDRESS,WORKSPACE,CLASS,TITLE
                const f = event.data.split(",")
                if (f[2] !== watch.agentClass) return
                watch.addresses = watch.addresses.concat([f[0]])
                // The layer had the keyboard: once it hides, give it to the prompt rather than to the window below
                Qt.callLater(() => Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ window = "address:0x${f[0]}" })`]))
            } else if (event.name === "closewindow") {
                if (watch.addresses.indexOf(event.data) >= 0)
                    watch.addresses = watch.addresses.filter(a => a !== event.data)
            }
        }
    }
}
