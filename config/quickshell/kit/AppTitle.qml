import QtQuick

// The app's name at the top of its sidebar, with the block cursor of Nightdrive's wordmark after it: "Mail█".
// pixelSize makes it a heading of a window of its own (Welcome to Nightdrive); the cursor grows with it.
Row {
    id: root
    required property QtObject c
    property string text
    property int pixelSize: 13
    height: pixelSize + 9
    spacing: Math.round(pixelSize / 4)
    Text { anchors.verticalCenter: parent.verticalCenter; text: root.text; color: root.c.title; font.family: root.c.font; font.pixelSize: root.pixelSize; font.weight: Font.DemiBold }
    Rectangle { width: Math.round(root.pixelSize * 7 / 13); height: Math.round(root.pixelSize * 14 / 13); color: root.c.primary; anchors.verticalCenter: parent.verticalCenter }
}
