import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The sessions bar: every Claude Code session (Claude.qml, the Claude menu's own list) in a row at the bottom of the main
// screen, edge to edge like the top bar, with its exclusive zone so tiled windows make room. On from Claude menu ›
// Sessions bar (Claude.barOn), off by default; hidden while there are no sessions, and then the room goes back.
// A chip (SessionChip.qml) per session, oldest on the left so they keep their places; a click goes to its window, the
// mouse over one shows more (SessionTip.qml). When they don't all fit, the long names give way first (widths below).
PanelWindow {
    id: sb
    readonly property int barH: 32
    readonly property int pad: 8          // from the screen's edges
    readonly property int gap: 6          // between chips
    readonly property int maxChip: 340    // one long name doesn't take the whole bar
    readonly property int minChip: 34     // the icon alone
    readonly property int textMin: 72     // narrower than this, a name shows too little ("#…"): the icon alone instead
    readonly property int chipPad: 10     // a chip's side padding
    readonly property int iconW: 16

    // The main screen: the one with workspace 1 (where everything comes back to, virtual-display.lua), never a virtual
    // one (a tablet over VNC); else the first real screen
    readonly property var mainScreen: {
        const real = Quickshell.screens.filter(s => !s.name.startsWith("HEADLESS-"))
        const w1 = Hyprland.workspaces.values.find(w => w.id === 1)
        const s = w1 && w1.monitor ? real.find(s => s.name === w1.monitor.name) : null
        return s || real[0] || Quickshell.screens[0] || null
    }
    readonly property var sessions: Claude.sessions.slice().sort((a, b) => a.started - b.started || (a.address < b.address ? -1 : 1))

    screen: mainScreen
    visible: Claude.barOn && sessions.length > 0 && mainScreen !== null
    anchors { bottom: true; left: true; right: true }
    implicitHeight: barH
    color: TopBar.c("bg")
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "nightdrive-sessions"

    function label(s) { return s.name || s.topic || s.project }

    FontMetrics { id: fm; font { family: Theme.font; pixelSize: 12 } }

    // Each chip's width: its whole name when they all fit; otherwise the room is shared out so the short ones keep
    // theirs and the long ones get the same share each, shortened with an ellipsis (water-filling)
    readonly property var widths: {
        const n = sessions.length
        if (n === 0) return []
        const nat = sessions.map(s => Math.min(maxChip, Math.ceil(2 * chipPad + iconW + 6 + fm.advanceWidth(label(s)))))
        let room = width - 2 * pad - gap * (n - 1)
        if (room / n < textMin) return nat.map(() => minChip)
        const out = new Array(n)
        const order = nat.map((w, i) => i).sort((a, b) => nat[a] - nat[b])
        let left = n
        for (const i of order) {
            const share = Math.floor(room / left)
            out[i] = share < textMin ? minChip : Math.min(nat[i], share)
            room -= out[i]; left--
        }
        return out
    }

    property var hovered: null            // the chip under the mouse, for the tip

    Row {
        id: row
        x: sb.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: sb.gap
        Repeater {
            model: sb.sessions
            delegate: SessionChip {
                id: chip
                required property var modelData
                required property int index
                session: modelData
                text: sb.label(modelData)
                width: sb.widths[index] || sb.minChip
                iconOnly: width < sb.textMin
                padding: sb.chipPad
                active: modelData.address === Claude.activeAddr
                onHoveredChanged: {
                    if (chip.hovered) sb.hovered = chip
                    else if (sb.hovered === chip) sb.hovered = null
                }
                onClicked: Claude.focus(modelData)
            }
        }
    }

    SessionTip {
        bar: sb
        chip: sb.hovered
    }
}
