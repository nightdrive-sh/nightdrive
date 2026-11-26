import QtQuick

// A section title inside a menu (e.g. "MACHINES"): capitals in the theme colour, smaller than the menu's own header.
// An optional subtitle on the right, dimmed as in MenuHeader (e.g. what the numbers below it mean). Menus have no
// dividers between sections: `apart: true` gives a section after other content more room above instead.
Text {
    id: s
    property string title: ""
    property string subtitle: ""
    // apart: a section after other content (meters, a list) gets more room above, which sets it apart without a divider
    property bool apart: false
    width: parent ? parent.width : 0
    topPadding: apart ? 20 : 6
    text: title.toUpperCase()
    textFormat: Text.PlainText   // a title may be a device's name: never markup
    color: Theme.primary
    font { family: Theme.font; pixelSize: 11; letterSpacing: 0.6 }
    Text {
        visible: s.subtitle !== ""
        anchors { right: parent.right; baseline: parent.baseline }
        text: s.subtitle.toUpperCase()
        textFormat: Text.PlainText
        color: Theme.dim
        font { family: Theme.font; pixelSize: 10; letterSpacing: 0.6 }
    }
}
