import QtQuick
import qs
import qs.kit

// The open thread: its subject, then each message with its attachments. Mail's reading pane, and a message window's.
Flickable {
    id: root
    // From the window it is in: the look, notmuch, and Mail's helpers (name, fullDate, rich, openPart …).
    required property QtObject c
    required property QtObject nm
    required property var app
    property var messages: []
    property int htmlMode: 0            // 0 text, 1 HTML on the dark page, 2 HTML on light paper
    signal cycleHtml()
    signal openBrowser()
    signal resumeDraft()
    // Buttons above the thread, for the mouse: [{ id, icon, text, short, tip, keys }]; a click sends act(id). Where they
    // don't all fit beside the view button, the short names show, and where those don't either, only the icons. Held
    // under the pointer, a button says what it does and its key (tip, keys).
    property var actions: []
    signal act(string id)
    // In a window too narrow for the list beside it, the thread has the window to itself: a back button first in the bar
    property bool back: false
    signal goBack()
    // The message's text is selected with the mouse but never takes the keyboard (activeFocusOnPress: false): with the
    // focus in a TextEdit the window's keys (the list's arrows, shortcuts, Esc) stopped working until a click on the list.
    // So the window's key handler copies the selection on ⌘C (copy()), persistentSelection shows it without the focus,
    // and one selection shows at a time.
    property var selecting: null
    function selected(t) {
        if (t.selectedText === "") return
        if (selecting && selecting !== t) selecting.deselect()
        selecting = t
    }
    function copy() { if (selecting && selecting.selectedText) selecting.copy() }
    // The copy key, for the key handlers: Hyprland sends ⌘C as Ctrl+Insert (bindings.lua, copy in every app), which a
    // TextEdit with the focus took as its own, so the window has to hear it too (StandardKey.Copy); Ctrl+C and Meta+C as well
    function isCopy(e) { return e.matches(StandardKey.Copy) || (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) && e.key === Qt.Key_C }
    // Light paper for HTML as sent: senders pick their colours for a white page, whatever the desktop's theme
    readonly property color paperBg: "#f4f1f6"
    readonly property color paperText: "#1d1a21"
    readonly property color paperSelection: "#d9c6e6"
    // Long threads: from foldFrom messages on, the read ones before the last show folded (sender, first line, date), and
    // a click opens one. The quote at the end of a message hides behind "…" only when all its text is in an earlier
    // message of the thread, so nothing that is only there is ever out of sight.
    readonly property int foldFrom: 3
    property var unfolded: ({})         // message ids opened by a click
    property var quotesShown: ({})      // message ids whose quote "…" shows
    onMessagesChanged: { unfolded = ({}); quotesShown = ({}) }
    function folded(m, i) {
        return messages.length >= foldFrom && i < messages.length - 1 && !m.draft && m.tags.indexOf("unread") < 0 && !unfolded[m.id]
    }
    // A link in a message opens on the web, or as a new message (mailto:). Any other kind (file:, smb:, an app's own)
    // would open something on this computer at a stranger's word, so it doesn't open at all.
    function openLink(link) {
        link = link.trim()
        if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link)
        else if (/^mailto:/i.test(link)) app.compose("new", null, app.mailtoFields(link))
        else app.say("Only web and email links open from a message")
    }
    function unfold(m) { const u = Object.assign({}, unfolded); u[m.id] = true; unfolded = u }
    function showQuote(m) { const q = Object.assign({}, quotesShown); q[m.id] = true; quotesShown = q }
    // The text without quote marks, whitespace as single spaces: a quote compared with the message it quotes
    function plain(t) { return t.replace(/^[ \t]*(>[ \t]?)+/gm, "").replace(/\s+/g, " ").trim() }
    // The first line of what the message itself says, for a folded one
    function firstLine(m, i) {
        const q = split(m, i)
        return ((q ? q.own : m.body).split("\n").find(l => l.trim() !== "" && !/^\s*>/.test(l)) || "").trim()
    }
    // The message's own text and the quote it ends with ({ own, quote }), or null when there is none or when some of
    // it can't be found in an earlier message. The quote is the > lines at the end, with blank lines among them, and
    // the one or two "On … wrote:" lines just before them.
    function split(m, i) {
        const lines = m.body.split("\n")
        let end = lines.length
        while (end > 0 && lines[end - 1].trim() === "") end--
        let start = end
        while (start > 0 && (/^\s*>/.test(lines[start - 1]) || lines[start - 1].trim() === "")) start--
        while (start < end && lines[start].trim() === "") start++
        const quoted = lines.slice(start, end).filter(l => /^\s*>/.test(l))
        const q = plain(quoted.join("\n"))
        if (q === "") return null
        const earlier = messages.filter((x, j) => j !== i && x.timestamp <= m.timestamp)
        if (!earlier.some(x => plain(x.body).indexOf(q) >= 0)) return null
        for (let n = 1; n <= 2 && start - n >= 0; n++) {
            if (/(wrote|kirjoitti|skrev|schrieb|a écrit|escribió|scrive):?\s*$/i.test(lines[start - n])) { start -= n; break }
        }
        return { own: lines.slice(0, start).join("\n").replace(/\s+$/, ""), quote: lines.slice(start, end).join("\n") }
    }
    clip: true
    contentHeight: page.implicitHeight + 96
    boundsBehavior: Flickable.StopAtBounds
    // A mouse drag selects a message's text instead of dragging the page; the wheel and the touchpad still scroll
    acceptedButtons: Qt.NoButton
    TouchScroll { view: root }
    component ActButton: Rectangle {
        id: btn
        property string icon
        property string label
        property string tip
        property string keys
        property bool compact: false
        signal clicked()
        Tip { y: btn.height + 6; c: root.c; text: btn.tip; keys: btn.keys; hovered: bh.hovered }
        implicitWidth: btnRow.implicitWidth + 20
        implicitHeight: 30
        radius: 8
        color: bh.hovered ? c.hover : "transparent"
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: btn.clicked() }
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 7
            Text { anchors.verticalCenter: parent.verticalCenter; text: Icons.g(btn.icon); font.family: Icons.family; font.pixelSize: 14; color: bh.hovered ? c.text : c.dim }
            Text { visible: !btn.compact; anchors.verticalCenter: parent.verticalCenter; text: btn.label; font.family: c.font; font.pixelSize: 12; color: bh.hovered ? c.text : c.dim }
        }
    }
    // The buttons measured with their names and short names, to see which fit left of the view button
    Row {
        id: fullBar
        visible: false
        spacing: 2
        Repeater { model: root.actions; delegate: ActButton { required property var modelData; icon: modelData.icon; label: modelData.text } }
    }
    Row {
        id: shortBar
        visible: false
        spacing: 2
        Repeater { model: root.actions; delegate: ActButton { required property var modelData; icon: modelData.icon; label: modelData.short || modelData.text } }
    }
    Row {
        id: iconBar
        visible: false
        spacing: 2
        Repeater { model: root.actions; delegate: ActButton { required property var modelData; icon: modelData.icon; compact: true } }
    }
    // The buttons stay at the top while the thread scrolls under them, on a solid band of the page's colour with a line
    // below it
    readonly property int barHeight: 54
    Rectangle {
        z: 1
        visible: bar.visible || viewButton.visible || root.back
        y: root.contentY
        width: root.width; height: root.barHeight
        color: c.solid
        TapHandler {}                   // a click on the band doesn't reach the text under it
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: c.divider }
    }
    Row {
        id: bar
        z: 2                            // the tips lie over the thread
        visible: root.messages.length > 0 && root.actions.length > 0
        // Where it may start: after the back button, if there is one; in one pane the buttons are centred from there on
        readonly property real start: root.back ? backButton.x + backButton.width + 6 : page.x - 10
        readonly property real end: viewButton.visible ? browserButton.x - 12 : root.back ? root.width - 12 : page.x + page.width
        readonly property real room: end - start
        readonly property bool full: fullBar.implicitWidth <= room
        readonly property bool compact: !full && shortBar.implicitWidth > room
        // Narrower still: the view button drops its key, then the last buttons give way (their keys still work)
        readonly property int fits: Math.floor((room + spacing) / (iconBar.implicitWidth / root.actions.length + spacing))
        x: root.back ? Math.max(start, Math.min((root.width - width) / 2, end - width)) : start
        y: root.contentY + 12
        spacing: 2
        Repeater {
            model: root.actions
            delegate: ActButton {
                required property var modelData
                required property int index
                visible: !bar.compact || index < bar.fits
                icon: modelData.icon; label: bar.full ? modelData.text : modelData.short || modelData.text; compact: bar.compact
                tip: modelData.tip || ""; keys: modelData.keys || ""
                onClicked: root.act(modelData.id)
            }
        }
    }
    // A finger's size, as the only way back to the list for the mouse
    AppIconButton {
        id: backButton
        visible: root.back
        z: 2
        x: 9; y: root.contentY + 7
        implicitWidth: 40; implicitHeight: 40; radius: 8
        c: root.c
        glyph: "arrow-left"; glyphSize: 17
        tip: "Back to the list"; keys: "Esc"
        onClicked: root.goBack()
    }
    // Plain text first; the HTML version is a press away when the message has one.
    Rectangle {
        id: viewButton
        visible: root.messages.some(m => m.html !== "")
        z: 2
        x: page.x + page.width - width + 12
        y: root.contentY + 12
        implicitWidth: viewRow.implicitWidth + 24
        implicitHeight: 30
        radius: 8
        color: vh.hovered ? c.hover : "transparent"
        HoverHandler { id: vh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.cycleHtml() }
        Row {
            id: viewRow
            anchors.centerIn: parent
            // The key a size smaller than the shared KeyCap's (scaled: its box is fixed), its gap to the text kept
            spacing: 6
            KeyCap {
                id: viewKey
                scale: 0.8
                anchors.verticalCenter: parent.verticalCenter; c: root.c; keys: "h"; tint: c.dim
                visible: iconBar.implicitWidth + 12 + browserButton.width + 2 + implicitWidth + viewRow.spacing + viewText.implicitWidth + 24
                         <= page.x + page.width + 12 - bar.start   // start, not x: x follows the width in one pane
            }
            Text { id: viewText; anchors.verticalCenter: parent.verticalCenter; text: ["Text", "HTML, dark", "HTML as sent"][root.htmlMode]; color: c.dim; font.family: c.font; font.pixelSize: 12 }
        }
    }
    // The HTML as sent, in the browser: tables and pictures sent with it as the sender laid them out, still with
    // nothing loaded from the network
    AppIconButton {
        id: browserButton
        visible: viewButton.visible
        z: 2
        x: viewButton.x - width - 2
        y: root.contentY + 12
        implicitWidth: 30; implicitHeight: 30; radius: 8
        c: root.c
        glyph: "external-link"; glyphSize: 14
        tip: "Open in the browser"; keys: "⇧H"
        onClicked: root.openBrowser()
    }
    Column {
        id: page
        width: Math.max(240, Math.min(640, root.width - 80))
        x: Math.max(24, (root.width - width) / 2)
        y: bar.visible || viewButton.visible || root.back ? root.barHeight + 33 : 33
        // The gaps are the messages' own, so folded ones lie close together
        spacing: 0
        Text {
            width: parent.width
            bottomPadding: 12
            visible: root.messages.length > 0
            text: root.messages.length ? root.messages[0].subject : ""
            wrapMode: Text.Wrap
            font.family: c.font; font.pixelSize: 22; font.weight: Font.Medium; font.letterSpacing: -0.2
            lineHeight: 1.1
            color: c.title
        }
        Repeater {
            model: root.messages
            delegate: Column {
                id: msgCol
                required property var modelData
                required property int index
                readonly property bool isFolded: root.folded(modelData, index)
                // The quote at the end, when it can hide (text view only)
                readonly property var cut: root.htmlMode > 0 && modelData.html ? null : root.split(modelData, index)
                width: page.width
                spacing: isFolded ? 0 : 28
                // An open message after a folded one gets its gap above
                Item { visible: !msgCol.isFolded && msgCol.index > 0 && root.folded(root.messages[msgCol.index - 1], msgCol.index - 1); width: 1; height: 4 }
                // Folded: one line, a click opens it
                Item {
                    visible: msgCol.isFolded
                    width: parent.width; height: visible ? 44 : 0
                    HoverHandler { id: foldHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.unfold(msgCol.modelData) }
                    Text {
                        id: foldName
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width * 0.3); elide: Text.ElideRight
                        text: app.name(msgCol.modelData.from); color: c.accent; font.family: c.font; font.pixelSize: 13
                    }
                    Text {
                        anchors.left: foldName.right; anchors.leftMargin: 16; anchors.right: foldDate.left; anchors.rightMargin: 16
                        anchors.baseline: foldName.baseline
                        elide: Text.ElideRight
                        text: msgCol.isFolded ? root.firstLine(msgCol.modelData, msgCol.index) : ""
                        color: foldHover.hovered ? c.text : c.dim; font.family: c.font; font.pixelSize: 13
                    }
                    Text {
                        id: foldDate
                        anchors.right: parent.right; anchors.baseline: foldName.baseline
                        text: app.when(msgCol.modelData.timestamp); color: c.faint; font.family: c.font; font.pixelSize: 12
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: c.line }
                }
                Item {
                    id: head
                    visible: !msgCol.isFolded
                    // In a narrow pane the date goes under the address instead of beside the name.
                    readonly property bool wide: width >= 520
                    width: parent.width; height: hdr.implicitHeight + 28
                    Column {
                        id: hdr
                        width: parent.width
                        spacing: 4
                        Item {
                            width: parent.width; height: sender.implicitHeight
                            Text {
                                id: sender
                                anchors.left: parent.left
                                anchors.right: head.wide ? sideDate.left : parent.right
                                anchors.rightMargin: head.wide ? 24 : 0
                                elide: Text.ElideRight
                                text: app.name(modelData.from); color: c.accent; font.family: c.font; font.pixelSize: 13
                            }
                            Text {
                                id: sideDate
                                visible: head.wide
                                anchors.right: parent.right; anchors.baseline: sender.baseline
                                text: app.fullDate(modelData.timestamp); color: c.faint; font.family: c.font; font.pixelSize: 12
                            }
                        }
                        // The address, and with Nightdrive Contacts the sender's card: opened, or made (Add to contacts)
                        Item {
                            id: fromLine
                            readonly property string addr: app.address(modelData.from) || modelData.from.trim()
                            readonly property bool known: app.book.known(addr)
                            width: parent.width; height: addrText.implicitHeight
                            Text {
                                id: addrText
                                width: Math.min(implicitWidth, parent.width - (bookButton.visible ? bookButton.width + 6 : 0))
                                elide: Text.ElideRight
                                text: app.address(modelData.from); color: c.faint; font.family: c.font; font.pixelSize: 12
                            }
                            AppIconButton {
                                id: bookButton
                                visible: app.book.available && fromLine.addr.indexOf("@") > 0
                                anchors.left: addrText.right; anchors.leftMargin: 6; anchors.verticalCenter: addrText.verticalCenter
                                implicitWidth: 22; implicitHeight: 22
                                c: root.c
                                glyph: fromLine.known ? "contact" : "user-plus"; glyphSize: 13; glyphColor: c.faint
                                tip: fromLine.known ? "Open in Contacts" : "Add to contacts"
                                onClicked: fromLine.known ? app.book.show(fromLine.addr) : app.book.add(app.name(modelData.from), fromLine.addr)
                            }
                        }
                        Text {
                            visible: !head.wide
                            text: app.fullDate(modelData.timestamp); color: c.faint; font.family: c.font; font.pixelSize: 12
                        }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: c.line }
                }
                TextEdit {
                    visible: !msgCol.isFolded && !(root.htmlMode > 0 && modelData.html)
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    activeFocusOnPress: false
                    persistentSelection: true
                    onSelectedTextChanged: root.selected(this)
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.RichText
                    text: !visible ? "" : app.rich(msgCol.cut && !root.quotesShown[modelData.id] ? msgCol.cut.own : modelData.body)
                    font.family: c.font; font.pixelSize: 14
                    color: c.body
                    selectionColor: c.sel
                    onLinkActivated: link => root.openLink(link)
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                }
                // The HTML version: on the dark page with the sender's colours taken out, or on light paper as sent
                // (senders pick their colours for a white page).
                // The hidden quote: … shows it
                Rectangle {
                    visible: !msgCol.isFolded && msgCol.cut !== null && !root.quotesShown[msgCol.modelData.id]
                    implicitWidth: 44; implicitHeight: 24
                    radius: 8
                    color: quoteHover.hovered ? c.hover : "transparent"
                    border.color: c.line
                    HoverHandler { id: quoteHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.showQuote(msgCol.modelData) }
                    Text { anchors.centerIn: parent; text: "•••"; color: c.dim; font.family: c.font; font.pixelSize: 11 }
                }
                Rectangle {
                    readonly property bool paper: root.htmlMode === 2
                    visible: !msgCol.isFolded && root.htmlMode > 0 && modelData.html !== ""
                    width: parent.width
                    height: visible ? html.implicitHeight + (paper ? 48 : 0) : 0
                    radius: 10
                    color: paper ? root.paperBg : "transparent"
                    TextEdit {
                        id: html
                        x: parent.paper ? 24 : 0; y: x
                        width: parent.width - 2 * x
                        readOnly: true
                        selectByMouse: true
                        activeFocusOnPress: false
                        persistentSelection: true
                        onSelectedTextChanged: root.selected(this)
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.RichText
                        text: !parent.visible ? "" : parent.paper ? modelData.html : nm.darken(modelData.html, c.accent)
                        font.pixelSize: 14
                        color: parent.paper ? root.paperText : c.body
                        selectionColor: parent.paper ? root.paperSelection : c.sel
                        onLinkActivated: link => root.openLink(link)
                        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                    }
                }
                // Attachments: a click opens one, "Save" puts it in the downloads folder.
                Flow {
                    width: parent.width
                    visible: !msgCol.isFolded && modelData.files.length > 0
                    spacing: 8
                    Repeater {
                        model: modelData.files
                        delegate: Rectangle {
                            id: file
                            required property var modelData
                            readonly property var msg: msgCol.modelData
                            implicitWidth: fileRow.implicitWidth + 28
                            implicitHeight: 34
                            radius: 8
                            border.color: c.line
                            color: fileHover.hovered ? c.hover : "transparent"
                            HoverHandler { id: fileHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: app.openPart(file.msg, file.modelData) }
                            Row {
                                id: fileRow
                                anchors.centerIn: parent
                                spacing: 10
                                Text {
                                    id: fileName
                                    text: file.modelData.name; color: c.text; font.family: c.font; font.pixelSize: 12
                                    width: Math.min(implicitWidth, 280); elide: Text.ElideMiddle
                                }
                                Text { text: app.size(file.modelData.size); color: c.faint; font.family: c.font; font.pixelSize: 11; anchors.baseline: fileName.baseline }
                                Text {
                                    text: "Save"; font.family: c.font; font.pixelSize: 11; anchors.baseline: fileName.baseline
                                    color: saveHover.hovered ? c.accent : c.dim
                                    opacity: fileHover.hovered ? 1 : 0
                                    HoverHandler { id: saveHover }
                                    TapHandler { onTapped: app.savePart(file.msg, file.modelData) }
                                }
                            }
                        }
                    }
                    // Two or more: all of them to the downloads folder at once
                    Rectangle {
                        visible: msgCol.modelData.files.length > 1
                        implicitWidth: allRow.implicitWidth + 24
                        implicitHeight: 34
                        radius: 8
                        color: allHover.hovered ? c.hover : "transparent"
                        HoverHandler { id: allHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: app.saveAll(msgCol.modelData) }
                        Row {
                            id: allRow
                            anchors.centerIn: parent
                            spacing: 7
                            Text { anchors.verticalCenter: parent.verticalCenter; text: Icons.g("download"); font.family: Icons.family; font.pixelSize: 14; color: allHover.hovered ? c.accent : c.dim }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Save all"; font.family: c.font; font.pixelSize: 12; color: allHover.hovered ? c.accent : c.dim }
                        }
                    }
                }
                // A draft is written on in the writing window.
                Rectangle {
                    visible: !msgCol.isFolded && modelData.draft
                    implicitWidth: draftRow.implicitWidth + 28
                    implicitHeight: 34
                    radius: 8
                    color: draftHover.hovered ? c.hover : "transparent"
                    border.color: c.line
                    HoverHandler { id: draftHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.resumeDraft() }
                    Row {
                        id: draftRow
                        anchors.centerIn: parent
                        spacing: 8
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; c: root.c; keys: "⏎"; tint: c.faint }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Continue writing"; color: c.accent; font.family: c.font; font.pixelSize: 12 }
                    }
                }
                Item { visible: !msgCol.isFolded; width: 1; height: 56 }
            }
        }
    }
    Text {
        visible: root.messages.length === 0
        anchors.centerIn: parent
        text: "No message selected"; color: c.faint; font.family: c.font; font.pixelSize: 12
    }
}
