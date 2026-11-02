import QtQuick

// The thread list's keys, which are most of Mail's (Mac Mail's, with j k and the rest): the list keeps the keyboard in
// every pane (Panes.qml), so this is where a key acts on the folders, the list or the open thread. Apart from
// ThreadList.qml so the list's look and its keys can each be read on their own.
QtObject {
    required property var win
    required property var ops           // Actions.qml
    required property var writer        // Writing.qml
    required property var panes
    required property var sheet
    required property var reader

    function pressed(e) {
        const k = e.key
        win.look.moved(e)              // Tab and the arrows show the keys' frame (AppPointer)
        // The list takes most keys before they reach the sheet: any but ? closes it here.
        if (win.cheats && k !== Qt.Key_Question && sheet.modifierKeys.indexOf(k) < 0) win.cheats = false
        if (panes.pressed(e)) { e.accepted = true; return }
        const ctrl = e.modifiers & Qt.ControlModifier
        const alt = e.modifiers & Qt.AltModifier
        const shift = e.modifiers & Qt.ShiftModifier
        // ⇧↑ ⇧↓ (⇧K ⇧J) pick threads from the open one on; ⌘A (Ctrl+A) picks them all, Esc none
        if (shift && (k === Qt.Key_Down || k === Qt.Key_J)) win.pickRange(win.current + 1)
        else if (shift && (k === Qt.Key_Up || k === Qt.Key_K)) win.pickRange(win.current - 1)
        else if ((ctrl || e.modifiers & Qt.MetaModifier) && k === Qt.Key_A) win.pickAll()
        else if (k === Qt.Key_Escape && win.picked.length) win.open(win.current)
        else if ((k === Qt.Key_Escape || k === Qt.Key_Left) && win.readerOpen) win.readerOpen = false
        else if (k === Qt.Key_Right && win.onePane && !win.readerOpen) win.openReader()
        else if (ctrl && k === Qt.Key_Down && win.folder < win.folders.length - 1) win.pickFolder(win.folder + 1)
        else if (ctrl && k === Qt.Key_Up && win.folder > 0) win.pickFolder(win.folder - 1)
        else if (ctrl && (k === Qt.Key_Up || k === Qt.Key_Down)) {}
        // The arrows move in the list, as in Mac Mail (Space pages through the message); with the thread
        // alone on show they scroll it, and j k or ⌥ arrows move on. Only the list on show: PgUp PgDn too
        else if (win.listOnly && (k === Qt.Key_Down || k === Qt.Key_J)) win.open(Math.min(win.current + 1, win.threads.length - 1))
        else if (win.listOnly && (k === Qt.Key_Up || k === Qt.Key_K)) win.open(Math.max(win.current - 1, 0))
        else if (win.listOnly && k === Qt.Key_PageDown) win.open(Math.min(win.current + 10, win.threads.length - 1))
        else if (win.listOnly && k === Qt.Key_PageUp) win.open(Math.max(win.current - 10, 0))
        else if ((k === Qt.Key_J || (alt || !win.readerOpen) && k === Qt.Key_Down) && win.current < win.threads.length - 1) win.open(win.current + 1)
        else if ((k === Qt.Key_K || (alt || !win.readerOpen) && k === Qt.Key_Up) && win.current > 0) win.open(win.current - 1)
        else if ((alt || !win.readerOpen) && (k === Qt.Key_Up || k === Qt.Key_Down)) {}
        else if (k === Qt.Key_Down) win.scrollMessage(win.arrowStep)
        else if (k === Qt.Key_Up) win.scrollMessage(-win.arrowStep)
        else if (k === Qt.Key_Question) win.cheats = !win.cheats
        else if (k === Qt.Key_H && shift) win.openBrowser()
        else if (k === Qt.Key_H) win.htmlMode = (win.htmlMode + 1) % 3
        // ⌘C copies the text selected in the message (Thread.copy), and never starts a new message
        else if (reader.isCopy(e)) reader.copy()
        else if (k === Qt.Key_C) win.compose("new")
        else if (k === Qt.Key_F) win.compose("forward")
        // Enter opens the thread in a window of its own; in one pane, first in the window
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (writer.draft()) win.compose("resume"); else if (win.onePane && !win.readerOpen) win.openReader(); else win.openWindow(win.current) }
        // r answers everyone, ⇧R only the sender; ⌘⇧C (Ctrl+Shift+C) has Claude write the reply.
        else if (k === Qt.Key_R && !alt) win.compose(e.modifiers & Qt.ShiftModifier ? "reply" : "all")
        else if (k === Qt.Key_A || k === Qt.Key_E) ops.archive()
        else if ((k === Qt.Key_Backspace || k === Qt.Key_Delete) && shift && (ctrl || e.modifiers & Qt.MetaModifier)) ops.emptyTrash()
        else if (k === Qt.Key_D || k === Qt.Key_NumberSign || k === Qt.Key_Backspace || k === Qt.Key_Delete) ops.trash()
        else if (k === Qt.Key_Exclam) ops.spam()
        else if (k === Qt.Key_U && shift) ops.markAllRead(win.folder)
        else if (k === Qt.Key_U) ops.toggleRead()
        else if (k >= Qt.Key_1 && k < Qt.Key_1 + win.folders.length) win.pickFolder(k - Qt.Key_1)
        else if (k === Qt.Key_PageDown || k === Qt.Key_PageUp) win.scrollMessage((k === Qt.Key_PageUp ? -1 : 1) * (reader.height - 80))
        else if (k === Qt.Key_Space) win.scrollMessage((e.modifiers & Qt.ShiftModifier ? -1 : 1) * (reader.height - 80))
        else return
        e.accepted = true
    }
}
