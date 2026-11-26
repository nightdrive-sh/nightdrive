import QtQuick

// A web page Claude found or drew on (AskClaudeResults.qml, #2245): its address, cut in the middle when long so both the
// site and the page's end show, and Open, which opens it in the browser. Nothing is downloaded: the card is the address.
AskClaudeCard {
    id: c
    glyph: "globe"

    Item {
        width: parent.width
        height: 28
        Text {
            anchors { left: parent.left; right: open.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            // The address without its scheme, which says nothing here
            text: String(c.card.url || "").replace(/^https?:\/\//i, "")
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: Theme.muted
            font { family: Theme.font; pixelSize: 12 }
        }
        AskClaudeCardButton {
            id: open
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            glyph: "external-link"
            label: "Open"
            compact: parent.width < 260
            onClicked: c.openSource()
        }
    }
}
