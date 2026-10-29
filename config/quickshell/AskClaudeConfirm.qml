import QtQuick
import qs.kit as Kit

// Claude's confirmation card inside Ask Claude's conversation (AskClaudeThread.qml), for a short request while the
// conversation is in view: ClaudeConfirm.qml decides that, and keeps its rules (the countdown, Enter only after a
// moment); this only shows it, compactly. Enter allows and Esc denies, in Ask Claude's field (AskClaudeField.qml), and
// its own buttons for the mouse.
// A long request (a mail's text) gets the full card instead, which wants it read to the end.
Rectangle {
    id: c
    property var card: null              // ClaudeConfirm: req, left, keyArmed
    property int fontSize: 17
    readonly property var req: card ? card.req : ({})

    // An answer as the launcher's footer shows a key: its cap (Kit.Key), then what it does; both bright, as neither is
    // the one to take without reading. A click counts as the key
    component Action: Row {
        id: act
        property string key: ""
        property string label: ""
        signal clicked()
        spacing: 4
        Kit.Key { key: act.key }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 4
            text: act.label
            color: Theme.text
            font { family: Theme.font; pixelSize: 12 }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: act.clicked() }
    }

    height: body.implicitHeight + 24
    radius: 10
    color: Theme.card
    border { color: Theme.warning; width: 1 }

    Column {
        id: body
        x: 14; y: 12
        width: parent.width - 28
        spacing: 10

        Row {
            width: parent.width
            spacing: 10
            Text {
                id: glyph
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.g(c.req.glyph || "shield-alert")
                color: Theme.warning
                font { family: Icons.family; pixelSize: 18 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - glyph.width - 10
                // An act's title says what it does ("Send an email"); an Ask names the kind, then the tool
                text: c.req.heading || "Claude asks to: " + (c.req.title || "")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.title
                font { family: Theme.font; pixelSize: c.fontSize - 3; bold: true }
            }
        }
        Repeater {
            model: c.req.fields || []
            ClaudeConfirmField {
                required property var modelData
                width: body.width
                entry: modelData
            }
        }
        Text {      // what follows from allowing it: a read goes to Anthropic, a change can be undone, a delete maybe not
            visible: !!c.req.note
            width: parent.width
            text: c.req.note || ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.dim
            font { family: Theme.font; pixelSize: 12 }
        }
        Text {
            text: "Denied in " + (c.card ? c.card.left : 0) + " s"
            color: c.card && c.card.left <= 10 ? Theme.warning : Theme.dim
            font { family: Theme.font; pixelSize: 12 }
        }
        // Its buttons under it, on the left where the eye already is; a click counts after the same moment as Enter
        Row {
            spacing: 18      // as between the footer's actions
            Action {
                key: "Enter"; label: "Allow"
                opacity: c.card && c.card.armed ? 1 : 0.4
                onClicked: if (c.card && c.card.armed) c.card.decide("allow")
            }
            Action {
                key: "Esc"; label: "Deny"
                onClicked: if (c.card) c.card.decide("deny")
            }
        }
    }
}
