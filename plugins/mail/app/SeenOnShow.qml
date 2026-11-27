import QtQuick
import "fresh.js" as Fresh

// Marks read the messages a refresh brings into the thread on show (#3615), as Apple Mail does: at once when its
// window is the active one and the thread can be seen, else as soon as it is. open() marks a thread read as it opens;
// this is for what arrives while it stays open (a sync's message, a reply from elsewhere). Only the new messages are
// marked (fresh.js arrived()), so one the user marked unread again stays so.
QtObject {
    id: seen
    required property QtObject nm       // Notmuch.qml
    property bool shown: false          // the window is active and the thread can be seen
    property var pending: []            // ids waiting for shown
    signal marked()                     // tagged: the list's dots and counts are read again

    function arrived(was, now) {
        const ids = Fresh.arrived(was, now)
        if (!ids.length) return
        pending = pending.concat(ids)
        flush()
    }
    // Another thread opened (or none): what waited was for the one before
    function forget() { pending = [] }
    function flush() {
        if (!shown || !pending.length) return
        const ids = pending
        pending = []
        nm.tag(["-unread"], ids.map(i => "id:\"" + i + "\"").join(" or "), () => seen.marked())
    }
    onShownChanged: flush()
}
