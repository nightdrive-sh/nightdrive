import QtQuick

// A list row's ground, for a ListView's delegate: the selected row's colour, or the fainter hover colour for the keyboard's
// place while the list isn't focused (marked) and under the pointer. It fills the list's width; what it shows goes inside.
Rectangle {
    id: root
    required property QtObject c
    property bool selected: false
    property bool marked: false
    property bool active: false         // the keys are in this list (Tab moves them between it and the sidebar): a frame
    readonly property alias hovered: hover.hovered
    width: ListView.view ? ListView.view.width : implicitWidth
    radius: 8
    color: selected ? c.sel : marked || hovered ? c.hover : "transparent"
    border.color: selected && active ? c.frame : "transparent"
    border.width: selected && active ? 2 : 1
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
}
