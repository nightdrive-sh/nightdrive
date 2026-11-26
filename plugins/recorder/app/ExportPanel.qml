import QtQuick
import Quickshell.Io
import qs
import qs.kit

// Export (e): the recording as MP3, M4A, FLAC or Opus, made beside its WAV (`recorder export NAME FORMAT`, lib/export.py,
// which also names the formats). ↑ ↓ or the format's first letter move, ⏎ or a click exports, Esc closes. One made
// already says so, and is made again. The export runs in its own process, so recording keys go on meanwhile; the
// panel stays until it is done, and the window says how it went (exported, failed).
AppPanel {
    id: p
    required property var store
    signal exported(var result)
    signal failed(string text)
    property var rec: null
    property int cursor: 0
    property var formats: []                  // [{ format, label, about }]
    readonly property bool busy: runner.running
    cardWidth: Math.min(440, parent ? parent.width - 32 : 440)
    visible: false

    function open(r) {
        if (!r) return
        rec = r
        if (!formats.length) lister.running = true
        visible = true
        forceActiveFocus()
    }
    function close() { if (!busy) visible = false }
    function made(fmt) { return !!rec && rec.exports.some(e => e.endsWith("." + fmt)) }
    function choose(i) {
        if (busy || i < 0 || i >= formats.length) return
        cursor = i
        runner.command = [store.command, "export", rec.name, formats[i].format, "--json"]
        runner.running = true
    }
    onOutsideTapped: close()

    Keys.onPressed: e => {
        const k = e.key
        const letter = formats.findIndex(f => f.format[0] === e.text)
        if (k === Qt.Key_Down || k === Qt.Key_J) cursor = Math.min(formats.length - 1, cursor + 1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) cursor = Math.max(0, cursor - 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) choose(cursor)
        else if (k === Qt.Key_Escape) close()
        else if (letter >= 0) cursor = letter
        else return
        e.accepted = true
    }

    Process {
        id: lister
        command: [p.store.command, "export", "formats", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { p.formats = JSON.parse(text) } catch (e) {} } }
    }
    Process {
        id: runner
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (code === 0) {
                try { p.exported(JSON.parse(out.text)) } catch (e) {}
                p.visible = false
            } else p.failed(err.text.trim() || "The export failed.")
            p.store.refresh()
        }
    }

    Text {
        width: parent.width
        elide: Text.ElideRight; textFormat: Text.PlainText
        text: "Export " + (p.rec ? p.rec.name : "")
        font.family: p.c.font; font.pixelSize: 15; font.weight: Font.DemiBold
        color: p.c.title
    }
    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: p.formats
            AppRow {
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: 44
                c: p.c
                selected: index === p.cursor
                TapHandler { onTapped: p.choose(index) }
                Text {
                    id: label
                    anchors.left: parent.left; anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54
                    text: modelData.label
                    font.family: p.c.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    color: p.c.title
                }
                Text {
                    anchors.left: label.right; anchors.leftMargin: 8
                    anchors.right: mark.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: modelData.about
                    font.family: p.c.font; font.pixelSize: 12
                    color: p.c.dim
                }
                Text {
                    id: mark
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: p.busy && index === p.cursor ? "Exporting…" : p.made(modelData.format) ? Icons.g("check") : ""
                    font.family: p.busy && index === p.cursor ? p.c.font : Icons.family
                    font.pixelSize: 12
                    color: p.busy ? p.c.dim : p.c.accent
                }
            }
        }
    }
    Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Saved beside the recording in " + (p.store.folder || "~/Recordings").replace(/^\/home\/[^/]+/, "~")
              + "; one made already is made again."
        font.family: p.c.font; font.pixelSize: 11
        color: p.c.faint
    }
    Row {
        spacing: 10
        AppPanelButton { c: p.c; keys: ["Enter"]; label: "Export"; strong: true; enabled: !p.busy; onClicked: p.choose(p.cursor) }
        AppPanelButton { c: p.c; keys: ["Esc"]; label: "Cancel"; enabled: !p.busy; onClicked: p.close() }
    }
}
