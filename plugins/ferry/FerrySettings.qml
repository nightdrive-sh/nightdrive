import QtQuick
import qs

// Ferry's menu › Settings beside Clear: its settings. For now the owner's other devices, each forgotten on all of them
// with two clicks: the first asks, the second forgets (Ferry's docs/protocol.md › Forgetting a device). A forgotten
// device stays gone, whatever it is: only Add Device brings it back, so the user can trust it is removed (no list of
// forgotten ones to bring back here). `ferry forget` runs the hook, and the menu's next `ferry list --json` leaves the
// row out. Its own file: FerryMenu.qml is long enough.
Column {
    id: s
    required property var menu        // FerryMenu.qml: devices, run(), deviceIcon(), deviceState(), addDevice()
    signal done()
    spacing: 8

    readonly property var devices: s.menu.devices
    // The devices just clicked, until `ferry list` leaves them out (or a while has gone): their rows wait
    property var pending: []
    // The device the first click asked about: the second click on it forgets it. It asks no longer after a while,
    // or on a click on another device, since a forgotten device comes back only with Add Device.
    property string asking: ""
    Timer { id: askGiveUp; interval: 4000; onTriggered: s.asking = "" }
    onDevicesChanged: s.pending = s.pending.filter(id => s.devices.some(d => d.id === id))
    function click(d) {
        if (s.pending.includes(d.id)) return
        if (s.asking !== d.id) { s.asking = d.id; askGiveUp.restart(); return }
        s.asking = ""
        s.pending = s.pending.concat([d.id])
        pendingGiveUp.restart()
        s.menu.run(["forget", d.id])
    }
    Timer { id: pendingGiveUp; interval: 10000; onTriggered: s.pending = [] }

    MenuHeader {
        width: parent.width
        title: "Ferry"
        action: "Done"
        onActionClicked: s.done()
    }

    // A device: its kind's icon, name and state; under the mouse, what a click does. Asking, it is red and says so.
    MenuSection { title: "Devices" }
    Repeater {
        model: s.devices
        delegate: MenuRow {
            required property var modelData
            readonly property bool asking: s.asking === modelData.id
            width: s.width
            icon: s.menu.deviceIcon(modelData)
            label: asking ? "Forget " + (modelData.name || modelData.id) + "?" : modelData.name || modelData.id
            detail: asking ? "click again" : s.menu.deviceState(modelData)
            danger: asking
            busy: s.pending.includes(modelData.id)
            hoverCheckIcon: busy || asking ? "" : "trash-2"
            onClicked: s.click(modelData)
        }
    }
    MenuNote {
        visible: s.devices.length === 0
        text: "No other device yet: add one with Add Device below."
    }

    // The pill's list has it too: here beside the devices, where one looks for it among the settings
    MenuButton {
        width: parent.width
        gap: 10
        icon: "qr-code"
        label: "Add Device…"
        onClicked: s.menu.addDevice()
    }
}
