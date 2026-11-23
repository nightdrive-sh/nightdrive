import QtQuick
import "AskClaudeCards.js" as Cards

// A picture Claude found (AskClaudeResults.qml, #2245): a small preview beside its size and Save; a click on the
// preview shows it as wide as the card (another click makes it small again). Both are decoded no bigger than they are
// shown (sourceSize), so a 6000 px photo doesn't hold its full size in memory for a thumbnail.
AskClaudeCard {
    id: c
    glyph: "image"
    property bool big: false

    // --- Tunables ---
    readonly property int thumbW: 112
    readonly property int thumbH: 76
    readonly property int bigMaxH: 420

    Column {
        width: parent.width
        spacing: 8

        Item {
            width: parent.width
            height: c.thumbH
            visible: !c.big
            Rectangle {
                id: thumbFrame
                width: c.thumbW; height: c.thumbH
                radius: 6
                color: Theme.bg
                clip: true
                Image {
                    id: thumb
                    anchors.fill: parent
                    source: c.path !== "" && !c.big ? "file://" + c.path : ""
                    sourceSize { width: c.thumbW * 2; height: c.thumbH * 2 }   // sharp on a scale-2 screen
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }
                Text {
                    anchors.centerIn: parent
                    visible: thumb.status === Image.Error
                    text: Icons.g("image")
                    color: Theme.dim
                    font { family: Icons.family; pixelSize: 20 }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: c.big = true }
            }
            Column {
                anchors { left: thumbFrame.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text {
                    width: parent.width
                    text: [Cards.kind(c.card), Cards.size(c.card.size)].filter(t => t).join(" · ")
                    elide: Text.ElideRight
                    color: Theme.dim
                    font { family: Theme.font; pixelSize: 12 }
                }
                AskClaudeCardButton {
                    glyph: "download"
                    label: done ? "Saved" : "Save"
                    done: !!c.saved && !c.saved.error
                    onClicked: c.session.save(c.card.file)
                }
            }
        }

        // As wide as the card, its height at most bigMaxH; a click makes it small again
        Image {
            id: large
            visible: c.big
            width: parent.width
            height: status === Image.Ready && implicitWidth > 0
                    ? Math.min(c.bigMaxH, width * implicitHeight / implicitWidth) : 120
            source: c.big && c.path !== "" ? "file://" + c.path : ""
            sourceSize.width: 1400
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            asynchronous: true
            cache: false
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: c.big = false }
        }
        Row {
            visible: c.big
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: [Cards.kind(c.card), Cards.size(c.card.size)].filter(t => t).join(" · ")
                color: Theme.dim
                font { family: Theme.font; pixelSize: 12 }
            }
            AskClaudeCardButton {
                glyph: "download"
                label: done ? "Saved" : "Save"
                done: !!c.saved && !c.saved.error
                onClicked: c.session.save(c.card.file)
            }
            AskClaudeCardButton {
                glyph: "minimize-2"
                label: "Smaller"
                onClicked: c.big = false
            }
        }
    }
}
