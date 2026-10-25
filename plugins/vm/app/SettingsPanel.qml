import QtQuick
import qs.kit

// A VM's settings (⌘,): its memory, CPUs and disk, the ISO in its drive, and deleting it. They change while it is
// stopped (vm-ctl set, one call each for what changed); while it runs they show, with a line on why they can't
// change. The disk only grows, and the guest then sees the new space unpartitioned: the line under the fields says so.
// The display has no setting: SDL gives the guest its window's size, and its scale is the guest's own.
AppPanel {
    id: root
    required property QtObject ctl
    property var vm: null
    property bool stopped: false
    property string problem: ""         // what is wrong with what was typed: the panel stays open
    signal done()
    signal deleteVm()
    cardWidth: 540
    onOutsideTapped: done()

    function load() {
        if (!vm) return
        mem.text = String(vm.mem / 1024); cpus.text = String(vm.cpus); disk.text = String(vm.disk)
        iso.text = vm.iso
        problem = ""
        mem.input.forceActiveFocus(); mem.input.selectAll()
    }
    onVisibleChanged: if (visible) load()

    function save() {
        if (!stopped) { done(); return }
        const whole = t => /^[0-9]+$/.test(t.trim())
        if (!whole(mem.text) || !whole(cpus.text) || !whole(disk.text)) { problem = "Memory, CPUs and disk are whole numbers"; return }
        if (+disk.text < vm.disk) { problem = "The disk only grows: " + vm.disk + " GB or more"; return }
        const name = vm.name, changes = []
        if (+mem.text !== vm.mem / 1024) changes.push(["mem", mem.text.trim()])
        if (+cpus.text !== vm.cpus) changes.push(["cpus", cpus.text.trim()])
        if (+disk.text !== vm.disk) changes.push(["disk", disk.text.trim()])
        if (iso.text.trim() !== vm.iso) changes.push(["iso", iso.text.trim()])
        for (const ch of changes) ctl.run(["set", name].concat(ch))
        done()
    }

    IsoPicker { id: picker }

    Text {
        text: root.vm ? root.vm.name : ""
        color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
    }

    Row {
        spacing: 16
        Field { id: mem; c: root.c; width: 130; label: "Memory, GB"; input.readOnly: !root.stopped; onAccepted: root.save(); onEscaped: root.done() }
        Field { id: cpus; c: root.c; width: 130; label: "CPUs, 1 to 8"; input.readOnly: !root.stopped; onAccepted: root.save(); onEscaped: root.done() }
        Field { id: disk; c: root.c; width: 130; label: "Disk, GB"; input.readOnly: !root.stopped; onAccepted: root.save(); onEscaped: root.done() }
    }
    Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "The disk only grows" + (root.vm && root.vm.used !== undefined ? " (" + root.vm.used + " GB of it in use)" : "")
            + ". The guest sees the new space unpartitioned: grow its partition inside it."
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11; lineHeight: 1.3
    }

    // The ISO: a path, chosen in a dialog or typed, and out with Eject. It boots after the disk, so an installed VM
    // boots its disk with one in.
    Row {
        spacing: 8
        Field {
            id: iso
            c: root.c
            width: root.cardWidth - 80 - choose.width - eject.width - 16
            label: "ISO in its drive (boots when the disk has nothing to boot)"
            input.readOnly: !root.stopped
            onAccepted: root.save(); onEscaped: root.done()
        }
        AppButton {
            id: choose
            anchors.bottom: parent.bottom; anchors.bottomMargin: 2
            c: root.c; glyph: "folder-open"; label: "Choose…"
            visible: root.stopped
            onClicked: picker.pick(iso.text, p => iso.text = p)
        }
        AppButton {
            id: eject
            anchors.bottom: parent.bottom; anchors.bottomMargin: 2
            c: root.c; glyph: "eject"; label: "Eject"
            visible: root.stopped && iso.text !== ""
            onClicked: iso.text = ""
        }
    }

    Text {
        visible: !root.stopped || root.problem !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: root.problem !== "" ? root.problem : "Shut " + (root.vm ? root.vm.name : "it") + " down to change these."
        color: root.problem !== "" ? root.c.danger : root.c.dim; font.family: root.c.font; font.pixelSize: 12
    }

    Row {
        spacing: 8
        AppButton { c: root.c; glyph: "check"; label: "Save"; strong: true; keys: "⏎"; visible: root.stopped; onClicked: root.save() }
        AppButton { c: root.c; label: root.stopped ? "Cancel" : "Close"; keys: "Esc"; onClicked: root.done() }
    }

    Rectangle { width: parent.width; height: 1; color: root.c.divider; visible: root.stopped }
    Row {
        visible: root.stopped
        spacing: 12
        AppButton { c: root.c; glyph: "trash-2"; label: "Delete VM…"; keys: "⌘⌫"; onClicked: root.deleteVm() }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Its disk and snapshots go with it."
            color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
        }
    }
}
