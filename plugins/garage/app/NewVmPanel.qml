import QtQuick
import Quickshell
import qs.kit

// A new VM, from a ready-made disk image (images.json: Fedora 44 Minimal) or an ISO. From an image it needs no
// installer: it is ready at its first boot with the user asked for here (garage-ctl create-image), and an image not yet
// downloaded is fetched first, the VM waiting in the sidebar meanwhile (Images.qml). From an ISO it gets an empty
// disk and boots the installer (garage-ctl create); the ISO field starts with the newest .iso in ~/Downloads (garage-ctl isos).
// What is wrong with what was typed shows under the fields, and the panel stays open.
AppPanel {
    id: root
    required property QtObject ctl
    required property QtObject images
    property string source: "iso"           // an image's id, or "iso"
    property string problem: ""
    readonly property var image: source === "iso" ? null : images.image(source)
    readonly property bool fromImage: image !== null
    signal done()
    cardWidth: 560
    onOutsideTapped: done()

    onVisibleChanged: if (visible) {
        images.refresh()
        name.text = ""; user.text = Quickshell.env("USER") || Quickshell.env("HOME").split("/").pop(); pass.text = ""
        mem.text = "4"; cpus.text = "4"; problem = ""
        pick(images.list.length ? images.list[0].id : "iso")
        ctl.run(["isos"], out => { const l = out.trim().split("\n"); iso.text = l[0] || "" })
        name.input.forceActiveFocus()
    }
    // An image's disk needs only room to grow from its own; an installer wants more
    function pick(id) { source = id; problem = ""; disk.text = id === "iso" ? "40" : "20" }

    function check() {
        const whole = t => /^[0-9]+$/.test(t.trim())
        // garage-ctl's rule (good_name): the name is its folder's
        if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name.text) || name.text === "images")
            return "A name: letters, digits, - . _, starting with a letter or digit"
        if (ctl.vms.some(v => v.name === name.text) || images.waiting.some(v => v.name === name.text))
            return "There is a VM called " + name.text + " already"
        if (fromImage && !/^[a-z_][a-z0-9_-]*$/.test(user.text)) return "A user name: small letters, digits, - _"
        if (fromImage && pass.text === "") return "A password for " + user.text + " (sudo asks for it)"
        if (!fromImage && iso.text.trim() === "") return "An ISO: Choose… one"
        if (!whole(mem.text) || !whole(cpus.text) || !whole(disk.text)) return "Memory, CPUs and disk are whole numbers"
        if (fromImage && +disk.text < image.minDisk) return "Disk: at least " + image.minDisk + " GB for " + image.name
        return ""
    }
    function create() {
        problem = check()
        if (problem !== "") return
        const vm = { name: name.text, mem: mem.text.trim(), disk: disk.text.trim(), cpus: cpus.text.trim() }
        if (fromImage) images.create(Object.assign(vm, { id: image.id, user: user.text, pass: pass.text }))
        else ctl.run(["create", vm.name, iso.text.trim(), vm.mem, vm.disk, vm.cpus], () => {
            ctl.power("start", vm.name)
            images.made(vm.name)
        })
        done()
    }

    IsoPicker { id: picker }

    Text { text: "New machine"; color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium }

    // Where it comes from: each ready-made image, or an ISO. The picked one has the picked row's ground, as AppButton's
    // on lights only its glyph
    Row {
        spacing: 8
        Repeater {
            model: root.images.list
            delegate: AppButton {
                required property var modelData
                c: root.c; glyph: "hard-drive"; label: modelData.name
                on: root.source === modelData.id
                color: on ? root.c.sel : hovered ? root.c.hover : "transparent"
                onClicked: root.pick(modelData.id)
            }
        }
        AppButton { c: root.c; glyph: "disc"; label: "ISO file"; on: root.source === "iso"
            color: on ? root.c.sel : hovered ? root.c.hover : "transparent"; onClicked: root.pick("iso") }
    }
    // Only a failed download says anything here: one to come shows in the button (Download and create), one under way in
    // the sidebar
    Text {
        visible: root.fromImage && root.image.state === "failed"
        width: parent.width
        wrapMode: Text.Wrap
        text: visible ? "The last download failed: " + root.image.error : ""
        color: root.c.danger; font.family: root.c.font; font.pixelSize: 12
    }

    Field { id: name; c: root.c; width: parent.width; label: "Name"; hint: "letters, digits, - . _"; onAccepted: root.create(); onEscaped: root.done() }
    Row {
        visible: root.fromImage
        spacing: 16
        Field { id: user; c: root.c; width: 200; label: "User"; onAccepted: root.create(); onEscaped: root.done() }
        Field {
            id: pass; c: root.c; width: 200; label: "Password"
            input.echoMode: TextInput.Password
            onAccepted: root.create(); onEscaped: root.done()
        }
    }
    Row {
        visible: !root.fromImage
        spacing: 8
        Field {
            id: iso; c: root.c; label: "ISO"
            width: root.cardWidth - 80 - choose.width - 8
            onAccepted: root.create(); onEscaped: root.done()
        }
        AppButton {
            id: choose
            anchors.bottom: parent.bottom; anchors.bottomMargin: 2
            c: root.c; glyph: "folder-open"; label: "Choose…"
            onClicked: picker.pick(iso.text, p => iso.text = p)
        }
    }
    Row {
        spacing: 16
        Field { id: mem; c: root.c; width: 120; label: "Memory"; hint: "GB"; onAccepted: root.create(); onEscaped: root.done() }
        Field { id: cpus; c: root.c; width: 120; label: "CPUs"; hint: "1 to 8"; onAccepted: root.create(); onEscaped: root.done() }
        Field { id: disk; c: root.c; width: 120; label: "Disk"; hint: "GB"; onAccepted: root.create(); onEscaped: root.done() }
    }

    Text {
        visible: root.problem !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: root.problem
        color: root.c.danger; font.family: root.c.font; font.pixelSize: 12
    }
    Row {
        spacing: 8
        PanelButton {
            c: root.c; strong: true; keys: ["Ctrl", "Enter"]
            label: root.fromImage && root.image.state !== "ready" ? "Download and create" : "Create and start"
            onClicked: root.create()
        }
        PanelButton { c: root.c; label: "Cancel"; keys: ["Esc"]; onClicked: root.done() }
    }
}
