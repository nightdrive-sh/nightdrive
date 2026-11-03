import QtQuick

// A hint, error or empty-state line in a menu ("Bluetooth is off", "No devices", a command's error message): one size and
// colour for all of them, wrapped at the menu's width. variant: "dim" (default), "warning" or "danger".
Text {
    property string variant: "dim"
    width: parent ? parent.width : 0
    visible: text !== ""   // an empty note takes no room (a menu's own visible: replaces this)
    wrapMode: Text.Wrap
    textFormat: Text.PlainText   // often a command's error or another device's words: never markup
    color: variant === "danger" ? Theme.danger : variant === "warning" ? Theme.warning : Theme.dim
    font { family: Theme.font; pixelSize: 12 }
}
