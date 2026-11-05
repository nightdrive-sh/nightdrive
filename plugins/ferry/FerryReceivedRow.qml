import QtQuick
import Quickshell.Widgets
import qs

// Ferry's menu › what the other devices sent (FerryReceivedList.qml): one item. A click does what the round mark says
// (copies a text, opens a file); a file or a text can be dragged into another app. A picture shows its own small copy, kept in
// the menu's thumbDir so the next opening doesn't read every photo again.
Item {
    id: r
    required property var menu
    required property var modelData
    required property int index
    readonly property bool isFile: modelData.kind === "file"
    readonly property bool isImage: isFile && /^image\//.test(modelData.type || "")
    // A picture only for what Qt reads (HEIC from an iPhone keeps the icon)
    readonly property bool hasThumb: /^image\/(png|jpeg|gif|webp|bmp)$/.test(modelData.type || "")
    readonly property string thumbFile: menu.thumbDir + "/" + modelData.id + ".png"
    property bool fromCopy: true   // the small copy, until it turns out there's none yet
    readonly property bool lit: rowArea.containsMouse && !MenuPointer.pointerAway || navSelected
    property bool navSelected: false
    function navActivate() { r.menu.act(r.modelData) }
    height: menu.rowHeight

    // The divider starts at the text, as in the phone's app
    Rectangle {
        visible: r.index > 0
        anchors { left: parent.left; leftMargin: 62; right: parent.right; rightMargin: 12 }
        height: 1
        color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.6)
    }
    Rectangle {
        id: rowBg
        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
        radius: 10
        color: r.lit ? Theme.hover : "transparent"
        border { width: r.navSelected ? 1 : 0; color: Theme.primary }
    }
    // While it's dragged out, the row stays and its picture follows the cursor: a file's row as it is, a text's start in
    // a small box (FerryTextDragImage.qml). A text goes as plain text; both types, as some apps ask only for the one
    // with the charset (GTK's) and others only for the plain one.
    Item {
        id: dragSource
        anchors.fill: parent
        Drag.active: rowArea.drag.active
        Drag.hotSpot: r.isFile ? Qt.point(30, height / 2) : Qt.point(12, 12)
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.mimeData: r.isFile ? { "text/uri-list": "file://" + encodeURI(r.modelData.path || "") + "\r\n" }
            : { "text/plain": r.modelData.text || "", "text/plain;charset=utf-8": r.modelData.text || "" }
        Drag.onActiveChanged: r.menu.dragging += Drag.active ? 1 : -1
        Drag.onDragFinished: r.menu.close()
    }
    Item { id: dragDummy; visible: false }   // drag.target: the row stays, its image follows
    // A text's picture, drawn out of sight (left of the menu) so grabToImage has something rendered to take
    Loader {
        id: textImage
        active: !r.isFile
        x: -1000
        sourceComponent: FerryTextDragImage { text: r.modelData.text || ""; secret: !!r.modelData.secret }
    }

    Rectangle {
        id: tile
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        width: 40; height: 40; radius: 10
        color: Theme.sel
        Text {
            visible: !thumb.visible
            anchors.centerIn: parent
            text: Icons.g(!r.isFile ? "text" : r.isImage ? "image" : "file")
            color: Theme.accent
            font { family: Icons.family; pixelSize: 19 }
        }
        // An image's own picture
        ClippingRectangle {
            id: thumb
            visible: r.hasThumb && thumbImg.status === Image.Ready
            anchors.fill: parent
            radius: 10
            color: "transparent"
            Image {
                id: thumbImg
                // A phone's photo is stored sideways, its turn in EXIF: Qt applies it only when asked
                autoTransform: true
                anchors.fill: parent
                source: !r.hasThumb || !r.modelData.path ? ""
                    : "file://" + (r.fromCopy ? r.thumbFile : r.modelData.path)
                sourceSize: Qt.size(80, 80)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                onStatusChanged: {
                    if (status === Image.Error && r.fromCopy) r.fromCopy = false
                    else if (status === Image.Ready && !r.fromCopy)
                        grabToImage(g => g.saveToFile(r.thumbFile), Qt.size(80, 80))
                }
            }
        }
    }
    Column {
        anchors { left: tile.right; leftMargin: 12; right: mark.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 4
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: r.isFile ? r.modelData.name : r.modelData.text.replace(/\s+/g, " ").trim()
            // Another device's text or file name: AutoText would draw it as markup if it looked like a tag (a link, an
            // <img> that loads from the net). The line under it holds the sender's name.
            textFormat: Text.PlainText
            color: Theme.accent
            font { family: Theme.font; pixelSize: 12 }
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: r.menu.flash === r.modelData.id ? "copied"
                : [r.isFile ? r.menu.size(r.modelData.size || 0) : "", r.menu.ago(r.modelData.time), r.modelData["from"] || ""]
                    .filter(x => x).join(" · ")
            textFormat: Text.PlainText
            color: r.menu.flash === r.modelData.id ? Theme.accent : Theme.dim
            font { family: Theme.font; pixelSize: 11 }
        }
    }
    // A click anywhere on the row does what the round mark says; a file or a text drags out from here
    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        drag.target: dragDummy
        onPressed: (r.isFile ? r : textImage.item).grabToImage(res => { dragSource.Drag.imageSource = res.url })
        onClicked: r.menu.act(r.modelData)
    }
    // What a click does: copy a text, open a file
    Rectangle {
        id: mark
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        width: 32; height: 32; radius: 16
        color: r.lit ? Theme.primary : Theme.sel
        Text {
            anchors.centerIn: parent
            text: Icons.g(r.menu.flash === r.modelData.id ? "check" : r.isFile ? "external-link" : "copy")
            color: r.lit ? Theme.bg : Theme.accent
            font { family: Icons.family; pixelSize: 15 }
        }
    }
}
