import QtQuick
import Quickshell
import Quickshell.Widgets
import qs

// One game in the grid: its cover (2:3, Steam's library capsule), or for a game without one (a .desktop game) its icon
// on a card of the theme's colours; the name under it, and while Steam downloads it, how far. The picked one has a
// frame in the theme's colour and lifts a little, as a console's home screen does.
Item {
    id: card
    required property QtObject c
    required property var game
    property bool current: false
    property int coverWidth: 180
    signal clicked()
    signal doubleClicked()

    width: coverWidth
    height: coverWidth * 1.5 + 54

    // An icon by its .desktop Icon=: a path as it is, a name through the icon theme
    function iconSource(icon) {
        if (!icon) return ""
        if (icon.startsWith("/")) return "file://" + icon
        return Quickshell.iconPath(icon, true)
    }

    // The card with round corners that cut its cover too
    ClippingRectangle {
        id: cover
        width: card.coverWidth
        height: card.coverWidth * 1.5
        radius: 10
        color: Qt.lighter(card.c.solid, 1.25)
        scale: card.current ? 1.04 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Image {
            id: art
            anchors.fill: parent
            source: card.game.cover ? "file://" + card.game.cover : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(card.coverWidth * 2, card.coverWidth * 3)
        }
        // No cover: the icon, big, on the card
        Image {
            anchors.centerIn: parent
            width: card.coverWidth * 0.5; height: width
            visible: art.status !== Image.Ready
            source: card.iconSource(card.game.icon)
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Text {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready && !card.game.icon
            text: Icons.g("gamepad-2")
            font { family: Icons.familyLight; pixelSize: card.coverWidth * 0.36 }
            color: card.c.dim
        }
        // Downloading: dimmed, with a bar at the foot
        Rectangle { anchors.fill: parent; radius: cover.radius; color: "#000"; opacity: card.game.installed ? 0 : 0.45 }
        Rectangle {
            visible: !card.game.installed
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            height: 5; radius: 2.5; color: Qt.rgba(1, 1, 1, 0.2)
            Rectangle { width: parent.width * (card.game.progress || 0) / 100; height: parent.height; radius: parent.radius; color: card.c.primary }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.clicked()
            onDoubleClicked: card.doubleClicked()
        }
    }
    // The picked one's frame, around the card (outside its clip), lifted with it
    Rectangle {
        anchors.fill: cover
        anchors.margins: -5
        scale: cover.scale
        radius: cover.radius + 5
        color: "transparent"
        border.width: 3
        border.color: card.current ? card.c.primary : "transparent"
    }
    Text {
        anchors { top: cover.bottom; topMargin: 12; left: parent.left; right: parent.right }
        text: card.game.name
        color: card.current ? card.c.title : card.c.text
        font { family: card.c.font; pixelSize: Math.round(card.coverWidth / 12); weight: card.current ? Font.DemiBold : Font.Normal }
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        anchors { top: cover.bottom; topMargin: 12 + Math.round(card.coverWidth / 12) + 8; left: parent.left; right: parent.right }
        text: !card.game.installed ? "Downloading " + card.game.progress + " %" : card.game.running ? "Running"
              : card.game.source === "steam" ? "Steam" : ""
        color: card.game.installed && card.game.running ? card.c.primary : card.c.dim   // running: A switches to it
        font { family: card.c.font; pixelSize: Math.round(card.coverWidth / 15) }
        horizontalAlignment: Text.AlignHCenter
    }
}
