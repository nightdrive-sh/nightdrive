import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Ferry (the `ferry` command of Ferry's own install): a mailbox between this computer and the owner's other devices (phones, other computers' Ferry). The
// menu lists what they sent here on one card: a click copies a text or opens a file, a file drags out into another app,
// and Clear empties the list. Below it the three ways to send, as in the phone's app: Aa (a
// text typed here), Send Clipboard and + (files from a dialog), to the device in the pill above them (the last one
// picked; a click on it lists the devices, and Add Device). Files dragged over the menu turn the list into a tile per
// device: the drop goes to the tile's device (a drop on the bar icon, or between the tiles, to the pill's). The big
// button says for a moment that a send went, whoever sent it (`ferry list --json`'s sent).
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
    readonly property var received: items.filter(i => i.to === "computer").reverse()
    readonly property var devices: st && st.devices ? st.devices : []
    property string picked: ""         // the device just picked, until `ferry list` says so too
    readonly property string targetId: picked || (st ? st.target || "" : "")
    readonly property var target: devices.find(d => d.id === targetId) || null
    property string mode: "list"       // list | pick (the pill's list floating over the list) | write (a text to send)
    property string flash: ""          // what says "copied" for a moment: an item's id or "url"
    property bool adding: false        // Add Device: the QR code in the middle of the screen
    property string qr: ""             // the QR code's SVG once made
    property int dragging: 0           // files being dragged out: shell.qml lets the drop through to the windows below
    property int tileDrags: 0          // tiles with files over them
    readonly property bool dropping: outerDrop.containsDrag || tileDrags > 0 || dropHold.running
    readonly property bool wantsKeyboard: mode === "write"   // shell.qml: the text field needs it
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
        if (it.kind === "text") { m.run(["copy", it.id]); m.flashOn(it.id) }
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
    Component.onCompleted: refresh()
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
    onDroppingChanged: if (!dropping) tileDrags = 0

    Sh {
        id: listProc
        command: [m.ferry, "list", "--json"]
        onResult: text => {
            try { m.st = JSON.parse(text) } catch (e) { return }
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

    // ---- the parts ----
    // A round button beside Send Clipboard: an icon or a short text (Aa)
    component RoundButton: Rectangle {
        id: rb
        property string icon: ""
        property string label: ""
        property bool on: false
        property bool usable: true
        property bool navSelected: false
        readonly property bool navEnabled: usable
        function navActivate() { rb.clicked() }
        signal clicked()
        width: 36; height: 36; radius: 18
        color: on ? Theme.sel : rbArea.containsMouse || navSelected ? Theme.hover : Theme.card
        border { width: 1; color: on || navSelected ? Theme.primary : Theme.border }
        opacity: usable ? 1 : 0.4
        Text {
            anchors.centerIn: parent
            text: rb.icon !== "" ? Icons.g(rb.icon) : rb.label
            color: Theme.accent
            font { family: rb.icon !== "" ? Icons.family : Theme.font; pixelSize: rb.icon !== "" ? 17 : 13 }
        }
        MouseArea {
            id: rbArea
            anchors.fill: parent
            enabled: rb.usable
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.clicked()
        }
    }

    // A device in the pill's list: its kind's icon, name and state; a check on the picked one
    component DeviceRow: Rectangle {
        id: dr
        property var dev: null
        property string label: dev ? dev.name : ""
        property string icon: m.deviceIcon(dev)
        readonly property bool usable: !dev || m.canTake(dev)
        readonly property bool picked: !!dev && dev.id === m.targetId
        property bool navSelected: false
        readonly property bool navEnabled: usable
        function navActivate() { dr.clicked() }
        signal clicked()
        width: parent.width; height: 40; radius: 9
        color: picked ? Theme.sel : drArea.containsMouse || navSelected ? Theme.hover : "transparent"
        border { width: navSelected ? 1 : 0; color: Theme.primary }
        opacity: usable ? 1 : 0.45
        Text {
            id: drIcon
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: Icons.g(dr.icon)
            color: Theme.accent
            font { family: Icons.family; pixelSize: 16 }
        }
        Text {
            anchors { left: drIcon.right; leftMargin: 12; right: drState.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: dr.label
            elide: Text.ElideRight
            color: dr.picked ? Theme.accent : Theme.text
            font { family: Theme.font; pixelSize: 13 }
        }
        Row {
            id: drState
            visible: !!dr.dev
            anchors { right: drCheck.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 6
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7; height: 7; radius: 4
                color: dr.dev && dr.dev.online ? Theme.ok : Theme.border
            }
            Text {
                text: dr.dev ? m.deviceState(dr.dev) : ""
                color: Theme.dim
                font { family: Theme.font; pixelSize: 11 }
            }
        }
        Text {
            id: drCheck
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: 14
            text: dr.picked ? Icons.g("check") : ""
            color: Theme.accent
            font { family: Icons.family; pixelSize: 13 }
        }
        MouseArea {
            id: drArea
            anchors.fill: parent
            enabled: dr.usable
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dr.clicked()
        }
    }

    // A device to drop files on, while files are dragged over the menu
    component DropTile: Rectangle {
        id: dt
        property var dev
        readonly property bool usable: m.canTake(dev)
        readonly property bool hot: tileDrop.containsDrag && usable
        height: 96; radius: 14
        color: hot ? Theme.sel : Theme.card
        border { width: hot ? 1.5 : 1; color: hot ? Theme.primary : Theme.border }
        opacity: usable ? 1 : 0.45
        Column {
            anchors.centerIn: parent
            spacing: 7
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Icons.g(m.deviceIcon(dt.dev))
                color: Theme.accent
                font { family: Icons.family; pixelSize: 26 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, dt.width - 16)
                elide: Text.ElideRight
                text: dt.dev.name
                color: dt.hot ? Theme.accent : Theme.text
                font { family: Theme.font; pixelSize: 12 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dt.hot ? "Drop to send" : m.deviceState(dt.dev)
                color: dt.hot ? Theme.accent : Theme.dim
                font { family: Theme.font; pixelSize: 10 }
            }
        }
        DropArea {
            id: tileDrop
            anchors.fill: parent
            keys: ["text/uri-list"]
            onEntered: drag => { drag.accepted = m.dragging === 0 && dt.usable; if (drag.accepted) m.tileDrags++ }
            onExited: { m.tileDrags = Math.max(0, m.tileDrags - 1); dropHold.restart() }
            onDropped: d => {
                m.tileDrags = 0
                const p = m.paths(d)
                if (!p.length) return
                m.run(["add", "--to", dt.dev.id].concat(p))
                d.acceptProposedAction()
            }
        }
    }

    // The plugin's name as in the other menus. Clear: what the other devices sent here leaves the box (files stay in
    // Downloads)
    MenuHeader {
        width: parent.width
        title: "Ferry"
        action: !m.dropping && m.received.length ? "Clear" : ""
        onActionClicked: m.run(["clear", "received"])
    }

    // Files dragged over turn the menu into device tiles: say what a drop does. The list of what arrived needs no title.
    MenuSection {
        visible: m.dropping
        title: "Send to"
        topPadding: 0
        color: Theme.dim
    }

    // Why the other devices can't get here, if they can't
    Rectangle {
        readonly property string why: !m.st ? ""
            : !m.st.on ? "Ferry's server isn't running. Turn it on: launcher › System › Install › Plugins › Ferry."
            : !m.st.tailscale ? "Tailscale is off: your other devices can't reach this computer."
            : !m.st.serving ? "Not on the tailnet yet. Run once: sudo tailscale set --operator=$USER, then: ferry enable"
            : ""
        visible: why !== "" && !m.dropping
        width: parent.width
        height: whyText.implicitHeight + 24
        radius: 12
        color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.08)
        Text {
            id: whyIcon
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: Icons.g("triangle-alert")
            color: Theme.warning
            font { family: Icons.family; pixelSize: 16 }
        }
        MenuNote {
            id: whyText
            anchors { left: whyIcon.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            variant: "warning"
            text: parent.why
        }
    }

    // The list, the pill (its list floats over the list) and the buttons; files over any of it turn it into tiles
    Item {
        id: body
        width: parent.width
        height: stack.y + stack.height

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
            Grid {
                visible: m.dropping
                width: parent.width
                columns: 2
                spacing: 10
                Repeater {
                    model: m.devices
                    delegate: DropTile {
                        required property var modelData
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
            // A long one runs on under the pill: the box takes m.listLift less room in the column than the card
            Item {
                id: listBox
                readonly property bool scrolls: list.height > m.rowHeight * 6.5
                visible: !m.dropping && m.received.length > 0
                width: parent.width
                height: listCard.height - (scrolls ? m.listLift : 0)
                Rectangle {
                    id: listCard
                    width: parent.width
                    height: flick.height + 8
                    radius: 14
                    color: Theme.card

                    Flickable {
                        id: flick
                        y: 4
                        width: parent.width
                        height: listBox.scrolls ? m.rowHeight * 6.5 : list.height
                        contentHeight: list.height
                        // Room after the last row to scroll it out from under the fade
                        bottomMargin: listBox.scrolls ? m.listFade - 4 : 0
                        interactive: listBox.scrolls
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        Column {
                            id: list
                            width: flick.width
                            Repeater {
                                model: m.received
                                // One item: a click does what the round mark says (copies a text, opens a file); a file
                                // can be dragged into another app
                                delegate: Item {
                                    id: r
                                    required property var modelData
                                    required property int index
                                    readonly property bool isFile: modelData.kind === "file"
                                    readonly property bool isImage: isFile && /^image\//.test(modelData.type || "")
                                    // A picture only for what Qt reads (HEIC from an iPhone keeps the icon)
                                    readonly property bool hasThumb: /^image\/(png|jpeg|gif|webp|bmp)$/.test(modelData.type || "")
                                    readonly property bool lit: rowArea.containsMouse || navSelected
                                    property bool navSelected: false
                                    function navActivate() { m.act(r.modelData) }
                                    width: list.width
                                    height: m.rowHeight

                                    // The divider starts at the text, as in the phone's app
                                    Rectangle {
                                        visible: r.index > 0
                                        anchors { left: parent.left; leftMargin: 62; right: parent.right; rightMargin: 12 }
                                        height: 1
                                        color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.6)
                                    }
                                    Rectangle {
                                        id: rowBg
                                        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                                        radius: 10
                                        color: r.lit ? Theme.hover : "transparent"
                                        border { width: r.navSelected ? 1 : 0; color: Theme.primary }
                                    }
                                    // The file itself under the cursor while it's dragged out (the row stays)
                                    Item {
                                        id: dragSource
                                        anchors.fill: parent
                                        Drag.active: rowArea.drag.active
                                        Drag.hotSpot: Qt.point(30, height / 2)
                                        Drag.dragType: Drag.Automatic
                                        Drag.supportedActions: Qt.CopyAction
                                        Drag.mimeData: ({ "text/uri-list": "file://" + encodeURI(r.modelData.path || "") + "\r\n" })
                                        Drag.onActiveChanged: m.dragging += Drag.active ? 1 : -1
                                        Drag.onDragFinished: m.close()
                                    }
                                    Item { id: dragDummy; visible: false }   // drag.target: the row stays, its image follows

                                    Rectangle {
                                        id: tile
                                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                        width: 40; height: 40; radius: 10
                                        color: Theme.sel
                                        Text {
                                            visible: !thumb.visible
                                            anchors.centerIn: parent
                                            text: Icons.g(!r.isFile ? "text" : r.isImage ? "image" : "file")
                                            color: Theme.accent
                                            font { family: Icons.family; pixelSize: 19 }
                                        }
                                        // An image's own picture
                                        ClippingRectangle {
                                            id: thumb
                                            visible: r.hasThumb && thumbImg.status === Image.Ready
                                            anchors.fill: parent
                                            radius: 10
                                            color: "transparent"
                                            Image {
                                                id: thumbImg
                                                // A phone's photo is stored sideways, its turn in EXIF: Qt applies it only when asked
                                                autoTransform: true
                                                anchors.fill: parent
                                                source: r.hasThumb && r.modelData.path ? "file://" + r.modelData.path : ""
                                                sourceSize: Qt.size(80, 80)
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                            }
                                        }
                                    }
                                    Column {
                                        anchors { left: tile.right; leftMargin: 12; right: mark.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                        spacing: 4
                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: r.isFile ? r.modelData.name : r.modelData.text.replace(/\s+/g, " ").trim()
                                            color: Theme.accent
                                            font { family: Theme.font; pixelSize: 12 }
                                        }
                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: m.flash === r.modelData.id ? "copied"
                                                : [r.isFile ? m.size(r.modelData.size || 0) : "", m.ago(r.modelData.time), r.modelData["from"] || ""]
                                                    .filter(x => x).join(" · ")
                                            color: m.flash === r.modelData.id ? Theme.accent : Theme.dim
                                            font { family: Theme.font; pixelSize: 11 }
                                        }
                                    }
                                    // A click anywhere on the row does what the round mark says; a file drags out from here
                                    MouseArea {
                                        id: rowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        drag.target: r.isFile ? dragDummy : null
                                        onPressed: if (r.isFile) r.grabToImage(res => { dragSource.Drag.imageSource = res.url })
                                        onClicked: m.act(r.modelData)
                                    }
                                    // What a click does: copy a text, open a file
                                    Rectangle {
                                        id: mark
                                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                        width: 32; height: 32; radius: 16
                                        color: r.lit ? Theme.primary : Theme.sel
                                        Text {
                                            anchors.centerIn: parent
                                            text: Icons.g(m.flash === r.modelData.id ? "check" : r.isFile ? "external-link" : "copy")
                                            color: r.lit ? Theme.bg : Theme.accent
                                            font { family: Icons.family; pixelSize: 15 }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The rows under the pill fade out, and the card with them; the pill and buttons come later in the
                    // column and are drawn over it
                    Rectangle {
                        visible: listBox.scrolls
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: m.listFade
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0) }
                            GradientStop { position: 0.35; color: Theme.card }
                            GradientStop { position: 1; color: Theme.bg }
                        }
                    }
                }
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

            // ---- the device sends go to (10 px more room above it than the column's spacing, but not over a long
            // list, which runs on under it) ----
            Item {
                id: pillWrap
                visible: !m.dropping
                width: parent.width
                height: pill.height + (listBox.scrolls ? 0 : 10)
                Rectangle {
                    id: pill
                    anchors.bottom: parent.bottom
                    property bool navSelected: false
                    function navActivate() { pillArea.clicked(null) }
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: pillRow.width + 26
                    height: 28; radius: 14
                    color: m.mode === "pick" ? Theme.sel : pillArea.containsMouse || navSelected ? Theme.hover : Theme.card
                    border { width: 1; color: m.mode === "pick" || navSelected ? Theme.primary : Theme.border }
                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle {
                            visible: !!m.target
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7; height: 7; radius: 4
                            color: m.target && m.target.online ? Theme.ok : Theme.border
                        }
                        Text {
                            visible: !m.target
                            anchors.verticalCenter: parent.verticalCenter
                            text: Icons.g("qr-code")
                            color: Theme.accent
                            font { family: Icons.family; pixelSize: 13 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: m.target ? m.target.name : "Add Device"
                            color: Theme.accent
                            font { family: Theme.font; pixelSize: 12 }
                        }
                        Text {
                            visible: !!m.target
                            anchors.verticalCenter: parent.verticalCenter
                            text: Icons.g(m.mode === "pick" ? "chevron-up" : "chevron-down")
                            color: Theme.dim
                            font { family: Icons.family; pixelSize: 12 }
                        }
                    }
                    MouseArea {
                        id: pillArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!m.target && m.devices.length === 0) m.addDevice(); else m.mode = m.mode === "pick" ? "list" : "pick"
                    }
                }
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
                RoundButton {
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
                RoundButton {
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
        Rectangle {
            id: picker
            visible: !m.dropping && m.mode === "pick"
            z: 10
            anchors.horizontalCenter: parent.horizontalCenter
            y: stack.y + pillWrap.y + 10 - height - 8   // the pill sits 10 px into its wrapper
            width: Math.min(parent.width, 290)
            height: pickList.height + 12
            radius: 14
            color: Theme.card
            border { width: 1; color: Theme.border }
            MouseArea { anchors.fill: parent; hoverEnabled: true }   // a click between the rows doesn't close it, nor light the list below
            Column {
                id: pickList
                x: 6; y: 6
                width: parent.width - 12
                spacing: 2
                Repeater {
                    model: m.devices
                    delegate: DeviceRow {
                        required property var modelData
                        dev: modelData
                        onClicked: m.pick(modelData)
                    }
                }
                Rectangle {
                    visible: m.devices.length > 0
                    width: parent.width - 12; x: 6
                    height: 1
                    color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.6)
                }
                DeviceRow {
                    label: "Add Device…"
                    icon: "qr-code"
                    onClicked: m.addDevice()
                }
            }
        }
    }

    // Add Device: in the middle of the screen, over everything, in a window of its own that goes with the menu. The
    // page's QR code (dark modules on white: the iPhone camera reads it from the screen), what to do with it, and the
    // address (a click copies it). A click outside, × or Esc closes it and the menu.
    PanelWindow {
        id: addDialog
        visible: m.adding
        anchors { top: true; bottom: true; left: true; right: true }
        color: Qt.rgba(0, 0, 0, 0.6)   // the dim behind, as AirPods settings
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        onVisibleChanged: if (visible) addKeys.forceActiveFocus()
        MouseArea { anchors.fill: parent; onClicked: m.close() }
        Item {
            id: addKeys
            focus: true
            Keys.onEscapePressed: m.close()
        }
        Rectangle {
            anchors.centerIn: parent
            width: 720
            height: Math.max(qrBox.height, addText.height) + 56
            radius: 18
            color: Theme.bg
            border { width: 1; color: Theme.border }
            MouseArea { anchors.fill: parent }   // a click on the card doesn't close it
            Rectangle {
                id: qrBox
                x: 28; y: 28
                width: 240; height: 240; radius: 14
                color: "white"
                Image {
                    anchors { fill: parent; margins: 12 }
                    source: m.qr !== "" ? "file://" + m.qr : ""
                    sourceSize: Qt.size(432, 432)
                    smooth: false
                    cache: false
                }
            }
            // Bigger text than a menu's: it's read from across the desk, phone in hand
            Column {
                id: addText
                anchors { left: qrBox.right; leftMargin: 28; right: parent.right; rightMargin: 28; top: qrBox.top }
                spacing: 16
                Text {
                    text: "ADD DEVICE"
                    color: Theme.primary
                    font { family: Theme.font; pixelSize: 15; weight: Font.Medium; letterSpacing: 1.2 }
                }
                Repeater {
                    model: ["Scan the code with the phone's camera", "Share › Add to Home Screen",
                            "Open Ferry there and turn on notifications"]
                    delegate: Row {
                        required property string modelData
                        required property int index
                        width: parent.width
                        spacing: 12
                        Text {
                            text: index + 1
                            color: Theme.primary
                            font { family: Theme.font; pixelSize: 15; weight: Font.Medium }
                        }
                        Text {
                            width: parent.width - 24
                            wrapMode: Text.Wrap
                            text: modelData
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 15 }
                        }
                    }
                }
                Item { width: 1; height: 4 }
                // The address: a click copies it
                Rectangle {
                    width: parent.width
                    height: 44; radius: 10
                    color: urlArea.containsMouse ? Theme.hover : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.07)
                    Text {
                        id: urlIcon
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: Icons.g(m.flash === "url" ? "check" : "copy")
                        color: Theme.dim
                        font { family: Icons.family; pixelSize: 17 }
                    }
                    Text {
                        anchors { left: urlIcon.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        text: m.flash === "url" ? "Copied" : m.st ? m.st.url.replace(/^https:\/\//, "").replace(/\/$/, "") : ""
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 14 }
                    }
                    MouseArea {
                        id: urlArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Quickshell.execDetached(["wl-copy", m.st.url]); m.flashOn("url") }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Another computer: open the address in its browser"
                    color: Theme.dim
                    font { family: Theme.font; pixelSize: 13 }
                }
            }
            Text {
                anchors { right: parent.right; rightMargin: 18; top: parent.top; topMargin: 18 }
                text: Icons.g("x")
                color: closeArea.containsMouse ? Theme.accent : Theme.dim
                font { family: Icons.family; pixelSize: 16 }
                MouseArea {
                    id: closeArea
                    anchors { fill: parent; margins: -8 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: m.close()
                }
            }
        }
    }
}
