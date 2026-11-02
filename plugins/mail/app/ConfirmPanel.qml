import QtQuick
import qs.kit

// Asks before what can't be undone (deleting for good, Actions.qml sets win.confirm): Enter does it, Esc or a click
// outside doesn't. Apart from shell.qml, which shows it over the window.
AppPanel {
    required property var win
    visible: win.confirm !== null
    c: win.look
    cardWidth: 520
    onOutsideTapped: win.confirm = null
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { const run = win.confirm.run; win.confirm = null; run() }
        else if (e.key === Qt.Key_Escape) win.confirm = null
        e.accepted = true
    }
    Text { textFormat: Text.PlainText; text: win.confirm ? win.confirm.title : ""; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
    Text { textFormat: Text.PlainText; width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2; text: win.confirm ? win.confirm.detail : ""; color: c.text; font.family: c.font; font.pixelSize: 12 }
    Row {
        spacing: 18
        AppKeyAction {
            c: win.look
            keys: "⏎"; label: win.confirm ? win.confirm.action : ""; color: c.danger; hoverColor: c.title
            onClicked: { const run = win.confirm.run; win.confirm = null; run() }
        }
        AppKeyAction { c: win.look; keys: "esc"; label: "Cancel"; onClicked: win.confirm = null }
    }
}
