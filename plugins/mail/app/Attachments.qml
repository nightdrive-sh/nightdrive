import QtQuick
import qs
import qs.kit

// A message's attachments, as the last row of its header (Thread.qml), so they show as soon as the message opens
// instead of below a long text: a click opens one, its save icon puts it in the downloads folder, and with two or more
// "Save all" puts them all there. The chips wrap onto more lines in a narrow pane.
Flow {
    id: root
    required property QtObject c
    required property var app
    required property var msg           // the message: { id, files: [{ part, name, size }] … }
    spacing: 8
    visible: msg.files.length > 0
    Repeater {
        model: root.msg.files
        delegate: Rectangle {
            id: file
            required property var modelData
            implicitWidth: fileRow.implicitWidth + 28
            implicitHeight: 34
            radius: 8
            border.color: c.line
            color: fileHover.hovered ? c.hover : "transparent"
            HoverHandler { id: fileHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: app.openPart(root.msg, file.modelData) }
            Row {
                id: fileRow
                anchors.centerIn: parent
                spacing: 10
                Text {
                    id: fileName
                    textFormat: Text.PlainText
                    text: file.modelData.name; color: c.text; font.family: c.font; font.pixelSize: 12
                    // The chip stays inside a narrow pane: the name gives way to its size and the save icon
                    width: Math.min(implicitWidth, 280, root.width - fileSize.implicitWidth - saveIcon.width - 48)
                    elide: Text.ElideMiddle
                }
                Text {
                    id: fileSize
                    text: app.size(file.modelData.size); color: c.faint; font.family: c.font; font.pixelSize: 11
                    anchors.baseline: fileName.baseline
                }
                // Save, always in sight as a quiet icon: a "Save" shown only under the pointer left an empty gap in
                // the chip the rest of the time. It says what it does when held under the pointer.
                Item {
                    id: saveIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    Text {
                        anchors.centerIn: parent
                        text: Icons.g("download"); font.family: Icons.family; font.pixelSize: 13
                        color: saveHover.hovered ? c.accent : fileHover.hovered ? c.dim : c.faint
                    }
                    HoverHandler { id: saveHover }
                    TapHandler { onTapped: app.savePart(root.msg, file.modelData) }
                    Tip { y: parent.height + 10; c: root.c; text: "Save to Downloads"; hovered: saveHover.hovered }
                }
            }
        }
    }
    // Two or more: all of them to the downloads folder at once
    Rectangle {
        visible: root.msg.files.length > 1
        implicitWidth: allRow.implicitWidth + 24
        implicitHeight: 34
        radius: 8
        color: allHover.hovered ? c.hover : "transparent"
        HoverHandler { id: allHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: app.saveAll(root.msg) }
        Row {
            id: allRow
            anchors.centerIn: parent
            spacing: 7
            Text { anchors.verticalCenter: parent.verticalCenter; text: Icons.g("download"); font.family: Icons.family; font.pixelSize: 14; color: allHover.hovered ? c.accent : c.dim }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Save all"; font.family: c.font; font.pixelSize: 12; color: allHover.hovered ? c.accent : c.dim }
        }
    }
}
