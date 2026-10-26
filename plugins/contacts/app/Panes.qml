import QtQuick

// Tab and ⇧Tab move the keys round the sidebar, the list and the card, as in Mail and Garage. The list keeps the keys
// for the sidebar too (`pane` says which they act on: there ↑ ↓ pick a row); the card takes them itself, a line of it
// at a time (ContactCard's line), so a number or an address can be copied without the mouse.
QtObject {
    id: root
    required property var win
    required property Item list
    required property Item card
    property string pane: "list"
    // The sidebar hides in a narrow window, and the keys go back to the list with it
    readonly property string at: pane === "sources" && win.sidebarShown ? "sources" : "list"

    function toList() { pane = "list"; list.forceActiveFocus() }
    function toSources() { if (win.sidebarShown) { pane = "sources"; list.forceActiveFocus() } else toList() }
    function toCard() {
        if (!win.contact) return false
        if (win.onePane) win.openCard(); else card.forceActiveFocus()
        card.line = 0
        return true
    }

    // From the list's key handler, before its own keys: true when the key was Tab's or the sidebar's
    function pressed(e) {
        const k = e.key
        if (k === Qt.Key_Tab) { if (at === "sources") toList(); else if (!toCard()) toSources() }
        else if (k === Qt.Key_Backtab) { if (at === "list") toSources(); else if (!toCard()) toList() }
        else if (at !== "sources") return false
        else if (k === Qt.Key_Down || k === Qt.Key_J) win.pickSource(win.source + 1, true)
        else if (k === Qt.Key_Up || k === Qt.Key_K) win.pickSource(win.source - 1, true)
        else if (k === Qt.Key_Escape || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right) pane = "list"
        else return false
        return true
    }

    // The card's Tab: on to the sidebar (⇧Tab back to the list); in one pane, where the card is alone, out of its lines
    function fromCard(back) {
        if (win.onePane) card.line = -1
        else if (back) toList()
        else toSources()
    }
}
