import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs
import qs.kit

// The microphones to record from (PipeWire's audio sources, not the monitors of the outputs), as a panel over the
// window: Default first (whatever input the desktop has picked: Sound menu), then each source by its name. ↑ ↓ move,
// ⏎ or a click picks, Esc closes. The pick is Settings' mic (`recorder config mic NODE`), so it is remembered, and a
// paused recording goes on from it (Store.pickMic). The window also asks it for a mic's name and its PwNode (the level
// meter's).
// Bluetooth headsets come last, by their card (`recorder headsets`, lib/bluetooth.py): in A2DP they have no source,
// so recording from one switches it to its headset profile until saved, and playback sounds poorer meanwhile.
AppPanel {
    id: p
    signal picked(string node)
    property string current: ""                // the node name picked ("" the default)
    property int cursor: 0
    cardWidth: Math.min(440, parent ? parent.width - 32 : 440)
    visible: false

    // { node: "" for the default, name, pw: the PwNode, bt: a headset's card }
    readonly property var sources: {
        const list = Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream && !(n.name || "").endsWith(".monitor")
                                                       && !headsets.some(h => isSourceOf(n, h.card)))
        const def = Pipewire.defaultAudioSource
        return [{ node: "", name: "Default" + (def ? " (" + nice(def) + ")" : ""), pw: def }]
            .concat(list.map(n => ({ node: n.name, name: nice(n), pw: n })))
            .concat(headsets.map(h => ({ node: h.card, name: h.name, pw: nodeOf(h.card), bt: true })))
    }
    property var headsets: []                  // [{ card, name, profile, headset }]
    function nice(n) { return n.nickname || n.description || n.name }
    // A headset's source in its headset profile: bluez_input.34_0E… or …34:0E…, by the card's address
    function isSourceOf(n, card) {
        const addr = card.replace(/^bluez_card\./, "")
        return (n.name || "").startsWith("bluez_input.") && n.name.replace(/:/g, "_").includes(addr)
    }
    function nodeOf(name) {
        if (!name) return Pipewire.defaultAudioSource
        if (name.startsWith("bluez_card.")) return Pipewire.nodes.values.find(n => isSourceOf(n, name)) || null
        return Pipewire.nodes.values.find(n => n.name === name) || null
    }
    // A mic gone (unplugged) still has its node name: shown as it is, so it is clear what was picked
    function nameOf(name) {
        if (!name) return "Default"
        const h = headsets.find(h => h.card === name)
        if (h) return h.name
        if (name.startsWith("bluez_card.")) return "Bluetooth headset (not connected)"
        const n = nodeOf(name)
        return n ? nice(n) : name + " (not connected)"
    }
    Process {
        id: headsetList
        command: [Quickshell.shellDir + "/../bin/recorder", "headsets", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { p.headsets = JSON.parse(text) } catch (e) {} } }
    }
    Component.onCompleted: headsetList.running = true

    function open() {
        headsetList.running = true             // one connected since
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
                implicitHeight: modelData.bt ? 46 : 34
                c: p.c
                selected: index === p.cursor
                TapHandler { onTapped: p.choose(index) }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.g(modelData.node === p.current ? "check" : modelData.bt ? "bluetooth" : "mic")
                    font.family: Icons.family; font.pixelSize: 14
                    color: modelData.node === p.current ? p.c.accent : p.c.dim
                }
                Column {
                    anchors.left: parent.left; anchors.leftMargin: 36
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight; textFormat: Text.PlainText
                        text: modelData.name
                        font.family: p.c.font; font.pixelSize: 13
                        color: p.c.title
                    }
                    Text {
                        visible: !!modelData.bt
                        width: parent.width
                        elide: Text.ElideRight
                        text: "Bluetooth: playback is poorer while it records"
                        font.family: p.c.font; font.pixelSize: 11
                        color: p.c.faint
                    }
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
