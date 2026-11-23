import QtQuick
import Quickshell.Io
import "AskClaudeCards.js" as Cards

// A sound Claude found (AskClaudeResults.qml, #2245): ▶/⏸ plays it at once from the conversation's own folder, a bar
// shows where it is (a click there moves to it), its length beside it, and Save copies it into Downloads. One sound
// plays at a time: the conversation's player (kit's AppAudio, given by AskClaudeThread) is shared, and this card's
// is the one playing while the player's path is this file.
AskClaudeCard {
    id: c
    glyph: "audio-lines"
    property var player: null

    readonly property bool mine: !!player && player.path === path
    readonly property bool playing: mine && player.playing
    property real length: 0              // seconds, from ffprobe; 0 while unknown

    function toggle() {
        if (!player) return
        if (mine) { player.toggle(); return }
        player.path = path               // stops another card's sound, and starts at 0
        player.title = card.title || card.file
        player.duration = length
        player.play()
    }
    // The player is told the length when it comes, should this card already be playing
    onLengthChanged: if (mine) player.duration = length

    // Its length: ffmpeg's ffprobe, which AppAudio's ffmpeg comes with
    Process {
        running: c.path !== ""
        command: ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", c.path]
        stdout: StdioCollector { onStreamFinished: { const n = parseFloat(text); if (n > 0) c.length = n } }
    }

    Item {
        width: parent.width
        height: 32
        readonly property bool narrow: width < 300

        AskClaudeCardButton {
            id: play
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            strong: true
            glyph: c.playing ? "pause" : "play"
            onClicked: c.toggle()
        }
        // Where it is: a thin bar, filled as it plays
        Item {
            id: bar
            anchors { left: play.right; leftMargin: 12; right: time.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            height: 16
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 4; radius: 2
                color: Theme.border
                Rectangle {
                    width: parent.width * (c.mine ? c.player.progress : 0)
                    height: parent.height; radius: 2
                    color: Theme.accent
                }
            }
            HoverHandler { cursorShape: c.mine && c.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { onTapped: e => { if (c.mine && c.length > 0) c.player.seek(e.position.x / bar.width * c.length) } }
        }
        Text {
            id: time
            anchors { right: save.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: c.mine && c.player.position > 0 ? Cards.duration(c.player.position) + " / " + Cards.duration(c.length)
                                                  : c.length > 0 ? Cards.duration(c.length) : ""
            color: Theme.dim
            font { family: Theme.font; pixelSize: 12; features: { "tnum": 1 } }
        }
        AskClaudeCardButton {
            id: save
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            compact: parent.narrow
            glyph: "download"
            label: done ? "Saved" : "Save"
            done: !!c.saved && !c.saved.error
            onClicked: c.session.save(c.card.file)
        }
    }
}
