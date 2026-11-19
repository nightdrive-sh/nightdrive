import QtQuick
import qs.kit
import "Markdown.js" as Markdown

// The open message, laid out as Notes' note: its bar at the top (MessageBar), then, scrolling together, its header
// (title, sender, when, the sender's session and task), its buttons, its text as formatted Markdown (Notes' Markdown.js,
// which shows HTML in it as the text it is and loads nothing from the web), and its files, pictures large
// (Attachments). A link opens in the browser, its address shown at the foot while hovered. The keys are shell.qml's.
Item {
    id: root
    required property QtObject c
    required property QtObject store
    property bool onePane: false
    signal back()
    signal archive()
    signal toggleRead()
    signal remove()
    signal press(string which)                 // a button, or the sender's "session" / "task"
    signal ask(int index)                      // a run button: RunPanel first
    signal viewImage(var images, int index)
    signal fromPicked(string key, string label)
    readonly property var message: store.message
    readonly property int margin: width < 520 ? 22 : 40
    function scroll(d) { flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + d)) }
    function home() { flick.contentY = 0 }
    onMessageChanged: if (!message || message.id !== shownId) { shownId = message ? message.id : ""; home() }
    property string shownId: ""

    MessageBar {
        id: bar
        z: 2                                   // its tips over the message under it
        width: parent.width
        c: root.c
        onePane: root.onePane
        message: root.message
        margin: root.margin
        onBack: root.back()
        onArchive: root.archive()
        onToggleRead: root.toggleRead()
        onRemove: root.remove()
    }

    Flickable {
        id: flick
        anchors.top: bar.bottom; anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        contentHeight: page.y + page.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: page
            visible: !!root.message
            x: root.margin; y: 28
            width: Math.min(root.width - 2 * root.margin, 900)
            spacing: 22
            MessageHeader {
                width: parent.width
                c: root.c
                message: root.message
                onFromPicked: (key, label) => root.fromPicked(key, label)
                onPress: which => root.press(which)
            }
            ActionButtons {
                visible: actions.length > 0
                width: parent.width
                c: root.c
                actions: root.message ? root.message.actions || [] : []
                onPress: i => root.press(String(i))
                onAsk: i => root.ask(i)
            }
            Text {
                id: body
                visible: text !== ""
                width: Math.min(parent.width, 760)
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                text: root.message && root.message.body ? Markdown.html(root.message.body, root.c) : ""
                font.family: root.c.font; font.pixelSize: 14
                color: root.c.body
                // Only addresses on the web: a box or a #tag (Notes' own links) does nothing here
                onLinkActivated: link => { if (/^(https?:\/\/|mailto:)/i.test(link)) Qt.openUrlExternally(link) }
                HoverHandler { cursorShape: body.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
            Attachments {
                id: files
                visible: files.files.length > 0
                width: parent.width
                c: root.c
                files: root.message ? root.message.attachments || [] : []
                onView: i => root.viewImage(files.images, i)
            }
        }
    }

    // The address a hovered link goes to, as Notes shows it: a link's text can name another address than its own
    Rectangle {
        visible: /^(https?:\/\/|mailto:)/i.test(body.hoveredLink)
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8
        width: Math.min(linkText.implicitWidth + 20, parent.width - 16); height: linkText.implicitHeight + 10
        radius: 6; color: root.c.solid; border.width: 1; border.color: root.c.divider
        Text {
            id: linkText
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: body.hoveredLink
            font.family: root.c.font; font.pixelSize: 11; color: root.c.dim
        }
    }

    Text {
        visible: root.store.loaded && !root.message && !root.store.picked
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 400)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: root.store.messages.length ? "Pick a message to read it."
            : "Claude's sessions leave messages here when they have something for you to look at: tell one \"leave the results in my Inbox\"."
        font.family: root.c.font; font.pixelSize: 13; color: root.c.faint
    }
}
