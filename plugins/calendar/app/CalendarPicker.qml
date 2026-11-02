import QtQuick

// The calendar a new event goes in: the calendars that take events (not read-only: an ICS address, a read-only account)
// as chips with their colour, one picked. A row of chips rather than a menu, as people have a handful of calendars and
// see them all at once. Tab reaches it; ← → move the pick, as the arrows do in the rest of the window.
FocusScope {
    id: root
    required property QtObject c
    property var calendars: []          // [{ id, name, color }], the writable ones
    property string picked: ""          // the id
    signal accepted()                   // ⏎: the panel saves
    signal escaped()
    activeFocusOnTab: true
    implicitHeight: label.implicitHeight + 6 + flow.implicitHeight
    implicitWidth: flow.implicitWidth

    function step(n) {
        const i = calendars.findIndex(x => x.id === picked)
        const next = Math.max(0, Math.min(calendars.length - 1, i + n))
        if (calendars.length) picked = calendars[next].id
    }
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Left || e.key === Qt.Key_H) step(-1)
        else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) step(1)
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) accepted()
        else if (e.key === Qt.Key_Escape) escaped()
        else return
        e.accepted = true
    }

    Text { id: label; text: "Calendar"; color: root.c.title; font.family: root.c.font; font.pixelSize: 13 }
    Flow {
        id: flow
        y: label.implicitHeight + 6
        width: root.width
        spacing: 6
        Repeater {
            model: root.calendars
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: modelData.id === root.picked
                width: row.implicitWidth + 22; height: 30; radius: 7
                color: on ? root.c.sel : hover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                // The frame shows where the keys are: on the picked chip while the picker has the focus
                border.color: on && root.activeFocus ? root.c.primary : root.c.line
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.picked = chip.modelData.id; root.forceActiveFocus() } }
                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9; height: 9; radius: 5
                        color: chip.modelData.color || root.c.dim
                    }
                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.name
                        color: chip.on ? root.c.title : root.c.text; font.family: root.c.font; font.pixelSize: 12
                    }
                }
            }
        }
    }
}
