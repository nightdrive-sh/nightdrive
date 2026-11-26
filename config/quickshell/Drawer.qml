import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The empty drawer: when the drawer (⌘D, Hyprland's special:drawer, hypr/bindings.lua) is open with no windows in it,
// a panel the size of the drawer slides up from the bottom and tells how to fill it. With windows in it, Hyprland's
// own drawer shows alone. The size matches the drawer's workspace rule in hypr/appearance.lua (95 % high, edge to edge).
Variants {
    model: Quickshell.screens

    // One per screen: the drawer opens on the focused screen (activespecial names it); a single panel showed on the first
    // screen whichever one the drawer was on
    delegate: PanelWindow {
        id: win
        required property var modelData
        screen: modelData
        property bool open: false
        readonly property int windows: Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.name === "special:drawer").length
        readonly property bool shown: open && windows === 0

        Connections {
            target: Hyprland
            function onRawEvent(e) {
                if (e.name !== "activespecial") return
                const [ws, mon] = e.data.split(",")
                if (mon === win.modelData.name) win.open = ws === "special:drawer"
            }
        }

        // always mapped (invisible, clicks pass through), so its size is settled before the first slide; mapped only on
        // demand, the very first slide started from the top
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "nightdrive-drawer"
        mask: Region {}          // clicks pass through

        Rectangle {
            id: panel
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height - Math.floor(win.screen.height * 0.05)     // the same top gap as the workspace rule (below the top bar)
            // slides by an offset from the bottom edge, so the window's own size settling doesn't move it
            transform: Translate { y: win.shown ? 0 : win.screen.height; Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
            color: { const c = Qt.darker(Theme.hover, 1.3); return Qt.rgba(c.r, c.g, c.b, 0.97) }   // the theme colour's dark shade, darkened

            Column {
                anchors.centerIn: parent
                spacing: 20
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Icons.g("archive")
                    color: Theme.dim
                    opacity: 0.5
                    font { family: Icons.family; pixelSize: 72 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Open windows right here,\nor send one in with ⌘⇧D"
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.dim
                    font { family: Theme.font; pixelSize: 15 }
                }
            }
        }
    }
}
