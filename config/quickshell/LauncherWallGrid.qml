import QtQuick
import Quickshell
import Quickshell.Widgets

// Settings › Theme › Background: the wallpapers as previews in two columns, the name below and the current one marked
// with ✓, in place of the list. Its selection is the list's (the keys move it), so it only draws.
GridView {
    id: wallGrid
    required property var launcher
    visible: wallGrid.launcher.grid
    width: parent.width
    readonly property int thumbH: Math.round((cellWidth - 12) * 390 / 600)
    cellWidth: width / wallGrid.launcher.gridCols
    cellHeight: thumbH + 40
    height: visible ? Math.min(Math.ceil(wallGrid.launcher.results.length / wallGrid.launcher.gridCols) * cellHeight, 2.2 * cellHeight) : 0
    model: visible ? wallGrid.launcher.results : []
    currentIndex: wallGrid.launcher.topFocused ? -1 : wallGrid.launcher.selIndex
    highlightMoveDuration: 0
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    TouchScroll { view: wallGrid; step: wallGrid.cellHeight }
    delegate: Item {
        id: cell
        required property var modelData
        required property int index
        readonly property bool current: !wallGrid.launcher.topFocused && index === wallGrid.launcher.selIndex
        readonly property bool active: modelData.path === wallGrid.launcher.levels.themes.wallCurrent
        width: wallGrid.cellWidth
        height: wallGrid.cellHeight
        Rectangle {
            id: frame
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            width: parent.width - 12
            height: wallGrid.thumbH
            radius: 8
            color: Theme.bg
            Text {
                visible: cell.modelData.kind === "walladd"
                anchors.centerIn: parent
                text: Icons.g("plus")
                color: cell.current ? Theme.accent : Theme.dim
                font { family: Icons.family; pixelSize: 44 }
            }
            ClippingRectangle {      // preview with rounded corners (frame's inner radius)
                anchors { fill: parent; margins: 3 }
                radius: 6
                color: "transparent"
                Image {
                    anchors.fill: parent
                    source: cell.modelData.thumb ? "file://" + cell.modelData.thumb : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 600
                }
            }
            Rectangle {      // selection frame
                anchors.fill: parent
                radius: 8
                color: "transparent"
                border.width: cell.current ? 3 : 1
                border.color: cell.current ? Theme.accent : Theme.border
            }
            Rectangle {      // current wallpaper
                visible: cell.active
                anchors { top: parent.top; right: parent.right; margins: 10 }
                width: 26; height: 26; radius: 13
                color: Theme.primary
                Text {
                    anchors.centerIn: parent
                    text: Icons.g("check")
                    color: Theme.bg
                    font { family: Icons.family; pixelSize: 16 }
                }
            }
        }
        Text {
            anchors { top: frame.bottom; topMargin: 6; left: frame.left; right: frame.right; leftMargin: 4; rightMargin: 4 }
            elide: Text.ElideRight
            textFormat: Text.PlainText
            readonly property bool armedNow: wallGrid.launcher.armed === "del:" + cell.modelData.path
            text: armedNow ? "⌘⌫ again to delete" : cell.modelData.name + (cell.modelData.group ? "  ·  " + cell.modelData.group : "")
            color: armedNow ? Theme.primary : cell.current ? Theme.accent : (cell.active ? Theme.text : Theme.dim)
            font { family: Theme.font; pixelSize: wallGrid.launcher.fontSize - 3; weight: wallGrid.launcher.fontWeight }
        }
        MouseArea {
            id: cellArea
            cursorShape: Qt.PointingHandCursor
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: mouse => wallGrid.launcher.hover(cellArea, mouse, cell.index)
            onClicked: wallGrid.launcher.activate(cell.modelData)
        }
    }
}
