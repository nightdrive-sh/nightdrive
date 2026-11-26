import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Ferry's menu › Add Device: in the middle of the screen, over everything, in a window of its own that goes with the
// menu. The page's QR code (dark modules on white: the iPhone camera reads it from the screen), what to do with it,
// and the address (a click copies it). A click outside, × or Esc closes it and the menu. The menu makes the code
// (`ferry qr --svg`) and says when this shows (adding).
PanelWindow {
    id: addDialog
    required property var menu
    anchors { top: true; bottom: true; left: true; right: true }
    color: Qt.rgba(0, 0, 0, 0.6)   // the dim behind, as AirPods settings
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    onVisibleChanged: if (visible) addKeys.forceActiveFocus()
    MouseArea { anchors.fill: parent; onClicked: addDialog.menu.close() }
    Item {
        id: addKeys
        focus: true
        Keys.onEscapePressed: addDialog.menu.close()
    }
    Rectangle {
        anchors.centerIn: parent
        width: 720
        height: Math.max(qrBox.height, addText.height) + 56
        radius: 18
        color: Theme.bg
        border { width: 1; color: Theme.border }
        MouseArea { anchors.fill: parent }   // a click on the card doesn't close it
        Rectangle {
            id: qrBox
            x: 28; y: 28
            width: 240; height: 240; radius: 14
            color: "white"
            Image {
                anchors { fill: parent; margins: 12 }
                source: addDialog.menu.qr !== "" ? "file://" + addDialog.menu.qr : ""
                sourceSize: Qt.size(432, 432)
                smooth: false
                cache: false
            }
        }
        // Bigger text than a menu's: it's read from across the desk, phone in hand
        Column {
            id: addText
            anchors { left: qrBox.right; leftMargin: 28; right: parent.right; rightMargin: 28; top: qrBox.top }
            spacing: 16
            Text {
                text: "ADD DEVICE"
                color: Theme.primary
                font { family: Theme.font; pixelSize: 15; weight: Font.Medium; letterSpacing: 1.2 }
            }
            Repeater {
                model: ["Scan the code with the phone's camera", "Share › Add to Home Screen",
                        "Open Ferry there and turn on notifications"]
                delegate: Row {
                    required property string modelData
                    required property int index
                    width: parent.width
                    spacing: 12
                    Text {
                        text: index + 1
                        color: Theme.primary
                        font { family: Theme.font; pixelSize: 15; weight: Font.Medium }
                    }
                    Text {
                        width: parent.width - 24
                        wrapMode: Text.Wrap
                        text: modelData
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 15 }
                    }
                }
            }
            Item { width: 1; height: 4 }
            // The address: a click copies it
            Rectangle {
                width: parent.width
                height: 44; radius: 10
                color: urlArea.containsMouse ? Theme.hover : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.07)
                Text {
                    id: urlIcon
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: Icons.g(addDialog.menu.flash === "url" ? "check" : "copy")
                    color: Theme.dim
                    font { family: Icons.family; pixelSize: 17 }
                }
                Text {
                    anchors { left: urlIcon.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: addDialog.menu.flash === "url" ? "Copied"
                        : addDialog.menu.st ? addDialog.menu.st.url.replace(/^https:\/\//, "").replace(/\/$/, "") : ""
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 14 }
                }
                MouseArea {
                    id: urlArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Quickshell.execDetached(["wl-copy", addDialog.menu.st.url]); addDialog.menu.flashOn("url") }
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Another computer: open the address in its browser"
                color: Theme.dim
                font { family: Theme.font; pixelSize: 13 }
            }
        }
        Text {
            anchors { right: parent.right; rightMargin: 18; top: parent.top; topMargin: 18 }
            text: Icons.g("x")
            color: closeArea.containsMouse ? Theme.accent : Theme.dim
            font { family: Icons.family; pixelSize: 16 }
            MouseArea {
                id: closeArea
                anchors { fill: parent; margins: -8 }
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: addDialog.menu.close()
            }
        }
    }
}
