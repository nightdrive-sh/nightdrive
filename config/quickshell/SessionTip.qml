import QtQuick
import Quickshell
import "SessionGroups.js" as Groups

// The card above a chip of the sessions bar (SessionsBar.qml) while the mouse is on it: the session's name, Claude's
// topic for it (the window title's), its folder, its state, who opened it or how many it opened (SessionGroups.js) and
// the last line of its last reply. After a short wait, so
// passing over the bar doesn't flash cards.
PopupWindow {
    id: tip
    property var bar: null               // the bar (SessionsBar)
    property var chip: null              // the hovered SessionChip, or null
    readonly property int maxW: 420
    readonly property int gap: 6         // between the card and the bar

    // The chip last shown: the card keeps its text while it goes
    property var shown: null
    readonly property var s: shown ? shown.session : ({})

    onChipChanged: {
        if (chip) { if (visible) shown = chip; else wait.restart() }
        else { wait.stop(); visible = false }
    }
    Timer { id: wait; interval: 400; onTriggered: if (tip.chip) { tip.shown = tip.chip; tip.visible = true } }

    function home(p) {
        const h = Quickshell.env("HOME")
        return p && p.indexOf(h) === 0 ? "~" + p.slice(h.length) : (p || "")
    }
    // "Opened by …" or "Opened 3 sessions", or nothing
    function family(x) {
        if (!x.address) return ""
        const all = Claude.sessions
        const o = Groups.openerOf(x, all)
        // by address: the card's copy may be from an earlier look than all's
        const n = all.filter(k => { const ko = Groups.openerOf(k, all); return ko && ko.address === x.address }).length
        const by = o ? "Opened by " + (o.name || o.topic || o.project) : ""
        const of = n ? "Opened " + n + (n === 1 ? " session" : " sessions") : ""
        return [by, of].filter(t => t).join(" · ")
    }
    function stateText(x) {
        if (x.asking) return "Asks you" + (x.waitingFor ? ": " + x.waitingFor : "")
        if (x.state === "working") return "Working"
        if (x.done) return "Done"
        if (x.wants) return "Finished while you were away"
        return "Waiting for you"
    }

    anchor.window: bar
    anchor.rect.x: shown && bar ? shown.mapToItem(bar.contentItem, 0, 0).x : 0
    anchor.rect.y: -gap
    anchor.rect.width: 1
    anchor.rect.height: 1
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Top | Edges.Right
    visible: false
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"

    Rectangle {
        id: card
        width: Math.min(tip.maxW, Math.max(200, col.implicitWidth + 24))
        height: col.implicitHeight + 20
        radius: 8
        color: Theme.bg
        border { width: 1; color: tip.s.asking ? Theme.primary : Theme.border }
        Column {
            id: col
            x: 12; y: 10
            width: card.width - 24
            spacing: 4
            Text {
                width: Math.min(implicitWidth, tip.maxW - 24)
                text: tip.s.name || tip.s.topic || tip.s.project || ""
                elide: Text.ElideRight
                color: Theme.title
                font { family: Theme.font; pixelSize: 13; bold: true }
            }
            Text {
                visible: !!tip.s.topic && tip.s.topic !== tip.s.name
                width: Math.min(implicitWidth, tip.maxW - 24)
                text: tip.s.topic || ""
                elide: Text.ElideRight
                color: Theme.text
                font { family: Theme.font; pixelSize: 12 }
            }
            Text {
                width: Math.min(implicitWidth, tip.maxW - 24)
                text: tip.home(tip.s.dir)
                elide: Text.ElideMiddle
                color: Theme.dim
                font { family: Theme.font; pixelSize: 12 }
            }
            Text {
                text: tip.stateText(tip.s)
                color: tip.s.asking ? Theme.accent : tip.s.done ? Theme.ok : Theme.text
                font { family: Theme.font; pixelSize: 12 }
            }
            Text {
                readonly property string t: tip.family(tip.s)
                visible: t !== ""
                width: Math.min(implicitWidth, tip.maxW - 24)
                text: t
                elide: Text.ElideRight
                color: Theme.dim
                font { family: Theme.font; pixelSize: 12 }
            }
            Text {
                visible: !!tip.s.last
                width: Math.min(implicitWidth, tip.maxW - 24)
                topPadding: 4
                text: tip.s.last || ""
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                lineHeight: 1.15
                color: Theme.muted
                font { family: Theme.font; pixelSize: 12 }
            }
        }
    }
}
