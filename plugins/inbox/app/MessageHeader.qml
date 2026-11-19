import QtQuick
import qs
import qs.kit

// The open message's header, at the top of what scrolls: its title, large and whole, then who sent it and when, and the
// sender's own buttons: its session (to go back to it) and its task, which the message needs no button of its own for.
// A click on the sender narrows the list to that session's or app's messages. A message neither from a Claude session
// nor an app says so in the danger colour: nothing says who left it, so its buttons deserve a second look.
Column {
    id: root
    required property QtObject c
    property var message: null           // Store.message
    signal fromPicked(string key, string label)
    signal press(string which)           // "session" or "task": the sender's own (config/inbox/press.py)
    spacing: 8
    readonly property var sender: message ? message.sender || {} : ({})
    readonly property var from: message ? message.from || {} : ({})

    Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: root.message ? root.message.title : ""
        font.family: root.c.font; font.pixelSize: 22; font.weight: Font.Medium; font.letterSpacing: -0.2
        lineHeight: 1.1
        color: root.c.title
    }
    // Who, then when (the update's time when it was added to): wrapped as a line of words in a narrow view
    Flow {
        width: parent.width
        spacing: 12
        Text {
            id: fromText
            width: Math.min(implicitWidth, root.width)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: (root.sender.kind === "other" ? root.sender.short : root.sender.label) || ""
            font.family: root.c.font; font.pixelSize: 12
            font.underline: fromHover.hovered
            color: root.sender.kind === "other" ? root.c.danger : root.c.dim
            HoverHandler { id: fromHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.fromPicked(root.sender.session, root.sender.short) }
        }
        Text {
            textFormat: Text.PlainText
            text: !root.message ? "" : Regional.format(new Date(root.message.updated || root.message.at), "medium")
                + "  " + Regional.format(new Date(root.message.updated || root.message.at), "time")
                + (root.message.updated && root.message.updated !== root.message.at ? "  (added to)" : "")
            font.family: root.c.font; font.pixelSize: 12; color: root.c.faint
        }
    }
    Text {
        visible: root.sender.kind === "other"
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: "Not from a Claude session or an app: look at what its buttons do before you press them."
        font.family: root.c.font; font.pixelSize: 11; color: root.c.danger
    }
    Row {
        visible: root.from.kind === "claude" || !!(root.message && root.message.task)
        spacing: 8
        topPadding: 2
        AppButton {
            visible: root.from.kind === "claude"
            c: root.c; glyph: "bot"; label: "Session"; tipAlign: "left"
            tip: "Go back to the session that left it (its terminal, or resumed in a new one)"
            onClicked: root.press("session")
        }
        AppButton {
            visible: !!(root.message && root.message.task)
            c: root.c; glyph: "list-checks"; label: root.message && root.message.task ? "#" + root.message.task : ""
            tip: "Open the task"; tipAlign: "left"
            onClicked: root.press("task")
        }
    }
}
