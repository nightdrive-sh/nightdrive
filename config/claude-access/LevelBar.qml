import QtQuick
import qs
import qs.kit
import "Words.js" as Words

// The top of the window: the level (Strict, Normal, Open), which sets every choice below; how many of them are the
// user's own; and the two things every user should know before choosing: what Claude reads goes to Anthropic, and
// these limits are only Nightdrive's (Claude Code's own Bash and file tools have their own permissions).
Column {
    id: root
    required property QtObject c
    property string level: ""
    property int own: 0
    signal picked(string level)
    spacing: 10

    Row {
        spacing: 8
        Text {
            width: 56
            anchors.verticalCenter: parent.verticalCenter
            text: "Level"; color: root.c.dim
            font { family: root.c.font; pixelSize: 12 }
        }
        Repeater {
            model: Words.LEVELS
            AppButton {
                required property var modelData
                required property int index
                c: root.c
                glyph: modelData.id === root.level ? "check" : ""
                label: modelData.name
                strong: modelData.id === root.level
                tip: modelData.about
                keys: "⌘" + (index + 1)
                tipAlign: "left"
                onClicked: root.picked(modelData.id)
            }
        }
        Text {
            visible: root.own > 0
            leftPadding: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.own + (root.own === 1 ? " choice of your own" : " choices of your own")
            color: root.c.primary
            font { family: root.c.font; pixelSize: 12 }
        }
    }
    Text {
        width: root.width
        text: (Words.LEVELS.find(l => l.id === root.level) || { about: "" }).about
        wrapMode: Text.Wrap
        color: root.c.text
        font { family: root.c.font; pixelSize: 12 }
    }
    Text {
        width: root.width
        text: "What Claude reads goes to Anthropic, Claude's maker, to answer you. These choices cover only "
            + "Nightdrive's tools: what Claude Code may do with its own (commands, files) is set in Claude Code."
        wrapMode: Text.Wrap
        color: root.c.dim
        font { family: root.c.font; pixelSize: 12 }
    }
}
