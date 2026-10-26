import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// The editor, in the card's place: the name and company, the numbers, addresses and links with their labels, the
// birthday and the note. It edits a draft of one card (a person in several accounts: the card of the account picked at
// the top); Store saves it through lib/edit.py, which keeps whatever else the card holds.
FocusScope {
    id: ed
    required property var app            // the window: accounts, everyone, the store and the question panel
    required property QtObject c
    property var draft: null
    property string original: ""         // the draft as it opened, to tell whether anything changed
    property var choices: []             // [card] the person has, one per account; or the accounts a new one can go in
    property string error: ""
    readonly property bool isNew: draft !== null && !draft.id
    readonly property int margin: width < 520 ? 24 : 40
    signal done(string id)

    readonly property var labels: ({
        phones: ["mobile", "iPhone", "home", "work", "main", "fax", "pager", "other"],
        emails: ["home", "work", "other"],
        addresses: ["home", "work", "other"],
        urls: ["homepage", "home", "work", "other"]
    })

    // The birthday as people write it here: 3.5.1980, or 3.5. without the year (cards.py has 1980-05-03 or --05-03)
    function day(b) {
        const m = (b || "").match(/^(\d{4}|-)-(\d{2})-(\d{2})$/)
        return !m ? b || "" : parseInt(m[3]) + "." + parseInt(m[2]) + "." + (m[1] === "-" ? "" : m[1])
    }
    function line(x) { return Object.assign({}, x, { orig: Object.assign({}, x) }) }
    function fromCard(x) {
        return {
            id: x.id, account: x.account, given: x.given, family: x.family, company: x.company || "",
            title: x.title, nickname: x.nickname, birthday: day(x.birthday), note: x.note,
            phones: x.phones.map(line), emails: x.emails.map(line), urls: x.urls.map(line), addresses: x.addresses.map(line)
        }
    }
    function blank(account) {
        return { id: "", account: account, given: "", family: "", company: "", title: "", nickname: "", birthday: "", note: "",
                 phones: [{ label: "mobile", value: "", ref: -1, orig: null }],
                 emails: [{ label: "home", value: "", ref: -1, orig: null }], urls: [], addresses: [] }
    }
    function start(d) {
        error = ""
        draft = d
        original = JSON.stringify(d)
        scroller.contentY = 0
        given.forceActiveFocus()
    }
    // cards: the person's, one per account (the first is opened); account: where a new one goes
    function openCards(cards) { choices = cards; start(fromCard(cards[0])) }
    // name, email: filled in already (Mail's Add to contacts), the last word of the name as the family name; the draft
    // counts as changed, so Esc asks before dropping them
    function openNew(account, name, email) {
        choices = []
        start(blank(account))
        if (!name && !email) return
        const words = (name || "").trim().split(/\s+/).filter(w => w)
        draft = Object.assign({}, draft, { given: words.length > 1 ? words.slice(0, -1).join(" ") : words.join(""),
                                           family: words.length > 1 ? words[words.length - 1] : "",
                                           emails: [{ label: "home", value: email || "", ref: -1, orig: null }] })
    }
    function dirty() { return draft !== null && JSON.stringify(draft) !== original }
    function pick(i) {
        if (isNew) draft = Object.assign({}, draft, { account: app.accounts[i].id })
        else if (!dirty()) start(fromCard(choices[i]))
    }
    function save() { if (draft) { error = ""; app.store.save(draft) } }
    function cancel() {
        if (!dirty()) { done(""); return }
        app.confirm.ask("Leave without saving?", "What you changed here is lost.", "Leave", () => ed.done(""))
    }

    Keys.onPressed: e => {
        const ctrl = e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
        if (ctrl && (e.key === Qt.Key_S || e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) save()
        else if (e.key === Qt.Key_Escape) cancel()
        else return
        e.accepted = true
    }

    // The top line: what this is, the account, and the two ways out
    RowLayout {
        id: top
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: ed.margin; anchors.rightMargin: 16
        y: 16
        spacing: 8
        Text {
            text: ed.isNew ? "New contact" : "Edit contact"
            color: c.title; font.family: c.font; font.pixelSize: 14; font.weight: Font.Medium
        }
        // The account: for a new one, where it goes; for a person in several, which card is edited
        Text {
            visible: chips.count > 0
            text: "in"; color: c.faint; font.family: c.font; font.pixelSize: 12
        }
        Repeater {
            id: chips
            model: ed.isNew ? (app.accounts.length > 1 ? app.accounts : []) : (ed.choices.length > 1 ? ed.choices : [])
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property string account: ed.isNew ? modelData.id : modelData.account
                readonly property bool on: ed.draft !== null && ed.draft.account === account
                implicitWidth: chip.implicitWidth + 16; implicitHeight: 22; radius: 11
                color: on ? c.sel : chipHover.hovered ? c.hover : "transparent"
                border.color: on ? c.primary : c.line
                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: ed.pick(parent.index) }
                Text {
                    id: chip
                    anchors.centerIn: parent
                    text: ed.app.store.accountName(parent.account)
                    color: parent.on ? c.title : c.dim; font.family: c.font; font.pixelSize: 11
                }
            }
        }
        Item { Layout.fillWidth: true }
        AppButton { c: ed.c; label: "Cancel"; tip: "Leave without saving"; keys: "Esc"; onClicked: ed.cancel() }
        AppButton { c: ed.c; glyph: "check"; label: "Save"; strong: true; tip: "Save the contact"; keys: "⌘S"; onClicked: ed.save() }
    }
    Text {
        id: errorText
        visible: ed.error !== ""
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: ed.margin; anchors.rightMargin: ed.margin
        anchors.top: top.bottom; anchors.topMargin: 10
        wrapMode: Text.Wrap
        text: ed.error; color: c.danger; font.family: c.font; font.pixelSize: 12
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        anchors.topMargin: (errorText.visible ? errorText.y + errorText.height : top.y + top.height) + 12
        clip: true
        contentHeight: form.implicitHeight + 64
        boundsBehavior: Flickable.StopAtBounds
        TouchScroll { view: scroller }
        // The field with the focus stays in sight as Tab goes down the form
        function reveal(item) {
            if (!item || height <= 0) return       // not laid out yet: the editor has just opened, at the top
            const p = item.mapToItem(form, 0, 0)
            if (p.y < contentY) contentY = Math.max(0, p.y - 24)
            else if (p.y + item.height > contentY + height) contentY = Math.min(contentHeight - height, p.y + item.height - height + 24)
        }
        Connections {
            target: ed.Window.window
            function onActiveFocusItemChanged() { if (ed.visible) scroller.reveal(ed.Window.window.activeFocusItem) }
        }

        ColumnLayout {
            id: form
            x: Math.max(ed.margin, (scroller.width - width) / 2)
            y: 16
            width: Math.min(560, scroller.width - 2 * ed.margin)
            spacing: 22

            RowLayout {
                spacing: 22
                Avatar {
                    Layout.alignment: Qt.AlignTop
                    visible: form.width >= 420
                    c: ed.c; size: 72; pixelSize: 24
                    person: ed.draft ? { initials: ((ed.draft.given || "").charAt(0) + (ed.draft.family || ed.draft.company || "").charAt(0)).toUpperCase() } : {}
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    EditField { id: given; Layout.fillWidth: true; c: ed.c; target: ed.draft; key: "given"; placeholder: "First name"; pixelSize: 16 }
                    EditField { Layout.fillWidth: true; c: ed.c; target: ed.draft; key: "family"; placeholder: "Last name"; pixelSize: 16 }
                    EditField { Layout.fillWidth: true; c: ed.c; target: ed.draft; key: "company"; placeholder: "Company" }
                    EditField { Layout.fillWidth: true; c: ed.c; target: ed.draft; key: "title"; placeholder: "Job title" }
                    EditField { Layout.fillWidth: true; c: ed.c; target: ed.draft; key: "nickname"; placeholder: "Nickname" }
                }
            }
            Section { text: "Phone" }
            EditLines { Layout.fillWidth: true; c: ed.c; draft: ed.draft; key: "phones"; options: ed.labels.phones; placeholder: "Number"; addText: "Add a number" }
            Section { text: "Email" }
            EditLines { Layout.fillWidth: true; c: ed.c; draft: ed.draft; key: "emails"; options: ed.labels.emails; placeholder: "Address"; addText: "Add an email address" }
            Section { text: "Address" }
            EditLines { Layout.fillWidth: true; c: ed.c; draft: ed.draft; key: "addresses"; options: ed.labels.addresses; address: true; addText: "Add an address" }
            Section { text: "Web" }
            EditLines { Layout.fillWidth: true; c: ed.c; draft: ed.draft; key: "urls"; options: ed.labels.urls; placeholder: "https://…"; addText: "Add a link" }
            Section { text: "Birthday" }
            EditField { Layout.fillWidth: true; c: ed.c; target: ed.draft; key: "birthday"; placeholder: "3.5.1980, or 3.5. without the year" }
            Section { text: "Note" }
            EditField { Layout.fillWidth: true; c: ed.c; target: ed.draft; key: "note"; multiline: true; placeholder: "Anything to remember" }

            AppButton {
                visible: !ed.isNew
                Layout.topMargin: 12
                c: ed.c
                glyph: "trash-2"; label: "Delete contact"; tipAlign: "left"
                tip: ed.choices.length > 1 ? "From every account it's in" : "From " + ed.app.store.accountName(ed.draft ? ed.draft.account : "")
                onClicked: ed.app.askDelete()
            }
        }
    }

    component Section: Text {
        Layout.topMargin: 6
        Layout.bottomMargin: -12
        color: ed.c.faint; font.family: ed.c.font; font.pixelSize: 11; font.weight: Font.Medium
    }
}
