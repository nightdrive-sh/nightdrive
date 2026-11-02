import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// The player along the window's bottom: the playing track with its cover, the controls over the playhead, and the note
// line, where the sound plays and the heart. Its own file as the one part that is the same whatever view is open.
// Below the window's playerMin it keeps to the controls and the track.
Item {
    id: root
    required property var win
    readonly property QtObject c: win.look
    readonly property var player: win.player
    readonly property var act: win.act
    readonly property bool narrow: win.nav.narrowPlayer
    // Where the sound outputs open from (OutputsPopup)
    readonly property alias speaker: speakerIcon

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 28
        spacing: 16
        Item {
            Layout.preferredWidth: 60; Layout.preferredHeight: 60
            Image {
                id: cover
                anchors.fill: parent
                sourceSize: Qt.size(120, 120)
                fillMode: Image.PreserveAspectCrop
                source: root.player.info && root.player.info.cover ? root.player.info.cover : ""
                visible: source !== "" && status === Image.Ready
            }
            HoverHandler { id: cvh; enabled: !!root.player.info; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !!root.player.info; onTapped: root.win.nav.openPlaying() }
            Tip { y: -height - 10; c: root.c; text: root.player.info && root.player.info.album_uri ? "Open the album" : "Open the radio"; keys: "n"; hovered: cvh.hovered }
            Rectangle {
                anchors.fill: parent; radius: 6
                visible: !cover.visible
                color: c.hover
                Text { anchors.centerIn: parent; text: Icons.g("disc-3"); color: c.dim; font.family: Icons.family; font.pixelSize: 24 }
            }
        }
        // A narrow player gives the track what the controls leave, and the note its second line
        Column {
            Layout.preferredWidth: root.narrow ? 1 : 260
            Layout.fillWidth: root.narrow
            // Room before the playhead's time, so a long album name doesn't run up to it
            Layout.rightMargin: 16
            spacing: 3
            Text {
                width: parent.width; elide: Text.ElideRight
                text: root.player.info ? root.player.info.title : root.player.alive ? "Nothing playing" : "Deck isn't running"; textFormat: Text.PlainText
                color: root.player.info ? c.accent : c.dim; font.family: c.font; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            Row {
                width: parent.width
                visible: !!root.player.info && !playerNote.visible
                spacing: 8
                Text {
                    width: Math.min(implicitWidth, parent.width - (shelfButton.visible ? shelfButton.width + 8 : 0))
                    elide: Text.ElideRight
                    text: root.player.info ? root.player.info.artist + " · " + root.player.info.album : ""; textFormat: Text.PlainText
                    color: c.dim; font.family: c.font; font.pixelSize: 12
                }
                // The playing album on the shelf, or off it: by the album's name, so it doesn't read as the
                // heart's (which is the track's). Not for a radio track: Deck knows no album for it.
                Text {
                    id: shelfButton
                    readonly property string uri: root.player.info && root.player.info.album_uri ? root.player.info.album_uri : ""
                    readonly property bool on: !!root.win.lib.shelfUris[uri]
                    anchors.verticalCenter: parent.verticalCenter
                    visible: uri !== ""
                    text: Icons.g("library")
                    color: on || sbh.hovered ? c.primary : c.faint
                    font.family: Icons.family; font.pixelSize: 14
                    HoverHandler { id: sbh; cursorShape: Qt.PointingHandCursor }
                    Tip { x: (parent.width - width) / 2; y: -height - 10; c: root.c; text: shelfButton.on ? "Take the album off the shelf" : "Put the album on the shelf"; hovered: sbh.hovered }
                    TapHandler {
                        onTapped: {
                            root.player.ctl([shelfButton.on ? "shelf-remove" : "shelf-add", shelfButton.uri])
                            root.act.note = (shelfButton.on ? "Taken off the shelf: " : "On the shelf: ") + root.player.info.album
                        }
                    }
                }
            }
            Text {
                id: playerNote
                visible: root.narrow && root.act.note !== ""
                width: parent.width; elide: Text.ElideRight
                text: root.act.note
                color: root.act.noteDanger ? c.danger : c.dim; font.family: c.font; font.pixelSize: 11
            }
            Text {
                visible: !root.player.alive && !playerNote.visible
                text: "Start Deck"
                color: sth.hovered ? c.primary : c.text; font.family: c.font; font.pixelSize: 12
                HoverHandler { id: sth; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.player.startDeck() }
            }
        }
        // Controls over the playhead; a click or a drag on the bar jumps
        ColumnLayout {
            Layout.fillWidth: !root.narrow
            Layout.preferredWidth: root.narrow ? 170 : -1
            spacing: 8
            opacity: root.player.info ? 1 : 0.35
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 26
                Repeater {
                    model: [
                        { glyph: "skip-back", size: 18, act: "previous", tip: "Previous track", keys: "←" },
                        { glyph: "play", size: 24, act: "toggle", tip: "Play, pause", keys: "Space" },
                        { glyph: "skip-forward", size: 18, act: "next", tip: "Next track", keys: "→" }
                    ]
                    delegate: Text {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.g(modelData.act === "toggle" ? (root.player.playing ? "pause" : "play") : modelData.glyph)
                        color: ch.hovered ? c.primary : c.text
                        font.family: Icons.family; font.pixelSize: modelData.size
                        HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                        Tip { x: (parent.width - width) / 2; y: -height - 10; c: root.c; text: modelData.tip; keys: modelData.keys; hovered: ch.hovered }
                        TapHandler { onTapped: modelData.act === "toggle" ? root.player.togglePlay() : modelData.act === "next" ? root.player.next() : root.player.ctl([modelData.act]) }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: root.win.page.fmt(bar.dragAt >= 0 ? bar.dragAt * root.player.duration : root.player.position); color: c.faint; font.family: c.font; font.pixelSize: 10 }
                // The bar stays 3 px; what takes the pointer is taller, so it is easy to hit
                Item {
                    id: bar
                    Layout.fillWidth: true; implicitHeight: 16
                    property real dragAt: -1          // while dragging: where it will jump, 0–1
                    readonly property real shown: dragAt >= 0 ? dragAt : root.player.duration > 0 ? root.player.position / root.player.duration : 0
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: seekArea.containsMouse || bar.dragAt >= 0 ? 5 : 3; radius: height / 2
                        color: c.line
                        Rectangle { width: parent.width * bar.shown; height: parent.height; radius: parent.radius; color: c.primary }
                    }
                    MouseArea {
                        id: seekArea
                        anchors.fill: parent
                        enabled: !!root.player.info && root.player.duration > 0
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: m => bar.dragAt = Math.max(0, Math.min(1, m.x / width))
                        onPositionChanged: m => { if (pressed) bar.dragAt = Math.max(0, Math.min(1, m.x / width)) }
                        onReleased: { root.player.seek(bar.dragAt); bar.dragAt = -1 }
                        onCanceled: bar.dragAt = -1
                    }
                }
                Text { text: root.win.page.fmt(root.player.duration); color: c.faint; font.family: c.font; font.pixelSize: 10 }
            }
        }
        Item {
            Layout.preferredWidth: root.narrow ? speakerIcon.width + (heart.visible ? 18 + heart.width : 0) : 260
            Layout.fillHeight: true
            Text {
                visible: !root.narrow
                anchors.right: speakerIcon.left; anchors.rightMargin: 18
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                text: root.act.note
                color: root.act.noteDanger ? c.danger : c.dim; font.family: c.font; font.pixelSize: 11
            }
            // Where the sound goes: the same list as the Sound menu's
            Text {
                id: speakerIcon
                anchors.right: heart.visible ? heart.left : parent.right; anchors.rightMargin: heart.visible ? 18 : 0
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.g("speaker")
                color: root.win.outputs.visible || oh.hovered ? c.primary : c.dim
                font.family: Icons.family; font.pixelSize: 18
                HoverHandler { id: oh; cursorShape: Qt.PointingHandCursor }
                // Ending at the button's right edge, as the heart's: the window's edge is near
                Tip { x: parent.width - width; y: -height - 10; c: root.c; text: "Where the sound plays"; keys: "o"; hovered: oh.hovered && !root.win.outputs.visible }
                TapHandler { onTapped: root.win.outputs.visible = !root.win.outputs.visible }
            }
            Text {
                id: heart
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                visible: root.player.liked !== null && root.player.liked !== undefined
                text: Icons.g("heart")
                color: root.player.liked ? c.primary : lh.hovered ? c.primary : c.dim
                font.family: Icons.family; font.pixelSize: 18
                HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
                Tip { x: parent.width - width; y: -height - 10; c: root.c; text: root.player.liked ? "Unlike the track" : "Like the track"; keys: "l"; hovered: lh.hovered }
                TapHandler { onTapped: root.player.toggleLike() }
            }
        }
    }
}
