import QtQuick
import qs.kit
import "Markdown.js" as Markdown

// The open note, to read: its title and when it was saved in the header, with Open in Apostrophe (where it is written:
// the window doesn't edit), then its Markdown as formatted text (Markdown.js). A link opens in the browser. The keys are shell.qml's.
Item {
    id: root
    required property QtObject c
    required property QtObject store
    property bool onePane: false
    signal back()
    readonly property var note: store.note
    readonly property int margin: width < 520 ? 24 : 40

    // The heading the note starts with is its title, which the header shows already
    readonly property string body: {
        const t = store.text
        const m = t.match(/^\s*#{1,6}\s+(.+?)\s*#*\s*(\n|$)/)
        return m && note && m[1] === note.title ? t.slice(m[0].length) : t
    }
    function scroll(d) { flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + d)) }
    function home() { flick.contentY = 0 }

    Item {
        id: header
        width: parent.width; height: 62
        AppIconButton {
            id: backButton
            visible: root.onePane
            anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
            c: root.c; glyph: "arrow-left"; tip: "The notes"; keys: "Esc"
            onClicked: root.back()
        }
        Column {
            anchors.left: root.onePane ? backButton.right : parent.left
            anchors.leftMargin: root.onePane ? 12 : root.margin
            anchors.right: editButton.left; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                textFormat: Text.PlainText
                width: parent.width; elide: Text.ElideRight
                text: root.note ? root.note.title : ""
                font.family: root.c.font; font.pixelSize: 17; font.weight: Font.Medium; color: root.c.title
            }
            Text {
                textFormat: Text.PlainText
                width: parent.width; elide: Text.ElideMiddle
                text: root.note ? Qt.formatDateTime(new Date(root.note.modified), "d MMM yyyy  HH:mm") + "   " + root.store.folder + "/" + root.note.id : ""
                font.family: root.c.font; font.pixelSize: 11; color: root.c.faint
            }
        }
        AppButton {
            id: editButton
            visible: !!root.note
            anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
            c: root.c; glyph: "pencil"; label: root.width < 480 ? "" : "Open in Apostrophe"
            tip: "Write in it in Apostrophe"; keys: "⏎  e"
            onClicked: root.store.edit()
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.c.divider }
    }

    Flickable {
        id: flick
        anchors.top: header.bottom; anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        contentHeight: page.implicitHeight + 64
        boundsBehavior: Flickable.StopAtBounds
        Text {
            id: page
            x: root.margin; y: 24
            width: Math.min(root.width - 2 * root.margin, 760)
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            text: Markdown.html(root.body, root.c)
            font.family: root.c.font; font.pixelSize: 14
            color: root.c.body
            onLinkActivated: link => { if (/^(https?:\/\/|mailto:)/i.test(link)) Qt.openUrlExternally(link) }
            HoverHandler { cursorShape: page.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
    }

    // The address a hovered link goes to, as a browser shows it: a link's text can name another address than its own
    // (a note Claude wrote, or one from the web), and this is the one a click opens (#1930)
    Rectangle {
        visible: page.hoveredLink !== ""
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8
        width: Math.min(linkText.implicitWidth + 20, parent.width - 16); height: linkText.implicitHeight + 10
        radius: 6; color: root.c.solid; border.width: 1; border.color: root.c.divider
        Text {
            id: linkText
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: page.hoveredLink
            font.family: root.c.font; font.pixelSize: 11; color: root.c.dim
        }
    }

    Text {
        visible: root.store.loaded && !root.note
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 380)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.store.error || (root.store.notes.length ? "Pick a note to read it."
            : "No notes in " + root.store.folder + " yet.\nWrite one in Apostrophe, or ask Claude to.")
        font.family: root.c.font; font.pixelSize: 13; color: root.c.faint
    }
}
