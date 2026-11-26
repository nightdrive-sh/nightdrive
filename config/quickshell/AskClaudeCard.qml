import QtQuick
import "AskClaudeCards.js" as Cards

// One result card's frame in Ask Claude's conversation (AskClaudeResults.qml, #2245): its type's glyph and title, the
// type's own part (content: a player, a picture, an address, a file's size), then where it came from: the page's
// domain (a click opens the page, where its licence is), the licence as a chip and whom to credit, and Claude's note.
// The licence chip is the point of the card's last line: "unknown" in the warning colour, so nothing reads as free to
// use without someone's word for it (AskClaudeCards.licenceTone).
// A downloaded file's Save (in the type's part: saved and session here) goes through AskClaudeSession.save, which
// keeps how it went for the card's line under its part: where it was saved, or why it wasn't.
Rectangle {
    id: c
    required property var card           // a card of results.json (config/mcp/results.py)
    property string glyph: "file"
    property int fontSize: 17
    default property alias content: slot.data

    // --- Tunables ---
    readonly property int pad: 12
    readonly property int gap: 8

    readonly property string domain: Cards.domain(card.url)
    readonly property string tone: Cards.licenceTone(card.licence)
    readonly property var session: AskClaudeSession
    readonly property var saved: card.file ? session.saved[card.file] : undefined   // {name} or {error}; undefined before
    readonly property string path: card.file ? session.filesDir + "/" + card.file : ""

    implicitHeight: col.implicitHeight + 2 * pad
    radius: 10
    color: Theme.card

    function openSource() { if (/^https?:\/\//i.test(card.url || "")) Qt.openUrlExternally(card.url) }

    Column {
        id: col
        x: c.pad; y: c.pad
        width: c.width - 2 * c.pad
        spacing: c.gap

        Row {
            width: parent.width
            spacing: 10
            Text {
                id: mark
                anchors.top: parent.top
                anchors.topMargin: 1
                text: Icons.g(c.glyph)
                color: Theme.accent
                font { family: Icons.family; pixelSize: 16 }
            }
            Text {
                width: parent.width - mark.width - 10
                text: c.card.title || ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.title
                font { family: Theme.font; pixelSize: c.fontSize - 3; weight: Font.Medium }
            }
        }

        Item {
            id: slot
            width: parent.width
            height: childrenRect.height
            visible: children.length > 0
        }
        Text {
            visible: !!c.saved
            width: parent.width
            text: !c.saved ? "" : c.saved.error ? c.saved.error : "Saved to Downloads as " + c.saved.name
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: c.saved && c.saved.error ? Theme.warning : Theme.ok
            font { family: Theme.font; pixelSize: 12 }
        }

        // Where it came from: wraps under itself on a narrow screen
        Flow {
            width: parent.width
            spacing: 8
            Text {
                id: source
                height: 20
                verticalAlignment: Text.AlignVCenter
                text: c.domain || "unknown source"
                textFormat: Text.PlainText
                color: sourceHover.hovered ? Theme.text : Theme.dim
                font { family: Theme.font; pixelSize: 12; underline: sourceHover.hovered }
                HoverHandler { id: sourceHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: c.openSource() }
            }
            Rectangle {
                height: 20
                width: chip.implicitWidth + 14
                radius: 10
                color: "transparent"
                border { width: 1; color: c.tone === "free" ? Theme.ok : c.tone === "unknown" ? Theme.warning : Theme.border }
                Text {
                    id: chip
                    anchors.centerIn: parent
                    text: c.tone === "unknown" ? "Licence unknown" : c.card.licence
                    textFormat: Text.PlainText
                    color: c.tone === "free" ? Theme.ok : c.tone === "unknown" ? Theme.warning : Theme.muted
                    font { family: Theme.font; pixelSize: 11 }
                }
            }
            Text {
                visible: !!c.card.author
                height: 20
                verticalAlignment: Text.AlignVCenter
                text: "by " + (c.card.author || "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                width: Math.min(implicitWidth, col.width)
                color: Theme.dim
                font { family: Theme.font; pixelSize: 12 }
            }
        }

        Text {
            visible: !!c.card.note
            width: parent.width
            text: c.card.note || ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.dim
            font { family: Theme.font; pixelSize: 12 }
        }
    }

}
