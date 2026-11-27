import QtQuick

// Under the open thread's subject in one of your own folders: why it is there ("Mail from news@shop.fi comes to
// Offers") and Stop, which ends the sender's rule (#3733); the mail stays where it is. Apart from Thread.qml, which
// places it, and Actions.stopSorting, which does it.
Item {
    id: root
    required property QtObject c
    property var rule: null             // Sorting.qml's rule for the thread's sender, or null: then it doesn't show
    signal stop()
    visible: rule !== null
    // By the rule, not by visible, which reads false while the thread itself is hidden
    implicitHeight: rule !== null ? line.implicitHeight + 14 : 0
    implicitWidth: line.implicitWidth
    Row {
        id: line
        spacing: 8
        Text {
            textFormat: Text.PlainText
            text: root.rule ? "Mail from " + (root.rule.sender || "all of " + root.rule.domain) + " comes to " + root.rule.folder : ""
            color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
        }
        Text { text: "·"; color: root.c.faint; font.family: root.c.font; font.pixelSize: 12 }
        Text {
            text: "Stop"
            color: stopHover.hovered ? root.c.title : root.c.accent
            font.family: root.c.font; font.pixelSize: 12
            HoverHandler { id: stopHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.stop() }
        }
    }
}
