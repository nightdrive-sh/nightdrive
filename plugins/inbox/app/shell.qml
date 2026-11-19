import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Inbox, Nightdrive's window for the messages Claude's sessions and apps leave to look at later (#3132; kept and acted
// on by the core's `nightdrive inbox`, config/inbox): Inbox, Archive and who they are from (NavSidebar), the messages
// newest first (MessageList), and the open one with its text, buttons and pictures (MessageView). A run button asks
// first (RunPanel), a picture opens over the window (ImageViewer). This file holds the window together: the narrow
// window's turns, the IPC, the keys (their sheet: KeyHelp.qml) and what the bar's and the message's buttons do.
ShellRoot {
    FloatingWindow {
        id: win
        title: "Inbox"
        implicitWidth: 1100
        implicitHeight: 700
        color: c.bg
        onClosed: Qt.quit()

        AppLook { id: c }
        Store { id: store }
        Actions { id: actions; command: store.command }
        KeyHelp { id: keyHelp }
        readonly property QtObject look: c

        // Narrow windows, as Notes': below navMin the sidebar hides (f or the list's button shows it), and below
        // onePaneMax the list and the message take turns: Esc on the message shows the list, a click or Enter on a
        // message the message; there f shows the sidebar in the list's place. ⌘B shows and hides the sidebars.
        readonly property int navMin: 960
        readonly property int onePaneMax: 640
        readonly property bool onePane: width < onePaneMax
        property var sidebarChoice: null
        property var navChoice: null
        property bool listOpen: true                // in one pane: the list shows instead of the message
        property bool navOpen: false                // in one pane, with the list open: the sidebar instead of it
        readonly property bool sidebarShown: onePane ? listOpen && !navOpen : sidebarChoice !== null ? sidebarChoice : true
        readonly property bool navShown: onePane ? listOpen && navOpen
            : sidebarShown && (navChoice !== null ? navChoice : width >= navMin)
        onOnePaneChanged: { listOpen = true; navOpen = false }
        function toggleSidebar() { if (onePane) { listOpen = !listOpen; navOpen = false } else sidebarChoice = !sidebarShown }
        property bool navForKeys: false
        function toFolders() {
            if (nav.activeFocus) return fromFolders()
            navForKeys = !navShown
            if (onePane) { listOpen = true; navOpen = true }
            else if (navForKeys) { sidebarChoice = true; navChoice = true }
            nav.forceActiveFocus()
        }
        function fromFolders() {
            if (onePane) navOpen = false
            else if (navForKeys) navChoice = null
            navForKeys = false
            view.forceActiveFocus()
        }
        function pick(id) { store.picked = id; listOpen = false; navOpen = false; view.forceActiveFocus() }
        function find() {
            if (onePane) { listOpen = true; navOpen = false } else sidebarChoice = true
            list.field.forceActiveFocus()
        }
        function searchDone(clear) {
            if (clear) { list.field.text = ""; store.setSearch("") }
            view.forceActiveFocus()
        }
        function fromPicked(key, label) { if (key) { store.pickFrom(key, label); if (onePane) listOpen = true } }

        function failed(text) { toast.show(text, { danger: true }) }
        // Archive (e): out of the list, the next one shown; Undo (⌘Z) puts it back where it was
        function archive() {
            const m = store.message
            if (!m) return
            if (m.archived) actions.unarchive(m.id, () => { store.forget(m.id); toast.show("Back in the inbox: " + m.title) }, failed)
            else actions.archive(m.id, () => {
                store.forget(m.id)
                toast.show("Archived " + m.title, { action: "Undo", run: () =>
                    actions.unarchive(m.id, () => { store.picked = m.id; store.raw = ""; store.refresh() }, win.failed) })
            }, failed)
        }
        function toggleRead() {
            const m = store.message
            if (m) actions.read(m.id, !m.read, () => { store.message = null; store.raw = ""; store.refresh() }, failed)
        }
        function askDelete() { if (store.message) confirm.visible = true }
        function remove() {
            const m = store.message
            if (m) actions.remove(m.id, () => { store.forget(m.id); toast.show("Deleted " + m.title) }, failed)
        }
        // A button, or the sender's session or task; a run one only by way of its card (ask)
        function press(which, yes) {
            const m = store.message
            if (!m) return
            actions.press(m.id, which, !!yes, r => toast.show(
                r.copied ? "Copied " + r.copied + ": no task address set (docs/inbox.md)"
                : r.ran ? "Started " + r.label : r.session ? "Going to the session" : "Opened " + r.label), failed)
        }
        function ask(i) {
            const m = store.message
            const a = m && m.actions ? m.actions[i] : null
            if (!a) return
            if (a.kind !== "run") return press(String(i))
            runPanel.index = i
            runPanel.ask(a, m.sender.label, m.sender.kind === "other")
        }
        function firstImage() {
            const imgs = store.message ? (store.message.attachments || []).filter(f => (f.type || "").startsWith("image/")) : []
            if (imgs.length) viewer.show(imgs, 0)
        }

        IpcHandler {
            target: "inbox"
            function refresh(): void { store.raw = ""; store.refresh() }
            // `inbox show ID`: picked, from the inbox or the archive it is in
            function pick(id: string): void { store.follow(id, false); win.listOpen = false }
            function pickArchived(id: string): void { store.follow(id, true); win.listOpen = false }
        }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.toggleSidebar() }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
        Shortcut { sequences: ["Ctrl+F", "Meta+F"]; enabled: !runPanel.visible && !confirm.visible; onActivated: win.find() }
        Shortcut { sequences: ["Ctrl+Z", "Meta+Z"]; enabled: !list.field.activeFocus; onActivated: toast.act() }

        RowLayout {
            id: content
            anchors.fill: parent
            spacing: 0
            AppPointer { c: win.look }

            NavSidebar {
                id: nav
                visible: win.navShown
                Layout.preferredWidth: win.onePane ? -1 : win.width < 1200 ? 190 : 220
                Layout.fillWidth: win.onePane
                z: 1
                c: win.look
                store: store
                active: activeFocus
                onDone: win.fromFolders()
                onChosen: if (win.onePane) win.navOpen = false
            }
            MessageList {
                id: list
                visible: win.sidebarShown
                navShown: win.navShown
                onShowNav: win.toFolders()
                Layout.preferredWidth: win.onePane ? -1 : win.width < 1200 ? 300 : 360
                Layout.fillWidth: win.onePane
                c: win.look
                store: store
                onSearchDone: clear => win.searchDone(clear)
                active: view.activeFocus
                onPicked: id => win.pick(id)
            }
            // While the list shows in one pane the message is there at no width: it keeps the keyboard, so the arrows
            // still move between the messages, as in Notes
            MessageView {
                id: view
                Layout.preferredWidth: win.onePane && win.listOpen ? 0 : -1
                Layout.fillWidth: !(win.onePane && win.listOpen)
                Layout.fillHeight: true
                clip: true
                c: win.look
                store: store
                onePane: win.onePane
                focus: true
                onBack: win.listOpen = true
                onArchive: win.archive()
                onToggleRead: win.toggleRead()
                onRemove: win.askDelete()
                onPress: which => win.press(which)
                onAsk: i => win.ask(i)
                onViewImage: (images, i) => viewer.show(images, i)
                onFromPicked: (key, label) => win.fromPicked(key, label)
                Keys.onPressed: e => win.key(e)
            }
        }

        function key(e) {
            const k = e.key, shift = e.modifiers & Qt.ShiftModifier
            const enter = k === Qt.Key_Return || k === Qt.Key_Enter
            win.look.moved(e)                  // Tab and the arrows show the keys' frame (AppPointer)
            sheet.pressed(e)
            if (e.accepted) return
            if (k === Qt.Key_Down || k === Qt.Key_J) store.step(1)
            else if (k === Qt.Key_Up || k === Qt.Key_K) store.step(-1)
            else if (k === Qt.Key_Home) store.pickAt(0)
            else if (k === Qt.Key_End) store.pickAt(store.messages.length - 1)
            else if (e.text === "/") win.find()
            else if (e.text === "e") win.archive()
            else if (e.text === "u") win.toggleRead()
            else if (k === Qt.Key_Delete) win.askDelete()
            else if (e.text >= "1" && e.text <= "8") win.ask(+e.text - 1)
            else if (e.text === "s" && store.message && store.message.from.kind === "claude") win.press("session")
            else if (e.text === "t" && store.message && store.message.task) win.press("task")
            else if (e.text === "i") win.firstImage()
            else if (e.text === "f") win.toFolders()
            else if (k === Qt.Key_Space) view.scroll((shift ? -1 : 1) * (view.height - 120))
            else if (k === Qt.Key_PageDown) view.scroll(view.height - 120)
            else if (k === Qt.Key_PageUp) view.scroll(-(view.height - 120))
            else if (win.onePane && win.listOpen && enter && store.message) win.listOpen = false
            else if (win.onePane && !win.listOpen && k === Qt.Key_Escape) win.listOpen = true
            else if (k === Qt.Key_Escape && store.search) win.searchDone(true)
            else if (k === Qt.Key_Escape && store.from) store.pickView(store.view)
            else return
            e.accepted = true
        }

        AppConfirm {
            id: confirm
            visible: false
            behind: content
            c: win.look
            cardWidth: Math.min(440, win.width - 32)
            question: store.message ? "Delete “" + store.message.title + "”?" : ""
            detail: "It goes for good, with its files. Archive (e) keeps it out of the way instead."
            onAnswered: ok => { visible = false; if (ok) win.remove(); view.forceActiveFocus() }
        }
        RunPanel {
            id: runPanel
            property int index: -1
            visible: false
            behind: content
            c: win.look
            cardWidth: Math.min(560, win.width - 32)
            onAnswered: ok => { visible = false; if (ok) win.press(String(index), true); view.forceActiveFocus() }
        }
        ImageViewer { id: viewer; c: win.look; behind: content; onClosed: view.forceActiveFocus() }
        KeySheet { id: sheet; c: win.look; groups: keyHelp.groups }
        AppToast { id: toast; c: win.look }
    }
}
