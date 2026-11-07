import QtQuick
import qs
import qs.kit

// The invitation card's answer (#2130): Accept, Maybe and Decline, each a mail to the organiser (an iTIP REPLY), sent
// from the account the invitation came to when it is pressed, and never before: the line under them says who gets it.
// The answer given shows as the strong button and in words; another press changes it (a new reply). An Accept or Maybe
// of one in no calendar puts it in the calendar picked on the card, as Add to calendar would; Decline leaves it out.
// Shown when Calendar says it can be answered (info.reply.can: an invitation, METHOD:REQUEST, someone else organises).
// Sending is `nightmail invitation ID --reply …` (lib/invitation_reply.py), through Invitation.qml's act().
Column {
    id: root
    required property QtObject c
    required property var card            // Invitation.qml: info, busy, narrow, act(), app.inviteCalendar
    readonly property var reply: card.info && card.info.reply ? card.info.reply : null
    // The calendar's copy has the answer; a declined one that never went in a calendar has only the one sent from here
    readonly property string answer: given || (reply && reply.answer ? reply.answer : "")
    property string given: ""
    property string sending: ""           // the answer on its way, for the button's "Sending…"

    visible: reply !== null && reply.can === true && card.info.state !== "older"
    spacing: 6

    readonly property var answers: [
        { key: "accept", partstat: "ACCEPTED", glyph: "circle-check", label: "Accept", said: "You accepted." },
        { key: "maybe", partstat: "TENTATIVE", glyph: "circle-help", label: "Maybe", said: "You said maybe." },
        { key: "decline", partstat: "DECLINED", glyph: "circle-x", label: "Decline", said: "You declined." }
    ]

    function send(a) {
        if (card.busy) return
        sending = a.key
        const args = ["--reply", a.key]
        // A new one goes in a calendar with a yes or a maybe, the one the card's chips picked
        if (card.info.state === "new" && a.key !== "decline" && card.app.inviteCalendar)
            args.push("--calendar", card.app.inviteCalendar)
        card.act(args, "Sending your answer…", r => { if (!r.error) given = a.partstat })
    }
    Connections {
        target: root.card
        function onBusyChanged() { if (!root.card.busy) root.sending = "" }
        function onMsgChanged() { root.given = "" }
    }

    Text {
        width: parent.width; visible: text !== ""
        textFormat: Text.PlainText; wrapMode: Text.Wrap
        text: { const a = root.answers.find(x => x.partstat === root.answer); return a ? a.said : "" }
        color: root.answer === "DECLINED" ? root.c.dim : root.c.accent
        font.family: root.c.font; font.pixelSize: 12
    }
    Flow {
        width: parent.width
        spacing: 8
        Repeater {
            model: root.answers
            AppButton {
                required property var modelData
                c: root.c
                glyph: modelData.glyph
                strong: root.answer === modelData.partstat
                label: root.sending === modelData.key ? "Sending…" : modelData.label
                tip: (root.answer === modelData.partstat ? "Send it again" : modelData.label) + " – a mail to "
                     + (root.reply ? root.reply.to : "")
                tipAlign: "left"
                onClicked: root.send(modelData)
            }
        }
    }
    // Who gets it, before anything goes: the organiser, from the address the invitation came to
    Text {
        width: parent.width
        textFormat: Text.PlainText; elide: Text.ElideRight
        text: root.reply ? "Your answer goes to " + root.reply.to + (root.card.narrow ? "" : ", from " + root.reply.as) : ""
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
}
