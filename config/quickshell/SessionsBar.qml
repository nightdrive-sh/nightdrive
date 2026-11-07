import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "SessionGroups.js" as Groups

// The sessions bar: every Claude Code session (Claude.qml, the Claude menu's own list) in a row at the bottom of the main
// screen, edge to edge like the top bar, with its exclusive zone so tiled windows make room. On from Claude menu ›
// Sessions bar (Claude.barOn), off by default; hidden while there are no sessions, and then the room goes back.
// A chip (SessionChip.qml) per session; a click goes to its window, the mouse over one shows more (SessionTip.qml).
// A session that opened others (nightdrive ask from it: a project manager) leads a group of them, first and joined to
// them by a line, its chip as wide as its name; the other chips share the rest of the row equally, so the bar is
// always full, their names shortened when it's crowded. A dot between groups and lone sessions (SessionGroups.js).
PanelWindow {
    id: sb
    readonly property int barH: 32
    readonly property int pad: 8          // from the screen's edges
    readonly property int gap: 8          // between chips: a group's line spans it
    readonly property int dotW: 8         // the dot between groups, with a gap on each side
    readonly property int maxLead: 220    // a lead's name, at most
    readonly property int minChip: 34     // the icon alone
    readonly property int textMin: 72     // narrower than this, a name shows too little ("#…"): the icon alone instead
    readonly property int chipPad: 10     // a chip's side padding
    readonly property int iconW: 16
    // A group's line, a lead's border and the dot: one quiet grey from the theme
    readonly property color line: Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.28)

    // The main screen: the one with workspace 1 (where everything comes back to, virtual-display.lua), never a virtual
    // one (a tablet over VNC); else the first real screen
    readonly property var mainScreen: {
        const real = Quickshell.screens.filter(s => !s.name.startsWith("HEADLESS-"))
        const w1 = Hyprland.workspaces.values.find(w => w.id === 1)
        const s = w1 && w1.monitor ? real.find(s => s.name === w1.monitor.name) : null
        return s || real[0] || Quickshell.screens[0] || null
    }
    readonly property var sessions: Claude.sessions
    readonly property var items: Groups.row(sessions)

    screen: mainScreen
    visible: Claude.barOn && sessions.length > 0 && mainScreen !== null
    anchors { bottom: true; left: true; right: true }
    implicitHeight: barH
    color: TopBar.c("bg")
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "nightdrive-sessions"

    function label(it) {
        const s = it.session
        return it.lead && s.name ? Groups.shortName(s.name) : s.name || s.topic || s.project
    }

    FontMetrics { id: fm; font { family: Theme.font; pixelSize: 12; bold: true } }

    // Each item's width: a lead's chip fits its (bold) name, a dot its own; the rest of the row is shared equally by the
    // other chips, so the row is always full. Too little for their names: the leads give theirs up first (the bot alone),
    // and if that isn't enough the others show only their icons, still sharing the row.
    readonly property var widths: {
        const n = items.length
        if (n === 0) return []
        const natural = it => Math.min(maxLead, Math.ceil(2 * chipPad + iconW + 6 + fm.advanceWidth(label(it))))
        const shareWith = leadW => {
            let room = width - 2 * pad - gap * (n - 1), shared = 0
            for (const it of items) {
                if (it.kind === "dot") room -= dotW
                else if (it.lead) room -= leadW(it)
                else shared++
            }
            return shared ? Math.max(minChip, Math.floor(room / shared)) : 0
        }
        let leadW = natural, share = shareWith(leadW)
        if (share > 0 && share < textMin) { leadW = () => minChip; share = shareWith(leadW) }
        return items.map(it => it.kind === "dot" ? dotW : it.lead ? leadW(it) : share)
    }

    property var hovered: null            // the chip under the mouse, for the tip

    Row {
        id: row
        x: sb.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: sb.gap
        Repeater {
            model: sb.items
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                width: sb.widths[index] || sb.minChip
                height: 24
                Rectangle {
                    visible: cell.modelData.kind === "dot"
                    anchors.centerIn: parent
                    width: 4; height: 4; radius: 2
                    color: sb.line
                }
                SessionChip {
                    id: chip
                    visible: cell.modelData.kind === "chip"
                    anchors.fill: parent
                    session: cell.modelData.session || ({})
                    lead: !!cell.modelData.lead
                    linked: !!cell.modelData.linked
                    linkWidth: sb.gap
                    lineColor: sb.line
                    text: visible ? sb.label(cell.modelData) : ""
                    iconOnly: width < sb.textMin
                    padding: sb.chipPad
                    active: !!cell.modelData.session && cell.modelData.session.address === Claude.activeAddr
                    onHoveredChanged: {
                        if (chip.hovered) sb.hovered = chip
                        else if (sb.hovered === chip) sb.hovered = null
                    }
                    onClicked: Claude.focus(cell.modelData.session)
                }
            }
        }
    }

    SessionTip {
        bar: sb
        chip: sb.hovered
    }
}
