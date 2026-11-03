import QtQuick
import qs

// Ferry's menu: a device to drop files on, one tile each while files are dragged over the menu. The drop goes to the
// tile's device. The menu counts the tiles with files over them (tileDrags) and holds them a moment between two
// (holdDrop), so the tiles don't go while the cursor crosses the gap (FerryMenu.qml › dropping).
Rectangle {
    id: dt
    required property var menu
    property var dev
    readonly property bool usable: menu.canTake(dev)
    readonly property bool hot: tileDrop.containsDrag && usable
    height: 96; radius: 14
    color: hot ? Theme.sel : Theme.card
    border { width: hot ? 1.5 : 1; color: hot ? Theme.primary : Theme.border }
    opacity: usable ? 1 : 0.45
    Column {
        anchors.centerIn: parent
        spacing: 7
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Icons.g(dt.menu.deviceIcon(dt.dev))
            color: Theme.accent
            font { family: Icons.family; pixelSize: 26 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, dt.width - 16)
            elide: Text.ElideRight
            text: dt.dev.name
            textFormat: Text.PlainText   // a device names itself: never markup
            color: dt.hot ? Theme.accent : Theme.text
            font { family: Theme.font; pixelSize: 12 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: dt.hot ? "Drop to send" : dt.menu.deviceState(dt.dev)
            color: dt.hot ? Theme.accent : Theme.dim
            font { family: Theme.font; pixelSize: 10 }
        }
    }
    DropArea {
        id: tileDrop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: drag => { drag.accepted = dt.menu.dragging === 0 && dt.usable; if (drag.accepted) dt.menu.tileDrags++ }
        onExited: { dt.menu.tileDrags = Math.max(0, dt.menu.tileDrags - 1); dt.menu.holdDrop() }
        onDropped: d => {
            dt.menu.tileDrags = 0
            const p = dt.menu.paths(d)
            if (!p.length) return
            dt.menu.run(["add", "--to", dt.dev.id].concat(p))
            d.acceptProposedAction()
        }
    }
}
