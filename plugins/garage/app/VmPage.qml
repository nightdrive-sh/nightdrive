import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.kit

// One VM's page: a header level with the sidebar's title (its name and state), the buttons for what it can do now, what
// it has (memory, CPUs, disk, the ISO in its drive, `ssh NAME` to copy), and its snapshots (SnapshotList.qml). The
// questions it asks go to the window's panels (askName, askConfirm).
Item {
    id: root
    required property QtObject c
    required property QtObject ctl
    property var vm: null
    property bool onePane: false        // a narrow window: the header's arrow goes back to the list
    property int headerHeight: 62       // as AppSidebar's, so the name lines up with the app's
    property int bottomInset: 0         // room kept at the foot (shell.qml's error line)
    signal askName(string title, string initial, var done)
    signal askConfirm(string question, string detail, string action, string glyph, var done)
    signal back()
    signal picked(string name)          // renamed: the window follows it to its new name
    signal settings()

    // Its state (VmCtl.stateOf: garage-ctl's, or what the window has just asked of it). running: qemu is, booting and
    // shutting down too, so its display and Force off are there meanwhile
    readonly property string vmState: ctl.stateOf(vm)
    readonly property bool running: !!vm && vmState !== "stopped"
    readonly property bool stopping: vmState === "stopping"
    readonly property bool slow: stopping && !!vm.slow && !ctl.pending[vm.name]
    readonly property bool stopped: !!vm && vmState === "stopped"
    readonly property bool paused: vmState === "paused"

    // What the buttons and the keys do (shell.qml's s, d, p, x, ⇧X)
    function act(args) { root.ctl.run(args) }
    function start() { if (root.stopped) root.ctl.power("start", root.vm.name) }
    // d toggles: a window that shows goes out of sight with the VM running on (garage-ctl hide), else it comes forward
    readonly property bool shown: running && !!vm.shown
    function display() { if (root.running) root.act([root.shown ? "hide" : "display", root.vm.name]) }
    // p toggles: a paused VM's CPUs stand still (its memory stays taken) until it resumes; not while it shuts down
    function pauseResume() {
        if (root.paused) root.ctl.power("resume", root.vm.name)
        else if (root.running && !root.stopping) root.ctl.power("pause", root.vm.name)
    }
    function shutDown() { if (root.running && (!root.stopping || root.slow)) root.ctl.power("stop", root.vm.name) }
    function forceOff() { if (root.running) root.ctl.power("kill", root.vm.name) }
    function takeSnapshot() { snapshots.take() }
    function focusSnapshots() { snapshots.focusList() }
    readonly property bool snapshotsFocused: snapshots.focused
    // After a panel: the keys go back where they were, the snapshot list or the page
    function refocus() {
        if (snapshots.returnHere) { snapshots.returnHere = false; snapshots.focusList() } else root.forceActiveFocus()
    }
    // ⌘⌫: in the snapshot list the snapshot, as Del there; else the VM
    function deleteKey() { if (snapshots.focused) snapshots.removeCurrent(); else deleteVm() }
    // What changes the machine itself shows while it runs too: a click then says why it can't, at the page's foot
    function whenStopped(what) {
        if (!root.stopped) root.ctl.error = "Shut " + root.vm.name + " down first to " + what
        return root.stopped
    }
    // A new name, while it is stopped: its ssh name follows (garage-ctl rename-vm)
    function renameVm() {
        if (!root.whenStopped("rename it")) return
        const name = root.vm.name
        root.askName("Rename the machine", name, n => {
            if (n && n !== name) root.ctl.run(["rename-vm", name, n], () => root.picked(n))
        })
    }
    function deleteVm() {
        if (!root.whenStopped("delete it")) return
        const name = root.vm.name
        root.askName("Type " + name + " to delete it, its disk and its snapshots", "", n => { if (n === name) root.act(["delete", name]) })
    }

    ColumnLayout {
        visible: !!root.vm
        anchors.fill: parent
        spacing: 0

        // The header: the way back in one pane, the name, and its state on the right
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            Layout.leftMargin: 28
            Layout.rightMargin: 28
            spacing: 10
            AppIconButton {
                visible: root.onePane
                Layout.leftMargin: -16
                implicitWidth: 40; implicitHeight: 40; radius: 8
                c: root.c; glyph: "arrow-left"; glyphSize: 17; tip: "VMs"; keys: "Esc"
                onClicked: root.back()
            }
            Text {
                Layout.maximumWidth: implicitWidth
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.vm ? root.vm.name : ""
                color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.DemiBold
            }
            // Renaming, beside the name it changes
            AppIconButton {
                visible: !!root.vm
                implicitWidth: 30; implicitHeight: 30; radius: 6
                c: root.c; glyph: "pencil"; glyphSize: 13; tip: "Rename"; keys: "F2"
                onClicked: root.renameVm()
            }
            Item { Layout.fillWidth: true }
            StateLine { c: root.c; vmState: root.vm ? root.vmState : "stopped"; slow: root.slow }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.c.divider }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 28
            Layout.topMargin: 22
            Layout.bottomMargin: 28 + root.bottomInset
            spacing: 22

            // What it can do now: the likeliest first and strong. Over what follows, which would draw over their tips, and
            // the tips start at the buttons' left edge, as they sit at the page's left (the page clips)
            Flow {
                Layout.fillWidth: true
                z: 1
                spacing: 8
                AppButton {
                    c: root.c; glyph: "play"; label: "Start"; strong: true; keys: "s"; tip: "Start it in a window"; tipAlign: "left"
                    visible: root.stopped
                    onClicked: root.start()
                }
                AppButton {
                    c: root.c; glyph: root.shown ? "monitor-off" : "monitor"; label: root.shown ? "Hide display" : "Show display"
                    strong: !root.stopping && !root.paused; keys: "d"; tipAlign: "left"
                    tip: root.shown ? "Out of sight, the VM running on" : "Bring its window forward"
                    visible: root.running
                    onClicked: root.display()
                }
                AppButton {
                    c: root.c; glyph: root.paused ? "play" : "pause"; label: root.paused ? "Resume" : "Pause"
                    strong: root.paused; keys: "p"; tipAlign: "left"
                    tip: root.paused ? "Go on where it stopped" : "Stop its CPUs where they are"
                    visible: root.running && !root.stopping
                    onClicked: root.pauseResume()
                }
                AppButton {
                    c: root.c; glyph: "power"; label: root.slow ? "Ask again" : "Shut down"; keys: "x"; tipAlign: "left"
                    tip: root.slow ? "It hasn't gone down yet" : "Ask it to power off"
                    visible: root.running && (!root.stopping || root.slow)
                    onClicked: root.shutDown()
                }
                AppButton {
                    c: root.c; glyph: "square"; label: "Force off"; strong: root.slow; keys: "⇧X"; tip: "Pull the plug"; tipAlign: "left"
                    visible: root.running
                    onClicked: root.forceOff()
                }
                AppButton {
                    c: root.c; glyph: "settings"; label: "Settings"; keys: "⌘,"; tip: "Memory, CPUs, disk, ISO"; tipAlign: "left"
                    onClicked: root.settings()
                }
            }

            // What it has, a label and its value a line each
            Column {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: !root.vm ? [] : [
                        { k: "Memory", v: (root.vm.mem / 1024) + " GB" },
                        { k: "CPUs", v: String(root.vm.cpus) },
                        { k: "Disk", v: root.vm.disk + " GB" + (root.vm.used !== undefined ? "  ·  " + root.vm.used + " GB in use" : "") },
                        { k: "ISO", v: root.vm.iso ? root.vm.iso.split("/").pop() : "", eject: true },
                        { k: "SSH", v: root.vm.ssh ? "ssh " + root.vm.name : "", copy: true,
                          note: "port " + root.vm.ssh + (root.vm.user ? "  ·  user " + root.vm.user : "") }
                    ].filter(r => r.v !== "")
                    delegate: Row {
                        id: info
                        required property var modelData
                        spacing: 0
                        height: 22
                        Text {
                            width: 96; anchors.verticalCenter: parent.verticalCenter
                            text: info.modelData.k
                            color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, root.width - 56 - 96 - 34)
                            elide: Text.ElideMiddle
                            rightPadding: info.modelData.eject || info.modelData.copy ? 6 : 0
                            text: info.modelData.v
                            color: root.c.text; font.family: root.c.font; font.pixelSize: 12
                        }
                        // The ISO comes out while it is stopped, so it boots from its disk from then on
                        AppIconButton {
                            visible: !!info.modelData.eject
                            anchors.verticalCenter: parent.verticalCenter
                            c: root.c; glyph: "eject"; glyphSize: 12; tip: "Eject: boot from the disk from now on"
                            onClicked: if (root.whenStopped("eject the ISO")) root.act(["eject", root.vm.name])
                        }
                        // The ssh command to the clipboard: ~/.ssh/config.d/garage knows its port and user
                        AppIconButton {
                            id: copyBtn
                            property bool copied: false
                            visible: !!info.modelData.copy
                            anchors.verticalCenter: parent.verticalCenter
                            c: root.c; glyph: copied ? "check" : "copy"; glyphSize: 12; tip: "Copy"
                            onClicked: { Quickshell.execDetached(["wl-copy", "--", info.modelData.v]); copied = true; copiedTimer.restart() }
                            Timer { id: copiedTimer; interval: 1500; onTriggered: copyBtn.copied = false }
                        }
                        Text {
                            visible: !!info.modelData.note
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 8
                            text: info.modelData.note || ""
                            color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
                        }
                    }
                }
            }

            SnapshotList {
                id: snapshots
                Layout.topMargin: 6
                Layout.fillWidth: true
                c: root.c
                ctl: root.ctl
                vm: root.vm
                stopped: root.stopped
                onAskName: (title, initial, done) => root.askName(title, initial, done)
                onAskConfirm: (question, detail, action, glyph, done) => root.askConfirm(question, detail, action, glyph, done)
                onLeave: root.forceActiveFocus()
            }
            Item { Layout.fillHeight: true }
        }
    }
}
