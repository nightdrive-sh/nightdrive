import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// Writing a message, in the reading pane's place: To, Cc, Subject and the text, nothing else.
Item {
    id: root
    required property QtObject c
    property string heading: "New message"
    property string status: ""
    property bool failed: false
    property bool busy: false
    property string inReplyTo: ""
    property string references: ""
    property string replyId: ""         // the message a reply answers: Claude reads the thread up to it
    property string forwardId: ""       // the message a forward passes on
    property var attachments: []        // file paths
    property var book: []               // addresses to complete To and Cc from (Notmuch.addresses)
    // The account it is sent from (compose.py accounts: { id, name, address, signature }), and its signature
    property var accounts: []
    property string account: ""
    readonly property var from: accounts.find(a => a.id === account) || accounts[0] || { address: "", signature: "" }
    readonly property string signature: from.signature || ""
    readonly property int bookShown: 6  // completions shown at once

    signal send(var fields)
    // ⌘⇧C: Claude writes the reply from your draft: the selected text, or all you wrote above the quote. The reply
    // takes the selection's place (from, to), or all of your text's (-1, -1). thread: Claude reads the thread too.
    // It shows first in the desktop's Claude writes card (Nightdrive's ClaudeWrite.qml, through `nightmail
    // ask-claude`), which asks Claude and hands the text back with Enter: answered(). gen ties the answer to the
    // request, so one for a message since closed or started again answers into nothing.
    signal suggest(var request, real x, real y)
    property var ask: null              // the request on the card: { hint, from, to, thread }
    property int gen: 0
    function askClaude(req) {
        ask = req
        gen++
        // By the mouse when it is over the window, else by the caret
        const p = pointer.hovered ? pointer.point.position : body.mapToItem(root, body.cursorRectangle.x, body.cursorRectangle.y + body.cursorRectangle.height)
        suggest({ gen: gen, msgid: replyId, account: from.id || "", hint: req.hint, thread: req.thread,
                  sent: req.thread ? "the thread" + (req.hint ? " and your draft: " + req.hint : "") : req.hint,
                  accept: req.from >= 0 ? "Replace selection" : "Insert reply" }, p.x, p.y)
    }
    // Enter on the card: the text goes in the selection's place, or in place of all you wrote above the quote.
    function answered(g, text, read) {
        if (g !== gen || !ask) return
        const before = body.text
        if (ask.from >= 0) {
            body.text = before.slice(0, ask.from) + text + before.slice(ask.to)
            body.cursorPosition = ask.from + text.length
        } else {
            body.text = text + (signed() ? "\n\n" + signature : "") + quote()
            body.cursorPosition = 0
        }
        gen++
        body.forceActiveFocus()
        // Each time, what Claude read.
        failed = false
        status = (ask.thread ? "Claude read the thread (" + read + (read === 1 ? " message)" : " messages)") + (ask.hint ? " and your draft" : "")
                             : "Claude read only your selection (" + ask.hint.length + " characters)") + ". Read it before sending"
    }
    // What Claude reads: "thread" (and the draft), "selection" (only that), or "" before you have chosen, when the
    // first ⌘⇧C asks (the consent panel below). Settings (⌘,) changes it later.
    property string claudeReads: ""
    signal chooseReads(string value)
    function rewrite() {
        if (claudeReads === "") { consent.show(); return }
        const sel = body.selectedText
        if (claudeReads === "selection" || replyId === "") {
            if (sel === "") { failed = false; status = "Select what Claude reads (⌘A: all of it), then ⌘⇧C"; return }
            askClaude({ hint: sel, from: body.selectionStart, to: body.selectionEnd, thread: false })
        }
        else if (sel !== "") askClaude({ hint: sel, from: body.selectionStart, to: body.selectionEnd, thread: true })
        else askClaude({ hint: own(), from: -1, to: -1, thread: true })
    }
    // ⌘S saves in Drafts and keeps writing; once saved, closing saves again. Esc otherwise drops what was written.
    signal save(var fields, bool close)
    signal dismiss()
    // ⌘⇧A asks for files to attach; they come back through attach().
    signal pickFiles()
    function attach(paths) {
        const add = paths.filter(p => attachments.indexOf(p) < 0)
        if (add.length) attachments = attachments.concat(add)
    }
    function detach(i) { attachments = attachments.filter((p, j) => j !== i) }
    property string draftId: ""         // the copy in Drafts, replaced by each save

    // The quote a reply starts with, and what was written above it (without the signature, which stays where it is).
    function quoteRe() { return /\n*On .* wrote:\n(>.*(\n|$))*\s*$/ }
    function quote() { const m = body.text.match(quoteRe()); return m ? "\n\n" + m[0].replace(/^\n+/, "") : "" }
    function signed() { return signature !== "" && body.text.replace(quoteRe(), "").trim().endsWith(signature) }
    function own() {
        const t = body.text.replace(quoteRe(), "").trim()
        return signed() ? t.slice(0, t.length - signature.length).trim() : t
    }

    // Nothing written: empty fields (the signature alone is nothing), or a reply with only the quote.
    function untouched() {
        const f = fields()
        return f.to.trim() === "" && f.subject.trim() === "" && own() === "" && f.attachments.length === 0
            || f.in_reply_to !== "" && own() === "" && f.attachments.length === 0
    }
    // A click on From sends from the next account; its signature takes the old one's place, or goes above the quote
    // (or the forwarded message) when there was none.
    function nextAccount() {
        const old = signature
        const i = accounts.findIndex(a => a.id === from.id)
        account = accounts[(i + 1) % accounts.length].id
        if (signature === old) return
        const t = body.text
        let at = old ? t.indexOf("\n\n" + old) : -1, len = old.length + 2
        if (at < 0) {
            const q = t.search(/\n*(On .* wrote:\n>|---------- Forwarded message ----------)/)
            at = q >= 0 ? q : t.trimEnd().length; len = 0
        }
        body.text = t.slice(0, at) + (signature ? "\n\n" + signature : "") + t.slice(at + len)
    }

    // Esc: a saved draft is saved again and closed. Unsaved writing asks once more, as Esc drops it.
    property bool armed: false
    Timer { id: disarm; interval: 3000; onTriggered: { root.armed = false; if (!root.failed) root.status = "" } }
    function escPressed() {
        if (draftId !== "") { save(fields(), true); return }
        if (untouched() || armed) { armed = false; dismiss(); return }
        armed = true; failed = false
        status = "Esc again to throw it away, ⌘S saves it"
        disarm.restart()
    }

    function fields() {
        return { account: from.id || "", to: to.text, cc: cc.text, subject: subject.text, body: body.text,
                 in_reply_to: inReplyTo, references: references, draft_id: draftId, attachments: attachments }
    }

    // Fills the form; a reply starts in the text, above the quote, a new message in To.
    function start(h, f) {
        heading = h
        account = f.account || ""
        to.text = f.to || ""; cc.text = f.cc || ""; subject.text = f.subject || ""; body.text = f.body || ""
        inReplyTo = f.in_reply_to || ""; references = f.references || ""; replyId = ""; gen++
        draftId = f.draft_id || ""; forwardId = ""; attachments = f.attachments || []
        status = ""; failed = false; busy = false; armed = false
        showCc = cc.text !== ""
        if (to.text === "") to.forceActiveFocus()
        else { body.cursorPosition = 0; body.forceActiveFocus() }
        scroller.contentY = 0
    }

    property bool showCc: false

    Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; enabled: root.visible && !root.busy; onActivated: root.send(root.fields()) }
    // ⌘⇧C again on the card writes another version of the same request.
    Shortcut { sequences: ["Meta+Shift+C", "Ctrl+Shift+C"]; enabled: root.visible && !consent.visible; onActivated: root.rewrite() }
    Shortcut { sequence: "Ctrl+S"; enabled: root.visible && !root.busy; onActivated: root.save(root.fields(), false) }
    Shortcut { sequences: ["Ctrl+Shift+A", "Meta+Shift+A"]; enabled: root.visible && !root.busy; onActivated: root.pickFiles() }
    Shortcut { sequence: "Escape"; enabled: root.visible && !root.busy && !consent.visible; onActivated: root.escPressed() }

    component Field: RowLayout {
        id: f
        property alias label: lbl.text
        property alias input: inp
        property bool completes: false     // To and Cc offer addresses while you type
        property var matches: []
        property int pick: 0
        z: matches.length ? 10 : 0
        Layout.fillWidth: true
        spacing: 0

        // The address being typed: what follows the last comma.
        function token() { return inp.text.slice(inp.text.lastIndexOf(",") + 1).trim().toLowerCase() }
        function complete() {
            const t = token()
            const have = inp.text.toLowerCase()
            matches = !completes || !inp.activeFocus || t === "" ? []
                : root.book.filter(a => (a.address.toLowerCase().indexOf(t) >= 0 || a.name.toLowerCase().indexOf(t) >= 0)
                                        && have.indexOf(a.address.toLowerCase()) < 0).slice(0, root.bookShown)
            pick = 0
        }
        function accept(i) {
            const head = inp.text.slice(0, inp.text.lastIndexOf(",") + 1)
            inp.text = (head ? head + " " : "") + matches[i].nameAddr + ", "
            inp.cursorPosition = inp.text.length
            matches = []
        }

        Text { id: lbl; Layout.preferredWidth: 88; color: root.c.faint; font.family: root.c.font; font.pixelSize: 13 }
        // The input clips its text, so the completions sit beside it, in this item.
        Item {
            Layout.fillWidth: true
            implicitHeight: inp.implicitHeight
            TextInput {
                id: inp
                width: parent.width
                color: root.c.text; font.family: root.c.font; font.pixelSize: 13
                selectionColor: root.c.sel; selectByMouse: true
                activeFocusOnTab: true
                clip: true
                onTextEdited: f.complete()
                onActiveFocusChanged: if (!activeFocus) f.matches = []
                // With completions open, Esc closes them instead of the window, and Tab or Enter takes the chosen one.
                Keys.onShortcutOverride: e => { if (f.matches.length && e.key === Qt.Key_Escape) e.accepted = true }
                Keys.onPressed: e => {
                    if (!f.matches.length) return
                    if (e.key === Qt.Key_Down) f.pick = (f.pick + 1) % f.matches.length
                    else if (e.key === Qt.Key_Up) f.pick = (f.pick + f.matches.length - 1) % f.matches.length
                    else if (e.key === Qt.Key_Escape) f.matches = []
                    else if ((e.key === Qt.Key_Tab || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ControlModifier)) f.accept(f.pick)
                    else return
                    e.accepted = true
                }
            }

            Rectangle {
                visible: f.matches.length > 0
                y: parent.height + 8
                x: -12
                width: Math.min(parent.width + 24, 520)
                height: picks.implicitHeight + 12
                radius: 10
                color: root.c.solid
                border.color: root.c.line
                Column {
                    id: picks
                    x: 6; y: 6
                    width: parent.width - 12
                    Repeater {
                        model: f.matches
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: picks.width
                            implicitHeight: 32
                            radius: 6
                            color: index === f.pick ? root.c.sel : ph.hovered ? root.c.hover : "transparent"
                            HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: f.accept(index) }
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 10
                                spacing: 12
                                Text { text: modelData.name || modelData.address; color: root.c.title; font.family: root.c.font; font.pixelSize: 12 }
                                Text { visible: modelData.name !== ""; text: modelData.address; color: root.c.faint; font.family: root.c.font; font.pixelSize: 12 }
                            }
                        }
                    }
                }
            }
        }
    }

    component Action: Rectangle {
        id: a
        property alias text: t.text
        property string hint: ""
        property color tint: root.c.dim
        signal clicked()
        implicitWidth: row.implicitWidth + 24
        implicitHeight: 34
        radius: 8
        color: ah.hovered ? root.c.hover : "transparent"
        HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (!root.busy) a.clicked() }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            // In a narrow window the keys go: with them the buttons are wider than the form and push it past the edge
            KeyCap { visible: root.width >= 560; anchors.verticalCenter: parent.verticalCenter; c: root.c; keys: a.hint; tint: root.c.faint }
            Text { id: t; anchors.verticalCenter: parent.verticalCenter; color: a.tint; font.family: root.c.font; font.pixelSize: 12 }
        }
    }

    ColumnLayout {
        id: form
        width: Math.max(240, Math.min(640, root.width - 80))
        x: Math.max(24, (root.width - width) / 2)
        y: 48
        height: root.height - 48 - 24
        spacing: 0

        Text {
            Layout.bottomMargin: 28
            text: root.heading; color: root.c.title
            font.family: root.c.font; font.pixelSize: 22; font.weight: Font.Medium; font.letterSpacing: -0.2
        }

        ColumnLayout {
            Layout.fillWidth: true
            z: 1        // completions lie over the text below
            spacing: 14
            // With more than one account: which one it goes from (a click changes it)
            RowLayout {
                visible: root.accounts.length > 1
                spacing: 0
                Text { Layout.preferredWidth: 88; text: "From"; color: root.c.faint; font.family: root.c.font; font.pixelSize: 13 }
                Text {
                    text: root.from.address; color: fromHover.hovered ? root.c.title : root.c.text; font.family: root.c.font; font.pixelSize: 13
                    HoverHandler { id: fromHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.nextAccount() }
                }
            }
            // Add Cc sits at To's right end, as in Gmail: the Cc row it shows comes right under it.
            Field {
                id: toRow; label: "To"; completes: true
                Text {
                    visible: !root.showCc
                    Layout.leftMargin: 12
                    text: "Add Cc"; color: addCcHover.hovered ? root.c.text : root.c.faint; font.family: root.c.font; font.pixelSize: 11
                    HoverHandler { id: addCcHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.showCc = true; cc.forceActiveFocus() } }
                }
            }
            Field { id: ccRow; label: "Cc"; visible: root.showCc; completes: true }
            Field { id: subjectRow; label: "Subject" }
            // Attachments: a file's name and ×, which takes it off.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 88
                visible: root.attachments.length > 0
                spacing: 8
                Repeater {
                    model: root.attachments
                    delegate: Rectangle {
                        id: chip
                        required property string modelData
                        required property int index
                        implicitWidth: chipRow.implicitWidth + 24
                        implicitHeight: 28
                        radius: 8
                        border.color: root.c.line
                        color: "transparent"
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                text: chip.modelData.replace(/^.*\//, ""); color: root.c.text
                                font.family: root.c.font; font.pixelSize: 12
                                width: Math.min(implicitWidth, 260); elide: Text.ElideMiddle
                            }
                            Text {
                                text: "×"; color: xh.hovered ? root.c.title : root.c.faint
                                font.family: root.c.font; font.pixelSize: 13
                                HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.detach(chip.index) }
                            }
                        }
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.topMargin: 24; implicitHeight: 1; color: root.c.line }

        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 24
            clip: true
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            TouchScroll { view: scroller }
            TextEdit {
                id: body
                width: scroller.width
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                color: root.c.body; font.family: root.c.font; font.pixelSize: 14
                selectionColor: root.c.sel; selectByMouse: true
                activeFocusOnTab: true
                // Keep the caret in view while typing past the bottom.
                onCursorRectangleChanged: {
                    const r = cursorRectangle
                    if (r.y < scroller.contentY) scroller.contentY = r.y
                    else if (r.y + r.height > scroller.contentY + scroller.height) scroller.contentY = r.y + r.height - scroller.height
                }
            }
            HoverHandler { cursorShape: Qt.IBeamCursor }
        }

        // What just happened (what Claude read, an error): a line of its own above the buttons, wrapped, not cut off
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 16
            visible: root.status !== ""
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignRight
            text: root.status
            color: root.failed ? root.c.danger : root.c.faint
            font.family: root.c.font; font.pixelSize: 12
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: root.status !== "" ? 8 : 16
            spacing: 4
            Item { Layout.fillWidth: true }
            Action { text: "Attach"; hint: "⌘⇧A"; onClicked: root.pickFiles() }
            Action { text: "Save"; hint: "⌘S"; onClicked: root.save(root.fields(), false) }
            Action { text: "Close"; hint: "esc"; onClicked: root.escPressed() }
            Action { text: "Send"; hint: "ctrl ⏎"; tint: root.c.accent; onClicked: root.send(root.fields()) }
        }
    }

    // Files dropped from a file manager are attached.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            root.attach(drop.urls.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, ""))))
            drop.accept()
        }
    }

    // The first ⌘⇧C asks what Claude may read, plainly, with more to read about sending mail to an AI. 1 or 2 chooses
    // (and Claude starts writing), as do the arrows and Enter; r shows more, Esc goes back to writing without Claude.
    Rectangle {
        id: consent
        property bool more: false
        property int sel: 0                 // the choice the arrows are on
        readonly property var values: ["thread", "selection"]
        function show() { more = false; sel = 0; visible = true; forceActiveFocus() }
        function pick(v) { visible = false; body.forceActiveFocus(); root.chooseReads(v); Qt.callLater(root.rewrite) }
        visible: false
        anchors.fill: parent
        color: Qt.rgba(root.c.scrim.r, root.c.scrim.g, root.c.scrim.b, 0.85)
        TapHandler {}
        Keys.onPressed: e => {
            if (e.key === Qt.Key_1) pick("thread")
            else if (e.key === Qt.Key_2) pick("selection")
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) sel = 1 - sel
            else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !more) pick(values[sel])
            else if (e.key === Qt.Key_R) more = !more
            else if (e.key === Qt.Key_Escape) { if (more) more = false; else { visible = false; body.forceActiveFocus() } }
            else return
            e.accepted = true
        }

        component Choice: Rectangle {
            id: ch
            property string key
            property string title
            property string detail
            property bool active: false
            signal picked()
            width: parent.width
            implicitHeight: chCol.implicitHeight + 28
            radius: 10
            color: active ? root.c.sel : chHover.hovered ? root.c.hover : "transparent"
            border.color: active ? root.c.primary : root.c.line
            HoverHandler { id: chHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ch.picked() }
            Text { x: 16; y: 14; text: ch.key; color: root.c.accent; font.family: root.c.font; font.pixelSize: 13 }
            Column {
                id: chCol
                x: 44; y: 14
                width: parent.width - 60
                spacing: 6
                Text { text: ch.title; color: root.c.title; font.family: root.c.font; font.pixelSize: 13 }
                Text { width: parent.width; text: ch.detail; wrapMode: Text.Wrap; color: root.c.dim; font.family: root.c.font; font.pixelSize: 12; lineHeight: 1.15 }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 600)
            height: panel.implicitHeight + 64
            radius: 14
            color: root.c.solid
            border.color: root.c.line
            Column {
                id: panel
                x: 32; y: 32
                width: parent.width - 64
                spacing: 18
                // Lucide's shield-alert before the title: this is a choice about your mail leaving the computer.
                Row {
                    spacing: 8
                    Text {
                        anchors.verticalCenter: consentTitle.verticalCenter
                        text: Icons.g("shield-alert"); color: root.c.accent
                        font.family: Icons.family; font.pixelSize: 16
                    }
                    Text { id: consentTitle; text: consent.more ? "Sending mail to an AI" : "What should Claude read?"; color: root.c.title; font.family: root.c.font; font.pixelSize: 14; font.bold: true }
                }
                Text {
                    visible: !consent.more
                    width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2
                    text: "Claude writes the reply on Anthropic's servers. What you choose here is sent there, nothing else. "
                        + "You can change this later in Settings (⌘,). This setting applies only in Nightdrive Mail."
                    color: root.c.text; font.family: root.c.font; font.pixelSize: 12
                }
                Choice {
                    visible: !consent.more
                    active: consent.sel === 0
                    key: "1"; title: "The whole thread"
                    detail: "Every message in it: names, addresses and all that is written in them, with your draft. "
                          + "The best replies, but sensitive details in the thread are sent to Claude too."
                    onPicked: consent.pick("thread")
                }
                Choice {
                    visible: !consent.more
                    active: consent.sel === 1
                    key: "2"; title: "Only what I select"
                    detail: "Just the text you select in the reply (⌘A selects all of it). The thread stays on this computer."
                    onPicked: consent.pick("selection")
                }
                Text {
                    visible: consent.more
                    width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.25; textFormat: Text.StyledText
                    color: root.c.text; font.family: root.c.font; font.pixelSize: 12
                    text: "<b>What is sent:</b> the text you chose, your name and address for the sign-off, and a short instruction. "
                        + "Claude gets no tools and keeps no session: it only writes text, and nothing is sent to anyone before you read it and press Send.<br><br>"
                        + "<b>Where it goes:</b> to Anthropic, under the terms of your Claude account.<br><br>"
                        + "<b>Think before you send.</b> Mail often holds other people's details: addresses, phone numbers, health, money, passwords, "
                        + "customer data. The people who wrote to you didn't choose to share it with an AI. When in doubt, select only what Claude needs, "
                        + "or write the reply yourself.<br><br>"
                        + "Whatever you choose, Mail tells you each time what Claude read."
                }
                Row {
                    spacing: 18
                    Row {
                        spacing: 8
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; c: root.c; keys: "r"; tint: root.c.faint }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: consent.more ? "Back" : "Read more"; color: moreHover.hovered ? root.c.accent : root.c.dim
                            font.family: root.c.font; font.pixelSize: 12
                            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: consent.more = !consent.more }
                        }
                    }
                    Row {
                        spacing: 8; visible: !consent.more
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; c: root.c; keys: "↑ ↓  ⏎"; tint: root.c.faint }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Choose"; color: root.c.faint; font.family: root.c.font; font.pixelSize: 12 }
                    }
                    Row {
                        spacing: 8; visible: !consent.more
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; c: root.c; keys: "esc"; tint: root.c.faint }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Write without Claude"; color: root.c.faint; font.family: root.c.font; font.pixelSize: 12 }
                    }
                }
            }
        }
    }

    HoverHandler { id: pointer }

    readonly property alias toInput: toRow.input
    property alias to: toRow.input
    property alias cc: ccRow.input
    property alias subject: subjectRow.input
    property alias bodyEdit: body
}
