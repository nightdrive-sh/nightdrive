import QtQuick
import qs.kit

// The sidebar's title line, over AppSidebar's own title (give it the sidebar as its parent): the sending badge
// (SendStatus.qml) at its right, and Settings' gear, which shows only while the pointer is over the line. ⌘, and
// launcher › Settings › Apps › Mail open Settings too, so the gear needn't take room all the time.
Item {
    id: root
    required property QtObject c
    required property QtObject outbox
    required property int headerHeight      // AppSidebar's: the title is centred in it
    signal settings()
    anchors.left: parent.left; anchors.right: parent.right
    height: headerHeight
    z: 2        // the badge's card lies over the folders

    HoverHandler { id: hover }

    Row {
        anchors.right: parent.right; anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        AppIconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: hover.hovered
            implicitWidth: 22       // a narrow sidebar (168 px) has just room for "Mail█", the gear and "Not sent"
            c: root.c
            glyph: "settings"; glyphColor: root.c.faint
            tip: "Settings"; keys: "⌘,"; tipAlign: "right"
            onClicked: root.settings()
        }
        SendStatus {
            anchors.verticalCenter: parent.verticalCenter
            c: root.c; outbox: root.outbox
            frame: root
        }
    }
}
