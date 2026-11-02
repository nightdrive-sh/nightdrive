import QtQuick
import QtQuick.Layouts

// The accounts, in a bar of their own at the sidebar's foot under a line (last in AppSidebar, after a filler, with the
// sidebar's bottomMargin 0 so the line reaches the foot): with more than one, each one's label with its count, the one
// shown marked; a click comes out as picked (Mail: Ctrl+Tab does it too). With one, its label alone and dimmer, so you
// still see whose this is. Mail's is the first: an address and its inbox's unread threads.
ColumnLayout {
    id: root
    required property QtObject c
    required property var accounts         // objects with an id and a label (labelRole)
    required property int current
    property var counts: ({})              // a number by account id; 0 or none shows nothing
    property string labelRole: "address"
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
                textFormat: Text.PlainText
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: count.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: modelData[root.labelRole]; font.family: root.c.font; font.pixelSize: several ? 12 : 11
                color: !several ? root.c.faint : index === root.current ? root.c.title : root.c.dim
            }
            Text {
                id: count
                anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                visible: several
                text: root.counts[modelData.id] > 0 ? root.counts[modelData.id] : ""
                font.family: root.c.font; font.pixelSize: 11; color: root.c.dim
            }
        }
    }
    Item { Layout.preferredHeight: 14 }
}
