import QtQuick
import Quickshell
import qs.kit

// A new VM from an ISO: its name, the ISO's path, memory and disk. Create makes the disk and starts it from the ISO.
// The ISO field starts with the newest .iso in ~/Downloads (vm-ctl isos), as that is where one usually is.
AppPanel {
    id: root
    required property QtObject ctl
    signal done()
    cardWidth: 560
    onOutsideTapped: done()
    onVisibleChanged: if (visible) {
        name.text = ""; mem.text = "4"; disk.text = "40"; cpus.text = "4"
        ctl.run(["isos"], out => { const l = out.trim().split("\n"); iso.text = l[0] || "" })
        name.input.forceActiveFocus()
    }
    Keys.onEscapePressed: done()

    function create() {
        if (!/^[A-Za-z0-9._-]+$/.test(name.text) || iso.text === "") return
        ctl.run(["create", name.text, iso.text, mem.text, disk.text, cpus.text], () => ctl.run(["start", name.text]))
        done()
    }

    Text { text: "New VM"; color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium }
    Field { id: name; c: root.c; width: parent.width; label: "Name (letters, digits, - . _)"; onAccepted: root.create() }
    Field { id: iso; c: root.c; width: parent.width; label: "ISO"; onAccepted: root.create() }
    Row {
        spacing: 16
        Field { id: mem; c: root.c; width: 120; label: "Memory, GB"; onAccepted: root.create() }
        Field { id: disk; c: root.c; width: 120; label: "Disk, GB"; onAccepted: root.create() }
        Field { id: cpus; c: root.c; width: 120; label: "CPUs"; onAccepted: root.create() }
    }
    AppButton { c: root.c; glyph: "plus"; label: "Create and start"; strong: true; keys: "⏎"; onClicked: root.create() }
}
