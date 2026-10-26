import QtQuick

// Tab and ⇧Tab move the keyboard to the folders and back to the list (as Garage's Tab goes to its snapshots and back);
// Ctrl+Tab and Ctrl+⇧Tab show the next and previous account's folders.
// The list keeps the keys in both: focus in the thread's text stopped the window's keys (Thread.qml), so `pane` only
// says which part they act on. In the folders ↑ ↓ pick a folder, Esc, Enter or → go back to the list, and every other
// key works as it does there.
QtObject {
    id: root
    required property var win
    property string pane: "list"
    // The folders hide in a narrow window, and the keys go back to the list with them
    readonly property string at: pane === "folders" && win.showFolders ? "folders" : "list"

    // From the list's key handler, before its own keys: true when the key was Tab's or the folders'
    function pressed(e) {
        const k = e.key, ctrl = e.modifiers & Qt.ControlModifier, n = win.accounts.length
        if (ctrl && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) {
            if (n > 1) win.pickAccount((win.acct + (k === Qt.Key_Tab ? 1 : n - 1)) % n, true)
        }
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) pane = at === "list" && win.showFolders ? "folders" : "list"
        else if (at !== "folders") return false
        else if (k === Qt.Key_Down || k === Qt.Key_J) { if (win.folder < win.folders.length - 1) win.pickFolder(win.folder + 1, true) }
        else if (k === Qt.Key_Up || k === Qt.Key_K) { if (win.folder > 0) win.pickFolder(win.folder - 1, true) }
        else if (k === Qt.Key_Escape || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right) pane = "list"
        else return false
        return true
    }
}
