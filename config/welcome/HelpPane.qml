import QtQuick
import qs

// Beside a step done by hand (h in StepView, More help): the README's section that the step's steps.md names, the whole
// of it, for when the plain-words step isn't enough. Read from the file, so it works offline. A panel of its own, with
// its heading and a ×, so it reads as help about the step rather than as part of it.
Item {
    id: root
    required property QtObject c
    property string name: ""                    // the plugin's: "More about Mail"
    property var help: ({ title: "", markdown: "" })
    signal close()

    // PgUp / PgDn from StepView's keys: the pane never takes the keyboard
    function page(dir) {
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dir * flick.height * 0.85))
    }
    onHelpChanged: flick.contentY = 0

    Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.035) }    // a shade off the step, over the see-through background
    Rectangle { width: 1; height: parent.height; color: root.c.divider }

    Column {
        id: head
        x: 28; y: 34
        width: parent.width - 28 - 60
        spacing: 4
        Text {
            width: parent.width
            text: root.name ? "More about " + root.name : "More help"
            elide: Text.ElideRight
            color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
        }
        Text {
            visible: text !== ""
            width: parent.width
            text: root.help.title || ""
            elide: Text.ElideRight
            color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
        }
    }
    // × closes it, as h does
    Rectangle {
        x: parent.width - width - 20; y: 28
        width: 32; height: 32; radius: 8
        color: closeHover.hovered ? root.c.hover : "transparent"
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Text {
            anchors.centerIn: parent
            text: Icons.g("x"); font.family: Icons.family; font.pixelSize: 16
            color: closeHover.hovered ? root.c.title : root.c.dim
        }
    }

    Flickable {
        id: flick
        x: 28; y: head.y + head.height + 18
        width: parent.width - 44
        height: parent.height - y - 28
        clip: true
        contentHeight: body.height + 16
        boundsBehavior: Flickable.StopAtBounds
        Text {
            id: body
            width: flick.width - 12
            text: root.help.markdown || "This step has no help of its own."
            textFormat: Text.MarkdownText
            wrapMode: Text.Wrap; lineHeight: 1.3
            color: root.c.body; linkColor: root.c.primary
            font.family: root.c.font; font.pixelSize: 13
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }
}
