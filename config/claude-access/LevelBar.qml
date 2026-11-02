import QtQuick
import qs
import qs.kit
import "Words.js" as Words

// The top of the window: the level (Strict, Normal, Open), which sets every choice below, or Custom once the user has
// changed any of them (#1902: a changed level isn't that level any more); and the two things every user should know before choosing: what Claude reads goes to Anthropic, and
// these limits are only Nightdrive's (Claude Code's own Bash and file tools have their own permissions).
Column {
    id: root
    required property QtObject c
    property string level: ""
    property int own: 0
    readonly property string levelName: (Words.LEVELS.find(l => l.id === level) || { name: level }).name
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
                readonly property bool chosen: modelData.id === root.level && root.own === 0
                glyph: chosen ? "check" : ""
                label: modelData.name
                strong: chosen
                tip: modelData.about
                keys: "⌘" + (index + 1)
                tipAlign: "left"
                onClicked: root.picked(modelData.id)
            }
        }
        // Not a level to pick: what the user's own choices made of one. A level button puts them back (it asks first).
        AppButton {
            visible: root.own > 0
            c: root.c
            glyph: "check"
            label: "Custom"
            strong: true
            tip: root.own + (root.own === 1 ? " choice of your own" : " choices of your own") + ", from " + root.levelName
            tipAlign: "left"
        }
    }
    Text {
        width: root.width
        text: root.own === 0 ? (Words.LEVELS.find(l => l.id === root.level) || { about: "" }).about
            : "Custom: " + root.levelName + " with " + root.own + (root.own === 1 ? " choice" : " choices")
              + " of your own, each marked with a dot below. Picking a level puts them back to the level's."
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
