import QtQuick
import qs.kit

// The first start: Deck plays as it is; your own Spotify app and Last.fm make the rest work. Enter (or the button)
// opens Claude Code in a terminal to set up what is missing (`deck-window setup`); Esc or a click outside puts it
// aside, and Curated's own button offers it again. Its own file as a panel over the window, as CuratePanel; the window
// shows it while CurateSetup's setupOffer holds.
AppPanel {
    id: root
    required property var win
    readonly property var setup: win.setup
    c: win.look
    onVisibleChanged: if (visible) forceActiveFocus()
    onOutsideTapped: setup.dismissSetup()
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) setup.startSetup()
        else if (e.key === Qt.Key_Escape) setup.dismissSetup()
        e.accepted = true
    }
    Text { text: root.setup.hasApp ? "Curated: albums picked for you" : "Set up Deck"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
    Text {
        width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2; color: c.text; font.family: c.font; font.pixelSize: 12
        text: root.setup.setupStarted
            ? "Claude opens in a terminal and goes through it with you. When it's done, Curated's New list makes your first list here."
            : root.setup.hasApp
            ? "Deck plays your Spotify as it is. Curated adds a list of albums you haven't heard, each with a reason why it is there for you, picked by Claude from your Last.fm listening history, or without it, from what you tell about your taste and play in Deck. Claude can set it up with you in a terminal, a step at a time."
            : "Deck plays your Spotify as it is. Two things make the rest work: your own Spotify app (free, a couple of minutes), for likes, search without Spotify's shared limits and Curated; and your taste, for Curated: a list of albums you haven't heard, each with a reason, picked by Claude from your Last.fm history or from what you tell it. Claude can set them up with you in a terminal, a step at a time. You sign in to Spotify only in your browser."
    }
    Row {
        spacing: 28
        AppKeyAction {
            c: root.c
            keys: "⏎"; label: root.setup.setupStarted ? "Open Claude again" : "Set up with Claude"; color: c.primary; hoverColor: c.title
            onClicked: root.setup.startSetup()
        }
        AppKeyAction {
            c: root.c
            keys: "esc"; label: root.setup.setupStarted ? "Close" : "Not now"
            onClicked: root.setup.dismissSetup()
        }
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap; color: c.faint; font.family: c.font; font.pixelSize: 11
        text: "Later: Curated (⌘2) has the same button. To do it yourself: Deck's README, " + (root.setup.hasApp ? "" : "Create your own Spotify app and ") + "Setting up Curated."
    }
}
