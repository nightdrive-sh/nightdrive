import QtQuick
import qs

// Ferry's menu › a received text dragged out (FerryReceivedRow.qml): the picture under the cursor, the start of the text
// in a small box. A code or a password shows only what it is, as the waiting card does (FerryWaiting.qml): the bar's
// menu may be seen by others, and a drag's picture can linger in a screenshot.
Rectangle {
    id: box
    property string text: ""
    property bool secret: false
    // At most a few lines: a long text is cut, the box only says what is being carried
    readonly property string shown: secret ? "Code or password"
        : text.replace(/\s+/g, " ").trim().slice(0, 160)
    width: Math.min(240, label.implicitWidth + 24)
    height: label.height + 16
    radius: 8
    color: Theme.bg
    border { width: 1; color: Theme.primary }
    Text {
        id: label
        x: 12; y: 8
        width: Math.min(implicitWidth, 216)
        text: box.shown
        // Another device's text: never markup (FerryReceivedRow.qml says why)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        color: box.secret ? Theme.dim : Theme.accent
        font { family: Theme.font; pixelSize: 12; italic: box.secret }
    }
}
