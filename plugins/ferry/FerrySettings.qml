import QtQuick
import qs

// Ferry's menu › Devices… (the pill's list): the owner's other devices, each forgotten on all of them with a click, and
// the forgotten ones brought back (Ferry's docs/protocol.md › Forgetting a device; the Mac's Settings › Devices and the
// Linux window's More › Devices… do the same). `ferry forget` / `unforget` run the hook, and the menu's next
// `ferry list --json` moves the row: `devices` and `forgotten`. Its own file: FerryMenu.qml is long enough.
Column {
    id: s
    required property var menu        // FerryMenu.qml: st, ferry, run(), deviceIcon(), deviceState()
    signal done()
    spacing: 8

    readonly property var devices: s.menu.devices
    readonly property var forgotten: s.menu.st && s.menu.st.forgotten ? s.menu.st.forgotten : []
    // A device just clicked, until `ferry list` shows it in its new list (or a while has gone): its row waits
    property var pending: ({})        // id: true to forget, false to bring back
    onDevicesChanged: settle()
    onForgottenChanged: settle()
    function settle() {
        const left = {}
        for (const id in s.pending)
            if ((s.pending[id] ? s.devices : s.forgotten).some(d => d.id === id)) left[id] = s.pending[id]
        s.pending = left
    }
    function decide(d, forget) {
        if (d.id in s.pending) return
        s.pending = Object.assign({}, s.pending, { [d.id]: forget })
        pendingGiveUp.restart()
        s.menu.run([forget ? "forget" : "unforget", d.id])
    }
    Timer { id: pendingGiveUp; interval: 10000; onTriggered: s.pending = ({}) }

    // A device: its kind's icon, name and state; what a click does shows under the mouse
    component DeviceRow: MenuRow {
        required property var modelData
        property bool forgotten: false
        width: s.width
        icon: s.menu.deviceIcon(modelData)
        label: modelData.name || modelData.id
        detail: forgotten ? "Forgotten" : s.menu.deviceState(modelData)
        busy: modelData.id in s.pending
        hoverCheckIcon: busy ? "" : forgotten ? "undo-2" : "eye-off"
        opacity: forgotten ? 0.6 : 1
        onClicked: s.decide(modelData, !forgotten)
    }

    MenuHeader {
        width: parent.width
        title: "Ferry"
        subtitle: "Devices"
        action: "Done"
        onActionClicked: s.done()
    }

    MenuSection { title: "Your devices"; subtitle: "click to forget" }
    Repeater {
        model: s.devices
        delegate: DeviceRow {}
    }
    MenuNote {
        visible: s.devices.length === 0
        text: "No other device yet: add one with Add Device."
    }

    MenuSection { visible: s.forgotten.length > 0; title: "Forgotten"; subtitle: "click to bring back" }
    Repeater {
        model: s.forgotten
        delegate: DeviceRow { forgotten: true }
    }

    MenuNote {
        topPadding: 6
        text: "Forget takes a device off the lists on all your devices, and a phone gets no more notifications. "
            + "It stays forgotten until you bring it back."
    }
}
