import QtQuick
import qs
import qs.kit
import "Words.js" as Words

// An area in full (› on its row): each right's choice and every tool under it in plain words, with which ones always
// ask and which come with Undo, so nothing Claude can do here is hidden behind a summary. The area's own finer
// choices (Contacts' fields, Mail's block list, the apps whose windows Claude may see, Home Assistant's: Dashboard
// #1789, #1830, #1832) go in this panel, under the rights.
AppPanel {
    id: root
    property var area: null
    cardWidth: 580
    visible: area !== null
    onOutsideTapped: area = null

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_Left || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            area = null
            e.accepted = true
        }
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

    Text {
        visible: !!root.area && !!root.area.rights.read && root.area.rights.read.value !== "no"
        width: parent.width
        text: "What these read goes to Anthropic with Claude's answer."
        wrapMode: Text.Wrap
        color: root.c.dim
        font { family: root.c.font; pixelSize: 12 }
    }
}
