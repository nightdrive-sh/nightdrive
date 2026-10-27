import QtQuick

// Where the Claude writes card goes (ClaudeWrite.qml), fixed when ⌘⇧C is pressed: in the middle of the window the key
// was pressed in. The mouse is no guide to where the text is (a selection made with the keyboard, a mouse moved since),
// and a caret's line put the card off to the side (#1696), so the window decides: of a window in a grid, its middle,
// near the text it holds; of a window that covers most of the screen (one window, a big floating one), the screen's.
// The card's top stays put and it grows down as Claude's text comes, so it doesn't jump; `room` says how tall it may
// get before it would leave the screen (the card scrolls its text instead).
QtObject {
    property rect window: Qt.rect(0, 0, 0, 0) // in the screen's coordinates; empty: the screen's middle
    property real screenWidth: 0
    property real screenHeight: 0
    property real width: 0                  // the card's size now
    property real height: 0

    readonly property real margin: 16       // from the screen's edges
    readonly property real usual: 300       // a card with a few lines of text: centred at this height
    readonly property real most: 0.66       // a window this much of the screen's width and height counts as all of it

    readonly property bool whole: window.width >= screenWidth * most && window.height >= screenHeight * most
    readonly property rect area: whole || window.width <= 0 ? Qt.rect(0, 0, screenWidth, screenHeight) : window
    readonly property real top: Math.max(margin, area.y + (area.height - usual) / 2)

    readonly property real room: Math.max(0, screenHeight - margin - top)
    readonly property real x: Math.max(margin, Math.min(area.x + (area.width - width) / 2, screenWidth - width - margin))
    readonly property real y: Math.max(margin, Math.min(top, screenHeight - height - margin))
}
