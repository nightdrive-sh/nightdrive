import QtQuick
import qs
import qs.kit
import "Words.js" as Words

// An area in full (› on its row): each right's choice and every tool under it in plain words, with which ones always
// ask and which come with Undo, so nothing Claude can do here is hidden behind a summary. The area's own finer
// choices (Contacts' fields, Mail's block list, the apps whose windows Claude may see, Home Assistant's: Dashboard
// #1789, #1830, #1832) go in this panel, under the rights: on or off each (OptionRow), ↑ ↓ and Space.
AppPanel {
    id: root
    property var area: null             // the row's area as it was when the panel opened
    property QtObject access: null      // the window's Store: the choices below follow what applies after a write
    readonly property var live: area && access ? access.area(area.id) || area : area
    readonly property var options: live && live.options ? live.options : []
    property int pick: 0
    cardWidth: 580
    visible: area !== null
    onOutsideTapped: area = null
    onAreaChanged: pick = 0

    function toggle(i) {
        const o = options[i]
        if (o && access) { pick = i; access.setOption(live.id, o.id, !o.value) }
    }

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_Left || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            area = null
        } else if ((e.key === Qt.Key_Down || e.key === Qt.Key_J) && options.length) {
            pick = Math.min(pick + 1, options.length - 1)
        } else if ((e.key === Qt.Key_Up || e.key === Qt.Key_K) && options.length) {
            pick = Math.max(pick - 1, 0)
        } else if (e.key === Qt.Key_Space) {
            toggle(pick)
        } else {
            return
        }
        e.accepted = true
    }

    Row {
        spacing: 10
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.area ? Icons.g(root.area.glyph) : ""; color: root.c.accent
            font { family: Icons.family; pixelSize: 18 }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.area ? root.area.name : ""; color: root.c.title
            font { family: root.c.font; pixelSize: 16; weight: Font.DemiBold }
        }
    }

    Repeater {
        model: root.area ? Words.RIGHTS.filter(r => root.area.rights[r]) : []
        Column {
            id: right
            required property string modelData
            readonly property var info: root.area.rights[modelData]
            width: parent.width
            spacing: 4
            Text {
                text: Words.RIGHT_NAMES[right.modelData] + " · " + Words.state(right.modelData, right.info)
                      + (right.info.own ? "  (your own; the level's is " + Words.VALUE_NAMES[right.info.preset] + ")" : "")
                color: right.info.value === "ask" ? Theme.warning : root.c.text
                font { family: root.c.font; pixelSize: 13; weight: Font.DemiBold }
            }
            Text {
                visible: !!right.info.words
                width: parent.width
                text: "Claude " + right.info.words + "."
                wrapMode: Text.Wrap
                color: root.c.dim
                font { family: root.c.font; pixelSize: 12 }
            }
            Repeater {
                model: right.info.tools
                Text {
                    required property var modelData
                    x: 12
                    width: right.width - 12
                    text: "• " + modelData.title
                          + (modelData.asks ? "  — always asks" : modelData.undo ? "  — with Undo" : "")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.c.text
                    font { family: root.c.font; pixelSize: 12 }
                }
            }
        }
    }

    // The area's own choices: what its tools may do within the rights above
    Column {
        visible: root.options.length > 0
        width: parent.width
        spacing: 4
        Text {
            text: "Choices"
            color: root.c.text
            font { family: root.c.font; pixelSize: 13; weight: Font.DemiBold }
        }
        Repeater {
            model: root.options
            OptionRow {
                required property var modelData
                required property int index
                width: parent.width
                c: root.c
                option: modelData
                picked: index === root.pick
                onToggled: root.toggle(index)
            }
        }
    }

    Text {
        visible: !!root.area && !!root.area.rights.read && root.area.rights.read.value !== "no"
        width: parent.width
        text: "What these read goes to Anthropic with Claude's answer."
        wrapMode: Text.Wrap
        color: root.c.dim
        font { family: root.c.font; pixelSize: 12 }
    }
}
