import QtQuick
import qs
import qs.kit

// The open card: the picture, the name and what the person does, then a line for each number, address and link, which a
// click copies, writes to or opens. Narrow, the picture goes above the name and each line's label above its value.
Flickable {
    id: card
    required property var app           // the window: the contact, its helpers (lineActions, use, when) and keys
    required property QtObject c
    signal edit()
    clip: true
    contentHeight: body.y + body.implicitHeight + 64
    readonly property int margin: width < 520 ? 24 : 40
    readonly property bool narrow: body.width < 420
    // The line the keys are on, after Tab (Panes.qml): ↑ ↓ move, ⏎ does its first button's (write, open, copy), c copies
    property int line: -1
    onActiveFocusChanged: if (!activeFocus) line = -1
    onLinesChanged: if (line >= lines.length) line = lines.length - 1
    onLineChanged: if (line >= 0) Qt.callLater(showLine)
    // The line in sight, scrolled no further than needed
    function showLine() {
        const f = fields.itemAt(line)
        if (!f) return
        const y = f.mapToItem(card.contentItem, 0, 0).y
        if (y < card.contentY + 16) card.contentY = Math.max(0, y - 16)
        else if (y + f.height > card.contentY + card.height - 16) card.contentY = Math.min(card.contentHeight - card.height, y + f.height - card.height + 16)
    }
    // A line's button, by key or click: a copied line says so on itself for a moment (the window's note is far off)
    property int copied: -1
    Timer { id: copiedTimer; interval: 1500; onTriggered: card.copied = -1 }
    function act(i, id) {
        app.use(id, lines[i].value)
        if (id === "copy") { copied = i; copiedTimer.restart() }
    }
    readonly property var lines: card.p ? card.p.phones.map(x => ({ kind: "phone", glyph: "phone", label: x.label || "phone", value: x.value }))
        .concat(card.p.emails.map(x => ({ kind: "email", glyph: "mail", label: x.label || "email", value: x.value })))
        .concat(card.p.addresses.map(x => ({ kind: "address", glyph: "map-pin", label: x.label || "address", value: x.lines.join("\n") })))
        .concat(card.p.urls.map(x => ({ kind: "url", glyph: "link", label: x.label || "web", value: x.value })))
        .concat(card.p.birthday ? [{ kind: "birthday", glyph: "cake", label: "birthday", value: app.when(card.p.birthday) }] : [])
        : []
    // Its keys in one pane, where the list is away: back, scrolling, editing
    Keys.onPressed: e => {
        const k = e.key
        const l = card.lines[card.line]
        card.c.moved(e)
        app.sheetKey(e)
        if (k === Qt.Key_Question) {}
        else if (k === Qt.Key_Tab && card.line < 0 && app.onePane && card.lines.length) card.line = 0
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) app.panes.fromCard(k === Qt.Key_Backtab)
        else if (l && (k === Qt.Key_Down || k === Qt.Key_J)) card.line = Math.min(card.line + 1, card.lines.length - 1)
        else if (l && (k === Qt.Key_Up || k === Qt.Key_K)) card.line = Math.max(card.line - 1, 0)
        else if (l && (k === Qt.Key_Return || k === Qt.Key_Enter)) { const a = app.lineActions(l.kind); card.act(card.line, a.length ? a[0].id : "copy") }
        else if (l && k === Qt.Key_C) card.act(card.line, "copy")
        else if (l && (k === Qt.Key_Escape || k === Qt.Key_Left) && !app.onePane) app.panes.toList()
        else if (l && k === Qt.Key_Escape) card.line = -1
        else if (k === Qt.Key_Escape || k === Qt.Key_Left || k === Qt.Key_Backspace) app.closeCard()
        else if (k === Qt.Key_E && !(e.modifiers & Qt.ControlModifier)) card.edit()
        else if (k === Qt.Key_W && !(e.modifiers & Qt.ControlModifier)) app.write()
        else if (k === Qt.Key_Delete) app.askDelete()
        else if (k === Qt.Key_J) { app.move(1); card.contentY = 0 }
        else if (k === Qt.Key_K) { app.move(-1); card.contentY = 0 }
        else if (k === Qt.Key_PageDown || k === Qt.Key_PageUp) app.scrollCard((k === Qt.Key_PageUp ? -1 : 1) * (card.height - 80))
        else if (k === Qt.Key_Down) app.scrollCard(app.arrowStep)
        else if (k === Qt.Key_Up) app.scrollCard(-app.arrowStep)
        else if (k === Qt.Key_Space) app.scrollCard((e.modifiers & Qt.ShiftModifier ? -1 : 1) * (card.height - 80))
        else return
        e.accepted = true
    }
    // A finger's size, as the only way back for the mouse
    AppIconButton {
        visible: app.onePane
        x: 10; y: 10; z: 1
        implicitWidth: 40; implicitHeight: 40; radius: 8
        c: card.c
        glyph: "arrow-left"; glyphSize: 17
        tip: "All of them"; keys: "Esc"
        onClicked: app.closeCard()
    }
    // A new email: straight to a single address, else the menu of them (each line has its own button too)
    AppButton {
        id: sendButton
        visible: card.p !== null && card.p.emails.length > 0
        anchors.right: editButton.left; anchors.rightMargin: 8; y: 16; z: 1
        c: card.c
        glyph: "send"; label: card.width < 420 ? "" : "Send email"
        tip: "A new email to them"; keys: "w"
        onClicked: app.write()
    }
    // A click away from the menu closes it
    MouseArea {
        visible: emailMenu.open
        x: 0; y: card.contentY; z: 2
        width: card.width; height: card.height
        onClicked: emailMenu.close()
    }
    EmailMenu {
        id: emailMenu
        anchors.right: sendButton.right; y: sendButton.y + sendButton.height + 4; z: 3
        c: card.c
        onChosen: address => card.app.use("write", address)
    }
    function chooseEmail() { emailMenu.show(card.p.emails) }
    AppButton {
        id: editButton
        visible: card.p !== null
        anchors.right: parent.right; anchors.rightMargin: 16; y: 16; z: 1
        c: card.c
        glyph: "pencil"; label: card.width < 420 ? "" : "Edit"
        tip: "Edit the contact"; keys: "⌘E  e"
        onClicked: card.edit()
    }
    boundsBehavior: Flickable.StopAtBounds
    TouchScroll { view: card }
    readonly property var p: app.contact
    Column {
        id: body
        visible: card.p !== null
        x: Math.max(card.margin, (card.width - width) / 2)
        y: app.onePane ? 64 : 56
        width: Math.min(560, card.width - 2 * card.margin)
        spacing: 28
        Grid {
            columns: card.narrow ? 1 : 2
            spacing: card.narrow ? 16 : 22
            verticalItemAlignment: Grid.AlignVCenter
            Avatar { c: card.c; size: card.narrow ? 72 : 84; person: card.p || {}; pixelSize: card.narrow ? 24 : 28 }
            Column {
                width: card.narrow ? body.width : body.width - 84 - 22
                spacing: 6
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: card.p ? card.p.name : ""
                    color: c.title; font.family: c.font; font.pixelSize: 22; font.weight: Font.Medium
                }
                Text {
                    visible: text !== ""
                    width: parent.width; wrapMode: Text.Wrap
                    text: card.p ? [card.p.title, card.p.org].filter(x => x).join(" · ") : ""
                    color: c.dim; font.family: c.font; font.pixelSize: 13
                }
                Text {
                    visible: text !== ""
                    text: card.p && card.p.nickname ? "“" + card.p.nickname + "”" : ""
                    color: c.faint; font.family: c.font; font.pixelSize: 12
                }
                // Where the card is from, with more than one account: one person's cards in several show as one
                Text {
                    visible: app.accounts.length > 1 && card.p !== null
                    text: !card.p ? "" : (card.p.accounts || [card.p.account])
                        .map(a => (app.accounts.find(x => x.id === a) || { name: a }).name).join(" · ")
                    color: c.faint; font.family: c.font; font.pixelSize: 11
                }
            }
        }
        Rectangle { width: parent.width; height: 1; color: c.divider }
        // One line each: phones, emails, addresses, links, the birthday; the note under them
        Column {
            width: parent.width
            spacing: 4
            Repeater {
                id: fields
                model: card.lines
                delegate: Rectangle {
                    id: field
                    required property var modelData
                    required property int index
                    readonly property bool keyed: index === card.line && card.activeFocus     // the keys' line, framed as the kit's rows
                    width: parent.width
                    implicitHeight: card.narrow ? valueText.y + valueText.implicitHeight + 12 : Math.max(40, valueText.implicitHeight + 20)
                    radius: 8
                    color: keyed ? c.sel : fh.hovered ? c.hover : "transparent"
                    border.color: keyed ? c.frame : "transparent"
                    border.width: 2
                    HoverHandler { id: fh; cursorShape: Qt.PointingHandCursor }
                    readonly property var actions: app.lineActions(modelData.kind)
                    // A click on one of its buttons is the button's alone
                    TapHandler { onTapped: if (field.actions.length && !buttons.hovered) card.act(field.index, field.actions[0].id) }
                    Text {
                        id: glyph
                        x: 12; y: 12
                        text: Icons.g(field.modelData.glyph); font.family: Icons.family; font.pixelSize: 15; color: c.dim
                    }
                    Text {
                        id: labelText
                        x: 44; y: 12; width: card.narrow ? parent.width - x - 12 : 96
                        elide: Text.ElideRight
                        text: field.modelData.label; color: c.faint; font.family: c.font; font.pixelSize: 12
                    }
                    Text {
                        id: valueText
                        x: card.narrow ? 44 : 148; y: card.narrow ? 32 : 11
                        width: parent.width - x - 64        // room for its buttons
                        wrapMode: Text.Wrap; lineHeight: 1.2
                        text: field.modelData.value; color: c.text; font.family: c.font; font.pixelSize: 13
                    }
                    Row {
                        visible: card.copied === field.index
                        anchors.right: parent.right; anchors.rightMargin: 14; y: 12
                        spacing: 6
                        Text { text: Icons.g("check"); font.family: Icons.family; font.pixelSize: 13; color: c.primary }
                        Text { text: "Copied"; color: c.dim; font.family: c.font; font.pixelSize: 12 }
                    }
                    Row {
                        id: buttons
                        readonly property bool hovered: bh.hovered
                        visible: fh.hovered && card.copied !== field.index
                        anchors.right: parent.right; anchors.rightMargin: 7; y: 7
                        spacing: 2
                        HoverHandler { id: bh }
                        Repeater {
                            model: field.actions
                            delegate: AppIconButton {
                                required property var modelData
                                c: card.c
                                glyph: modelData.glyph; glyphColor: c.faint; hoverColor: c.sel
                                tip: modelData.tip
                                onClicked: card.act(field.index, modelData.id)
                            }
                        }
                    }
                }
            }
        }
        Text {
            visible: card.p !== null && card.p.note !== ""
            width: parent.width
            leftPadding: 12; rightPadding: 12
            wrapMode: Text.Wrap; lineHeight: 1.25
            text: card.p ? card.p.note : ""
            color: c.dim; font.family: c.font; font.pixelSize: 12
        }
    }
    Text {
        visible: app.loaded && card.p === null && !app.needsAccount
        anchors.centerIn: parent
        text: "No contact open"
        color: c.faint; font.family: c.font; font.pixelSize: 12
    }
}
