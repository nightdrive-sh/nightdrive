import QtQuick
import qs.kit

// Mail's first start, before an account: Enter (or the button) opens Claude Code in a terminal, which sets it up with
// you by README.md (`nightmail setup`). Apart from shell.qml, which shows it while win.needsAccount.
AppPanel {
    id: setup
    required property var win
    property bool setupStarted: false
    function startSetup() { setup.setupStarted = true; win.mailer.nightmail(["setup"], () => {}) }
    visible: win.needsAccount
    c: win.look
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) setup.startSetup()
        e.accepted = true
    }
    Text { text: "Set up your email account"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
    Text {
        width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2; color: c.text; font.family: c.font; font.pixelSize: 12
        text: setup.setupStarted
            ? "Claude opens in a terminal and goes through it with you. When it's done, your inbox shows here."
            : "Mail keeps your mail on this computer, fetched from your provider. Claude can set up the account with you in a terminal, a step at a time: it asks your address and writes the settings. Your password goes only into the login keyring, never to Claude."
    }
    AppKeyAction {
        c: win.look
        keys: "⏎"; label: setup.setupStarted ? "Open Claude again" : "Set up with Claude"; color: c.primary; hoverColor: c.title
        onClicked: setup.startSetup()
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap; color: c.faint; font.family: c.font; font.pixelSize: 11
        text: "To do it yourself: Mail's README has the steps (plugins/mail/README.md in Nightdrive)."
    }
}
