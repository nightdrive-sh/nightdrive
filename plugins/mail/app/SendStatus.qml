import QtQuick
import qs.kit

// A small badge at the right of the sidebar's title while a message goes (Outbox.qml): "Sending…", or "Not sent". Only
// these two short words: what went wrong, and Try again / Open (back into the writing window), are in a card that a click
// on "Not sent" opens under it. Hidden when there is nothing to show.
Item {
    id: root
    required property QtObject c
    required property QtObject outbox
    property Item frame: parent         // the card starts at its left (the sidebar's)
    readonly property var job: outbox.failedJob
    readonly property bool cardOpen: card.visible
    visible: outbox.jobs.length > 0
    implicitWidth: badge.width
    implicitHeight: badge.height
    onJobChanged: if (!job) card.visible = false

    Rectangle {
        id: badge
        width: label.implicitWidth + 12; height: 18; radius: 9
        color: root.job ? Qt.rgba(root.c.danger.r, root.c.danger.g, root.c.danger.b, badgeHover.hovered || card.visible ? 0.28 : 0.16)
                        : root.c.hover
        Text {
            id: label
            anchors.centerIn: parent
            text: root.job ? "Not sent" : "Sending…"
            color: root.job ? root.c.danger : root.c.dim; font.family: root.c.font; font.pixelSize: 10
        }
        HoverHandler { id: badgeHover; enabled: !!root.job; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: !!root.job; onTapped: card.visible = !card.visible }
        Tip {
            y: parent.height + 8; c: root.c; hovered: badgeHover.hovered && !card.visible
            text: "What went wrong"
        }
    }

    // Lies over the list beside the sidebar (the sidebar is above it), starting at the sidebar's left so it isn't cut
    // off by the window's edge in a narrow one. It closes once the pointer has been away from it and the badge a moment.
    Rectangle {
        id: card
        visible: false
        z: 10
        y: badge.height + 8
        width: 260; height: column.implicitHeight + 24
        radius: 10
        color: root.c.solid
        border.color: root.c.line
        onVisibleChanged: if (visible) x = root.mapFromItem(root.frame, 12, 0).x
        HoverHandler { id: cardHover }
        Timer { interval: 600; running: card.visible && !cardHover.hovered && !badgeHover.hovered; onTriggered: card.visible = false }
        Column {
            id: column
            x: 14; y: 12; width: parent.width - 28
            spacing: 10
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: root.job ? root.job.error : ""
                color: root.c.text; font.family: root.c.font; font.pixelSize: 12
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "The message is kept in Drafts."
                color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
            }
            Row {
                spacing: 8
                AppButton {
                    c: root.c; glyph: "rotate-cw"; label: "Try again"; strong: true
                    onClicked: { card.visible = false; root.outbox.retry(root.job) }
                }
                AppButton {
                    c: root.c; glyph: "pencil"; label: "Open"
                    onClicked: { card.visible = false; root.outbox.open(root.job) }
                }
            }
        }
    }
}
