import QtQuick
import Quickshell.Io
import qs.kit

// Contacts' settings (⌘, or launcher › Settings › Apps › Contacts): the accounts with how many contacts each has here,
// when the sync last ran, and the two things to do about them: sync now, and add an account (with Claude, as the first
// start does). The accounts themselves are the user's accounts.conf (README.md › Setting up an account).
AppPanel {
    id: root
    required property var app           // the window: accounts, command, startSetup(), say()
    signal closed()
    visible: false
    cardWidth: 520
    spacing: 22

    property string lastSync: ""        // HH:MM of the timer's last round today, else its date
    property bool syncing: false

    function open() { visible = true; forceActiveFocus(); when.running = true }
    function close() { visible = false; closed() }
    function syncNow() {
        if (syncing) return
        syncing = true
        syncer.running = true
    }
    function addAccount() { close(); app.startSetup() }

    onOutsideTapped: close()
    Keys.onPressed: e => {
        const k = e.key
        if (k === Qt.Key_Escape || ((k === Qt.Key_Comma) && (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)))) close()
        else if (k === Qt.Key_S) syncNow()
        else if (k === Qt.Key_A) addAccount()
        e.accepted = true
    }

    // The sync timer's last round (systemd's): "Mon 2026-10-26 14:30:12 EET"
    Process {
        id: when
        command: ["systemctl", "--user", "show", "-p", "ExecMainExitTimestamp", "--value", "nightdrive-contacts-sync.service"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})/)
                const today = Qt.formatDate(new Date(), "yyyy-MM-dd")
                root.lastSync = !m ? "" : m[1] === today ? m[2] : Qt.formatDate(new Date(m[1]), "d MMMM") + " " + m[2]
            }
        }
    }
    Process {
        id: syncer
        command: [root.app.command, "sync"]
        onExited: code => {
            root.syncing = false
            root.app.say(code === 0 ? "Synced" : "Some accounts couldn't be reached: they sync at the next round.")
            when.running = true
        }
    }

    Row {
        width: parent.width
        Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - escHint.width; text: "Settings"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
        KeyCap { id: escHint; anchors.verticalCenter: parent.verticalCenter; c: root.c; keys: "esc"; tint: root.c.faint }
    }

    Column {
        width: parent.width
        spacing: 10
        Text { text: "Accounts"; color: c.text; font.family: c.font; font.pixelSize: 13 }
        Repeater {
            model: root.app.accounts
            delegate: Row {
                required property var modelData
                width: parent.width
                Text { width: parent.width - count.width; elide: Text.ElideRight; text: modelData.name; color: c.title; font.family: c.font; font.pixelSize: 12 }
                Text { id: count; text: modelData.count + " contacts"; color: c.faint; font.family: c.font; font.pixelSize: 12 }
            }
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap; color: c.faint; font.family: c.font; font.pixelSize: 11
            text: root.syncing ? "Syncing…"
                : "Synced both ways every 30 minutes" + (root.lastSync ? ", last at " + root.lastSync : "") + ". A change made here goes at once."
        }
    }

    Row {
        spacing: 22
        AppKeyAction { c: root.c; keys: "S"; label: "Sync now"; color: c.primary; hoverColor: c.title; onClicked: root.syncNow() }
        AppKeyAction { c: root.c; keys: "A"; label: "Add an account with Claude"; onClicked: root.addAccount() }
    }

    Text {
        width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2; color: c.faint; font.family: c.font; font.pixelSize: 11
        text: "Your contacts are in the launcher's search too (launcher › Settings › Launcher), and Mail completes addresses from them."
    }
}
