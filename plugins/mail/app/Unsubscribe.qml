import QtQuick
import qs
import qs.kit

// A newsletter's Unsubscribe, at the end of its header's attachments row (Attachments.qml, #2393). The link is
// lib/unsubscribe.py's (the List-Unsubscribe header, else the body's own link), loaded for the whole thread by
// Thread.qml. A web link opens in the browser and a mailto: one as a new message to send, both through Thread's
// openLink: nothing is sent or posted here. The tip says where it goes, as the sender wrote it.
AppButton {
    id: root
    required property var link            // { url, kind: "web"|"mail", from } or null
    property var open: null               // Thread.openLink
    // Beside a narrow pane's chips the word gives way to the glyph, and the tip says the rest
    property bool narrow: false
    visible: link !== null && link !== undefined
    implicitHeight: 34
    glyph: "mail-x"
    label: narrow ? "" : "Unsubscribe"
    tipAlign: "left"
    tip: !visible ? "" : (narrow ? "Unsubscribe: " : "") + (link.kind === "web" ? "opens " + host(link.url) + " in the browser"
        : "writes to " + link.url.replace(/^mailto:/i, "").split("?")[0])
    onClicked: if (open) open(link.url)

    function host(url) { const m = /^https?:\/\/([^\/?#:]+)/i.exec(url); return m ? m[1] : url }
}
