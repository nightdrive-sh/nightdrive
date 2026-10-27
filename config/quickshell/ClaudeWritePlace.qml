import QtQuick

// Where the Claude writes card goes (ClaudeWrite.qml), fixed when ⌘⇧C is pressed. Where the app tells where its text
// is (Mail's caret), by that line: below it when there is enough room, else above it, else where there is more. The
// side is chosen once, so the card doesn't jump over the line when Claude's text makes it taller: it grows away from
// the line, and `room` says how tall it may get without covering the line or leaving the screen (the card scrolls its
// text instead). Elsewhere the mouse is no guide (a selection made with the keyboard, a mouse moved since), so the card
// goes in the middle of the window the key was pressed in: of a window in a grid, by the text it holds, and of the
// screen when the window covers most of it (one window, a big floating one). Its top stays put and it grows down.
QtObject {
    property bool atLine: false             // true: by `line`; false: in the middle of `window`
    property rect line: Qt.rect(0, 0, 0, 0) // the text's line in the screen's coordinates: a caret, or a line around a point
    property rect window: Qt.rect(0, 0, 0, 0)
    property real screenWidth: 0
    property real screenHeight: 0
    property real width: 0                  // the card's size now
    property real height: 0

    readonly property real margin: 16       // from the screen's edges
    readonly property real gap: 10          // from the line
    readonly property real enough: 300     // a card this tall fits below: the header, a few lines and the buttons
    readonly property real most: 0.66       // a window this much of the screen's width and height counts as all of it

    readonly property real roomBelow: screenHeight - margin - (line.y + line.height + gap)
    readonly property real roomAbove: line.y - gap - margin
    readonly property bool below: roomBelow >= enough || (roomAbove < enough && roomBelow >= roomAbove)

    readonly property bool whole: window.width >= screenWidth * most && window.height >= screenHeight * most
    readonly property rect area: whole || window.width <= 0 ? Qt.rect(0, 0, screenWidth, screenHeight) : window
    // The top of a card of `enough` height centred in the area
    readonly property real top: area.y + (area.height - enough) / 2

    readonly property real room: Math.max(0, !atLine ? screenHeight - margin - Math.max(margin, top)
                                                     : below ? roomBelow : roomAbove)

    readonly property real x: Math.max(margin, Math.min(atLine ? line.x - 24 : area.x + (area.width - width) / 2,
                                                        screenWidth - width - margin))
    readonly property real y: Math.max(margin, Math.min(!atLine ? top
                                                        : below ? line.y + line.height + gap : line.y - gap - height,
                                                        screenHeight - height - margin))

    // A point in a line of text (Mail's caret): the line around it, for a font of the usual size
    function around(px, py) { return Qt.rect(px, py - 12, 0, 24) }
}
