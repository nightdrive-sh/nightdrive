import QtQuick
import Quickshell
import qs

// Ferry (the `ferry` command of Ferry's own install): a mailbox between this computer and the owner's other devices (phones, other computers' Ferry). The
// menu lists what they sent here on one card: a click copies a text or opens a file, a file drags out into another app,
// and Clear empties the list. Below it the three ways to send, as in the phone's app: Aa (a
// text typed here), Send Clipboard and + (files from a dialog), to the device in the pill above them (the last one
// picked; a click on it lists the devices, and Add Device). Files dragged over the menu turn the list into a tile per
// device: the drop goes to the tile's device (a drop on the bar icon, or between the tiles, to the pill's). The big
// button says for a moment that a send went, whoever sent it (`ferry list --json`'s sent). Settings beside Clear opens
// the settings in the menu's place (FerrySettings.qml): forgetting devices.
// This file holds the menu's state and layout; its parts are files of their own beside it, each passed the menu:
// FerryWarning, FerryReceivedList (FerryReceivedRow), FerryDropTile, FerryPill, FerryPicker (FerryDeviceRow),
// FerryRoundButton and FerryAddDevice.
Column {
    id: m
    width: parent ? parent.width : 360
    spacing: 12
    readonly property int preferredWidth: 360
    signal close()

    // Ferry's command, which its install script links into ~/.local/bin (install.sh): not on Quickshell's PATH for sure
    readonly property string ferry: Quickshell.env("HOME") + "/.local/bin/ferry"
    property var st: null              // `ferry list --json`: { on, tailscale, url, serving, items, devices, target, sent }
    readonly property var items: st ? st.items : []
    // A copied code or password leaves the box at once: its row stays while it says "copied", or it would look lost
    readonly property var received: {
        const r = items.filter(i => i.to === "computer").reverse()
        if (copied && flash === copied.id && !r.some(i => i.id === copied.id)) r.splice(copied.at, 0, copied.item)
        return r
    }
    property var copied: null          // the row last copied, and where it was
    readonly property var devices: st && st.devices ? st.devices : []
    property string picked: ""         // the device just picked, until `ferry list` says so too
    readonly property string targetId: picked || (st ? st.target || "" : "")
    readonly property var target: devices.find(d => d.id === targetId) || null
    property string mode: "list"       // list | pick (the pill's list floating over the list) | write (a text to send) | settings
    property string flash: ""          // what says "copied" for a moment: an item's id or "url"
    property bool adding: false        // Add Device: the QR code in the middle of the screen
    property string qr: ""             // the QR code's SVG once made
    property int dragging: 0           // files being dragged out: shell.qml lets the drop through to the windows below
    property int tileDrags: 0          // tiles with files over them
    readonly property bool dropping: outerDrop.containsDrag || tileDrags > 0 || dropHold.running
    readonly property int rowHeight: 56
    readonly property int listLift: 30   // how far the pill comes up over a long list
    readonly property int listFade: 64   // the fade at the bottom of a long list
    // The big button says how every send went, its own and a drop's (here, on a tile or on the bar icon), a pick's (+)
    // or `ferry send`'s: "Sent to …" for a moment once `ferry list` reports it (sent.json), "Not sent" when it failed
    // (a notification says why). Its own send says "Sending…" until then, and gives up waiting after a while.
    property real sendingSince: 0      // seconds: when the button sent, while waiting for it to show
    property real shownSent: 0         // the sent.json time the button has shown
    property bool justSent: false
    property bool sendFailed: false    // the button's own send didn't go: "Not sent" for a moment

    function refresh() { listProc.running = true }
    function run(args) { Quickshell.execDetached([m.ferry].concat(args)); soon.restart() }
    function flashOn(what) { m.flash = what; flashTimer.restart() }
    function ago(t) {
        const s = Date.now() / 1000 - t
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + " min" : s < 86400 ? Math.floor(s / 3600) + " h" : Math.floor(s / 86400) + " d"
    }
    function size(n) {
        const u = ["B", "KB", "MB", "GB"]
        let i = 0
        while (n >= 1000 && i < 3) { n /= 1000; i++ }
        return (i === 0 ? n : n.toFixed(1)) + " " + u[i]
    }
    function act(it) {
        if (it.kind === "text") { m.copied = { id: it.id, item: it, at: Math.max(0, m.received.indexOf(it)) }; m.run(["copy", it.id]); m.flashOn(it.id) }
        else { m.run(["open", it.id]); m.close() }
    }
    function deviceIcon(d) { return !d ? "qr-code" : d.kind === "computer" ? "laptop" : d.kind === "tablet" ? "tablet" : "smartphone" }
    function deviceState(d) { return d.inUse ? "in use" : d.online ? "online" : d.kind === "computer" ? "asleep" : "offline" }
    // An asleep computer can't take a send (it goes straight there); a phone picks it up later
    function canTake(d) { return d.online || d.kind !== "computer" }
    function pick(d) { m.picked = d.id; m.run(["target", d.id]); m.mode = "list" }
    function paths(drop) {
        return Array.from(drop.urls, u => u.toString()).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)))
    }
    function sendText() {
        const t = textEdit.text
        if (!t.trim() || !m.target) return
        m.sendFrom(["text", "--to", m.target.id, t])
        textEdit.text = ""
        m.mode = "list"
    }
    function sendFrom(args) {
        m.sendingSince = Date.now() / 1000 - 1
        m.justSent = m.sendFailed = false
        sendGiveUp.restart()
        m.run(args)
    }
    function addDevice() {
        m.mode = "list"
        m.adding = true
        if (m.qr === "") qrProc.running = true
    }
    // The pictures' small copies (the list's rows): the menu is made anew at each opening, and Qt forgets a picture
    // soon after, so each opening read every photo again. Gone at logout.
    readonly property string thumbDir: Quickshell.env("XDG_RUNTIME_DIR") + "/ferry-menu"
    Component.onCompleted: { refresh(); Quickshell.execDetached(["mkdir", "-p", m.thumbDir]) }
    onStChanged: {
        if (m.picked && st && st.target === m.picked) m.picked = ""
        if (st && st.sent && st.sent.time !== m.shownSent && (!m.sendingSince || st.sent.time >= m.sendingSince)) {
            m.shownSent = st.sent.time
            m.sendingSince = 0
            m.justSent = !st.sent.error
            m.sendFailed = !!st.sent.error
            sentFlash.restart()
        }
    }
    Timer { id: sentFlash; interval: 2000; onTriggered: { m.justSent = false; m.sendFailed = false } }
    Timer { id: sendGiveUp; interval: 15000; onTriggered: m.sendingSince = 0 }
    Timer { interval: 500; repeat: true; running: m.sendingSince > 0; onTriggered: m.refresh() }   // to show "Sent" soon
    onModeChanged: if (mode === "write") Qt.callLater(() => textEdit.forceActiveFocus())   // once it shows
    Timer { interval: 2000; repeat: true; running: true; onTriggered: m.refresh() }
    Timer { id: soon; interval: 400; onTriggered: m.refresh() }
    Timer { id: flashTimer; interval: 1500; onTriggered: m.flash = "" }
    // Between two tiles the files are over neither for a moment: the tiles stay meanwhile
    Timer { id: dropHold; interval: 150 }
    function holdDrop() { dropHold.restart() }   // FerryDropTile.qml, as a tile's drop leaves it
    onDroppingChanged: if (!dropping) tileDrags = 0

    Sh {
        id: listProc
        command: [m.ferry, "list", "--json"]
        // Read every 2 s, but only a change is shown: a new list would make every row anew, and with them the keyboard's
        // pick and a picture's load
        property string last: ""
        onResult: text => {
            if (text === last) return
            try { m.st = JSON.parse(text) } catch (e) { return }
            last = text
            // Seen once the menu shows them: the bar's count goes
            if (m.st.items.some(i => i.to === "computer" && !i.seen)) seenProc.running = true
        }
    }
    Sh { id: seenProc; command: [m.ferry, "seen"]; onResult: TopBar.refresh("ferry") }
    Sh {
        id: qrProc
        command: [m.ferry, "qr", "--svg"]
        onResult: text => m.qr = text.trim()
    }

    // The plugin's name as in the other menus. Clear: what the other devices sent here leaves the box (files stay in
    // Downloads)
    MenuHeader {
        visible: m.mode !== "settings"
        width: parent.width
        title: "Ferry"
        action: !m.dropping && m.received.length ? "Clear" : ""
        onActionClicked: m.run(["clear", "received"])
        tool: m.dropping ? "" : "settings"
        toolLabel: "Settings"
        onToolClicked: m.mode = "settings"
    }

    FerryWarning {
        menu: m
        width: parent.width
    }

    // The list, the pill (its list floats over the list) and the buttons; files over any of it turn it into tiles
    // While files are over it, it keeps at least the height it had before: tiles shorter than the list would leave the
    // cursor below it, the tiles would go, the list come back under the cursor, and so on (the menu flickered).
    Item {
        id: body
        visible: m.mode !== "settings"
        property real restHeight: 0
        width: parent.width
        height: Math.max(stack.y + stack.height, m.dropping ? restHeight : 0)
        onHeightChanged: if (!m.dropping) restHeight = height

        // Files dropped between the tiles go to the pill's device, as on the bar icon. Under the tiles, which take
        // the drop over them.
        DropArea {
            id: outerDrop
            anchors.fill: parent
            keys: ["text/uri-list"]
            onEntered: drag => { drag.accepted = m.dragging === 0 }   // not a row of this list dragged out
            onExited: dropHold.restart()
            onDropped: d => {
                const p = m.paths(d)
                if (!p.length || !m.target) return
                m.run(["add", "--to", m.target.id].concat(p))
                d.acceptProposedAction()
            }
        }

        Column {
            id: stack
            // Room above the pill for its list when the list is short
            y: picker.visible ? Math.max(0, picker.height - 2 - pillWrap.y) : 0
            width: parent.width
            spacing: 12

            // ---- dropping: a tile per device ----
            // What a drop does; the list of what arrived needs no title. Here in the drop area, not above it: coming
            // down from the bar icon, a title above would push the area from under the cursor as it showed.
            MenuSection {
                visible: m.dropping
                title: "Send to"
                topPadding: 0
                color: Theme.dim
            }
            Grid {
                visible: m.dropping
                width: parent.width
                columns: 2
                spacing: 10
                Repeater {
                    model: m.devices
                    delegate: FerryDropTile {
                        required property var modelData
                        menu: m
                        dev: modelData
                        width: (stack.width - 10) / 2
                    }
                }
            }
            MenuNote {
                visible: m.dropping && m.devices.length === 0
                width: parent.width
                text: "No other device yet: add one with Add Device below the list."
            }

            // ---- the list: what the other devices sent ----
            FerryReceivedList {
                id: listBox
                menu: m
                visible: !m.dropping && m.received.length > 0
                width: parent.width
            }

            // ---- nothing received ----
            Rectangle {
                visible: !m.dropping && m.received.length === 0
                width: parent.width
                height: 120
                radius: 14
                color: Theme.card
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 44; height: 44; radius: 12
                        color: Theme.sel
                        Text {
                            anchors.centerIn: parent
                            text: Icons.g("inbox")
                            color: Theme.accent
                            font { family: Icons.family; pixelSize: 22 }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Nothing received yet"
                        color: Theme.dim
                        font { family: Theme.font; pixelSize: 12 }
                    }
                }
            }

            // ---- the device sends go to ----
            FerryPill {
                id: pillWrap
                menu: m
                visible: !m.dropping
                width: parent.width
                roomAbove: !listBox.scrolls
            }

            // ---- Aa: a text to send, below the pill that says to whom ----
            Rectangle {
                visible: !m.dropping && m.mode === "write"
                width: parent.width
                height: Math.max(96, textEdit.contentHeight + 28)
                radius: 14
                color: Theme.card
                border { width: 1; color: textEdit.activeFocus ? Theme.primary : Theme.border }
                Text {
                    visible: textEdit.text === ""
                    anchors { left: textEdit.left; top: textEdit.top }
                    text: m.target ? "A text for " + m.target.name : "A text"
                    textFormat: Text.PlainText   // the device's name: never markup
                    color: Theme.dim
                    font: textEdit.font
                }
                TextEdit {
                    id: textEdit
                    anchors { fill: parent; margins: 14 }
                    wrapMode: TextEdit.Wrap
                    color: Theme.accent
                    selectionColor: Theme.sel
                    selectedTextColor: Theme.accent
                    font { family: Theme.font; pixelSize: 13 }
                    // Enter sends, Shift+Enter starts a new line; Esc goes back to the list
                    Keys.onPressed: e => {
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                            m.sendText(); e.accepted = true
                        } else if (e.key === Qt.Key_Escape) {
                            m.mode = "list"; e.accepted = true
                        }
                    }
                }
            }

            // ---- Aa, Send Clipboard, + ----
            Row {
                visible: !m.dropping
                width: parent.width
                spacing: 10
                FerryRoundButton {
                    label: "Aa"
                    on: m.mode === "write"
                    usable: !!m.target
                    onClicked: m.mode = m.mode === "write" ? "list" : "write"
                }
                // In the text's place: Send (the text); otherwise Send Clipboard
                MenuButton {
                    width: parent.width - 2 * (36 + parent.spacing)
                    usable: !!m.target && m.canTake(m.target) && !m.sendingSince && (m.mode !== "write" || textEdit.text.trim() !== "")
                    icon: m.justSent ? "check" : m.sendFailed ? "circle-x" : m.sendingSince ? "loader" : m.mode === "write" ? "send" : "clipboard-copy"
                    label: m.justSent ? "Sent to " + (m.st && m.st.sent ? m.st.sent.to : "") : m.sendFailed ? "Not sent" : m.sendingSince ? "Sending…"
                         : m.mode === "write" ? "Send" : "Send Clipboard"
                    onClicked: if (m.mode === "write") m.sendText(); else m.sendFrom(["send-clipboard", "--to", m.target.id])
                }
                // Files from a dialog: the menu closes for it and opens again with "Sent"
                FerryRoundButton {
                    icon: "plus"
                    usable: !!m.target && m.canTake(m.target)
                    onClicked: { Quickshell.execDetached([m.ferry, "pick", "--to", m.target.id]); m.close() }
                }
            }
        }

        // The pill's list, floating above the pill over the list (the menu grows when there's no room above it). A click
        // beside it closes it, the pill's own too.
        MouseArea {
            visible: picker.visible
            anchors.fill: parent
            z: 9
            hoverEnabled: true   // takes the hover too: the rows under it don't light up
            onClicked: m.mode = "list"
        }
        FerryPicker {
            id: picker
            menu: m
            visible: !m.dropping && m.mode === "pick"
            z: 10
            anchors.horizontalCenter: parent.horizontalCenter
            y: stack.y + pillWrap.y + 10 - height - 8   // the pill sits 10 px into its wrapper
        }
    }

    FerrySettings {
        visible: m.mode === "settings"
        width: parent.width
        menu: m
        onDone: m.mode = "list"
    }

    // Add Device: the QR code in the middle of the screen
    FerryAddDevice {
        menu: m
        visible: m.adding
    }
}
