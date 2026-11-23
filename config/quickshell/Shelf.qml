import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Shelf: a temporary dock for files (like Dropover/Yoink on macOS).
// Drag a file to the top edge of the screen (center) -> the shelf opens -> drop the file on it.
// Files can be dragged from the shelf into another app (a successful drop removes them from the shelf). The shelf closes by itself when the cursor leaves.
// Files are not copied, the shelf only holds paths. State is in memory (reset when Quickshell restarts).
// Keyboard: qs ipc call shelf toggle  (keeps the shelf open until you close it)  /  qs ipc call shelf clear
// Settings › Shelf turns it off (launcher.json's shelf)
Scope {
    id: shelf
    property var items: []             // file:// URLs
    property bool open: false
    property bool pinned: false        // a shelf opened via IPC doesn't close by itself
    // Settings › Shelf (launcher.json's shelf, missing = on). Off: the trigger at the top edge is gone and IPC toggle does
    // nothing, so neither a dragged file nor a lingering cursor opens it (#3128). shell.qml binds it to the launcher's
    // prefs, which already watch launcher.json: a FileView of its own here cost a second inotify instance (#3165)
    property bool enabled: true
    onEnabledChanged: if (!enabled) { pinned = false; open = false }
    // An outgoing drag in progress (the shelf must not close mid-drag); it runs from DragOut.qml (#3020)
    readonly property int dragging: DragOut.active && DragOut.from(card) ? 1 : 0
    // 0 = hidden above the screen, 1 = fully down; the window stays mapped until the slide-up has finished
    property real reveal: open ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 80; easing.type: shelf.open ? Easing.OutCubic : Easing.InCubic } }
    readonly property bool busy: pinned || dragging > 0 || card.hovered || dropArea.containsDrag || trigger.containsDrag || triggerHover.hovered

    function add(urls) {
        const cur = shelf.items.slice()
        for (const u of urls) {
            const s = u.toString()
            if (s.startsWith("file://") && cur.indexOf(s) < 0) cur.push(s)
        }
        shelf.items = cur
    }
    function remove(url) { shelf.items = shelf.items.filter(u => u !== url) }
    function clear() { shelf.items = [] }
    function name(url) { return decodeURIComponent(url.split("/").pop()) }
    function ext(url) {
        const n = name(url)
        const i = n.lastIndexOf(".")
        return i > 0 ? n.slice(i + 1).toLowerCase() : ""
    }
    function isImage(url) { return ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"].indexOf(ext(url)) >= 0 }

    onBusyChanged: if (!busy && open) closeTimer.restart()
    onOpenChanged: if (open && !busy) closeTimer.restart()
    Timer { id: hoverOpen; interval: 250; onTriggered: if (triggerHover.hovered) shelf.open = true }
    // Short delay: moving the cursor from the top edge to the shelf doesn't close it
    Timer { id: closeTimer; interval: 120; onTriggered: if (!shelf.busy) shelf.open = false }

    // Drop into another app succeeded -> remove from the shelf.
    // The Wayland target doesn't always report the action (Ignore), so a drag that ends outside the shelf also removes.
    Connections {
        target: DragOut
        function onFinished(action) {
            if (DragOut.from(card) && (action !== Qt.IgnoreAction || !card.hovered))
                Qt.callLater(shelf.remove, String(DragOut.mime["text/uri-list"] || "").trim())
        }
    }

    IpcHandler {
        target: "shelf"
        function toggle(): void { if (!shelf.enabled) return; shelf.pinned = !shelf.open || !shelf.pinned; shelf.open = shelf.pinned }
        function clear(): void { shelf.clear() }
    }

    // Invisible trigger at the top edge (center): a drag arriving here opens the shelf.
    PanelWindow {
        visible: shelf.enabled
        anchors { top: true }
        // The trigger is the notch: hovering or dragging over it opens the shelf, and dropping works there already.
        // No wider: the bar's icons on either side must stay clickable.
        implicitWidth: Theme.notchWidth
        implicitHeight: Theme.barHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay   // Overlay: the bar (layer Top) must not cover the trigger
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Mouse at the top edge (lingering briefly) opens the shelf
        HoverHandler { id: triggerHover; onHoveredChanged: if (hovered) hoverOpen.restart() }

        DropArea {
            id: trigger
            anchors.fill: parent
            keys: ["text/uri-list"]
            onEntered: drag => { drag.accepted = true; shelf.open = true }
            onDropped: drop => { if (drop.hasUrls) { shelf.add(drop.urls); drop.acceptProposedAction() } }
        }
    }

    PanelWindow {
        visible: shelf.open || shelf.reveal > 0
        anchors { top: true }
        implicitWidth: card.width
        implicitHeight: Theme.barHeight + card.height   // from the top edge: the shelf covers the bar behind it, like a dropped-down notch
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        HoverHandler { id: hover }
        DropArea {   // the part over the bar takes drops too
            anchors.fill: parent
            keys: ["text/uri-list"]
            onEntered: drag => { drag.accepted = true }
            onDropped: drop => { if (drop.hasUrls) { shelf.add(drop.urls); drop.acceptProposedAction() } }
        }

        // Everything visible slides down from above the top edge when the shelf opens
        Item {
            width: card.width
            height: Theme.barHeight + card.height
            transform: Translate { y: -(1 - shelf.reveal) * (Theme.barHeight + card.height) }

        // The black reaches the top edge (the see-through bar would show between the notch and the shelf otherwise)
        Rectangle { width: card.width; height: Theme.barHeight + card.radius; color: card.color }

        Rectangle {
            id: card
            y: Theme.barHeight
            property bool hovered: hover.hovered
            // 4 files fit comfortably; width grows up to 6, after that the list scrolls (mouse wheel / two fingers)
            function chipsW(n) { return n * 64 + (n - 1) * 10 }
            width: 16 + flick.width + 12 + 56 + 16
            height: 74
            radius: 10
            color: "#000000"
            // Square top corners: the shelf continues the top bar
            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: parent.radius; color: parent.color }

            DropArea {
                id: dropArea
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: drag => { drag.accepted = true }
                onDropped: drop => {
                    if (drop.hasUrls) { shelf.add(drop.urls); drop.acceptProposedAction() }
                }
            }

            Row {
                visible: shelf.items.length === 0
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.g("download")
                    color: Theme.primary
                    font { family: Icons.family; pixelSize: 16 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DROP FILES HERE"
                    color: Theme.primary
                    font { family: Theme.font; pixelSize: 11; letterSpacing: 1 }
                }
            }

            Flickable {
                id: flick
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                height: 62
                width: Math.max(card.chipsW(4), Math.min(row.implicitWidth, card.chipsW(6)))
                contentWidth: row.implicitWidth
                contentHeight: height
                clip: true
                interactive: false
                WheelHandler {
                    onWheel: event => {
                        const d = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                        flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - d))
                    }
                }

            Row {
                id: row
                spacing: 10

                Repeater {
                    model: shelf.items
                    delegate: Item {
                        id: chip
                        required property string modelData
                        width: 64
                        height: 62

                        // Drag: the file goes to another app (text/uri-list), from DragOut.qml (the MouseArea below starts it)
                        Item {
                            id: dragSource
                            anchors.fill: parent
                            property var grab: null   // the drag's picture (kept so its url stays valid)

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: ma.drag.active || chipHover.hovered ? Theme.hover : "transparent"
                            }
                            Rectangle {
                                id: thumb
                                width: 34; height: 34
                                anchors { top: parent.top; topMargin: 4; horizontalCenter: parent.horizontalCenter }
                                radius: 6
                                color: Theme.sel
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    visible: shelf.isImage(chip.modelData)
                                    source: visible ? chip.modelData : ""
                                    sourceSize: Qt.size(68, 68)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !shelf.isImage(chip.modelData)
                                    text: shelf.ext(chip.modelData).toUpperCase().slice(0, 4) || "FILE"
                                    color: Theme.accent
                                    font { family: Theme.font; pixelSize: 11; bold: true }
                                }
                            }
                            Text {
                                anchors { top: thumb.bottom; topMargin: 3; left: parent.left; right: parent.right; leftMargin: 2; rightMargin: 2 }
                                text: shelf.name(chip.modelData)
                                elide: Text.ElideMiddle
                                horizontalAlignment: Text.AlignHCenter
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 10 }
                            }

                            HoverHandler { id: chipHover }
                            Item { id: dragDummy; visible: false }   // drag.target: the chip itself doesn't move, an image follows the cursor
                            MouseArea {
                                cursorShape: Qt.PointingHandCursor
                                id: ma
                                anchors.fill: parent
                                drag.target: dragDummy
                                // Drag image (chip following the cursor): grabbed in advance on press
                                onPressed: dragSource.grabToImage(res => { dragSource.grab = res })
                                drag.onActiveChanged: drag.active
                                    ? DragOut.start(dragSource, { "text/uri-list": chip.modelData + "\r\n" },
                                                    dragSource.grab ? dragSource.grab.url : "", Qt.point(dragSource.width / 2, dragSource.height / 2))
                                    : DragOut.release(dragSource)
                            }
                        }

                        // Remove from the shelf (doesn't delete the file)
                        Rectangle {
                            visible: chipHover.hovered && !ma.drag.active
                            width: 16; height: 16; radius: 8
                            anchors { top: parent.top; right: parent.right; topMargin: 0; rightMargin: 0 }
                            color: Theme.border
                            Text { anchors.centerIn: parent; text: "×"; color: Theme.text; font { family: Theme.font; pixelSize: 13 } }
                            MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill: parent; onClicked: shelf.remove(chip.modelData) }
                        }
                    }
                }
            }
            }

            // Clear all
            Row {
                id: clearRow
                visible: shelf.items.length > 0
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: -8; rightMargin: 21 }
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.g("trash-2")
                    color: clearArea.containsMouse ? Theme.accent : Theme.primary
                    font { family: Icons.family; pixelSize: 10 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Clear"
                    color: clearArea.containsMouse ? Theme.accent : Theme.primary
                    font { family: Theme.font; pixelSize: 10 }
                }
            }
            MouseArea {
                cursorShape: Qt.PointingHandCursor
                id: clearArea
                visible: shelf.items.length > 0
                anchors { fill: clearRow; margins: -4 }
                hoverEnabled: true
                onClicked: { shelf.clear(); shelf.pinned = false; shelf.open = false }   // Clear hides the shelf immediately
            }
        }
        }
    }
}
