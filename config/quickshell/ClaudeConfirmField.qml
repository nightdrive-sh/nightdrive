import QtQuick

// One argument on Claude's confirmation card (ClaudeConfirm.qml): a short value on the label's line, a long one (a
// mail's text, a list of recipients, JSON) in a box of its own under the label, with its length when it runs to several
// lines, so text pushed far down the box isn't missed. The value is a tool's argument, i.e. whatever Claude wrote or
// read: it is shown as plain text, never as markup (confirm.py has already spelled out the characters that hide or
// reorder text).
Column {
    id: f
    property var entry: ({})            // { label, text, long, mono, lines, chars } from confirm.py
    spacing: 6

    readonly property real labelWidth: 96

    // Short: label and value side by side
    Row {
        visible: !f.entry.long
        width: parent.width
        spacing: 10
        Text {
            width: f.labelWidth
            text: f.entry.label || ""
            textFormat: Text.PlainText
            color: Theme.dim
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: 12 }
        }
        Text {
            width: parent.width - f.labelWidth - 10
            text: f.entry.text || ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.title
            font { family: Theme.font; pixelSize: 13 }
        }
    }

    // Long: the label and its length, then the whole value
    Row {
        visible: f.entry.long === true
        width: parent.width
        spacing: 8
        Text {
            text: f.entry.label || ""
            textFormat: Text.PlainText
            color: Theme.dim
            font { family: Theme.font; pixelSize: 12 }
        }
        Text {
            visible: (f.entry.lines || 0) > 3
            text: f.entry.lines + " lines, " + (f.entry.chars || 0).toLocaleString() + " characters"
            color: Qt.darker(Theme.dim, 1.3)
            font { family: Theme.font; pixelSize: 11 }
        }
    }
    Rectangle {
        visible: f.entry.long === true
        width: parent.width
        height: value.implicitHeight + 20
        radius: 8
        color: Theme.card
        Text {
            id: value
            x: 12; y: 10
            width: parent.width - 24
            text: f.entry.text || ""
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            color: Qt.lighter(Theme.text, 1.12)
            lineHeight: 1.15
            font { family: f.entry.mono ? "monospace" : Theme.font; pixelSize: 13 }
        }
    }
}
