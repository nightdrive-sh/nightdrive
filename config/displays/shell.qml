import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Displays (#1800): the screens as tiles to drag where they stand on the desk, as macOS's Arrangement: the laptop's own
// (dimmed with the lid closed, still movable), the external displays and the virtual ones (VNC Display's iPads), the
// main display with its label (workspaces 1–9), and the shelf of virtual screens put away. A drop is saved and applied at
// once (hypr/scripts/arrange). Beside it the picked screen's own settings (ScreenSettings: resolution, scale, refresh
// rate). This file holds the window together: the picked screen, the layout from wide to narrow, the keys.
ShellRoot {
    FloatingWindow {
        id: win
        title: "Displays"
        implicitWidth: 980
        implicitHeight: 620
        color: c.bg
        onClosed: Qt.quit()

        AppLook { id: c }
        readonly property QtObject look: c
        KeyHelp { id: keyHelp }
        Screens {
            id: screens
            onChanged: toast.show("Arranged")
            onErrorChanged: if (error !== "") toast.show(error, { danger: true })
            onScreensChanged: displayCtl.refresh()       // a reload or a display plugged in: its settings may be new too
        }
        DisplayCtl {
            id: displayCtl
            onApplied: screens.refresh()          // a new scale or resolution resizes it, and display fits the arrangement
            onErrorChanged: if (error !== "") toast.show(error, { danger: true })
        }
        // Wide enough for the picture and the panel side by side; narrower, the panel goes under the picture
        readonly property int panelWidth: 300
        readonly property bool wide: width >= 700

        // The picked screen: the first one's id until one is picked, and one that went (a device let go) gives its turn
        property string picked: ""
        readonly property var current: screens.byId(picked) || (screens.screens.length ? screens.screens[0] : null)
        function cycle(d) {
            const l = screens.screens
            if (!l.length) return
            const i = Math.max(0, l.findIndex(s => s.id === (current ? current.id : "")))
            picked = l[(i + d + l.length) % l.length].id
        }
        function toggleAway(s) {
            if (!s || s.kind !== "virtual") return
            if (s.away) screens.bringBack(s.id); else screens.putAway(s.id)
        }

        IpcHandler {
            target: "displays"
            function select(id: string): void { win.picked = id }
            function screens(): string { return JSON.stringify(screens.screens) }
            function refresh(): void { screens.refresh() }
        }

        Shortcut { sequences: ["Ctrl+Q", "Meta+Q"]; onActivated: Qt.quit() }

        // Wide: the title and the picture on the left, a line, the picked screen's panel on the right from the top down.
        // Narrow: the three one under another, without the line.
        GridLayout {
            id: content
            anchors.fill: parent
            columns: win.wide ? 3 : 1
            columnSpacing: 0; rowSpacing: 0
            focus: true
            AppPointer { c: win.look }

            Keys.onPressed: e => {
                const k = e.key, s = win.current
                win.look.moved(e)
                if (sheet.shown) { sheet.shown = false; e.accepted = true; return }
                if (k === Qt.Key_Question) sheet.shown = true
                else if (k === Qt.Key_Tab) win.cycle(1)
                else if (k === Qt.Key_Backtab) win.cycle(-1)
                else if (k === Qt.Key_Escape) Qt.quit()
                else if (!s) return
                else if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down) {
                    if (s.away) win.toggleAway(s)
                    else screens.step(s.id, { [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "above", [Qt.Key_Down]: "below" }[k])
                }
                else if (e.text === "m" && s.kind !== "virtual") screens.makeMain(s.id)
                else if (e.text === "a") win.toggleAway(s)
                else return
                e.accepted = true
            }

            ColumnLayout {
                Layout.fillWidth: true
                // Narrow, the picture takes its share and the panel the rest: both would fill, and the panel has no height of its own
                Layout.fillHeight: win.wide
                Layout.preferredHeight: win.wide ? -1 : Math.max(260, win.height * 0.5)
                Layout.margins: 20
                spacing: 12
                AppTitle { c: win.look; text: "Displays"; pixelSize: 15 }
                ArrangeCanvas {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    c: win.look
                    model: screens
                    selected: win.current ? win.current.id : ""
                    onPicked: id => { win.picked = id; content.forceActiveFocus() }
                    onRefused: text => toast.show(text, { danger: true })
                }
            }
            Rectangle {
                visible: win.wide
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: c.divider
            }
            ScreenSettings {
                Layout.fillHeight: true
                Layout.fillWidth: !win.wide
                Layout.preferredWidth: win.wide ? win.panelWidth : -1
                Layout.margins: 20
                Layout.topMargin: win.wide ? 20 : 0
                c: win.look
                ctl: displayCtl
                screen: win.current
                onMakeMain: screens.makeMain(win.current.id)
                onToggleAway: win.toggleAway(win.current)
            }
        }

        AppToast { id: toast; c: win.look }
        KeySheet { id: sheet; c: win.look; groups: keyHelp.groups }
    }
}
