import QtQuick

// One of a few, as chips in a row that wraps, for the panels (the list a new task goes in): a handful people see all at
// once, where a menu would hide them. Tab reaches it; ← → (h l) move the pick, as the arrows do elsewhere in the apps;
// ⏎ comes out as accepted (the panel saves), Esc as escaped. An option with a color gets a dot of it.
FocusScope {
    id: root
    required property QtObject c
    property string label
    property var options: []            // [{ id, name, color? }]
    property string picked: ""          // the id
    signal accepted()
    signal escaped()
    activeFocusOnTab: true
    implicitHeight: (title.visible ? title.implicitHeight + 6 : 0) + flow.implicitHeight
    implicitWidth: flow.implicitWidth

    function step(n) {
        const i = options.findIndex(x => x.id === picked)
        if (options.length) picked = options[Math.max(0, Math.min(options.length - 1, i + n))].id
    }
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Left || e.key === Qt.Key_H) step(-1)
        else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) step(1)
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) accepted()
        else if (e.key === Qt.Key_Escape) escaped()
        else return
        e.accepted = true
    }

    Text { id: title; visible: root.label !== ""; text: root.label; color: root.c.title; font.family: root.c.font; font.pixelSize: 13 }
    Flow {
        id: flow
        y: title.visible ? title.implicitHeight + 6 : 0
        width: root.width
        spacing: 6
        Repeater {
            model: root.options
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: modelData.id === root.picked
                width: row.implicitWidth + 22; height: 30; radius: 7
                color: on ? root.c.sel : hover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                // The frame shows where the keys are: on the picked chip while the chips have the focus
                border.color: on && root.activeFocus ? root.c.primary : root.c.line
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.picked = chip.modelData.id; root.forceActiveFocus() } }
                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        visible: !!chip.modelData.color
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9; height: 9; radius: 5
                        color: chip.modelData.color || "transparent"
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
