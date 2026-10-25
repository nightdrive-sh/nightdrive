import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// A rough prototype (task #1528, branch vm): qemu/KVM VMs in a window. The VMs in the sidebar, the picked one's page
// beside it; bin/vm-ctl does the work.
ShellRoot {
    FloatingWindow {
        id: win
        title: "VM"
        implicitWidth: 880
        implicitHeight: 600
        color: c.bg
        onClosed: Qt.quit()

        AppLook { id: c }
        VmCtl { id: ctl }
        readonly property QtObject look: c

        property string picked: ""
        readonly property int index: Math.max(0, ctl.vms.findIndex(v => v.name === picked))
        readonly property var vm: ctl.vms.length ? ctl.vms[index] : null
        property bool showNew: false

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

        // The name panel's question and what to do with its answer (a snapshot's name, a delete's confirmation)
        property string askTitle: ""
        property var askDone: null
        function ask(title, initial, done) { askTitle = title; askDone = done; askField.text = initial; askField.input.forceActiveFocus(); askField.input.selectAll() }
        function answer(ok) { const d = askDone; askTitle = ""; askDone = null; if (ok && d) d(askField.text.trim()); page.forceActiveFocus() }

        // The yes-or-no panel's question (deleting a snapshot) and what to do on yes
        property var confirmDone: null
        function confirm(question, detail, done) { confirmPanel.question = question; confirmPanel.detail = detail; confirmDone = done }
        function confirmed(ok) { const d = confirmDone; confirmDone = null; if (ok && d) d(); page.forceActiveFocus() }

        IpcHandler {
            target: "vm"
            function newVm(): void { win.showNew = true }
            function pick(name: string): void { win.picked = name }
        }

        Shortcut { sequences: ["Ctrl+N", "Meta+N"]; onActivated: win.showNew = true }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.toggleSidebar() }

        RowLayout {
            anchors.fill: parent
            spacing: 0
            VmSidebar {
                visible: win.sidebarShown
                Layout.preferredWidth: win.onePane ? -1 : 200
                Layout.fillWidth: win.onePane
                c: win.look
                ctl: ctl
                current: win.vm ? win.vm.name : ""
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
                onAskName: (title, initial, done) => win.ask(title, initial, done)
                onAskConfirm: (question, detail, done) => win.confirm(question, detail, done)

                EmptyState {
                    visible: ctl.loaded && ctl.vms.length === 0
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 48, 420)
                    c: win.look
                    onNewVm: win.showNew = true
                }

                Keys.onPressed: e => {
                    const v = win.vm, n = ctl.vms.length
                    if (e.key === Qt.Key_Down && n) win.picked = ctl.vms[(win.index + 1) % n].name
                    else if (e.key === Qt.Key_Up && n) win.picked = ctl.vms[(win.index + n - 1) % n].name
                    else if (win.onePane && win.listOpen && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) win.listOpen = false
                    else if (win.onePane && !win.listOpen && e.key === Qt.Key_Escape && n) win.listOpen = true
                    else if (!v) return
                    else if (e.text === "s") page.start()
                    else if (e.text === "d") page.display()
                    else if (e.text === "x") page.shutDown()
                    else if (e.text === "X") page.forceOff()
                    else if (e.key === Qt.Key_Delete && page.snap >= 0) page.deleteSnap(page.snap)
                    else return
                    e.accepted = true
                }
            }
        }

        NewVmPanel {
            visible: win.showNew
            c: win.look
            ctl: ctl
            onDone: { win.showNew = false; page.forceActiveFocus() }
        }

        AppPanel {
            visible: win.askTitle !== ""
            c: win.look
            cardWidth: 440
            onOutsideTapped: win.answer(false)
            Field {
                id: askField
                c: win.look
                width: parent.width
                label: win.askTitle
                onAccepted: win.answer(true)
                input.Keys.onEscapePressed: win.answer(false)
            }
        }

        ConfirmPanel {
            id: confirmPanel
            visible: win.confirmDone !== null
            c: win.look
            onAnswered: ok => win.confirmed(ok)
        }
    }
}
