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
        implicitWidth: 1000
        implicitHeight: 640
        color: c.bg
        onClosed: Qt.quit()

        AppLook { id: c }
        VmCtl { id: ctl }
        readonly property QtObject look: c

        property string picked: ""
        readonly property int index: Math.max(0, ctl.vms.findIndex(v => v.name === picked))
        readonly property var vm: ctl.vms.length ? ctl.vms[index] : null
        property bool showNew: false

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

        RowLayout {
            anchors.fill: parent
            spacing: 0
            AppSidebar {
                Layout.preferredWidth: 200
                c: win.look
                title: "VM"
                Repeater {
                    model: ctl.vms
                    delegate: AppNavRow {
                        required property var modelData
                        c: win.look
                        glyph: "server"
                        label: modelData.name
                        count: modelData.running ? "●" : ""
                        countColor: win.look.primary
                        selected: win.vm && win.vm.name === modelData.name
                        onClicked: win.picked = modelData.name
                    }
                }
                Item { Layout.fillHeight: true }
                AppNavRow { c: win.look; glyph: "plus"; label: "New VM"; onClicked: win.showNew = true }
            }
            VmPage {
                id: page
                Layout.fillWidth: true
                Layout.fillHeight: true
                c: win.look
                ctl: ctl
                vm: win.vm
                focus: true
                onAskName: (title, initial, done) => win.ask(title, initial, done)
                onAskConfirm: (question, detail, done) => win.confirm(question, detail, done)
                Keys.onPressed: e => {
                    const v = win.vm, n = ctl.vms.length
                    if (e.key === Qt.Key_Down && n) win.picked = ctl.vms[(win.index + 1) % n].name
                    else if (e.key === Qt.Key_Up && n) win.picked = ctl.vms[(win.index + n - 1) % n].name
                    else if (!v) return
                    else if (e.text === "s" && !v.running) ctl.run(["start", v.name])
                    else if (e.text === "d" && v.running) ctl.run(["display", v.name])
                    else if (e.text === "x" && v.running) ctl.run(["stop", v.name])
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
