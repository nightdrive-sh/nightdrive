import QtQuick
import qs.kit
import "Format.js" as Format

// c: the marked files, or the picked one, packed into an archive in the folder on show (lib/pack.py through Ops). The
// panel asks the archive's name (one file's or folder's own, several the folder's: "Projects") and its format as chips:
// zip opens anywhere (a Mac, Windows), tar.gz and tar.xz keep Linux's links and modes, xz smaller and slower, tar
// unsqueezed for what is squeezed already (photos, videos). ↑ ↓ in the name or Tab to the chips changes it, ⏎ packs,
// Esc doesn't. The format last used is the next one's (settings.json, "archive").
AppPanel {
    id: root
    required property var app             // FilesWindow: selection(), path, ops, settings, setting()
    readonly property var formats: [
        { id: "zip", name: "zip" }, { id: "tar.gz", name: "tar.gz" }, { id: "tar.xz", name: "tar.xz" }, { id: "tar", name: "tar" }
    ]
    property var paths: []
    property string folder: ""
    visible: false
    cardWidth: 440
    c: app.look
    onOutsideTapped: close()
    onVisibleChanged: if (!visible) app.toList()

    function ask() {
        if (app.readOnly()) return
        const ps = app.trashShown ? [] : app.selection()
        if (!ps.length) return
        paths = ps
        folder = app.path
        const one = ps.length === 1 ? app.rows.find(r => r.path === ps[0]) : null
        // One file's name without its ending ("report.pdf" → "report"), else the folder's own: "Projects"
        const name = one ? (one.dir || one.name.lastIndexOf(".") <= 0 ? one.name : one.name.slice(0, one.name.lastIndexOf(".")))
                         : ps.length === 1 ? Format.base(ps[0]) : (Format.base(folder) || "Archive")
        chips.picked = formats.some(f => f.id === app.settings.archive) ? app.settings.archive : "zip"
        field.text = name
        visible = true
        field.input.forceActiveFocus()
        field.input.selectAll()
    }
    function close() { visible = false }
    function pack() {
        const name = field.text.trim()
        if (!name) return
        visible = false
        if (app.settings.archive !== chips.picked) app.setting("archive", chips.picked)
        app.ops.compress(paths, folder, name, chips.picked)
        app.marks = ({})                  // done with them, as a cut is
    }
    function step(n) { chips.step(n) }

    Text {
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        text: root.paths.length === 1 ? "Compress “" + Format.base(root.paths[0]) + "”" : "Compress " + root.paths.length + " items"
        color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
    }
    AppField {
        id: field
        c: root.c
        width: parent.width
        label: "Name"
        hint: "." + chips.picked
        keyFilter: e => {
            if (e.key === Qt.Key_Down) { root.step(1); e.accepted = true }
            else if (e.key === Qt.Key_Up) { root.step(-1); e.accepted = true }
        }
        onAccepted: root.pack()
        onEscaped: root.close()
    }
    AppChips {
        id: chips
        c: root.c
        width: parent.width
        label: "Format"
        options: root.formats
        onAccepted: root.pack()
        onEscaped: root.close()
    }
    Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: chips.picked === "zip" ? "Opens anywhere: a Mac, Windows, a phone."
            : chips.picked === "tar.gz" ? "Linux's own: keeps links and who may run what."
            : chips.picked === "tar.xz" ? "Smaller than tar.gz, slower to make."
            : "Not squeezed: for photos and videos, squeezed already."
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
    Row {
        spacing: 8
        AppPanelButton { c: root.c; label: "Compress"; strong: true; keys: ["Enter"]; onClicked: root.pack() }
        AppPanelButton { c: root.c; label: "Cancel"; keys: ["Esc"]; onClicked: root.close() }
    }
}
