import QtQuick
import Quickshell
import qs

// Home Assistant: the pinned devices (a click turns one on/off or runs a scene; a light that's on is yellow, a dimmable one
// shows its brightness as a ring around the bulb and takes the scroll wheel), and the webapp. Devices are pinned in
// the launcher: ⌘Space › Home, Shift+Enter. Data: Home.qml (bin/home-assistant).
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 8
    signal close()

    Component.onCompleted: { Home.check(); Home.refresh() }
    Timer { interval: 3000; repeat: true; running: true; onTriggered: Home.refresh() }

    MenuHeader { width: parent.width; title: "Home" }

    MenuNote {
        visible: !Home.loaded || Home.error !== "" || Home.favorites.length === 0
        variant: Home.error !== "" ? "danger" : "dim"
        text: !Home.loaded ? "Loading…"
            : Home.error !== "" ? Home.error
            : "No pinned devices. Pin them in the Launcher: ⌘Space › Home, Shift+Enter on a device."
    }

    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: Home.favorites
            // A dimmable light: its brightness as a ring around the bulb; the scroll wheel over it sets it
            delegate: Column {
                id: fav
                required property var modelData
                readonly property bool dimmable: modelData.dimmable && modelData.state !== "unavailable" && modelData.state !== "unknown"
                width: m.width
                MenuRow {
                    width: parent.width
                    icon: Home.icon(fav.modelData)
                    // a light: a yellow bulb (and the ring) instead of the filled circle
                    readonly property bool light: fav.modelData.domain === "light"
                    iconFilled: !light && Home.canToggle(fav.modelData) && Home.isOn(fav.modelData)
                    iconColor: light && Home.isOn(fav.modelData) ? Theme.caution : "transparent"
                    label: fav.modelData.name
                    // a dimmable light: the brightness is the ring, not a percentage
                    detail: [fav.modelData.area, fav.dimmable && /%$/.test(Home.detail(fav.modelData)) ? "" : Home.detail(fav.modelData)].filter(x => x).join(" · ")
                    level: fav.dimmable ? Home.bright(fav.modelData) : -1
                    opacity: fav.modelData.state === "unavailable" ? 0.5 : 1
                    onClicked: Home.toggle(fav.modelData)
                }
                // One wheel notch = 5 %; a touchpad's small deltas add up to that
                property real wheelAcc: 0
                WheelHandler {
                    enabled: fav.dimmable
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: ev => {
                        fav.wheelAcc += ev.angleDelta.y || -ev.angleDelta.x
                        while (Math.abs(fav.wheelAcc) >= 120) {
                            const dir = fav.wheelAcc > 0 ? 1 : -1
                            Home.stepBright(fav.modelData, dir, 5)
                            fav.wheelAcc -= dir * 120
                        }
                    }
                }
            }
        }
    }

    MenuButton {
        width: parent.width
        gap: 10   // no divider above it: the room sets it apart
        icon: "external-link"
        label: "Open Home Assistant"
        onClicked: { Quickshell.execDetached([Home.bin, "open"]); m.close() }
    }
}
