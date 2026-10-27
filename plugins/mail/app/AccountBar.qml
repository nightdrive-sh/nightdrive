import QtQuick
import QtQuick.Layouts

// The accounts, in a bar of their own at the sidebar's foot under a line: with more than one, each address with its
// inbox's unread count, the one shown marked; a click (or Ctrl+Tab) shows another one's folders. With one, its address
// alone, so you still see which mail this is.
ColumnLayout {
    id: root
    required property QtObject c
    required property var accounts         // compose.py accounts: { id, address, … }
    required property int current
    required property var unread           // inbox unread threads, by account id
    signal picked(int index)
    Layout.fillWidth: true
    spacing: 0

    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; Layout.rightMargin: 1; color: root.c.divider }

    Item { Layout.preferredHeight: 10 }
    Repeater {
        model: root.accounts
        delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool several: root.accounts.length > 1
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            implicitHeight: 30
            radius: 8
            color: several && ah.hovered ? root.c.hover : "transparent"
            HoverHandler { id: ah; enabled: several; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: several; onTapped: root.picked(index) }
            Rectangle {
                visible: several && index === root.current
                x: 6; anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 14; radius: 1.5; color: root.c.primary
            }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: count.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: modelData.address; font.family: root.c.font; font.pixelSize: several ? 12 : 11
                color: !several ? root.c.faint : index === root.current ? root.c.title : root.c.dim
            }
            Text {
                id: count
                anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                visible: several
                text: root.unread[modelData.id] > 0 ? root.unread[modelData.id] : ""
                font.family: root.c.font; font.pixelSize: 11; color: root.c.dim
            }
        }
    }
    Item { Layout.preferredHeight: 14 }
}
