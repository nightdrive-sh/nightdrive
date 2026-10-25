import QtQuick
import qs.kit

// A VM's settings (⌘,): its memory, CPUs and disk, the ISO in its drive, its ssh user, and deleting it.
// They change while it is stopped (garage-ctl set, one call each for what changed), but for the user, which only ssh's
// config reads; while it runs the rest show, and a click on what would change them says why it can't. The disk only grows, and the guest then sees the new space unpartitioned: the line under the fields says so.
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
        user.text = vm.user || ""
        problem = ""
        mem.input.forceActiveFocus(); mem.input.selectAll()
    }
    onVisibleChanged: if (visible) load()

    function whenStopped(what) {
        if (!stopped) problem = "Shut " + vm.name + " down first to " + what
        return stopped
    }

    function save() {
        const u = user.text.trim()
        if (u !== "" && !/^[a-z_][a-z0-9_-]{0,31}$/.test(u)) { problem = "User: lower-case letters, digits, - and _"; return }
        if (u !== (vm.user || "")) ctl.run(["set", vm.name, "user", u])
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
        Field { id: mem; c: root.c; width: 130; label: "Memory"; hint: "GB"; input.readOnly: !root.stopped; onRefused: root.whenStopped("change these"); onAccepted: root.save(); onEscaped: root.done() }
        Field { id: cpus; c: root.c; width: 130; label: "CPUs"; hint: "1 to 8"; input.readOnly: !root.stopped; onRefused: root.whenStopped("change these"); onAccepted: root.save(); onEscaped: root.done() }
        Field { id: disk; c: root.c; width: 130; label: "Disk"; hint: "GB"; input.readOnly: !root.stopped; onRefused: root.whenStopped("change these"); onAccepted: root.save(); onEscaped: root.done() }
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
            label: "ISO in its drive"; hint: "boots when the disk has nothing to boot"
            input.readOnly: !root.stopped
            onRefused: root.whenStopped("change the ISO")
            onAccepted: root.save(); onEscaped: root.done()
        }
        AppButton {
            id: choose
            anchors.bottom: parent.bottom; anchors.bottomMargin: 2
            c: root.c; glyph: "folder-open"; label: "Choose…"
            onClicked: if (root.whenStopped("change the ISO")) picker.pick(iso.text, p => iso.text = p)
        }
        AppButton {
            id: eject
            anchors.bottom: parent.bottom; anchors.bottomMargin: 2
            c: root.c; glyph: "eject"; label: "Eject"
            visible: iso.text !== ""
            onClicked: if (root.whenStopped("eject the ISO")) iso.text = ""
        }
    }

    // Who `ssh NAME` logs in as: an image's VM has its first boot's, an installed one the user typed in its installer
    Field {
        id: user
        c: root.c
        width: 200
        label: "SSH user"; hint: "ssh " + (root.vm ? root.vm.name : "NAME") + " logs in as"
        onAccepted: root.save(); onEscaped: root.done()
    }

    Text {
        visible: root.problem !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: root.problem
        color: root.c.danger; font.family: root.c.font; font.pixelSize: 12
    }

    // Save and Cancel on the left, deleting the machine on the right
    Item {
        width: parent.width
        height: answers.height
        Row {
            id: answers
            spacing: 8
            PanelButton { c: root.c; label: "Save"; strong: true; keys: ["Enter"]; onClicked: root.save() }
            PanelButton { c: root.c; label: "Cancel"; keys: ["Esc"]; onClicked: root.done() }
        }
        AppButton {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            c: root.c; glyph: "trash-2"; label: "Delete machine…"; keys: "⌘⌫"
            onClicked: if (root.whenStopped("delete it")) root.deleteVm()
        }
    }
}
