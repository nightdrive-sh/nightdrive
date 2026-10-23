import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Nightdrive Contacts: the accounts and groups, the contact list and the open card, over the vCards the sync keeps in
// ~/.local/share/contacts (lib/cards.py reads them).
ShellRoot {
    id: shell
    FloatingWindow {
        id: win
        title: "Contacts"
        implicitWidth: 1200
        implicitHeight: 820
        color: c.bg
        // Closing the window (⌘W) quits Contacts, as Mail: a process left without its window would only look open
        onClosed: Qt.quit()

        AppLook { id: c }
        readonly property QtObject look: c

        // `contacts sync` asks for a reload once it has fetched; `contacts settings` has nothing to open yet
        IpcHandler {
            target: "contacts"
            function refresh(): void { win.load() }
            function openSettings(): void {}
            // All contacts, searched (`contacts search TEXT`; the launcher's later)
            function search(text: string): void { win.source = 0; searchField.text = text; win.filter(""); list.forceActiveFocus() }
        }

        readonly property int headerHeight: 22  // the sidebar's title line and the list's search line, as Mail's
        readonly property int headerGap: 30     // from them to the first row
        readonly property int arrowStep: 80     // px an arrow key scrolls the card
        readonly property string helper: Quickshell.shellDir + "/../lib/cards.py"
        readonly property string command: Quickshell.shellDir + "/../bin/contacts"

        property var accounts: []           // [{ id, name, count }]
        property var groups: []             // [{ id, account, name, members: [uid] }]
        property var everyone: []           // every account's cards, by name (cards.py list)
        property var people: []             // the same with one person's cards in several accounts as one (All contacts)
        property bool loaded: false
        // The sidebar's rows: All, each account (with more than one), then the groups
        readonly property var sources: {
            const rows = [{ kind: "all", name: "All contacts", glyph: "users", count: people.length }]
            if (accounts.length > 1)
                for (const a of accounts) rows.push({ kind: "account", id: a.id, name: a.name, glyph: "cloud", count: a.count })
            for (const g of groups) rows.push({ kind: "group", id: g.id, name: g.name, glyph: "tag", members: g.members, account: g.account, count: g.members.length })
            return rows
        }
        property int source: 0
        property var shown: []              // the contacts of the source, narrowed by the search
        property int current: -1
        readonly property var contact: shown[current] || null

        function load() {
            loader.running = true
        }
        Process {
            id: loader
            command: ["python3", win.helper, "list"]
            stdout: StdioCollector {
                onStreamFinished: {
                    let d
                    try { d = JSON.parse(text) } catch (e) { console.warn("cards.py list: " + e); return }
                    const keep = win.contact ? win.contact.id : ""
                    win.accounts = d.accounts
                    win.groups = d.groups
                    const add = x => Object.assign(x, { letter: win.letter(x.name), haystack: win.haystack(x) })
                    win.everyone = d.contacts.map(add)
                    win.people = d.people.map(add)
                    win.loaded = true
                    win.source = Math.min(win.source, win.sources.length - 1)
                    win.filter(keep)
                }
            }
        }
        Component.onCompleted: { load(); list.forceActiveFocus() }

        // The list's section letter: A–Z, Å Ä Ö, and # for the rest
        function letter(name) {
            const ch = (name || "").charAt(0).toUpperCase()
            return /[A-ZÅÄÖÜ]/.test(ch) ? ch : "#"
        }
        // What the search looks in: names, company, addresses, and the numbers without their spaces
        function haystack(x) {
            return [x.name, x.nickname, x.org, x.title].concat(x.emails.map(e => e.value))
                .concat(x.phones.map(p => p.value.replace(/[\s\-()]/g, ""))).join("\n").toLowerCase()
        }

        // A number is looked for without its spaces and leading 0, so 040 123 finds +358 40 123 too
        function needle(w) { return /^\+?[\d\-]+$/.test(w) ? w.replace(/-/g, "").replace(/^0+/, "") : w }
        // keep: the contact to stay on (by id), when it is still there
        function filter(keep) {
            const s = sources[source] || sources[0]
            let list = s.kind === "all" ? people : everyone
            if (s.kind === "account") list = list.filter(x => x.account === s.id)
            else if (s.kind === "group") list = list.filter(x => x.account === s.account && s.members.indexOf(x.uid) >= 0)
            const words = searchField.text.trim().toLowerCase().split(/\s+/).filter(w => w !== "")
            if (words.length)
                list = list.filter(x => words.every(w => x.haystack.indexOf(win.needle(w)) >= 0))
            shown = list
            const i = keep ? list.findIndex(x => x.id === keep || (x.ids || []).indexOf(keep) >= 0) : -1
            current = i >= 0 ? i : list.length ? 0 : -1
            list.length && listView.positionViewAtIndex(current, ListView.Contain)
        }
        function pickSource(i) {
            if (i < 0 || i >= sources.length) return
            source = i; searchField.text = ""; filter(""); list.forceActiveFocus()
        }
        function move(d) {
            if (!shown.length) return
            current = Math.max(0, Math.min(shown.length - 1, current + d))
            listView.positionViewAtIndex(current, ListView.Contain)
            card.contentY = 0
        }
        function scrollCard(dy) {
            card.cancelFlick()
            card.contentY = Math.max(0, Math.min(card.contentHeight - card.height, card.contentY + dy))
        }

        // A line of the card's buttons, under the pointer: an address can be written to or copied, a link opened or
        // copied, the rest copied. A click on the line does the first.
        Process { id: copier }
        function lineActions(kind) {
            const copy = { id: "copy", glyph: "copy", tip: "Copy" }
            if (kind === "email") return [{ id: "write", glyph: "send", tip: "Write an email" }, copy]
            if (kind === "url") return [{ id: "open", glyph: "external-link", tip: "Open" }, copy]
            return kind === "birthday" ? [] : [copy]
        }
        function use(action, value) {
            if (action === "write") Qt.openUrlExternally("mailto:" + value)
            else if (action === "open") Qt.openUrlExternally(/^\w+:/.test(value) ? value : "https://" + value)
            else if (action === "copy") { copier.command = ["wl-copy", value]; copier.running = true; say("Copied: " + value.replace(/\n/g, ", ")) }
        }
        function when(b) {
            // YYYY-MM-DD or --MM-DD (no year)
            const m = b.match(/^(\d{4}|-)-(\d{2})-(\d{2})$/) || b.match(/^--(\d{2})-(\d{2})$/)
            if (!m) return b
            const year = m.length === 4 ? m[1] : "", mo = parseInt(m.length === 4 ? m[2] : m[1]), d = parseInt(m.length === 4 ? m[3] : m[2])
            const date = Qt.formatDate(new Date(2000, mo - 1, d), "d MMMM")
            return year && year !== "-" ? date + " " + year : date
        }

        // A quiet line under the list for what just happened
        property string note: ""
        function say(t) { note = t; noteTimer.restart() }
        Timer { id: noteTimer; interval: 4000; onTriggered: win.note = "" }

        // Without an account yet, Contacts offers to set one up (setupPanel), and looks again now and then, so the
        // contacts show once the setup's first sync has fetched them
        readonly property bool needsAccount: loaded && accounts.length === 0
        onNeedsAccountChanged: if (needsAccount) setupPanel.forceActiveFocus(); else list.forceActiveFocus()
        Timer { interval: 15000; running: win.needsAccount; repeat: true; onTriggered: win.load() }
        property bool setupStarted: false
        Process { id: setupRun; command: [win.command, "setup"] }
        function startSetup() { setupStarted = true; setupRun.running = true }

        Shortcut { sequences: ["/", "Ctrl+F"]; onActivated: searchField.forceActiveFocus() }
        Shortcut { sequence: "Ctrl+R"; onActivated: win.load() }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.sidebarChoice = !win.sidebarShown }

        // Narrow windows: the sidebar hides below sidebarMin (⌘B shows it all the same), and below twoPanes the list and
        // the card take turns: Enter or a click opens the card, Esc or ← goes back to the list
        readonly property int sidebarMin: 820
        readonly property int twoPanes: 640
        property var sidebarChoice: null    // ⌘B's, over what the width says
        readonly property bool sidebarShown: sidebarChoice !== null ? sidebarChoice : width >= sidebarMin
        readonly property bool onePane: width < twoPanes
        property bool cardOpen: false       // in one pane: the card shows instead of the list
        function openCard() { if (onePane && contact) { cardOpen = true; card.contentY = 0; card.forceActiveFocus() } }
        function closeCard() { cardOpen = false; list.forceActiveFocus() }
        onOnePaneChanged: if (!onePane && cardOpen) closeCard()

        RowLayout {
            anchors.fill: parent
            Keys.onPressed: e => sheet.pressed(e)
            spacing: 0

            AppSidebar {
                Layout.preferredWidth: win.width < 900 ? 168 : 208
                visible: win.sidebarShown
                c: win.look
                title: "Contacts"
                headerHeight: 2 * 18 + win.headerHeight
                contentTop: 18 + win.headerHeight + win.headerGap
                bottomMargin: 24
                Repeater {
                    model: win.sources
                    delegate: AppNavRow {
                        required property var modelData
                        required property int index
                        // A line between the accounts and the groups
                        Layout.topMargin: modelData.kind === "group" && (index === 0 || win.sources[index - 1].kind !== "group") ? 14 : 0
                        c: win.look
                        glyph: modelData.glyph
                        label: modelData.name
                        count: modelData.count
                        selected: index === win.source
                        onClicked: win.pickSource(index)
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // The list (the whole window's width in one pane)
            Rectangle {
                Layout.preferredWidth: Math.max(250, Math.min(340, win.width * 0.3 - 30))
                Layout.fillWidth: win.onePane
                Layout.fillHeight: true
                visible: !(win.onePane && win.cardOpen)
                color: "transparent"
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    AppSearchField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.margins: 28
                        Layout.topMargin: 16
                        Layout.preferredHeight: win.headerHeight
                        Layout.bottomMargin: 0
                        c: win.look
                        pixelSize: 13
                        placeholder: "Search names, numbers, addresses"
                        onEdited: win.filter(win.contact ? win.contact.id : "")
                        onEscapePressed: { text = ""; win.filter(win.contact ? win.contact.id : ""); list.forceActiveFocus() }
                        onReturnPressed: list.forceActiveFocus()
                        onDownPressed: list.forceActiveFocus()
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 17
                        Layout.preferredHeight: 1
                        color: c.divider
                    }
                    FocusScope {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Keys.onPressed: e => {
                            const k = e.key
                            if (win.cheats && k !== Qt.Key_Question && sheet.modifierKeys.indexOf(k) < 0) win.cheats = false
                            const ctrl = e.modifiers & Qt.ControlModifier
                            if (ctrl && k === Qt.Key_Down) win.pickSource(win.source + 1)
                            else if (ctrl && k === Qt.Key_Up) win.pickSource(win.source - 1)
                            else if (k === Qt.Key_Down || k === Qt.Key_J) win.move(1)
                            else if (k === Qt.Key_Up || k === Qt.Key_K) win.move(-1)
                            else if (k === Qt.Key_PageDown) win.move(10)
                            else if (k === Qt.Key_PageUp) win.move(-10)
                            else if (k === Qt.Key_Home) win.move(-win.shown.length)
                            else if (k === Qt.Key_End) win.move(win.shown.length)
                            else if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right) && win.onePane) win.openCard()
                            else if (k === Qt.Key_Space) win.scrollCard((e.modifiers & Qt.ShiftModifier ? -1 : 1) * (card.height - 80))
                            else if (k === Qt.Key_Escape && searchField.text !== "") { searchField.text = ""; win.filter(win.contact ? win.contact.id : "") }
                            else if (k === Qt.Key_Question) win.cheats = !win.cheats
                            else if (k >= Qt.Key_1 && k <= Qt.Key_9 && !ctrl) win.pickSource(k - Qt.Key_1)
                            else return
                            e.accepted = true
                        }
                        focus: true
                        ListView {
                            id: listView
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            clip: true
                            model: win.shown
                            currentIndex: win.current
                            boundsBehavior: Flickable.StopAtBounds
                            highlightMoveDuration: 0
                            TouchScroll { view: listView }
                            spacing: 2
                            topMargin: 4
                            bottomMargin: 12
                            section.property: "letter"
                            section.delegate: Text {
                                required property string section
                                leftPadding: 16; topPadding: 10; bottomPadding: 4
                                text: section; color: c.faint; font.family: c.font; font.pixelSize: 11; font.weight: Font.Medium
                            }
                            delegate: AppRow {
                                id: row
                                required property var modelData
                                required property int index
                                implicitHeight: 48
                                c: win.look
                                selected: index === win.current
                                TapHandler { onTapped: { win.current = row.index; card.contentY = 0; list.forceActiveFocus(); win.openCard() } }
                                Avatar {
                                    id: face
                                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                    c: win.look; size: 30; person: row.modelData
                                }
                                Column {
                                    anchors.left: face.right; anchors.leftMargin: 12
                                    anchors.right: parent.right; anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: row.modelData.name
                                        font.family: c.font; font.pixelSize: 13; color: c.title
                                    }
                                    Text {
                                        visible: text !== ""
                                        width: parent.width; elide: Text.ElideRight
                                        text: row.modelData.org
                                        font.family: c.font; font.pixelSize: 11; color: c.faint
                                    }
                                }
                            }
                            Text {
                                visible: win.loaded && win.shown.length === 0 && !win.needsAccount
                                anchors.centerIn: parent
                                text: searchField.text ? "No one found" : "No contacts here"
                                color: c.faint; font.family: c.font; font.pixelSize: 12
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.margins: 28
                        Layout.topMargin: 8
                        visible: win.note !== ""
                        elide: Text.ElideRight
                        text: win.note; color: c.dim; font.family: c.font; font.pixelSize: 11
                    }
                }
                Rectangle { visible: !win.onePane; anchors.right: parent.right; width: 1; height: parent.height; color: c.divider }
            }

            // The open card. Narrow, its picture goes above the name and each line's label above its value
            Flickable {
                id: card
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !win.onePane || win.cardOpen
                clip: true
                contentHeight: body.y + body.implicitHeight + 64
                readonly property int margin: width < 520 ? 24 : 40
                readonly property bool narrow: body.width < 420
                // Its keys in one pane, where the list is away: back, and scrolling
                Keys.onPressed: e => {
                    const k = e.key
                    sheet.pressed(e)
                    if (k === Qt.Key_Question) {}
                    else if (k === Qt.Key_Escape || k === Qt.Key_Left || k === Qt.Key_Backspace) win.closeCard()
                    else if (k === Qt.Key_J) { win.move(1); card.contentY = 0 }
                    else if (k === Qt.Key_K) { win.move(-1); card.contentY = 0 }
                    else if (k === Qt.Key_PageDown || k === Qt.Key_PageUp) win.scrollCard((k === Qt.Key_PageUp ? -1 : 1) * (card.height - 80))
                    else if (k === Qt.Key_Down) win.scrollCard(win.arrowStep)
                    else if (k === Qt.Key_Up) win.scrollCard(-win.arrowStep)
                    else if (k === Qt.Key_Space) win.scrollCard((e.modifiers & Qt.ShiftModifier ? -1 : 1) * (card.height - 80))
                    else return
                    e.accepted = true
                }
                // A finger's size, as the only way back for the mouse
                AppIconButton {
                    visible: win.onePane
                    x: 10; y: 10; z: 1
                    implicitWidth: 40; implicitHeight: 40; radius: 8
                    c: win.look
                    glyph: "arrow-left"; glyphSize: 17
                    tip: "All of them"; keys: "Esc"
                    onClicked: win.closeCard()
                }
                boundsBehavior: Flickable.StopAtBounds
                TouchScroll { view: card }
                readonly property var p: win.contact
                Column {
                    id: body
                    visible: card.p !== null
                    x: Math.max(card.margin, (card.width - width) / 2)
                    y: win.onePane ? 64 : 56
                    width: Math.min(560, card.width - 2 * card.margin)
                    spacing: 28
                    Grid {
                        columns: card.narrow ? 1 : 2
                        spacing: card.narrow ? 16 : 22
                        verticalItemAlignment: Grid.AlignVCenter
                        Avatar { c: win.look; size: card.narrow ? 72 : 84; person: card.p || {}; pixelSize: card.narrow ? 24 : 28 }
                        Column {
                            width: card.narrow ? body.width : body.width - 84 - 22
                            spacing: 6
                            Text {
                                width: parent.width; wrapMode: Text.Wrap
                                text: card.p ? card.p.name : ""
                                color: c.title; font.family: c.font; font.pixelSize: 22; font.weight: Font.Medium
                            }
                            Text {
                                visible: text !== ""
                                width: parent.width; wrapMode: Text.Wrap
                                text: card.p ? [card.p.title, card.p.org].filter(x => x).join(" · ") : ""
                                color: c.dim; font.family: c.font; font.pixelSize: 13
                            }
                            Text {
                                visible: text !== ""
                                text: card.p && card.p.nickname ? "“" + card.p.nickname + "”" : ""
                                color: c.faint; font.family: c.font; font.pixelSize: 12
                            }
                            // Where the card is from, with more than one account: one person's cards in several show as one
                            Text {
                                visible: win.accounts.length > 1 && card.p !== null
                                text: !card.p ? "" : (card.p.accounts || [card.p.account])
                                    .map(a => (win.accounts.find(x => x.id === a) || { name: a }).name).join(" · ")
                                color: c.faint; font.family: c.font; font.pixelSize: 11
                            }
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: c.divider }
                    // One line each: phones, emails, addresses, links, the birthday; the note under them
                    Column {
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: card.p ? card.p.phones.map(x => ({ kind: "phone", glyph: "phone", label: x.label || "phone", value: x.value }))
                                .concat(card.p.emails.map(x => ({ kind: "email", glyph: "mail", label: x.label || "email", value: x.value })))
                                .concat(card.p.addresses.map(x => ({ kind: "address", glyph: "map-pin", label: x.label || "address", value: x.lines.join("\n") })))
                                .concat(card.p.urls.map(x => ({ kind: "url", glyph: "link", label: x.label || "web", value: x.value })))
                                .concat(card.p.birthday ? [{ kind: "birthday", glyph: "cake", label: "birthday", value: win.when(card.p.birthday) }] : [])
                                : []
                            delegate: Rectangle {
                                id: field
                                required property var modelData
                                width: parent.width
                                implicitHeight: card.narrow ? valueText.y + valueText.implicitHeight + 12 : Math.max(40, valueText.implicitHeight + 20)
                                radius: 8
                                color: fh.hovered ? c.hover : "transparent"
                                HoverHandler { id: fh; cursorShape: Qt.PointingHandCursor }
                                readonly property var actions: win.lineActions(modelData.kind)
                                // A click on one of its buttons is the button's alone
                                TapHandler { onTapped: if (field.actions.length && !buttons.hovered) win.use(field.actions[0].id, field.modelData.value) }
                                Text {
                                    id: glyph
                                    x: 12; y: 12
                                    text: Icons.g(field.modelData.glyph); font.family: Icons.family; font.pixelSize: 15; color: c.dim
                                }
                                Text {
                                    id: labelText
                                    x: 44; y: 12; width: card.narrow ? parent.width - x - 12 : 96
                                    elide: Text.ElideRight
                                    text: field.modelData.label; color: c.faint; font.family: c.font; font.pixelSize: 12
                                }
                                Text {
                                    id: valueText
                                    x: card.narrow ? 44 : 148; y: card.narrow ? 32 : 11
                                    width: parent.width - x - 64        // room for its buttons
                                    wrapMode: Text.Wrap; lineHeight: 1.2
                                    text: field.modelData.value; color: c.text; font.family: c.font; font.pixelSize: 13
                                }
                                Row {
                                    id: buttons
                                    readonly property bool hovered: bh.hovered
                                    visible: fh.hovered
                                    anchors.right: parent.right; anchors.rightMargin: 7; y: 7
                                    spacing: 2
                                    HoverHandler { id: bh }
                                    Repeater {
                                        model: field.actions
                                        delegate: AppIconButton {
                                            required property var modelData
                                            c: win.look
                                            glyph: modelData.glyph; glyphColor: c.faint; hoverColor: c.sel
                                            tip: modelData.tip
                                            onClicked: win.use(modelData.id, field.modelData.value)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        visible: card.p !== null && card.p.note !== ""
                        width: parent.width
                        leftPadding: 12; rightPadding: 12
                        wrapMode: Text.Wrap; lineHeight: 1.25
                        text: card.p ? card.p.note : ""
                        color: c.dim; font.family: c.font; font.pixelSize: 12
                    }
                }
                Text {
                    visible: win.loaded && card.p === null && !win.needsAccount
                    anchors.centerIn: parent
                    text: "No contact open"
                    color: c.faint; font.family: c.font; font.pixelSize: 12
                }
            }
        }

        // What just happened (Copied: …), where the list's line for it is away: under the card, in one pane
        Text {
            visible: win.note !== "" && win.onePane && win.cardOpen
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 24
            elide: Text.ElideRight
            text: win.note; color: c.dim; font.family: c.font; font.pixelSize: 11
        }

        // Contacts' first start, before an account: Enter (or the button) opens Claude Code in a terminal, which sets
        // one up with you by README.md (`contacts setup`)
        AppPanel {
            id: setupPanel
            visible: win.needsAccount
            c: win.look
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.startSetup()
                e.accepted = true
            }
            Text { text: "Set up your contacts"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
            Text {
                width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2; color: c.text; font.family: c.font; font.pixelSize: 12
                text: win.setupStarted
                    ? "Claude opens in a terminal and goes through it with you. When it's done, your contacts show here."
                    : "Contacts keeps your iCloud or Google contacts on this computer, fetched from the account. Claude can set it up with you in a terminal, a step at a time. Your password goes only into the login keyring, never to Claude."
            }
            AppKeyAction {
                c: win.look
                keys: "⏎"; label: win.setupStarted ? "Open Claude again" : "Set up with Claude"; color: c.primary; hoverColor: c.title
                onClicked: win.startSetup()
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap; color: c.faint; font.family: c.font; font.pixelSize: 11
                text: "To do it yourself: launcher › System › Install › Plugins › Contacts has the steps."
            }
        }

        property alias cheats: sheet.shown
        KeySheet {
            id: sheet
            c: win.look
            groups: [
                { title: "Contacts", keys: [["↑ ↓  j k", "Previous, next"], ["⏎  →", "Open the card (a narrow window)"], ["Esc  ←", "Back to the list (on the card: ↑ ↓ scroll, j k next)"], ["PgUp PgDn", "Ten up, down"], ["Space ⇧Space", "Scroll the card"],
                                           ["⌘F  /", "Search"], ["Esc", "Clear the search"]] },
                { title: "Window", keys: [["Ctrl ↑ ↓", "Previous, next in the sidebar"], ["1 – 9", "Go to a row of the sidebar"], ["⌘R", "Read the contacts again"], ["⌘B", "Hide or show the sidebar"],
                                         ["Click", "Copy a number, write to an address"]] }
            ]
        }
    }
}
