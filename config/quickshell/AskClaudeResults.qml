import QtQuick
import "AskClaudeCards.js" as Cards

// The result cards of one turn of Ask Claude's conversation (#2245, #2225), under its answer in AskClaudeThread: what
// Claude added with results_add (config/mcp/results.py) while the turn ran, from AskClaudeSession.cards. Each type has
// a card of its own on AskClaudeCard's frame: a sound to play (AskClaudeCardSound), a picture to look at
// (AskClaudeCardImage), a page to open (AskClaudeCardPage), a file to save (AskClaudeCardFile). The running turn's
// cards come in as Claude adds them (to: Infinity).
Column {
    id: r
    property double from: 0              // the turn's start and end, ms (AskClaudeCards.during)
    property double to: Infinity
    property var player: null            // the conversation's one player (kit's AppAudio, in AskClaudeThread)
    property int fontSize: 17
    property bool active: true           // false: an entry that isn't a turn's results, which shows none

    readonly property var cards: active ? Cards.during(AskClaudeSession.cards, from, to) : []
    spacing: 8
    visible: cards.length > 0

    Repeater {
        model: r.cards
        Loader {
            id: slot
            required property var modelData
            width: r.width
            sourceComponent: modelData.type === "sound" ? sound : modelData.type === "image" ? image
                           : modelData.type === "page" ? page : file

            Component { id: sound; AskClaudeCardSound { card: slot.modelData; player: r.player; fontSize: r.fontSize } }
            Component { id: image; AskClaudeCardImage { card: slot.modelData; fontSize: r.fontSize } }
            Component { id: page; AskClaudeCardPage { card: slot.modelData; fontSize: r.fontSize } }
            Component { id: file; AskClaudeCardFile { card: slot.modelData; fontSize: r.fontSize } }
        }
    }
}
