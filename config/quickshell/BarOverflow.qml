import QtQuick

// The "…" left of the top bar's modules when some don't fit beside the workspaces (a narrow screen; Bar.qml tucks them
// away): a click opens OverflowMenu.qml, which lists them. Drawn like an icon-only BarModule.
Item {
    id: more
    property bool open: false               // its menu, or the menu of a module in it, is open
    property real dpr: 1
    signal clicked(real centerX)

    readonly property var isz: TopBar.size("icon")
    readonly property color fg: open ? TopBar.c("hlFg") : TopBar.c("fg")
    function snap(v) { return Math.round(v * dpr) / dpr }

    width: Math.max(34, 8 + isz.size + 8)
    height: 27

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: more.open ? TopBar.c("hlBg") : "transparent"
    }
    Image {
        width: more.isz.size; height: more.isz.size
        x: more.snap((more.width - width) / 2)
        y: more.snap((more.height - height) / 2)
        sourceSize: Qt.size(Math.ceil(width * more.dpr), Math.ceil(height * more.dpr))
        source: TopBar.iconUrl("ellipsis", more.fg)
        opacity: more.fg.a
        smooth: true
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: more.clicked(more.mapToItem(null, more.width / 2, 0).x)
    }
}
