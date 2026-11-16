import QtQuick

// One more icon and text in a top bar module, after its own (the status's "more": Claude's gauge for each account,
// claude-bar): the module's sizes, and its colours by a class of its own, so one account's gauge can warn alone.
Item {
    id: part
    property string icon: ""
    property string label: ""
    property string cls: ""
    property bool lit: false             // the module's menu is open or it is active: the highlight colour
    property real dpr: 1
    property real size: 16               // the icon's square (adjust.conf, as the module's)
    property int gap: 5
    readonly property color fg: TopBar.fg(cls, lit)
    function snap(v) { return Math.round(v * dpr) / dpr }

    height: parent ? parent.height : 0
    // whole device pixels, so the next part starts on one too
    width: Math.ceil(((icon ? size : 0) + (icon && label ? gap : 0) + (label ? txt.implicitWidth : 0)) * dpr) / dpr

    Image {
        id: img
        visible: part.icon !== ""
        width: part.icon ? part.size : 0; height: part.size
        y: part.snap((part.height - height) / 2)
        sourceSize: Qt.size(Math.ceil(part.size * part.dpr), Math.ceil(part.size * part.dpr))
        source: part.icon ? TopBar.iconUrl(part.icon, part.fg) : ""
        opacity: part.fg.a
        smooth: true
        cache: false
    }
    BarText {
        id: txt
        visible: part.label !== ""
        text: part.label
        color: part.fg
        dpr: part.dpr
        x: part.snap(part.icon ? img.width + part.gap : 0)
    }
}
