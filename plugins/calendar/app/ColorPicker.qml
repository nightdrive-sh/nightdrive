import QtQuick
import Quickshell.Io
import qs
import qs.kit

// A calendar's colour (#2031): the theme's colours as swatches, and first the colour its server (or calendars.conf)
// gives it, to go back to. A click, or ⏎ on the swatch the arrows are on, saves it by `calendar color` and closes;
// the window reloads, so every view and the events take it. Esc or a click outside leave it as it was. The palette is
// the command's (lib/colors.py), read once, so the window and `calendar color` offer the same colours.
AppPanel {
    id: root
    required property var app           // the window: command, reload, say
    property var calendar: null         // { id, name, color, custom, own_color }
    property var colorSet: []            // [{ name, color }]
    property int cursor: 0              // the swatch the keys are on: 0 the server's, then the palette's
    property bool busy: false
    signal closed()
    visible: false
    cardWidth: Math.min(520, width - 24)     // the swatches in one row; a narrow window: the card fits in it
    spacing: 16

    // The swatches: the calendar's own colour first, then the palette's (value: what `calendar color` takes)
    readonly property var swatches: calendar
        ? [{ value: "reset", name: "Its own colour", color: calendar.own_color }]
              .concat(colorSet.map(p => ({ value: p.name, name: p.name.charAt(0).toUpperCase() + p.name.slice(1), color: p.color })))
        : []
    // The swatch of the colour the calendar has now: the server's while none is picked
    function current() {
        if (!calendar || !calendar.custom) return 0
        const i = colorSet.findIndex(p => p.color.toLowerCase() === calendar.color.toLowerCase())
        return i < 0 ? -1 : i + 1
    }

    function open(cal) {
        if (!cal || !cal.id) return
        calendar = cal
        cursor = Math.max(0, current())
        visible = true
        forceActiveFocus()
    }
    function close() { if (!busy) { visible = false; closed() } }
    function pick(i) {
        const s = swatches[i]
        if (!s || busy) return
        if (i === current()) { close(); return }
        busy = true
        setter.calendarName = calendar.name
        setter.command = [app.command, "color", "--json", calendar.id, s.value]
        setter.running = true
    }

    onOutsideTapped: close()
    Keys.onPressed: e => {
        const k = e.key
        const n = swatches.length
        if (k === Qt.Key_Escape) close()
        else if (k === Qt.Key_Left || k === Qt.Key_H) cursor = Math.max(0, cursor - 1)
        else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Tab) cursor = Math.min(n - 1, cursor + 1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) cursor = Math.max(0, cursor - grid.perRow)
        else if (k === Qt.Key_Down || k === Qt.Key_J) cursor = Math.min(n - 1, cursor + grid.perRow)
        else if (k === Qt.Key_Home) cursor = 0
        else if (k === Qt.Key_End) cursor = n - 1
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) pick(cursor)
        else if (k >= Qt.Key_0 && k <= Qt.Key_9) pick(k - Qt.Key_0)     // 0 its own colour, 1–9 the palette's first nine
        e.accepted = true
    }

    Process {
        id: paletteReader
        command: [root.app.command, "color", "--json"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { root.colorSet = JSON.parse(text).palette } catch (e) {} } }
    }
    Process {
        id: setter
        property string calendarName: ""
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            root.busy = false
            let r = null
            if (code === 0) try { r = JSON.parse(out.text) } catch (e) {}
            if (!r) {
                root.app.say(err.text.trim().split("\n").pop() || "The colour wasn't saved: calendar log says why.", false, true)
                return
            }
            root.close()
            root.app.reload()
            root.app.colorSaved(r)
        }
    }

    Text {
        textFormat: Text.PlainText
        width: parent.width; wrapMode: Text.Wrap
        text: root.calendar ? "Colour of " + root.calendar.name : ""
        color: c.title; font.family: c.font; font.pixelSize: 16; font.weight: Font.Medium
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap
        text: "On this computer: your phone and other devices keep their own."
        color: c.dim; font.family: c.font; font.pixelSize: 12
    }
    // The swatches in rows that fit the card: a narrow window gets more rows, not a cut row
    Flow {
        id: grid
        width: parent.width
        spacing: 10
        readonly property int size: 34
        readonly property int perRow: Math.max(1, Math.floor((width + spacing) / (size + spacing)))
        Repeater {
            model: root.swatches
            delegate: Item {
                id: sw
                required property var modelData
                required property int index
                readonly property bool picked: index === root.current()
                readonly property bool keyed: index === root.cursor
                width: grid.size; height: grid.size
                // The keys' place: a ring around it in the theme colour, apart from the swatch so its colour reads
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: sw.keyed ? root.c.primary : swHover.hovered ? root.c.line : "transparent"
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: grid.size - 10; height: width; radius: width / 2
                    color: sw.modelData.color
                    // Its own colour is marked apart from the palette's, by a ring of the card inside it
                    border.width: sw.index === 0 ? 3 : 0
                    border.color: root.c.solid
                }
                // The colour it has now: a check over it, dark so it reads on these light colours
                Text {
                    visible: sw.picked
                    anchors.centerIn: parent
                    text: Icons.g("check"); font.family: Icons.family; font.pixelSize: 14
                    color: root.c.solid
                }
                HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.cursor = sw.index }
                TapHandler { onTapped: root.pick(sw.index) }
            }
        }
    }
    // What the swatch under the keys or the pointer is
    Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        readonly property var s: root.swatches[root.cursor]
        text: !s ? "" : root.cursor === 0 ? s.name + ", the one it comes with (" + s.color.toUpperCase() + ")" : s.name
        color: c.text; font.family: c.font; font.pixelSize: 12
    }
    Flow {
        width: parent.width
        spacing: 10
        layoutDirection: Qt.RightToLeft
        AppPanelButton { c: root.c; keys: ["Esc"]; label: "Cancel"; onClicked: root.close() }
        AppPanelButton { c: root.c; keys: ["Enter"]; label: root.busy ? "Saving…" : "Use it"; strong: true; onClicked: root.pick(root.cursor) }
    }
}
