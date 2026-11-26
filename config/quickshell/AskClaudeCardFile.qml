import QtQuick
import "AskClaudeCards.js" as Cards

// Any other file Claude downloaded (a PDF, a zip; AskClaudeResults.qml, #2245): its name, type and size, and Save into
// Downloads. It isn't opened from here: a zip isn't unpacked, and what a file holds is the user's to open once saved.
AskClaudeCard {
    id: c
    glyph: Cards.kind(card) === "ZIP" ? "file-archive" : "file-text"

    Item {
        width: parent.width
        height: 28
        Text {
            anchors { left: parent.left; right: save.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: [c.card.file, Cards.kind(c.card), Cards.size(c.card.size)].filter(t => t).join(" · ")
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: Theme.muted
            font { family: Theme.font; pixelSize: 12 }
        }
        AskClaudeCardButton {
            id: save
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            compact: parent.width < 260
            glyph: "download"
            label: done ? "Saved" : "Save"
            done: !!c.saved && !c.saved.error
            onClicked: c.session.save(c.card.file)
        }
    }
}
