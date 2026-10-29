import QtQuick
import qs
import "Words.js" as Words

// The drop-down of a right: Allow, Ask, No, each with a line on what it means, under the cell it opened from. Only
// the choices the right has (where every tool has consequences, Allow isn't one). ↑↓ and Enter, or 1 2 3, or a click
// choose; Esc or a click outside close it. It fills the window, so a click anywhere else lands here first.
Item {
    id: root
    required property QtObject c
    property string areaName: ""
    property string which: ""
    property var info: null              // the right's { value, choices, tools… }
    property int current: 0
    signal chosen(string value)
    signal closed()
    visible: false
    anchors.fill: parent

    readonly property var choices: info ? info.choices : []
    readonly property bool consequential: !!info && info.choices.indexOf("allow") < 0

    // Shown under (or, near the bottom, over) a point in the window
    function show(areaName, right, info, x, y) {
        root.areaName = areaName; root.which = right; root.info = info
        current = Math.max(0, info.choices.indexOf(info.value))
        card.x = Math.max(8, Math.min(x, width - card.width - 8))
        card.y = y + card.height + 8 < height ? y : Math.max(8, y - card.height - 36)
        visible = true
        forceActiveFocus()
    }
    function close() { visible = false; closed() }
    function pick(i) { if (i >= 0 && i < choices.length) { visible = false; chosen(choices[i]) } }

    Keys.onPressed: e => {
        const k = e.key
        if (k === Qt.Key_Escape || k === Qt.Key_Left || k === Qt.Key_Right) close()
        else if (k === Qt.Key_Down || k === Qt.Key_J) current = Math.min(current + 1, choices.length - 1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) current = Math.max(current - 1, 0)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) pick(current)
        else if (k >= Qt.Key_1 && k <= Qt.Key_3) pick(choices.indexOf(["allow", "ask", "no"][k - Qt.Key_1]))
        else return
        e.accepted = true
    }

    MouseArea { anchors.fill: parent; onClicked: root.close(); onWheel: w => w.accepted = true }

    Rectangle {
        id: card
        width: 340
        height: list.implicitHeight + 20
        radius: 10
        color: root.c.solid
        border.color: root.c.line
        MouseArea { anchors.fill: parent }      // a click on the card's padding keeps it open

        Column {
            id: list
            x: 6; y: 10
            width: parent.width - 12
            spacing: 2
            Text {
                x: 10; width: parent.width - 20
                text: root.areaName + " · " + (Words.RIGHT_NAMES[root.which] || "")
                color: root.c.dim; elide: Text.ElideRight
                font { family: root.c.font; pixelSize: 11 }
                bottomPadding: 4
            }
            Repeater {
                model: root.choices
                Rectangle {
                    id: item
                    required property string modelData
                    required property int index
                    width: list.width
                    height: words.y + words.implicitHeight + 8
                    radius: 7
                    color: index === root.current ? root.c.sel : hover.hovered ? root.c.hover : "transparent"
                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.current = item.index }
                    TapHandler { onTapped: root.pick(item.index) }
                    Text {
                        x: 10; y: 8; width: 16
                        text: root.info && item.modelData === root.info.value ? Icons.g("check") : ""
                        color: root.c.accent
                        font { family: Icons.family; pixelSize: 13 }
                    }
                    Text {
                        x: 30; y: 7
                        text: Words.VALUE_NAMES[item.modelData]
                        color: item.modelData === "ask" ? Theme.warning : root.c.text
                        font { family: root.c.font; pixelSize: 13; weight: Font.DemiBold }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 8 }
                        text: ["allow", "ask", "no"].indexOf(item.modelData) + 1
                        color: root.c.faint
                        font { family: root.c.font; pixelSize: 11 }
                    }
                    Text {
                        id: words
                        x: 30; y: 27; width: parent.width - 40
                        text: Words.choiceText(root.which, item.modelData, root.consequential)
                        wrapMode: Text.Wrap
                        color: root.c.dim
                        font { family: root.c.font; pixelSize: 12 }
                    }
                }
            }
            Text {
                visible: root.consequential
                x: 10; width: parent.width - 20
                topPadding: 6
                text: Words.ALWAYS_ASKS
                wrapMode: Text.Wrap
                color: root.c.faint
                font { family: root.c.font; pixelSize: 11 }
            }
        }
    }
}
