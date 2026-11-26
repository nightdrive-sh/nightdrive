import QtQuick
import qs

// Ferry's menu: what the other devices sent here, on one card, a FerryReceivedRow each. A long list scrolls and runs
// on under the pill: the box takes menu.listLift less room in the menu's column than the card, and its last rows fade
// out (scrolls tells the menu, which then gives the pill no extra room above it).
Item {
    id: listBox
    required property var menu
    readonly property bool scrolls: list.height > menu.rowHeight * 6.5
    height: listCard.height - (scrolls ? menu.listLift : 0)
    Rectangle {
        id: listCard
        width: parent.width
        height: flick.height + 8
        radius: 14
        color: Theme.card

        Flickable {
            id: flick
            y: 4
            width: parent.width
            height: listBox.scrolls ? listBox.menu.rowHeight * 6.5 : list.height
            contentHeight: list.height
            // Room after the last row to scroll it out from under the fade
            bottomMargin: listBox.scrolls ? listBox.menu.listFade - 4 : 0
            interactive: listBox.scrolls
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: list
                width: flick.width
                Repeater {
                    model: listBox.menu.received
                    delegate: FerryReceivedRow {
                        menu: listBox.menu
                        width: list.width
                    }
                }
            }
        }

        // The rows under the pill fade out, and the card with them; the pill and buttons come later in the menu's
        // column and are drawn over it
        Rectangle {
            visible: listBox.scrolls
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: listBox.menu.listFade
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0) }
                GradientStop { position: 0.35; color: Theme.card }
                GradientStop { position: 1; color: Theme.bg }
            }
        }
    }
}
