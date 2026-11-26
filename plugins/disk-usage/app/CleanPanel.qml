import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.kit
import "Fmt.js" as Fmt

// Clean up: what can go without losing anything of yours (lib/clean.py lists them: the Trash, thumbnails, browsers'
// caches, downloaded packages, shader caches), each with the space it takes and a tick. Enter frees the ticked ones;
// ↑ ↓ and Space tick from the keyboard, Esc or a click outside closes. Nothing else is ever touched: the list is
// clean.py's, not a guess at what a folder is.
AppPanel {
    id: root
    property var kinds: []               // [{ id, name, glyph, what, size }]
    property var off: ({})               // the kinds you unticked, by id
    property int row: 0                  // the keyboard's row
    property bool working: false
    property string result: ""           // "Freed 2.3 GB" once done
    readonly property string helper: Quickshell.shellDir + "/../lib/clean.py"
    readonly property real total: kinds.reduce((t, k) => t + k.size, 0)
    readonly property var ticked: kinds.filter(k => k.size > 0 && !off[k.id])
    readonly property real tickedSize: ticked.reduce((t, k) => t + k.size, 0)
    signal closed()
    signal cleaned(real freed)
    visible: false
    cardWidth: 600
    spacing: 16

    function refresh() { listProc.running = true }
    function open() { result = ""; row = 0; refresh(); visible = true; forceActiveFocus() }
    function close() { visible = false; closed() }
    function toggle(i) {
        const k = kinds[i]
        if (!k || k.size <= 0) return
        const o = Object.assign({}, off)
        o[k.id] = !o[k.id]
        off = o
    }
    function clean() {
        if (working || !ticked.length) return
        working = true
        runProc.command = ["python3", helper, "run"].concat(ticked.map(k => k.id))
        runProc.running = true
    }

    onOutsideTapped: if (!working) close()
    Keys.onPressed: e => {
        const k = e.key
        if (k === Qt.Key_Escape && !working) close()
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) clean()
        else if (k === Qt.Key_Down || k === Qt.Key_J) row = Math.min(kinds.length - 1, row + 1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) row = Math.max(0, row - 1)
        else if (k === Qt.Key_Space) toggle(row)
        e.accepted = true
    }

    Process {
        id: listProc
        command: ["python3", root.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.kinds = JSON.parse(text) } catch (e) { console.warn("clean.py list: " + e) } }
        }
    }
    Process {
        id: runProc
        stdout: StdioCollector { id: runOut }
        stderr: StdioCollector { id: runErr }
        onExited: code => {
            root.working = false
            let r = { freed: 0, failed: [] }
            try { r = JSON.parse(runOut.text) } catch (e) {}
            root.result = code !== 0 ? (runErr.text.trim() || "Clean up failed")
                : "Freed " + Fmt.bytes(r.freed) + (r.failed.length ? ". Some files couldn't go: " + r.failed[0] : "")
            root.cleaned(r.freed)
            root.refresh()
        }
    }

    Text { text: "Clean up"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
    Text {
        width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2
        text: "What apps make again by themselves, and what you already threw away. Your own files stay."
        color: c.dim; font.family: c.font; font.pixelSize: 12
    }

    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: root.kinds
            delegate: Rectangle {
                id: kind
                required property var modelData
                required property int index
                readonly property bool empty: modelData.size <= 0
                readonly property bool on: !empty && !root.off[modelData.id]
                width: parent.width; height: 50; radius: 8
                color: index === root.row && root.c.keyboard ? root.c.sel : hover.hovered && !empty ? root.c.hover : "transparent"
                HoverHandler { id: hover; cursorShape: kind.empty ? Qt.ArrowCursor : Qt.PointingHandCursor }
                TapHandler { onTapped: { root.row = kind.index; root.toggle(kind.index) } }
                Text {
                    id: tick
                    // On the title's line, not the row's middle: the row has two lines, and the icons belong to its name
                    x: 12; y: texts.y + nameText.y + (nameText.height - height) / 2
                    text: Icons.g(kind.on ? "square-check" : "square"); font.family: Icons.family; font.pixelSize: 15
                    color: kind.on ? root.c.primary : root.c.faint
                }
                Text {
                    id: glyph
                    anchors.left: tick.right; anchors.leftMargin: 14; y: tick.y
                    text: Icons.g(kind.modelData.glyph); font.family: Icons.family; font.pixelSize: 15
                    color: kind.empty ? root.c.faint : root.c.dim
                }
                Column {
                    id: texts
                    anchors.left: glyph.right; anchors.leftMargin: 14
                    anchors.right: size.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        id: nameText
                        text: kind.modelData.name
                        color: kind.empty ? root.c.dim : root.c.title; font.family: root.c.font; font.pixelSize: 13
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: kind.modelData.what
                        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
                    }
                }
                Text {
                    id: size
                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    text: kind.empty ? "Empty" : Fmt.bytes(kind.modelData.size)
                    color: kind.empty ? root.c.faint : root.c.text; font.family: root.c.font; font.pixelSize: 12
                }
            }
        }
        Text {
            visible: root.kinds.length === 0
            text: "Measuring…"; color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
        }
    }

    Text {
        visible: root.result !== "" || root.working
        width: parent.width; wrapMode: Text.Wrap
        text: root.working ? "Cleaning…" : root.result
        color: root.c.text; font.family: root.c.font; font.pixelSize: 12
    }

    Row {
        spacing: 8
        AppPanelButton {
            c: root.c; strong: root.tickedSize > 0; keys: ["Enter"]
            label: root.tickedSize > 0 ? "Free " + Fmt.bytes(root.tickedSize) : "Nothing to free"
            onClicked: root.clean()
        }
        AppPanelButton { c: root.c; label: "Close"; keys: ["Esc"]; onClicked: if (!root.working) root.close() }
    }
}
