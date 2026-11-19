import QtQuick
import qs.kit

// The card before a run button runs (#3132's decision): the whole command, the folder it runs in and who asked for it,
// and only Enter (or Run) runs it, as an argv without a shell (config/inbox/press.py with --yes). Esc or a click outside
// cancels. Everything on it is plain text: the command is the sender's, and nothing in it may style or hide itself.
AppPanel {
    id: root
    property var action: null            // the run button: { label, argv, dir, line }
    property string sender: ""           // the message's sender line
    property bool unknown: false         // not from a Claude session or an app
    signal answered(bool ok)
    cardWidth: 560
    onOutsideTapped: answered(false)
    onVisibleChanged: if (visible) forceActiveFocus()
    Keys.onReturnPressed: answered(true)
    Keys.onEnterPressed: answered(true)
    Keys.onEscapePressed: answered(false)
    function ask(action, sender, unknown) {
        root.action = action; root.sender = sender; root.unknown = unknown
        visible = true
    }

    Text {
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: "Run “" + (root.action ? root.action.label : "") + "”?"
        color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
    }
    Label { text: "Command" }
    Rectangle {
        width: parent.width
        height: command.implicitHeight + 20
        radius: 8
        color: root.c.solid
        border.width: 1; border.color: root.c.divider
        Text {
            id: command
            x: 12; y: 10
            width: parent.width - 24
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
            text: root.action ? root.action.line : ""
            font.family: "monospace"; font.pixelSize: 12
            color: root.c.title
        }
    }
    Label { text: "In" }
    Text {
        width: parent.width
        wrapMode: Text.WrapAnywhere
        textFormat: Text.PlainText
        text: root.action ? root.action.dir : ""
        font.family: "monospace"; font.pixelSize: 12
        color: root.c.text
    }
    Text {
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: root.unknown ? "Left by " + root.sender + ", not by a Claude session or an app."
                           : "Left by " + root.sender + ". It runs in the background; its output goes to a log."
        font.family: root.c.font; font.pixelSize: 12
        color: root.unknown ? root.c.danger : root.c.dim
    }
    Row {
        spacing: 8
        AppPanelButton { c: root.c; label: "Run"; strong: true; keys: ["Enter"]; onClicked: root.answered(true) }
        AppPanelButton { c: root.c; label: "Cancel"; keys: ["Esc"]; onClicked: root.answered(false) }
    }

    component Label: Text {
        textFormat: Text.PlainText
        font.family: root.c.font; font.pixelSize: 11; font.weight: Font.Medium
        color: root.c.faint
    }
}
