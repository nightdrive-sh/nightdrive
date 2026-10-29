import QtQuick
import qs
import qs.kit
import "Words.js" as Words

// An area in full (› on its row): each right's choice and every tool under it in plain words, with which ones always
// ask and which come with Undo, so nothing Claude can do here is hidden behind a summary. The area's own finer
// choices (Contacts' fields, Mail's block list, the apps whose windows Claude may see, Home Assistant's: Dashboard
// #1789, #1830, #1832) go in this panel, under the rights: on or off each (OptionRow), ↑ ↓ and Space. A list choice
// is a row per entry: those on it ticked, and under them what areas.py's `offer` finds to add (the open apps for the
// apps whose windows Claude sees without asking, those in the notification history for the ones whose notifications
// it doesn't), so Space or a click puts one on or takes it off; a typed list (Mail's blocked senders) ends in a field
// to add one (AddItemRow).
AppPanel {
    id: root
    property var area: null             // the row's area as it was when the panel opened
    property QtObject access: null      // the window's Store: the choices below follow what applies after a write
    readonly property var live: area && access ? access.area(area.id) || area : area
    readonly property var options: live && live.options ? live.options : []
    // A row per on-or-off choice, and per app of a list; the first of a list carries its heading, and a list with
    // nothing to show has one row that only says so (note), which ↑ ↓ pass by
    readonly property var picks: {
        let out = []
        for (const o of options) {
            if (!o.list) { out.push({ option: o, row: o }); continue }
            const label = v => o.offer === "windows" ? openApps.name(v) : v
            const on = o.value.map(v => ({ option: o, item: v, row: { name: label(v), value: true, on: o.on } }))
            const listed = o.value.map(v => v.toLowerCase())
            const offered = o.offer === "windows" ? openApps.classes : o.offer === "notifications" ? notifApps.names : []
            const off = offered.filter(v => listed.indexOf(v.toLowerCase()) < 0)
                .map(v => ({ option: o, item: v, row: { name: label(v), value: false, off: o.off } }))
                .sort((a, b) => a.row.name.localeCompare(b.row.name))
            const rows = on.concat(off)
            if (o.offer === "typed") rows.push({ option: o, add: true })
            if (!rows.length) rows.push({ option: o, note: o.offer === "notifications"
                ? "None listed: an app shows here to add once it has sent a notification."
                : "None listed: open an app and it shows here to add." })
            rows[0].heading = o
            out = out.concat(rows)
        }
        return out
    }
    property int pick: 0
    readonly property int margin: 24    // the window's edge to the card when it scrolls
    // The picked choice stays in view as ↑ ↓ move it
    onPickChanged: Qt.callLater(() => {
        // A typed list's field takes the keys while picked (AddItemRow); anything else gives them back to the panel
        if (visible && !(picks[pick] && picks[pick].add)) root.forceActiveFocus()
        const item = choiceRows.itemAt(pick)
        if (!item) return
        const y = item.mapToItem(body, 0, 0).y
        if (y < scroll.contentY) scroll.contentY = y
        else if (y + item.height > scroll.contentY + scroll.height)
            scroll.contentY = Math.min(y + item.height - scroll.height, scroll.contentHeight - scroll.height)
    })
    cardWidth: 580
    visible: area !== null
    onOutsideTapped: area = null
    onAreaChanged: {
        pick = Math.max(0, picks.findIndex(p => !p.note && !p.add)); scroll.contentY = 0
        // The area's own: `options` may not have followed it yet here
        if (area && (area.options || []).some(o => o.offer === "notifications")) notifApps.refresh()
    }

    OpenApps { id: openApps }
    NotifApps { id: notifApps; nd: root.access ? root.access.nd : "" }

    function toggle(i) {
        const p = picks[i]
        if (!p || p.note || p.add || !access) return
        pick = i
        if (p.item !== undefined) access.setListItem(live.id, p.option.id, p.item, !p.row.value)
        else access.setOption(live.id, p.option.id, !p.option.value)
    }
    function step(d) {
        for (let i = pick + d; i >= 0 && i < picks.length; i += d)
            if (!picks[i].note) { pick = i; return }
    }

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_Left || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            area = null
        } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
            step(1)
        } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
            step(-1)
        } else if (e.key === Qt.Key_Space) {
            toggle(pick)
        } else {
            return
        }
        e.accepted = true
    }

    // The card grows with what it holds up to the window's height, and scrolls past it: a short window (or Contacts'
    // eight choices, #1789) would push the rights and the last choices out of sight, as the kit's panel doesn't scroll
    Flickable {
        id: scroll
        width: parent.width
        height: Math.min(body.implicitHeight, Math.max(160, root.height - 72 - 2 * root.margin))
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        TouchScroll { view: scroll }

        Column {
            id: body
            width: scroll.width
            spacing: 18
            Row {
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.area ? Icons.g(root.area.glyph) : ""; color: root.c.accent
                    font { family: Icons.family; pixelSize: 18 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.area ? root.area.name : ""; color: root.c.title
                    font { family: root.c.font; pixelSize: 16; weight: Font.DemiBold }
                }
            }

            Repeater {
                model: root.area ? Words.RIGHTS.filter(r => root.area.rights[r]) : []
                Column {
                    id: right
                    required property string modelData
                    readonly property var info: root.area.rights[modelData]
                    width: parent.width
                    spacing: 4
                    Text {
                        text: Words.RIGHT_NAMES[right.modelData] + " · " + Words.state(right.modelData, right.info)
                              + (right.info.own ? "  (your own; the level's is " + Words.VALUE_NAMES[right.info.preset] + ")" : "")
                        color: right.info.value === "ask" ? Theme.warning : root.c.text
                        font { family: root.c.font; pixelSize: 13; weight: Font.DemiBold }
                    }
                    Text {
                        visible: !!right.info.words
                        width: parent.width
                        text: "Claude " + right.info.words + "."
                        wrapMode: Text.Wrap
                        color: root.c.dim
                        font { family: root.c.font; pixelSize: 12 }
                    }
                    Repeater {
                        model: right.info.tools
                        Text {
                            required property var modelData
                            x: 12
                            width: right.width - 12
                            text: "• " + modelData.title
                                  + (modelData.asks ? "  — always asks" : modelData.undo ? "  — with Undo" : "")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: root.c.text
                            font { family: root.c.font; pixelSize: 12 }
                        }
                    }
                }
            }

            // The area's own choices: what its tools may do within the rights above
            Column {
                visible: root.options.length > 0
                width: parent.width
                spacing: 4
                Text {
                    text: "Choices"
                    color: root.c.text
                    font { family: root.c.font; pixelSize: 13; weight: Font.DemiBold }
                }
                Repeater {
                    id: choiceRows
                    model: root.picks
                    Column {
                        id: pickRow
                        required property var modelData
                        required property int index
                        width: parent.width
                        spacing: 2
                        Text {
                            visible: !!pickRow.modelData.heading
                            width: parent.width
                            topPadding: pickRow.index > 0 ? 8 : 0
                            text: pickRow.modelData.heading ? pickRow.modelData.heading.name : ""
                            color: root.c.text
                            font { family: root.c.font; pixelSize: 13 }
                        }
                        Text {
                            visible: !!pickRow.modelData.heading && !!pickRow.modelData.heading.words
                            width: parent.width
                            bottomPadding: 2
                            text: pickRow.modelData.heading ? pickRow.modelData.heading.words || "" : ""
                            wrapMode: Text.Wrap
                            color: root.c.dim
                            font { family: root.c.font; pixelSize: 12 }
                        }
                        Text {
                            visible: !!pickRow.modelData.note
                            x: 8
                            width: parent.width - 8
                            text: pickRow.modelData.note || ""
                            wrapMode: Text.Wrap
                            color: root.c.faint
                            font { family: root.c.font; pixelSize: 12 }
                        }
                        AddItemRow {
                            visible: !!pickRow.modelData.add
                            width: parent.width
                            c: root.c
                            option: pickRow.modelData.option
                            picked: visible && pickRow.index === root.pick
                            onAdded: text => {
                                const id = pickRow.modelData.option.id
                                root.access.setListItem(root.live.id, id, text, true)
                                // The new entry's row goes above the field: the field stays picked, for the next one
                                Qt.callLater(() => root.pick = root.picks.findIndex(p => p.add && p.option.id === id))
                            }
                            onMoved: d => root.step(d)
                            onClicked: root.pick = pickRow.index
                            onEscaped: root.area = null
                        }
                        OptionRow {
                            visible: !pickRow.modelData.note && !pickRow.modelData.add
                            width: parent.width
                            c: root.c
                            option: pickRow.modelData.row || ({ name: "", value: false, on: "", off: "" })
                            picked: pickRow.index === root.pick
                            onToggled: root.toggle(pickRow.index)
                        }
                    }
                }
            }

            Text {
                visible: !!root.area && !!root.area.rights.read && root.area.rights.read.value !== "no"
                width: parent.width
                text: "What these read goes to Anthropic with Claude's answer."
                wrapMode: Text.Wrap
                color: root.c.dim
                font { family: root.c.font; pixelSize: 12 }
            }
        }
    }
}
