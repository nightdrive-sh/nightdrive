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
// Each chip ends with how long it has worked or waited (Claude.sessions' since), ticking once a second; crowded, the
// times go first, then the leads' names, then all names.
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
    readonly property int stuckAfter: 600 // a turn running longer is probably stuck: its time in the warning colour
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
    // The Repeater's model is the items' keys, not the items: a new array on every claude-sessions poll would make it
    // build every chip anew, and the one under the mouse would lose its hover and its card (#2404). ScriptModel keeps
    // the delegate of a key that stays; each looks its item up by key. A chip's key is its window, a dot's the chip
    // after it.
    readonly property var keys: items.map((it, i) => it.kind === "dot" ? "dot " + items[i + 1].session.address
                                                                        : it.session.address)
    readonly property var byKey: {
        const m = {}
        items.forEach((it, i) => m[keys[i]] = it)
        return m
    }

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
    FontMetrics { id: tfm; font { family: Theme.font; pixelSize: 10; bold: true } }
    // A time's room: a typical one, so widths don't change with every tick ("1 h 5 min" shortens a name a little)
    readonly property int timeW: Math.ceil(tfm.advanceWidth("59 min")) + 6

    // Now, in epoch seconds, once a second while the bar shows: only the chips' times read it, so a tick rebuilds nothing
    property real now: Date.now() / 1000
    Timer { interval: 1000; repeat: true; running: sb.visible; onTriggered: sb.now = Date.now() / 1000 }
    // 42 s, 7 min, 1 h 5 min; "" when unknown (an old Claude Code without its record)
    function age(since) {
        if (!since) return ""
        const t = Math.max(0, Math.floor(now - since))
        if (t < 60) return t + " s"
        if (t < 3600) return Math.floor(t / 60) + " min"
        const m = Math.floor(t / 60) % 60
        return Math.floor(t / 3600) + " h" + (m ? " " + m + " min" : "")
    }

    // Each item's width: a lead's chip fits its (bold) name and its time, a dot its own; the rest of the row is shared
    // equally by the other chips, so the row is always full. Too little for names and times: the times go first, then
    // the leads give up their names (the bot alone), and if that isn't enough the others show only their icons, still
    // sharing the row. { widths, times }: times = whether the chips show theirs.
    readonly property var layout: {
        const n = items.length
        if (n === 0) return { widths: [], times: false }
        const natural = t => it => Math.min(maxLead + t, Math.ceil(2 * chipPad + iconW + 6 + fm.advanceWidth(label(it)) + t))
        const shareWith = leadW => {
            let room = width - 2 * pad - gap * (n - 1), shared = 0
            for (const it of items) {
                if (it.kind === "dot") room -= dotW
                else if (it.lead) room -= leadW(it)
                else shared++
            }
            return shared ? Math.max(minChip, Math.floor(room / shared)) : 0
        }
        let leadW = natural(timeW), share = shareWith(leadW), times = true
        if (share > 0 && share < textMin + timeW) { times = false; leadW = natural(0); share = shareWith(leadW) }
        if (share > 0 && share < textMin) { leadW = () => minChip; share = shareWith(leadW) }
        return { widths: items.map(it => it.kind === "dot" ? dotW : it.lead ? leadW(it) : share), times: times }
    }
    readonly property var widths: layout.widths

    property var hovered: null            // the chip under the mouse, for the tip

    Row {
        id: row
        x: sb.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: sb.gap
        Repeater {
            model: ScriptModel { values: sb.keys }
            delegate: Item {
                id: cell
                required property var modelData     // its key
                required property int index
                readonly property var it: sb.byKey[modelData] || ({ kind: "dot" })
                width: sb.widths[index] || sb.minChip
                height: 24
                Rectangle {
                    visible: cell.it.kind === "dot"
                    anchors.centerIn: parent
                    width: 4; height: 4; radius: 2
                    color: sb.line
                }
                SessionChip {
                    id: chip
                    visible: cell.it.kind === "chip"
                    anchors.fill: parent
                    session: cell.it.session || ({})
                    lead: !!cell.it.lead
                    linked: !!cell.it.linked
                    linkWidth: sb.gap
                    lineColor: sb.line
                    text: visible ? sb.label(cell.it) : ""
                    iconOnly: width < sb.textMin
                    showTime: sb.layout.times
                    time: visible ? sb.age(chip.session.since) : ""
                    stuck: chip.working && !chip.asking && chip.session.since > 0 && sb.now - chip.session.since >= sb.stuckAfter
                    padding: sb.chipPad
                    active: !!cell.it.session && cell.it.session.address === Claude.activeAddr
                    onHoveredChanged: {
                        if (chip.hovered) sb.hovered = chip
                        else if (sb.hovered === chip) sb.hovered = null
                    }
                    onClicked: Claude.focus(cell.it.session)
                }
            }
        }
    }

    SessionTip {
        bar: sb
        chip: sb.hovered
    }
}
