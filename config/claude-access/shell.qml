import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit
import "Words.js" as Words

// Claude's access, the window of Settings › Claude › Access (Dashboard #1831): what Claude Code may do on this desktop
// through Nightdrive's tools. The level at the top (LevelBar); then a row per area (AreaRow) with Read, Modify and
// Delete, each Allow, Ask or No in a drop-down (ChoiceMenu), and the picked row's choices in plain words under it; ›
// shows an area in full (AreaPanel). What applies, and every write, is config/mcp/access.py's (Store).
// This file holds the window together: the keys (their sheet: KeyHelp.qml), the level's question and the IPC.
ShellRoot {
    FloatingWindow {
        id: win
        title: "Claude's access"
        implicitWidth: 860
        implicitHeight: 700
        color: c.bg
        onClosed: Qt.quit()

        AppLook { id: c }
        Store { id: store }
        KeyHelp { id: keyHelp }
        readonly property QtObject look: c

        readonly property int nameWidth: 280
        readonly property int cellWidth: 112
        property int cur: 0                         // the picked area
        property int col: 0                         // its column: 0–2 Read, Modify, Delete; 3 the panel
        property string askLevel: ""                // a level waiting for its yes (it would undo the user's own choices)
        readonly property var areas: store.areas

        function rights(i) { return areas[i] ? areas[i].rights : {} }
        // The column on a right the row has, nearest to where it was: a row without Delete doesn't hold the keys on a dash
        function fitCol() {
            if (col === 3) return
            const r = rights(cur)
            for (let d = 0; d < 3; d++)
                for (const c of [col - d, col + d])
                    if (c >= 0 && c <= 2 && r[Words.RIGHTS[c]]) { col = c; return }
            col = 3
        }
        function moveCol(d) {
            const r = rights(cur)
            let c = col
            do { c += d } while (c >= 0 && c <= 2 && !r[Words.RIGHTS[c]])
            if (c >= 0 && c <= 3) col = c
        }
        function pickRow(i) { cur = Math.max(0, Math.min(i, areas.length - 1)); fitCol(); list.positionViewAtIndex(cur, ListView.Contain) }

        // The drop-down under the cell, or the panel for ›
        function open(i, c, cell) {
            pickRow(i)
            col = c
            if (c === 3) { panel.area = areas[cur]; panel.forceActiveFocus(); return }
            const info = rights(cur)[Words.RIGHTS[c]]
            if (!info) return
            const row = list.itemAtIndex(cur)
            const at = (cell || (row && row.cellAt(c)))
            const p = at ? at.mapToItem(win.contentItem, 0, at.height + 4) : Qt.point(win.width / 2, win.height / 2)
            menu.show(areas[cur].name, Words.RIGHTS[c], info, p.x, p.y)
        }
        function choose(value) {
            const info = rights(cur)[Words.RIGHTS[col]]
            if (info && info.choices.indexOf(value) >= 0 && info.value !== value)
                store.set(areas[cur].id, Words.RIGHTS[col], value)
            list.forceActiveFocus()
        }
        // A level replaces the user's own choices: with some, it asks first
        function level(id) {
            if (!store.now) return
            if (store.now.own > 0) { askLevel = id; question.forceActiveFocus() }
            else if (id !== store.now.level) store.setLevel(id)
        }

        IpcHandler {
            target: "claudeAccess"
            function refresh(): void { store.refresh() }
            // Opens on an area: Settings or a card could point here (`ipc call claudeAccess area mail`)
            function area(id: string): void { const i = win.areas.findIndex(a => a.id === id); if (i >= 0) win.pickRow(i) }
            // …and on its details (›): its own choices, the apps Claude sees without asking (`details screen`)
            function details(id: string): void { area(id); if (win.areas[win.cur] && win.areas[win.cur].id === id) win.open(win.cur, 3) }
        }

        Shortcut { sequences: ["Ctrl+Q", "Meta+Q"]; onActivated: Qt.quit() }
        Shortcut { sequences: ["Ctrl+1", "Meta+1"]; onActivated: win.level("strict") }
        Shortcut { sequences: ["Ctrl+2", "Meta+2"]; onActivated: win.level("normal") }
        Shortcut { sequences: ["Ctrl+3", "Meta+3"]; onActivated: win.level("open") }

        RowLayout {
            anchors.fill: parent
            spacing: 0
            AppPointer { c: win.look }

            ColumnLayout {
                id: page
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 28
                spacing: 18

                AppTitle { c: win.look; text: "Claude's access"; pixelSize: 20 }
                LevelBar {
                    Layout.fillWidth: true
                    c: win.look
                    level: store.now ? store.now.level : ""
                    own: store.now ? store.now.own : 0
                    onPicked: id => win.level(id)
                }
                Text {
                    visible: store.failed || !!(store.now && store.now.problem)
                    Layout.fillWidth: true
                    text: store.failed ? "Access can't be read: see `nightdrive mcp access` in a terminal."
                                       : store.now ? store.now.problem || "" : ""
                    wrapMode: Text.Wrap
                    color: c.danger
                    font { family: c.font; pixelSize: 12 }
                }

                Repeater {
                    model: store.warnings
                    Text {
                        required property string modelData
                        Layout.fillWidth: true
                        text: modelData
                        wrapMode: Text.Wrap
                        color: c.danger
                        font { family: c.font; pixelSize: 12 }
                    }
                }

                // The columns' names, over the cells
                Row {
                    Item { width: win.nameWidth + 12; height: 1 }
                    Repeater {
                        model: Words.RIGHTS
                        Text {
                            required property string modelData
                            width: win.cellWidth
                            text: Words.RIGHT_NAMES[modelData]
                            color: c.dim
                            font { family: c.font; pixelSize: 12; weight: Font.DemiBold }
                        }
                    }
                }
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    focus: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: win.areas
                    currentIndex: win.cur
                    delegate: AreaRow {
                        required property var modelData
                        area: modelData
                        c: win.look
                        nameWidth: win.nameWidth
                        cellWidth: win.cellWidth
                        selected: index === win.cur
                        active: list.activeFocus
                        col: win.col
                        onCellClicked: (c, cell) => { if (c < 0) win.pickRow(index); else win.open(index, c, cell) }
                    }

                    Keys.onPressed: e => {
                        const k = e.key
                        win.look.moved(e)
                        sheet.pressed(e)
                        if (e.accepted || e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) return
                        if (k === Qt.Key_Down || k === Qt.Key_J) win.pickRow(win.cur + 1)
                        else if (k === Qt.Key_Up || k === Qt.Key_K) win.pickRow(win.cur - 1)
                        else if (k === Qt.Key_Home) win.pickRow(0)
                        else if (k === Qt.Key_End) win.pickRow(win.areas.length - 1)
                        else if (k === Qt.Key_Right || k === Qt.Key_L) win.moveCol(1)
                        else if (k === Qt.Key_Left || k === Qt.Key_H) win.moveCol(-1)
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) win.open(win.cur, win.col)
                        else if (e.text === "i") win.open(win.cur, 3)
                        else if (k >= Qt.Key_1 && k <= Qt.Key_3 && win.col < 3) win.choose(["allow", "ask", "no"][k - Qt.Key_1])
                        else if (k === Qt.Key_Escape) Qt.quit()
                        else return
                        e.accepted = true
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: "A dot marks a choice of your own, apart from the level. More ›: an area's tools and its own choices.  ?  keys"
                    color: c.faint
                    font { family: c.font; pixelSize: 11 }
                }
            }
        }

        ChoiceMenu {
            id: menu
            c: win.look
            onChosen: value => win.choose(value)
            onClosed: list.forceActiveFocus()
        }
        AreaPanel {
            id: panel
            c: win.look
            access: store
            behind: page
            onAreaChanged: if (area === null) list.forceActiveFocus()
        }
        // Going to a level puts the user's own choices back to it: say so before it happens
        AppPanel {
            id: question
            c: win.look
            behind: page
            visible: win.askLevel !== ""
            cardWidth: 460
            onOutsideTapped: { win.askLevel = ""; list.forceActiveFocus() }
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { store.setLevel(win.askLevel); win.askLevel = "" }
                else if (e.key === Qt.Key_Escape) win.askLevel = ""
                else return
                e.accepted = true
                list.forceActiveFocus()
            }
            Text {
                width: parent.width
                text: "Use " + ((Words.LEVELS.find(l => l.id === win.askLevel) || {}).name || "") + "?"
                color: c.title
                font { family: c.font; pixelSize: 15; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                readonly property int own: store.now ? store.now.own : 0
                text: own === 1 ? "Your own choice goes back to the level's."
                                : "Your " + own + " own choices go back to the level's."
                wrapMode: Text.Wrap
                color: c.text
                font { family: c.font; pixelSize: 13 }
            }
            Row {
                spacing: 16
                AppKeyAction { c: win.look; keys: "⏎"; label: "Use it"; onClicked: { store.setLevel(win.askLevel); win.askLevel = ""; list.forceActiveFocus() } }
                AppKeyAction { c: win.look; keys: "Esc"; label: "Keep mine"; onClicked: { win.askLevel = ""; list.forceActiveFocus() } }
            }
        }

        KeySheet { id: sheet; c: win.look; groups: keyHelp.groups }
    }
}
