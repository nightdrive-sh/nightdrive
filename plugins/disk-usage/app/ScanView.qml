import QtQuick
import qs
import qs.kit
import "Fmt.js" as Fmt

// While a place is scanned: what has been found so far, the folder it is in, and a line that fills when the last
// scan's size says how far it is (else a stretch that runs to and fro). Esc or Stop ends it.
Column {
    id: root
    required property QtObject c
    required property QtObject scanner
    property string what: ""             // "Home", or the folder a closer look is for
    signal stop()
    spacing: 12

    readonly property real fraction: scanner.expect > 0 ? Math.min(1, scanner.bytes / scanner.expect) : -1

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Icons.g("hard-drive"); font.family: Icons.familyThin; font.pixelSize: 44
        color: root.c.faint
    }
    Text {
        textFormat: Text.PlainText
        width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        text: (root.scanner.graft ? "Looking closer at " : "Scanning ") + root.what + "…"
        color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
    }
    Text {
        width: parent.width; horizontalAlignment: Text.AlignHCenter
        text: Fmt.bytes(root.scanner.bytes) + "  ·  " + Fmt.plural(root.scanner.files, "file", "files")
        color: root.c.text; font.family: root.c.font; font.pixelSize: 12
    }
    Item {
        width: parent.width; height: 4
        Rectangle { anchors.fill: parent; radius: 2; color: root.c.line }
        Rectangle {
            id: fill
            height: parent.height; radius: 2; color: root.c.primary
            width: root.fraction >= 0 ? parent.width * root.fraction : parent.width * 0.25
            Behavior on width { enabled: root.fraction >= 0; NumberAnimation { duration: 150 } }
            // Without a size to go by: a stretch running to and fro
            SequentialAnimation on x {
                running: root.fraction < 0 && root.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: fill.parent.width * 0.75; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { from: fill.parent.width * 0.75; to: 0; duration: 900; easing.type: Easing.InOutQuad }
                onRunningChanged: if (!running) fill.x = 0
            }
        }
    }
    Text {
        textFormat: Text.PlainText
        width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle
        text: root.scanner.folder
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
    Item { width: 1; height: 4 }
    AppButton {
        anchors.horizontalCenter: parent.horizontalCenter
        c: root.c; glyph: "x"; label: "Stop"; keys: "Esc"; tip: "Stop the scan"
        onClicked: root.stop()
    }
}
