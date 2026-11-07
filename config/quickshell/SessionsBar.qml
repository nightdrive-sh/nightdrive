import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "SessionGroups.js" as Groups

// The sessions bar: every Claude Code session (Claude.qml, the Claude menu's own list) in a row at the bottom of the main
// screen, edge to edge like the top bar, with its exclusive zone so tiled windows make room. On from Claude menu ›
// Sessions bar (Claude.barOn), off by default; hidden while there are no sessions, and then the room goes back.
// A chip (SessionChip.qml) per session; a click goes to its window, the mouse over one shows more (SessionTip.qml).
// A session that opened others (nightdrive ask from it: a project manager) leads a group of them, first and
// in bold (no lines between them: the bar reads quieter). Groups and lone sessions follow each other, a dot between
// each (SessionGroups.js); a chip is as wide as its name, and the chips share the bar equally only when they don't
// fit (layout below).
// Its background is the top bar's (TopBar.c("bg")), so it follows Settings › Top bar opacity.
// Each chip but a lead's ends with how long it has worked or waited (Claude.sessions' since), ticking once a second;
// crowded, the times go first, then the names (the leads keep theirs).
PanelWindow {
    id: sb
    readonly property int barH: Theme.barHeight   // as tall as the top bar
    readonly property int chipH: Theme.pillHeight   // as the top bar's workspace highlight
    readonly property int pad: 8          // from the screen's edges
    readonly property int gap: 0          // between chips: their own padding keeps them apart
    readonly property int dotW: 8         // the dot between groups, with a gap on each side
    readonly property int dotPad: 10      // more room on the dot's left: a chip with no box ends close to it otherwise
    readonly property int dotPadR: 11     // and on its right, so it sits midway (the next icon has its padding too)
    readonly property int maxLead: 220    // a lead's name, at most
    readonly property int maxChip: 320    // another chip's name and time, at most
    readonly property int timeGap: 10     // between a name and its time
    readonly property int minChip: 34     // the icon alone
    readonly property int textMin: 72     // narrower than this, a name shows too little ("#…"): the icon alone instead
    readonly property int chipPad: 10     // a chip's side padding
    readonly property int iconW: 16
    readonly property int stuckAfter: 600 // a turn running longer is probably stuck: its time in the warning colour
    // The dot between groups: a quiet grey from the theme
    readonly property color line: Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.38)

    // The main screen: the one with workspace 1 (where everything comes back to, virtual-display.lua), never a virtual
    // one (a tablet over VNC); else the first real screen
    readonly property var mainScreen: {
        const real = Quickshell.screens.filter(s => !s.name.startsWith("HEADLESS-"))
        const w1 = Hyprland.workspaces.values.find(w => w.id === 1)
        const s = w1 && w1.monitor ? real.find(s => s.name === w1.monitor.name) : null
        return s || real[0] || Quickshell.screens[0] || null
    }
    readonly property var sessions: Claude.sessions
    readonly property var items: Groups.row(sessions, Claude.keptLeads)
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
    FontMetrics { id: nfm; font { family: Theme.font; pixelSize: 12 } }   // the others' names
    FontMetrics { id: tfm; font { family: Theme.font; pixelSize: 10; bold: true } }
    // A typical time's room, for when shared chips are too narrow to show theirs (an unshared chip fits its time as is)
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

    // The row: groups and lone sessions one after another, with no shares of their own (#2410), the room
    // after the last chip left empty. A lead's chip is always as wide as its (bold) name, with no time; every other chip
    // as wide as its name and time, and only when they don't all fit do they share what the leads, dots and gaps leave
    // equally: then their times go first, and narrower still they show only their icons. { widths, times }: each item's
    // width and whether it shows its time.
    readonly property var layout: {
        const n = items.length
        if (n === 0) return { widths: [], times: [] }
        const leadW = it => Math.min(maxLead, Math.ceil(2 * chipPad + iconW + 6 + fm.advanceWidth(label(it))))
        // The time as it reads now: it grows a step at 10 s, 1 min, 10 min, 1 h (the font's digits are one width)
        const ownW = it => {
            const t = age(it.session.since)
            return Math.min(maxChip, Math.ceil(2 * chipPad + iconW + 6 + nfm.advanceWidth(label(it))
                                               + (t ? timeGap + tfm.advanceWidth(t) : 0)))
        }
        const widths = items.map(it => it.kind === "dot" ? dotW + dotPad + dotPadR : it.lead ? leadW(it) : ownW(it))
        const others = items.map((it, i) => i).filter(i => items[i].kind === "chip" && !items[i].lead)
        let room = width - 2 * pad - gap * (n - 1)
        items.forEach((it, i) => { if (it.kind === "dot" || it.lead) room -= widths[i] })
        const fits = others.reduce((a, i) => a + widths[i], 0) <= room
        const share = others.length ? Math.max(minChip, Math.floor(room / others.length)) : 0
        const times = items.map(() => false)
        for (const i of others) {
            if (!fits) widths[i] = share
            times[i] = fits || share >= textMin + timeW
        }
        return { widths: widths, times: times }
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
                height: sb.chipH
                Rectangle {
                    visible: cell.it.kind === "dot"
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: (sb.dotPad - sb.dotPadR) / 2
                    width: 4; height: 4; radius: 2
                    color: sb.line
                }
                SessionChip {
                    id: chip
                    visible: cell.it.kind === "chip"
                    anchors.fill: parent
                    session: cell.it.session || ({})
                    lead: !!cell.it.lead
                    text: visible ? sb.label(cell.it) : ""
                    iconOnly: width < sb.textMin
                    showTime: !!sb.layout.times[cell.index]
                    time: visible ? sb.age(chip.session.since) : ""
                    stuck: chip.working && !chip.asking && chip.session.since > 0 && sb.now - chip.session.since >= sb.stuckAfter
                    padding: sb.chipPad
                    timeGap: sb.timeGap
                    active: !!cell.it.session && cell.it.session.address === Claude.activeAddr
                    onHoveredChanged: {
                        if (chip.hovered) sb.hovered = chip
                        else if (sb.hovered === chip) sb.hovered = null
                    }
                    // A click closes the card too; it comes back only when the mouse enters a chip again
                    onClicked: { sb.hovered = null; Claude.focus(cell.it.session) }
                }
            }
        }
    }

    SessionTip {
        bar: sb
        chip: sb.hovered
    }
}
