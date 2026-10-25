import QtQuick
import QtQuick.Layouts
import qs.kit

// A VM's snapshots: its title with Take, the list (a name and when), and what the keys do under it. Tab from the page
// comes here (focusList), Tab or Esc goes back (leave). Taking, restoring and deleting need the VM stopped, as qemu-img
// writes the disk then; a name changes any time (vm-ctl rename: names.json only). Restoring and deleting ask first:
// what changed since, or the snapshot, is gone.
ColumnLayout {
    id: root
    required property QtObject c
    required property QtObject ctl
    property var vm: null
    property bool stopped: false
    readonly property var snaps: vm ? vm.snapshots : []
    readonly property string vmName: vm ? vm.name : ""
    property int current: 0
    readonly property bool focused: list.activeFocus
    property bool returnHere: false     // the list had the keys when it asked: they come back here after (VmPage.refocus)
    signal askName(string title, string initial, var done)
    signal askConfirm(string question, string detail, string action, string glyph, var done)
    signal leave()
    spacing: 10

    onVmNameChanged: current = 0
    onSnapsChanged: if (current >= snaps.length) current = Math.max(0, snaps.length - 1)
    function focusList() { if (snaps.length) list.forceActiveFocus() }
    function ask(f) { returnHere = list.activeFocus; f() }

    function take() {
        if (!stopped) return
        const name = vmName
        // The tag is the time (unique, no spaces); the name is what shows, and can change
        ask(() => askName("Name the snapshot", "Snapshot " + Qt.formatDateTime(new Date(), "d.M. hh:mm"),
                n => { if (n) ctl.run(["snapshot", name, "s" + Math.floor(Date.now() / 1000), n]) }))
    }
    function restore(i) {
        if (!stopped || i < 0 || i >= snaps.length) return
        const name = vmName, s = snaps[i]
        ask(() => askConfirm("Go back to " + s.name + "?", name + "'s disk returns to " + s.date + ": what changed since is lost.",
                   "Restore", "rotate-ccw", () => ctl.run(["restore", name, s.tag])))
    }
    function rename(i) {
        if (i < 0 || i >= snaps.length) return
        const name = vmName, s = snaps[i]
        ask(() => askName("Rename the snapshot", s.name, n => { if (n && n !== s.name) ctl.run(["rename", name, s.tag, n]) }))
    }
    function remove(i) {
        if (!stopped || i < 0 || i >= snaps.length) return
        const name = vmName, s = snaps[i]
        ask(() => askConfirm("Delete the snapshot " + s.name + "?", name + "'s disk can no longer go back to it.",
                   "Delete", "trash-2", () => ctl.run(["unsnap", name, s.tag])))
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            text: "Snapshots"
            color: root.c.title; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium
        }
        Item { Layout.fillWidth: true; Layout.preferredHeight: 28 }
        AppButton {
            c: root.c; glyph: "camera"; label: "Take"; keys: "t"; tip: "Its disk as it is now"
            visible: root.stopped
            onClicked: root.take()
        }
    }

    ListView {
        id: list
        visible: root.snaps.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 260)
        clip: true
        model: root.snaps
        currentIndex: root.current
        spacing: 2
        Keys.onPressed: e => {
            const k = e.key, n = root.snaps.length
            if (k === Qt.Key_Down || k === Qt.Key_J) root.current = Math.min(n - 1, root.current + 1)
            else if (k === Qt.Key_Up || k === Qt.Key_K) root.current = Math.max(0, root.current - 1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.restore(root.current)
            else if (k === Qt.Key_E || k === Qt.Key_F2) root.rename(root.current)
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
            selected: list.activeFocus && index === root.current
            marked: !list.activeFocus && index === root.current && root.snaps.length > 1
            TapHandler { onTapped: { root.current = row.index; list.forceActiveFocus() } }
            Text {
                x: 14; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, date.x - 24)
                elide: Text.ElideRight
                text: row.modelData.name
                color: row.selected ? root.c.title : root.c.text; font.family: root.c.font; font.pixelSize: 12
            }
            Text {
                id: date
                anchors.right: tools.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.date
                color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
            }
            // Under the pointer or picked; kept in place while hidden, so the dates don't shift
            Row {
                id: tools
                anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                opacity: row.hovered || row.selected ? 1 : 0
                AppIconButton {
                    c: root.c; glyph: "pencil"; glyphSize: 12; tip: "Rename"; keys: "e"; tipSide: "above"
                    enabled: parent.opacity > 0
                    onClicked: root.rename(row.index)
                }
                AppIconButton {
                    c: root.c; glyph: "trash-2"; glyphSize: 12; tip: "Delete"; keys: "Del"; tipSide: "above"
                    opacity: root.stopped ? 1 : 0
                    enabled: parent.opacity > 0 && root.stopped
                    onClicked: root.remove(row.index)
                }
            }
        }
    }

    Text {
        visible: root.snaps.length === 0
        text: root.stopped ? "None yet: t takes one, its disk as it is now." : "None yet."
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
    }

    // What the keys do: in the list its keys, else how to get there; while it runs, why the rest waits
    Row {
        Layout.topMargin: 2
        spacing: 18
        visible: root.snaps.length > 0
        AppKeyAction { c: root.c; keys: "Tab"; label: "To the list"; visible: !root.focused; onClicked: root.focusList() }
        AppKeyAction { c: root.c; keys: "⏎"; label: "Restore"; visible: root.focused && root.stopped; onClicked: root.restore(root.current) }
        AppKeyAction { c: root.c; keys: "e"; label: "Rename"; visible: root.focused; onClicked: root.rename(root.current) }
        AppKeyAction { c: root.c; keys: "Del"; label: "Delete"; visible: root.focused && root.stopped; onClicked: root.remove(root.current) }
    }
    Text {
        visible: !!root.vm && !root.stopped
        text: "Shut it down to take, restore or delete a snapshot."
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
}
