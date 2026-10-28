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

        // `contacts sync` asks for a reload once it has fetched
        IpcHandler {
            target: "contacts"
            function refresh(): void { win.load() }
            // Settings › Apps › Contacts (`contacts settings`)
            function openSettings(): void { win.showSettings = true }
            // All contacts, searched (`contacts search TEXT`)
            function create(): void { win.newContact() }
            // A new contact with a name and an address in it (`contacts new NAME EMAIL`: Mail's Add to contacts)
            function createWith(name: string, email: string): void { if (win.loaded) win.newContact(name, email); else win.newNext = { name: name, email: email } }
            function edit(): void { win.edit() }
            function search(text: string): void { win.source = 0; searchField.text = text; win.filter(""); list.forceActiveFocus() }
            // One person's card (`contacts show WHO`: the launcher's Open in Contacts, Mail's sender), once the list is read
            function card(who: string): void { if (win.loaded) win.showWho(who); else win.showNext = who }
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
                    const keep = win.keepNext || (win.contact ? win.contact.id : "")
                    win.keepNext = ""
                    win.accounts = d.accounts
                    win.groups = d.groups
                    const add = x => Object.assign(x, { letter: win.letter(x.name), haystack: win.haystack(x) })
                    win.everyone = d.contacts.map(add)
                    win.people = d.people.map(add)
                    win.loaded = true
                    win.source = Math.min(win.source, win.sources.length - 1)
                    win.filter(keep)
                    if (win.showNext) { win.showWho(win.showNext); win.showNext = "" }
                    if (win.newNext) { win.newContact(win.newNext.name, win.newNext.email); win.newNext = null }
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
        // WHO: a card's id, an email address or a number (its last 9 digits, as cards.py's people() matches them)
        property string showNext: ""
        property var newNext: null          // createWith's, likewise
        function showWho(who) {
            const w = who.trim().toLowerCase(), digits = w.replace(/\D/g, "").slice(-9)
            const isNumber = /^\+?[\d\s\-()]+$/.test(w) && digits.length >= 5
            const p = people.find(x => (x.ids || [x.id]).indexOf(who) >= 0)
                || people.find(x => x.emails.some(e => e.value.toLowerCase() === w))
                || (isNumber ? people.find(x => x.phones.some(n => n.value.replace(/\D/g, "").slice(-9) === digits)) : null)
            if (editing) return
            showSettings = false
            source = 0; searchField.text = ""
            if (!p) { filter(""); say("Not in your contacts: " + who); list.forceActiveFocus(); return }
            filter(p.id)
            if (onePane) openCard(); else { card.contentY = 0; list.forceActiveFocus() }
        }
        // stay: picked from the keyboard in the sidebar (Panes.qml), which keeps it; a click goes back to the list
        function pickSource(i, stay) {
            if (i < 0 || i >= sources.length) return
            source = i; searchField.text = ""; filter("")
            if (!stay) panes.pane = "list"
            list.forceActiveFocus()
        }
        readonly property QtObject panes: Panes { win: win; list: list; card: card }
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
            if (kind === "email") return [{ id: "write", glyph: "send", tip: "New email" }, copy]
            if (kind === "url") return [{ id: "open", glyph: "external-link", tip: "Open" }, copy]
            return kind === "birthday" ? [] : [copy]
        }
        function use(action, value) {
            if (action === "write") Qt.openUrlExternally("mailto:" + value)
            else if (action === "open") Qt.openUrlExternally(/^\w+:/.test(value) ? value : "https://" + value)
            else if (action === "copy") { copier.command = ["wl-copy", value]; copier.running = true; say("Copied: " + value.replace(/\n/g, ", ")) }
        }
        // w and Send email: a new email in the email app (Settings › Apps › Default apps), straight to a single address,
        // else from the card's menu of them (opening the card first in one pane)
        function write() {
            if (!contact || !contact.emails.length) return
            if (contact.emails.length === 1) { use("write", contact.emails[0].value); return }
            if (onePane && !cardOpen) openCard()
            card.chooseEmail()
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
        // sticky: it stays until the next one (a sync, which tells when it's done)
        function say(t, sticky) { note = t; if (sticky) noteTimer.stop(); else noteTimer.restart() }
        Timer { id: noteTimer; interval: 4000; onTriggered: win.note = "" }

        // Without an account yet, Contacts offers to set one up (setupPanel), and looks again now and then, so the
        // contacts show once the setup's first sync has fetched them
        readonly property bool needsAccount: loaded && accounts.length === 0
        onNeedsAccountChanged: if (needsAccount) setupPanel.forceActiveFocus(); else list.forceActiveFocus()
        Timer { interval: 15000; running: win.needsAccount; repeat: true; onTriggered: win.load() }
        property bool setupStarted: false
        Process { id: setupRun; command: [win.command, "setup"] }
        function startSetup() { setupStarted = true; setupRun.running = true }

        // Editing (ContactEditor, saved by Store): ⌘E or e edits the open contact, ⌘N makes a new one, Delete deletes it
        property bool editing: false
        property string keepNext: ""        // the contact to open once the list is read again: the one just saved
        readonly property alias store: store
        readonly property alias confirm: confirm
        // The open contact's cards: one, or one per account for a person in All contacts
        function cardsOf(x) {
            if (!x) return []
            return (x.ids || [x.id]).map(i => everyone.find(y => y.id === i)).filter(y => y)
        }
        function edit() {
            const cards = cardsOf(contact)
            if (editing || !cards.length) return
            editing = true
            editor.openCards(cards)
        }
        // name, email: filled in already (`contacts new`)
        function newContact(name, email) {
            if (editing || !accounts.length) return
            // In the account (or its group) the sidebar is on, else the first one
            const s = sources[source] || {}
            showSettings = false
            editing = true
            editor.openNew(s.kind === "account" ? s.id : s.kind === "group" ? s.account : accounts[0].id, name || "", email || "")
        }
        function endEdit() {
            editing = false
            if (onePane && contact) openCard(); else list.forceActiveFocus()
        }
        function saved(id) { keepNext = id; load(); endEdit() }
        function failed(message) { editor.error = message }
        function askDelete() {
            const cards = cardsOf(contact)
            if (!cards.length) return
            const names = cards.map(x => store.accountName(x.account))
            confirm.ask("Delete " + contact.name + "?",
                        "From " + names.join(" and ") + ", and from the phones and computers that share " + (names.length > 1 ? "them." : "it."),
                        "Delete", () => {
                            // The list stays where it was: on the next one (or the one before, at the end)
                            const next = win.shown[win.current + 1] || win.shown[win.current - 1]
                            win.keepNext = next ? next.id : ""
                            win.editing = false
                            win.store.remove(cards.map(x => x.id))
                        })
        }
        Shortcut { sequences: ["Ctrl+N", "Meta+N"]; onActivated: win.newContact() }
        Shortcut { sequences: ["Ctrl+E", "Meta+E"]; onActivated: win.edit() }

        Shortcut { sequences: ["/", "Ctrl+F"]; onActivated: searchField.forceActiveFocus() }
        Shortcut { sequence: "Ctrl+R"; onActivated: win.load() }
        Shortcut { sequences: ["Ctrl+,", "Meta+,"]; onActivated: win.showSettings = !win.showSettings }
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
            id: content          // what a panel turns off while it shows (AppPanel.behind)
            anchors.fill: parent
            Keys.onPressed: e => sheet.pressed(e)
            AppPointer { c: win.look }      // the pointer hides the keys' frame
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
                        active: win.panes.at === "sources" && list.activeFocus     // Tab's (Panes.qml)
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
                visible: !(win.onePane && (win.cardOpen || win.editing))
                color: "transparent"
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    // The search, and the new contact's button at its end
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 28
                        Layout.rightMargin: 14
                        Layout.topMargin: 16
                        Layout.preferredHeight: win.headerHeight
                        spacing: 8
                        AppSearchField {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.preferredHeight: win.headerHeight
                            c: win.look
                            pixelSize: 13
                            placeholder: "Search names, numbers, addresses"
                            onEdited: win.filter(win.contact ? win.contact.id : "")
                            onEscapePressed: { text = ""; win.filter(win.contact ? win.contact.id : ""); list.forceActiveFocus() }
                            onReturnPressed: list.forceActiveFocus()
                            onDownPressed: list.forceActiveFocus()
                        }
                        AppIconButton {
                            visible: win.accounts.length > 0
                            c: win.look
                            glyph: "user-plus"; glyphColor: c.dim; hoverColor: c.sel
                            tip: "New contact"; keys: "⌘N"
                            onClicked: win.newContact()
                        }
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
                            win.look.moved(e)              // Tab and the arrows show the keys' frame (AppPointer)
                            if (win.cheats && k !== Qt.Key_Question && sheet.modifierKeys.indexOf(k) < 0) win.cheats = false
                            if (win.panes.pressed(e)) { e.accepted = true; return }
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
                            else if (k === Qt.Key_E && !ctrl) win.edit()
                            else if (k === Qt.Key_W && !ctrl) win.write()
                            else if (k === Qt.Key_Delete || k === Qt.Key_Backspace) win.askDelete()
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
                                active: list.activeFocus && win.panes.at === "list"     // the kit's frame while the keys are here
                                TapHandler { onTapped: { win.current = row.index; card.contentY = 0; win.panes.toList(); win.openCard() } }
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

            // The open card, or the editor in its place
            ContactCard {
                id: card
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: (!win.onePane || win.cardOpen) && !win.editing
                app: win
                c: win.look
                onEdit: win.edit()
            }
            ContactEditor {
                id: editor
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.editing
                app: win
                c: win.look
                onDone: win.endEdit()
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
            behind: content
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
                text: "To do it yourself: Launcher › System › Set up Nightdrive shows the steps one at a time."
            }
        }

        // Settings (⌘,): the accounts, Sync now, Add an account (SettingsPanel)
        property bool showSettings: false
        onShowSettingsChanged: if (showSettings) settings.open(); else if (settings.visible) settings.close()
        SettingsPanel {
            behind: content
            id: settings
            app: win
            c: win.look
            onClosed: { win.showSettings = false; if (win.editing) editor.forceActiveFocus(); else list.forceActiveFocus() }
        }

        Store { id: store; app: win }
        ConfirmPanel {
            behind: content
            id: confirm
            c: win.look
            onClosed: if (win.editing) editor.forceActiveFocus(); else list.forceActiveFocus()
        }

        property alias cheats: sheet.shown
        function sheetKey(e) { sheet.pressed(e) }      // for the card's keys (ContactCard)
        KeySheet {
            id: sheet
            c: win.look
            groups: [
                { title: "Contacts", keys: [["↑ ↓  j k", "Previous, next"], ["⏎  →", "Open the card (a narrow window)"], ["Esc  ←", "Back to the list (on the card: ↑ ↓ scroll, j k next)"], ["PgUp PgDn", "Ten up, down"], ["Space ⇧Space", "Scroll the card"], ["Tab ⇧Tab", "Sidebar, list, card"], ["↑ ↓", "On the card after Tab: a line"], ["⏎", "…write, open or copy"], ["c  ⌘C", "…copy it"],
                                           ["⌘F  /", "Search"], ["Esc", "Clear the search"]] },
                { title: "Editing", keys: [["⌘N", "New contact"], ["⌘E  e", "Edit the contact"], ["w", "Send email (a menu if they have more addresses)"], ["⌘S  ⌘⏎", "Save"], ["Esc", "Leave the editor"],
                                          ["Tab", "Next field"], ["Delete", "Delete the contact"]] },
                { title: "Window", keys: [["Ctrl ↑ ↓", "Previous, next in the sidebar"], ["1 – 9", "Go to a row of the sidebar"], ["⌘R", "Read the contacts again"], ["⌘,", "Settings: accounts, sync"], ["⌘B", "Hide or show the sidebar"],
                                         ["Click", "Copy a number, write to an address"]] }
            ]
        }
    }
}
