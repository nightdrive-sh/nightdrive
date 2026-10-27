import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// A device coming or going plays system/device-in or device-out (hypr/scripts/sounds event): a Bluetooth device
// connecting or disconnecting (BlueZ, through Quickshell.Bluetooth), a USB device plugged in or out (udev).
// They happen by themselves, so not in do not disturb or under the login screen. Quiet at times when devices come and
// go on their own: the first seconds after Quickshell starts (Bluetooth reconnects at login) and after waking from
// sleep (USB comes back, Bluetooth reconnects). A dock or a hub brings several devices at once: they play once.
Scope {
    id: d

    // --- Tunables ---
    readonly property int quietMs: 10000        // after starting and after waking
    readonly property int gapMs: 1500           // events closer together than this play once (per direction)

    property double quietUntil: Date.now() + quietMs
    property var last: ({ "device-in": 0, "device-out": 0 })

    function play(name) {
        const now = Date.now()
        if (now < quietUntil || Notifs.dnd || Notifs.locked || now - last[name] < gapMs) return
        last[name] = now
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "event", name])
    }

    // Sleep shows as a jump in the clock between two ticks: the machine was away, stay quiet a while
    property double tick: Date.now()
    Timer {
        interval: 2000; running: true; repeat: true
        onTriggered: {
            const now = Date.now()
            if (now - d.tick > 3 * interval) d.quietUntil = now + d.quietMs
            d.tick = now
        }
    }

    Instantiator {
        model: Bluetooth.devices
        delegate: Connections {
            required property BluetoothDevice modelData
            target: modelData
            function onConnectedChanged() { d.play(modelData.connected ? "device-in" : "device-out") }
        }
    }

    // udev's USB events: a block of KEY=value lines each; the device itself (DEVTYPE=usb_device), not its interfaces,
    // and only add and remove (not bind, change)
    Process {
        id: usb
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=usb", "--property"]
        property string action: ""
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("ACTION=")) usb.action = line.slice(7)
                else if (line === "DEVTYPE=usb_device" && (usb.action === "add" || usb.action === "remove"))
                    d.play(usb.action === "add" ? "device-in" : "device-out")
            }
        }
    }
}
