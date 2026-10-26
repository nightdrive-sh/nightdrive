import QtQuick
import qs.kit

// The sidebar's foot while a message goes (Outbox.qml), right of the Settings glyph: "Sending…", or what went wrong
// with Retry and Open (back into the writing window). Hidden when there is nothing to show.
Item {
    id: root
    required property QtObject c
    required property QtObject outbox
    readonly property var job: outbox.failedJob
    visible: outbox.jobs.length > 0
    implicitHeight: 26

    Text {
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        visible: !root.job
        text: root.outbox.jobs.length > 1 ? "Sending " + root.outbox.jobs.length + " messages…" : "Sending…"
        color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
    }
    // The error in full in the tip: the line has room for little more than "Not sent"
    Text {
        id: failed
        anchors.left: parent.left; anchors.right: buttons.left; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
        visible: !!root.job
        elide: Text.ElideRight
        text: "Not sent"
        color: root.c.danger; font.family: root.c.font; font.pixelSize: 11
        HoverHandler { id: errHover }
        Tip { y: -height - 8; c: root.c; text: root.job ? root.job.error + " (kept in Drafts)" : ""; hovered: errHover.hovered }
    }
    Row {
        id: buttons
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        visible: !!root.job
        AppIconButton {
            c: root.c
            glyph: "rotate-cw"; glyphColor: root.c.dim
            tip: "Try again"; tipSide: "above"
            onClicked: root.outbox.retry(root.job)
        }
        AppIconButton {
            c: root.c
            glyph: "pencil"; glyphColor: root.c.dim
            tip: "Open the message"; tipSide: "above"
            onClicked: root.outbox.open(root.job)
        }
    }
}
