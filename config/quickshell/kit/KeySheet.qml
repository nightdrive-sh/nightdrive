import QtQuick
import qs

// The keys of a window, shown by ? or Ctrl+? (GNOME's key for an app's shortcuts) until any other key. The window passes
// its key events to pressed(): the keys its own handlers leave alone (Ctrl+? among them, and ? from where nothing takes
// it). No ⌘ hold: ⌘ drags windows and starts the apps' shortcuts, so a hold showed the sheet by accident. Nightdrive's apps
// (Mail, Deck) share it, with the rest of the apps' kit (README.md).
Rectangle {
    id: root
    required property QtObject c
    property var groups: []             // [{ title, keys: [[key, what], …] }, …]
    // The keys stay their size, as small ones are hard to read: a sheet too tall for the window scrolls. As many columns
    // as fit side by side (and fill every row), two when they show it all, else the most, which scroll least; one in a
    // narrow window, where the descriptions wrap rather than the keys shrinking.
    readonly property int columns: {
        const n = groupRows.count
        if (narrow) return 1
        let best = 1, bestH = Infinity
        for (let cols = 1; cols <= n; cols++) {
            if (n % cols !== 0) continue        // full rows only: no group left on a row of its own
            let w = 0, h = 0
            for (let r = 0; r < n; r += cols) {
                let rowH = 0
                for (let i = r; i < Math.min(n, r + cols); i++) {
                    const g = groupRows.itemAt(i)
                    if (!g) return best
                    w = Math.max(w, g.natural); rowH = Math.max(rowH, g.implicitHeight)
                }
                h += rowH
            }
            h += (Math.ceil(n / cols) - 1) * grid.rowSpacing + 2 * padV
            if (cols * w + (cols - 1) * grid.columnSpacing + 2 * pad > width - 32) break
            if (cols === 2 && h <= height - 32) return 2
            if (h < bestH) { best = cols; bestH = h }
        }
        return best
    }
    // Narrower than one column: the card's sides close in, the keys get 40 % of the width at most and a description wraps,
    // going under keys too wide for theirs
    readonly property real natural: {
        let w = 0
        for (let i = 0; i < groupRows.count; i++) { const g = groupRows.itemAt(i); if (g) w = Math.max(w, g.natural) }
        return w
    }
    readonly property bool narrow: natural + 80 > width - 32
    readonly property int pad: narrow ? 24 : 40           // the card's sides
    readonly property int padV: narrow ? 24 : 36          // its top and bottom
    readonly property real room: width - 32 - 2 * pad      // a group's width in a narrow window
    property bool shown: false

    readonly property var modifierKeys: [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R]
    function pressed(e) {
        if (e.key === Qt.Key_Question) { shown = !shown; e.accepted = true }
        else if (modifierKeys.indexOf(e.key) < 0) shown = false       // Shift, on the way to ?, keeps it
    }

    anchors.fill: parent
    visible: shown
    color: root.c.scrim
    onShownChanged: flick.contentY = 0
    FontMetrics { id: line; font.family: root.c.font; font.pixelSize: 12 }
    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: Math.max(height, card.height + 32)
        boundsBehavior: Flickable.StopAtBounds
        TouchScroll { view: flick }
        // A click outside the keys closes them; one on them keeps them
        Item {
            width: flick.width; height: flick.contentHeight
            TapHandler { onTapped: root.shown = false }
            Rectangle {
                id: card
                TapHandler {}
                x: (parent.width - width) / 2
                y: Math.max(16, (parent.height - height) / 2)
                width: grid.implicitWidth + 2 * root.pad
                height: grid.implicitHeight + 2 * root.padV
                radius: 14
                color: root.c.solid
                border.color: root.c.line
                Grid {
                    id: grid
                    anchors.centerIn: parent
                    columns: root.columns
                    columnSpacing: 56
                    rowSpacing: 32
                    Repeater {
                        id: groupRows
                        model: root.groups
                        delegate: Column {
                            id: group
                            required property var modelData
                            property real keyWidth: 0       // the group's widest keys: the descriptions start right after them
                            property real textWidth: 0      // its longest description, unwrapped
                            readonly property real natural: keyWidth + 20 + textWidth
                            readonly property real keyColumn: root.narrow ? Math.min(keyWidth, root.room * 0.4) : keyWidth
                            width: root.narrow ? root.room : natural
                            spacing: 10
                            Text { text: modelData.title; color: root.c.title; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium; bottomPadding: 4 }
                            Repeater {
                                model: modelData.keys
                                delegate: Item {
                                    required property var modelData
                                    readonly property bool under: cap.implicitWidth > group.keyColumn
                                    width: group.width
                                    height: under ? 26 + what.height : Math.max(22, what.y + what.height)
                                    KeyCap {
                                        id: cap
                                        y: (22 - height) / 2
                                        c: root.c; keys: modelData[0]; tint: root.c.accent; or: true
                                        onImplicitWidthChanged: group.keyWidth = Math.max(group.keyWidth, implicitWidth)
                                    }
                                    Text {
                                        id: what
                                        x: group.keyColumn + 20
                                        y: parent.under ? 26 : (22 - line.height) / 2
                                        width: group.width - x
                                        wrapMode: Text.WordWrap
                                        text: modelData[1]; color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
                                        onImplicitWidthChanged: group.textWidth = Math.max(group.textWidth, implicitWidth)
                                        Component.onCompleted: group.textWidth = Math.max(group.textWidth, implicitWidth)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
