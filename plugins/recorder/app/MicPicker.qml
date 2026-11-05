import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.kit

// The microphones to record from (PipeWire's audio sources, not the monitors of the outputs), as a panel over the
// window: Default first (whatever input the desktop has picked: Sound menu), then each source by its name. ↑ ↓ move,
// ⏎ or a click picks, Esc closes. The pick is Settings' mic (`recorder config mic NODE`), so it is remembered, and a
// paused recording goes on from it (Store.pickMic). The window also asks it for a mic's name and its PwNode (the level
// meter's).
AppPanel {
    id: p
    signal picked(string node)
    property string current: ""                // the node name picked ("" the default)
    property int cursor: 0
    cardWidth: Math.min(440, parent ? parent.width - 32 : 440)
    visible: false

    // { node: "" for the default, name, pw: the PwNode }
    readonly property var sources: {
        const list = Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream && !(n.name || "").endsWith(".monitor"))
        const def = Pipewire.defaultAudioSource
        return [{ node: "", name: "Default" + (def ? " (" + nice(def) + ")" : ""), pw: def }]
            .concat(list.map(n => ({ node: n.name, name: nice(n), pw: n })))
    }
    function nice(n) { return n.nickname || n.description || n.name }
    function nodeOf(name) {
        if (!name) return Pipewire.defaultAudioSource
        return Pipewire.nodes.values.find(n => n.name === name) || null
    }
    // A mic gone (unplugged) still has its node name: shown as it is, so it is clear what was picked
    function nameOf(name) {
        if (!name) return "Default"
        const n = nodeOf(name)
        return n ? nice(n) : name + " (not connected)"
    }

    function open() {
        cursor = Math.max(0, sources.findIndex(s => s.node === current))
        visible = true
        forceActiveFocus()
    }
    function close() { visible = false }
    function choose(i) { if (i >= 0 && i < sources.length) { p.picked(sources[i].node); close() } }
    onOutsideTapped: close()

    Keys.onPressed: e => {
        const k = e.key
        if (k === Qt.Key_Down || k === Qt.Key_J) cursor = Math.min(sources.length - 1, cursor + 1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) cursor = Math.max(0, cursor - 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) choose(cursor)
        else if (k === Qt.Key_Escape) close()
        else return
        e.accepted = true
    }

    Text {
        text: "Microphone"
        font.family: p.c.font; font.pixelSize: 15; font.weight: Font.DemiBold
        color: p.c.title
    }
    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: p.sources
            AppRow {
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: 34
                c: p.c
                selected: index === p.cursor
                TapHandler { onTapped: p.choose(index) }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.g(modelData.node === p.current ? "check" : "mic")
                    font.family: Icons.family; font.pixelSize: 14
                    color: modelData.node === p.current ? p.c.accent : p.c.dim
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 36
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight; textFormat: Text.PlainText
                    text: modelData.name
                    font.family: p.c.font; font.pixelSize: 13
                    color: p.c.title
                }
            }
        }
    }
    Row {
        spacing: 10
        AppPanelButton { c: p.c; keys: ["Enter"]; label: "Use"; strong: true; onClicked: p.choose(p.cursor) }
        AppPanelButton { c: p.c; keys: ["Esc"]; label: "Cancel"; onClicked: p.close() }
    }
}
