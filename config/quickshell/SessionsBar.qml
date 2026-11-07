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
// them by a line. Each group has an equal section of the bar, the lone sessions one more together (layout below); a
// chip is as wide as its name, and a section's sessions share it equally only when they don't fit. A dot between
// groups and lone sessions (SessionGroups.js).
// Each chip but a lead's ends with how long it has worked or waited (Claude.sessions' since), ticking once a second;
// crowded, the times go first, then the names (the leads keep theirs).
PanelWindow {
    id: sb
    readonly property int barH: 32
    readonly property int pad: 8          // from the screen's edges
    readonly property int gap: 8          // between chips: a group's line spans it
    readonly property int dotW: 8         // the dot between groups, with a gap on each side
    readonly property int maxLead: 220    // a lead's name, at most
    readonly property int maxChip: 320    // another chip's name and time, at most
    readonly property int timeGap: 10     // between a name and its time
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
    // A typical time's room, for when shared chips are too narrow to show theirs (a chip of its own fits its time as is)
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

    // The row in sections of equal width: one for each group (its lead and the sessions it opened; a lead whose
    // openings have all closed keeps its section, Claude.keptLeads), one more for all the lone sessions together, so
    // with two project managers each has half the bar. In a section the lead's chip is always as wide as its (bold)
    // name, with no time; every other chip as wide as its name and time, and only when they don't all fit do they share
    // what is left equally: then their times go first, and narrower still they show only their icons. The dots and
    // their gaps come off the bar first. { widths, chips, times }: each item's cell (a section's last one takes the rest
    // of it, so the sections stay put), its chip's width in that, and whether it shows its time.
    readonly property var layout: {
        const n = items.length
        if (n === 0) return { widths: [], chips: [], times: [] }
        const leadW = it => Math.min(maxLead, Math.ceil(2 * chipPad + iconW + 6 + fm.advanceWidth(label(it))))
        // The time as it reads now: it grows a step at 10 s, 1 min, 10 min, 1 h (the font's digits are one width)
        const ownW = it => {
            const t = age(it.session.since)
            return Math.min(maxChip, Math.ceil(2 * chipPad + iconW + 6 + nfm.advanceWidth(label(it))
                                               + (t ? timeGap + tfm.advanceWidth(t) : 0)))
        }
        const sections = {}, order = []
        let dots = 0
        items.forEach((it, i) => {
            if (it.kind === "dot") { dots++; return }
            if (!(it.unit in sections)) { sections[it.unit] = []; order.push(it.unit) }
            sections[it.unit].push(i)
        })
        const each = Math.floor((width - 2 * pad - dots * (dotW + 2 * gap)) / order.length)
        const widths = items.map(() => dotW), chips = items.map(() => dotW), times = items.map(() => false)
        for (const u of order) {
            const idx = sections[u]
            // The lone sessions stand apart (a dot between each, already off), a group's are joined across gaps
            const lead = u === "" ? -1 : idx[0]
            const rest = u === "" ? idx : idx.slice(1)
            let room = each - (u === "" ? 0 : gap * rest.length)
            if (lead >= 0) {
                chips[lead] = widths[lead] = Math.max(minChip, Math.min(leadW(items[lead]), room))
                room -= chips[lead]
            }
            const own = rest.map(i => ownW(items[i]))
            const fits = own.reduce((a, b) => a + b, 0) <= room
            const share = rest.length ? Math.max(minChip, Math.floor(room / rest.length)) : 0
            rest.forEach((i, k) => {
                chips[i] = widths[i] = fits ? own[k] : share
                times[i] = !items[i].lead && (fits || share >= textMin + timeW)
            })
            // What is left of the section: in its last cell, after its chip
            const used = idx.reduce((a, i) => a + widths[i], 0) + (u === "" ? 0 : gap * rest.length)
            widths[idx[idx.length - 1]] += Math.max(0, each - used)
        }
        return { widths: widths, chips: chips, times: times }
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
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: sb.layout.chips[cell.index] || parent.width
                    session: cell.it.session || ({})
                    lead: !!cell.it.lead
                    linked: !!cell.it.linked
                    linkWidth: sb.gap
                    lineColor: sb.line
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
