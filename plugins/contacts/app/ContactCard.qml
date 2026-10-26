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
    // Its keys in one pane, where the list is away: back, scrolling, editing
    Keys.onPressed: e => {
        const k = e.key
        app.sheetKey(e)
        if (k === Qt.Key_Question) {}
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
                model: card.p ? card.p.phones.map(x => ({ kind: "phone", glyph: "phone", label: x.label || "phone", value: x.value }))
                    .concat(card.p.emails.map(x => ({ kind: "email", glyph: "mail", label: x.label || "email", value: x.value })))
                    .concat(card.p.addresses.map(x => ({ kind: "address", glyph: "map-pin", label: x.label || "address", value: x.lines.join("\n") })))
                    .concat(card.p.urls.map(x => ({ kind: "url", glyph: "link", label: x.label || "web", value: x.value })))
                    .concat(card.p.birthday ? [{ kind: "birthday", glyph: "cake", label: "birthday", value: app.when(card.p.birthday) }] : [])
                    : []
                delegate: Rectangle {
                    id: field
                    required property var modelData
                    width: parent.width
                    implicitHeight: card.narrow ? valueText.y + valueText.implicitHeight + 12 : Math.max(40, valueText.implicitHeight + 20)
                    radius: 8
                    color: fh.hovered ? c.hover : "transparent"
                    HoverHandler { id: fh; cursorShape: Qt.PointingHandCursor }
                    readonly property var actions: app.lineActions(modelData.kind)
                    // A click on one of its buttons is the button's alone
                    TapHandler { onTapped: if (field.actions.length && !buttons.hovered) app.use(field.actions[0].id, field.modelData.value) }
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
                        id: buttons
                        readonly property bool hovered: bh.hovered
                        visible: fh.hovered
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
                                onClicked: app.use(modelData.id, field.modelData.value)
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
