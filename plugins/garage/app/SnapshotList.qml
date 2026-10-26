import QtQuick
import QtQuick.Layouts
import qs.kit

// A VM's snapshots: its title with Take snapshot, and the list (a name, when, and the space it alone keeps), each row's
// buttons telling their keys in their tips (KeyHelp.qml has them all). Tab from the page comes here (focusList), Tab or Esc goes back (leave). Taking, restoring,
// duplicating and deleting need the VM stopped, as qemu-img writes the disk then: their buttons show while it runs too,
// and say so at the page's foot when clicked. A name changes any time (garage-ctl rename: names.json only). Restoring and deleting ask first: what changed since, or the snapshot, is gone.
ColumnLayout {
    id: root
    required property QtObject c
    required property QtObject ctl
    property var vm: null
    property bool stopped: false
    readonly property var snaps: vm ? vm.snapshots : []
    readonly property string vmName: vm ? vm.name : ""
    property int current: 0
    property string copying: ""         // the snapshot being duplicated, while garage-ctl is at it
    // The one being taken, { vm, tag, name }: a row of its own at the top until the list has it (qemu-img takes a moment)
    property var saving: null
    readonly property bool savingHere: !!saving && saving.vm === vmName
    readonly property bool focused: list.activeFocus
    property bool returnHere: false     // the list had the keys when it asked: they come back here after (VmPage.refocus)
    signal askName(string title, string initial, var done)
    signal askConfirm(string question, string detail, string action, string glyph, var done)
    signal leave()
    spacing: 10

    onVmNameChanged: current = 0
    onSnapsChanged: {
        if (current >= snaps.length) current = Math.max(0, snaps.length - 1)
        if (savingHere && snaps.some(s => s.tag === saving.tag)) saving = null
    }
    function focusList() { if (snaps.length) list.forceActiveFocus() }
    function ask(f) { returnHere = list.activeFocus; f() }
    // 7286358016 → "6.8 GB", 434438144 → "414 MB"
    function bytes(n) {
        return n >= 1073741824 ? (n / 1073741824).toFixed(1) + " GB" : Math.round(n / 1048576) + " MB"
    }

    function whenStopped(what) {
        if (!stopped) ctl.error = "Shut " + vmName + " down first to " + what
        return stopped
    }

    function take() {
        if (!whenStopped("take a snapshot")) return
        const name = vmName
        // The tag is the time (unique, no spaces); the name is what shows, and can change. Its row stays until the list
        // shows it (onSnapsChanged), so it doesn't blink out between garage-ctl's exit and the next list; a failure takes it
        ask(() => askName("Name the snapshot", "Snapshot " + Qt.formatDateTime(new Date(), "d.M. hh:mm"), n => {
            if (!n) return
            const tag = "s" + Math.floor(Date.now() / 1000)
            root.saving = { vm: name, tag: tag, name: n }
            ctl.run(["snapshot", name, tag, n], null, () => root.saving = null)
        }))
    }
    function restore(i) {
        if (i < 0 || i >= snaps.length || !whenStopped("restore a snapshot")) return
        const name = vmName, s = snaps[i]
        ask(() => askConfirm("Go back to " + s.name + "?", name + "'s disk returns to " + s.date + ": what changed since is lost.",
                   "Restore", "rotate-ccw", () => ctl.run(["restore", name, s.tag])))
    }
    function rename(i) {
        if (i < 0 || i >= snaps.length) return
        const name = vmName, s = snaps[i]
        ask(() => askName("Rename the snapshot", s.name, n => { if (n && n !== s.name) ctl.run(["rename", name, s.tag, n]) }))
    }
    // A copy under a name of its own, in the same disk (garage-ctl duplicate: it shares the original's clusters, so it
    // takes no space of its own). Its tag is the time, as a new one's
    function duplicate(i) {
        if (copying || i < 0 || i >= snaps.length || !whenStopped("duplicate a snapshot")) return
        const name = vmName, s = snaps[i]
        ask(() => askName("Name the copy of " + s.name, s.name + " (copy)", n => {
            if (!n) return
            root.copying = s.name
            ctl.run(["duplicate", name, s.tag, "s" + Math.floor(Date.now() / 1000), n],
                    () => root.copying = "", () => root.copying = "")
        }))
    }
    function removeCurrent() { remove(current) }
    function remove(i) {
        if (i < 0 || i >= snaps.length || !whenStopped("delete a snapshot")) return
        const name = vmName, s = snaps[i]
        ask(() => askConfirm("Delete the snapshot " + s.name + "?", name + "'s disk can no longer go back to it.",
                   "Delete", "trash-2", () => ctl.run(["unsnap", name, s.tag])))
    }

    // Over the list while Take snapshot's tip shows on it; else under it, as the first row's tips may reach up here
    RowLayout {
        Layout.fillWidth: true
        z: take.hovered ? 3 : 0
        Text {
            text: "Snapshots"
            color: root.c.title; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium
        }
        Item { Layout.fillWidth: true; Layout.preferredHeight: 28 }
        AppButton {
            id: take
            c: root.c; glyph: "camera"; label: "Take snapshot"; keys: "t"; tip: "Save the disk's current state"
            onClicked: root.take()
        }
    }

    // The one being taken, where the list will show it (newest first): a row's place, but nothing to click yet
    Item {
        visible: root.savingHere
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        Layout.bottomMargin: 2 - root.spacing   // as close to the rows under it as they are to each other
        Row {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.saving ? root.saving.name : ""
                color: root.c.text; font.family: root.c.font; font.pixelSize: 12
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Saving snapshot…"
                color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
            }
        }
    }

    ListView {
        id: list
        visible: root.snaps.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 260)
        // Only while it scrolls: clipped, the rows' tips would be cut off at its edges
        clip: contentHeight > height
        z: 2
        model: root.snaps
        currentIndex: root.current
        spacing: 2
        Keys.onPressed: e => {
            const k = e.key, n = root.snaps.length
            root.c.keyboard = true
            if (k === Qt.Key_Down || k === Qt.Key_J) root.current = Math.min(n - 1, root.current + 1)
            else if (k === Qt.Key_Up || k === Qt.Key_K) root.current = Math.max(0, root.current - 1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.restore(root.current)
            else if (k === Qt.Key_E || k === Qt.Key_F2) root.rename(root.current)
            else if (k === Qt.Key_C) root.duplicate(root.current)
            else if (k === Qt.Key_Delete) root.remove(root.current)
            else if (k === Qt.Key_Escape || k === Qt.Key_Tab || k === Qt.Key_Backtab) root.leave()
            else return
            e.accepted = true
        }
        delegate: AppRow {
            id: row
            required property var modelData
            required property int index
            c: root.c
            height: 32
            // Over the next row, which its tips reach (below it; the last row's above it, into the one before)
            z: hovered || selected ? 1 : 0
            readonly property string tipSide: index === root.snaps.length - 1 && index > 0 ? "above" : "below"
            selected: list.activeFocus && index === root.current
            active: true        // selected only while the keys are here
            marked: !list.activeFocus && index === root.current && root.snaps.length > 1
            // A double click restores it, as its Restore button does (asking first, and only while the VM is stopped)
            TapHandler {
                onTapped: { root.current = row.index; list.forceActiveFocus() }
                onDoubleTapped: root.restore(row.index)
            }
            // Its name, then when it was taken and the space it alone keeps (garage-ctl list's size), close after it
            Row {
                x: 14; anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, tools.x - 40 - about.implicitWidth)
                    elide: Text.ElideRight
                    text: row.modelData.name
                    color: row.selected ? root.c.title : root.c.text; font.family: root.c.font; font.pixelSize: 12
                }
                Text {
                    id: about
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.date + (row.modelData.size != null ? "  ·  " + root.bytes(row.modelData.size) : "")
                    color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
                }
            }
            // Under the pointer or picked; kept in place while hidden
            Row {
                id: tools
                anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                opacity: row.hovered || row.selected ? 1 : 0
                AppIconButton {
                    c: root.c; glyph: "rotate-ccw"; glyphSize: 12; tip: "Restore"; keys: "⏎"; tipSide: row.tipSide; tipAlign: "right"
                    enabled: parent.opacity > 0
                    onClicked: root.restore(row.index)
                }
                AppIconButton {
                    c: root.c; glyph: "pencil"; glyphSize: 12; tip: "Rename"; keys: "e"; tipSide: row.tipSide; tipAlign: "right"
                    enabled: parent.opacity > 0
                    onClicked: root.rename(row.index)
                }
                AppIconButton {
                    c: root.c; glyph: "copy"; glyphSize: 12; tip: "Duplicate"; keys: "c"; tipSide: row.tipSide; tipAlign: "right"
                    enabled: parent.opacity > 0
                    onClicked: root.duplicate(row.index)
                }
                AppIconButton {
                    c: root.c; glyph: "trash-2"; glyphSize: 12; tip: "Delete"; keys: "Del"; tipSide: row.tipSide; tipAlign: "right"
                    enabled: parent.opacity > 0
                    onClicked: root.remove(row.index)
                }
            }
        }
    }

    Text {
        visible: root.snaps.length === 0 && !root.savingHere
        text: "None yet: t saves the disk's current state."
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
    }

    Text {
        visible: !!root.copying
        text: "Duplicating " + root.copying + "…"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
}
