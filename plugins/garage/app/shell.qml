import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Garage, Nightdrive's window of virtual machines: qemu/KVM VMs in the sidebar, the picked one's page beside it;
// bin/garage-ctl does the work. This file holds the window together: which VM shows, the narrow window's turns, the
// panels that ask, and the keys (their sheet: KeyHelp.qml).
ShellRoot {
    FloatingWindow {
        id: win
        title: "Garage"
        implicitWidth: 880
        implicitHeight: 600
        color: c.bg
        onClosed: Qt.quit()

        AppLook { id: c }
        VmCtl { id: ctl }
        Images { id: images; ctl: ctl; onMade: name => win.pick(name) }
        KeyHelp { id: keyHelp }
        readonly property QtObject look: c

        property string picked: ""
        readonly property int index: Math.max(0, ctl.vms.findIndex(v => v.name === picked))
        readonly property var vm: ctl.vms.length ? ctl.vms[index] : null
        property bool showNew: false
        property bool showSettings: false
        function step(d) { const n = ctl.vms.length; if (n) picked = ctl.vms[(index + d + n) % n].name }

        // Narrow windows: below onePaneMax the list and the page take turns, as in Deck: Esc on the page shows the list,
        // a click or Enter on a VM its page. ⌘B shows and hides the sidebar, in a wide window too.
        readonly property int onePaneMax: 640
        readonly property bool onePane: width < onePaneMax
        property var sidebarChoice: null            // ⌘B's, in a wide window
        property bool listOpen: false               // in one pane: the list shows instead of the page
        readonly property bool sidebarShown: onePane ? listOpen : sidebarChoice !== null ? sidebarChoice : true
        onOnePaneChanged: listOpen = false
        function toggleSidebar() { if (onePane) listOpen = !listOpen; else sidebarChoice = !sidebarShown }
        function pick(name) { picked = name; listOpen = false }

        // The yes-or-no panel's question (restoring or deleting a snapshot) and what to do on yes
        property var confirmDone: null
        function confirm(question, detail, action, glyph, done) {
            confirmPanel.question = question; confirmPanel.detail = detail
            confirmPanel.action = action; confirmPanel.glyph = glyph
            confirmDone = done
        }
        function confirmed(ok) { const d = confirmDone; confirmDone = null; if (ok && d) d(); page.refocus() }

        IpcHandler {
            target: "garage"
            function newVm(): void { win.showNew = true }
            function pick(name: string): void { win.picked = name }
        }

        Shortcut { sequences: ["Ctrl+N", "Meta+N"]; onActivated: win.showNew = true }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.toggleSidebar() }
        Shortcut { sequences: ["Ctrl+,", "Meta+,"]; onActivated: if (win.vm) win.showSettings = !win.showSettings }
        Shortcut { sequences: ["Ctrl+Backspace", "Meta+Backspace"]; onActivated: page.deleteKey() }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }

        RowLayout {
            anchors.fill: parent
            spacing: 0
            // ? and Ctrl+? show the keys, as in Mail and Deck: what the page and the snapshot list leave alone comes here
            Keys.onPressed: e => sheet.pressed(e)
            AppPointer { c: win.look }      // the pointer hides the keys' frame

            VmSidebar {
                visible: win.sidebarShown
                Layout.preferredWidth: win.onePane ? -1 : 200
                Layout.fillWidth: win.onePane
                c: win.look
                ctl: ctl
                images: images
                current: win.vm ? win.vm.name : ""
                active: page.activeFocus && !page.snapshotsFocused
                onPicked: name => win.pick(name)
                onNewVm: win.showNew = true
            }
            // While the list shows in one pane the page is there at no width: it keeps the keyboard, so the arrows still
            // move between the VMs, as in Deck
            VmPage {
                id: page
                Layout.preferredWidth: win.onePane && win.listOpen ? 0 : -1
                Layout.fillWidth: !(win.onePane && win.listOpen)
                Layout.fillHeight: true
                clip: true
                c: win.look
                ctl: ctl
                vm: win.vm
                onePane: win.onePane
                focus: true
                onBack: win.listOpen = true
                onSettings: win.showSettings = true
                onPicked: name => win.pick(name)
                bottomInset: note.visible ? note.height + 16 : 0
                onAskName: (title, initial, done) => namePanel.ask(title, initial, done)
                onAskConfirm: (question, detail, action, glyph, done) => win.confirm(question, detail, action, glyph, done)

                EmptyState {
                    visible: ctl.loaded && ctl.vms.length === 0
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 48, 420)
                    c: win.look
                    onNewVm: win.showNew = true
                }

                NoteLine {
                    id: note
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: 20
                    c: win.look
                    text: ctl.error
                    onDismissed: ctl.error = ""
                }

                // The page's keys (KeyHelp.qml lists them); the snapshot list takes its own first, while it has focus
                Keys.onPressed: e => {
                    const k = e.key, v = win.vm
                    win.look.moved(e)              // Tab and the arrows show the keys' frame (AppPointer)
                    if (sheet.shown) { sheet.shown = false; e.accepted = true; return }
                    if (k === Qt.Key_Down || k === Qt.Key_J) win.step(1)
                    else if (k === Qt.Key_Up || k === Qt.Key_K) win.step(-1)
                    else if (win.onePane && win.listOpen && (k === Qt.Key_Return || k === Qt.Key_Enter)) win.listOpen = false
                    else if (win.onePane && !win.listOpen && k === Qt.Key_Escape && ctl.vms.length) win.listOpen = true
                    else if (!v) return
                    else if (e.text === "s") page.start()
                    else if (e.text === "d") page.display()
                    else if (e.text === "x") page.shutDown()
                    else if (e.text === "X") page.forceOff()
                    else if (e.text === "t") page.takeSnapshot()
                    else if (k === Qt.Key_Tab) page.focusSnapshots()
                    else if (k === Qt.Key_F2) page.renameVm()
                    else return
                    e.accepted = true
                }
            }
        }

        NewVmPanel {
            visible: win.showNew
            c: win.look
            ctl: ctl
            images: images
            onDone: { win.showNew = false; page.forceActiveFocus() }
        }

        SettingsPanel {
            visible: win.showSettings && !!win.vm
            c: win.look
            ctl: ctl
            vm: win.vm
            stopped: page.stopped
            onDone: { win.showSettings = false; page.forceActiveFocus() }
            onDeleteVm: { win.showSettings = false; page.deleteVm() }
        }

        NamePanel {
            id: namePanel
            c: win.look
            onClosed: page.refocus()
        }

        ConfirmPanel {
            id: confirmPanel
            visible: win.confirmDone !== null
            c: win.look
            onAnswered: ok => win.confirmed(ok)
        }

        KeySheet { id: sheet; c: win.look; groups: keyHelp.groups }
    }
}
