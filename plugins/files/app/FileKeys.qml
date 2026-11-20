import QtQuick

// Files' keys, yazi's letters and the desktop's ⌘ keys side by side (⌘ reaches the app as Ctrl or Meta). Moving and opening
// take hjkl and the arrows alone: ⌘ + an arrow is the window manager's. g starts a pair: gg the first row, gh home,
// gd Downloads. Space is the big preview (Quick Look's key), so marking is v, ⇧↑ ⇧↓ and ⌘-click. press(e) does what e asks and answers whether it was one of these; the window's handler passes on the
// rest. In the sidebar (Tab) the moving keys walk its rows instead.
QtObject {
    id: root
    required property var app
    property bool gPending: false
    readonly property Timer gTimer: Timer { interval: 800; onTriggered: root.gPending = false }

    function press(e) {
        const a = app, k = e.key, t = e.text
        // ⌘: Hyprland turns only some ⌘ keys into Ctrl (⌘C ⌘Z ⌘A ⌘F …, bindings.lua); the rest (⌘N ⌘D ⌘L ⌘O …) come as
        // Meta, so either is ⌘ here
        const ctrl = (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) !== 0
        const shift = (e.modifiers & Qt.ShiftModifier) !== 0
        const alt = (e.modifiers & Qt.AltModifier) !== 0
        const enter = k === Qt.Key_Return || k === Qt.Key_Enter

        if (gPending && !ctrl) {
            gPending = false; gTimer.stop()
            if (t === "g") { a.moveTo(0); return true }
            if (t === "h") { a.go(a.home, ""); return true }
            if (t === "d") { a.goDownloads(); return true }
        }
        // Tab in the filter's field turns its scope (this folder, and below); elsewhere it moves between the panes
        if ((k === Qt.Key_Tab || k === Qt.Key_Backtab) && a.filtering && a.fieldFocused) { a.toggleScope(); return true }
        if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { a.switchPane(); return true }

        if (a.pane === "side") {
            if (k === Qt.Key_Down || t === "j") a.sideMove(1)
            else if (k === Qt.Key_Up || t === "k") a.sideMove(-1)
            else if (enter || k === Qt.Key_Right || t === "l") a.sideOpen()
            else if (k === Qt.Key_Escape || k === Qt.Key_Left || t === "h") a.toList()
            else return false
            return true
        }

        // With ⌘ (Ctrl)
        if (ctrl) {
            if (k === Qt.Key_C) a.acts.copy(false)
            else if (k === Qt.Key_X) a.acts.copy(true)
            else if (k === Qt.Key_V) a.acts.paste()
            else if (k === Qt.Key_O) a.openPicked()
            else if (k === Qt.Key_A) a.markAll()
            else if (k === Qt.Key_F) a.startFilter()
            else if (k === Qt.Key_L) a.acts.askGo()
            else if (k === Qt.Key_N && shift) a.acts.askNew(true)
            else if (k === Qt.Key_N) a.newWindow()
            else if (k === Qt.Key_D) a.acts.toggleBookmark()
            else if (k === Qt.Key_R) a.reload()
            else if (k === Qt.Key_Backspace && shift && a.trashShown) a.acts.askEmpty()
            else if (k === Qt.Key_Backspace || k === Qt.Key_Delete) a.acts.trashPicked()
            else if (k === Qt.Key_Period || k === Qt.Key_Greater) a.showHidden = !a.showHidden   // ⌘⇧. as on a Mac
            else return false
            return true
        }
        // ⌥ arrows: back and forward (⌃⌘← → arrive as these), up and open as a Mac's ⌘↑ ⌘↓
        if (alt) {
            if (k === Qt.Key_Left) a.back()
            else if (k === Qt.Key_Right) a.forward()
            else if (k === Qt.Key_Up) a.up()
            else if (k === Qt.Key_Down) a.openPicked()
            else return false
            return true
        }

        if (k === Qt.Key_Down && shift) a.markMove(1)
        else if (k === Qt.Key_Up && shift) a.markMove(-1)
        else if (k === Qt.Key_Down || t === "j") a.move(1)
        else if (k === Qt.Key_Up || t === "k") a.move(-1)
        else if (k === Qt.Key_PageDown) a.move(a.page())
        else if (k === Qt.Key_PageUp) a.move(-a.page())
        else if (k === Qt.Key_Home) a.moveTo(0)
        else if (k === Qt.Key_End || t === "G") a.moveTo(a.rows.length - 1)
        else if (t === "g") { gPending = true; gTimer.restart() }
        else if (enter || k === Qt.Key_Right || t === "l") a.openPicked()
        else if (k === Qt.Key_Left || t === "h" || k === Qt.Key_Backspace) a.up()
        else if (k === Qt.Key_Space) a.quick.toggle()
        else if (t === "v") a.toggleMark()
        else if (k === Qt.Key_Escape) a.letGo()
        else if (t === "y") a.acts.copy(false)
        else if (t === "x") a.acts.copy(true)
        else if (t === "p") a.acts.paste()
        else if (t === "d" || k === Qt.Key_Delete) a.trashShown ? a.acts.askDelete() : a.acts.trashPicked()
        else if (t === "u" && a.trashShown) a.acts.restorePicked()
        else if (t === "r" || k === Qt.Key_F2) a.acts.askRename()
        else if (t === "a") a.acts.askNew(false)
        else if (t === "/") a.startFilter()
        else if (t === "f" || t === "F") a.startFilter(true)
        else if (t === ".") a.showHidden = !a.showHidden
        else if (t === "s") a.cycleSort()
        else if (t === "S") a.reversed = !a.reversed
        else if (t === "~") a.go(a.home, "")
        else if (t === "i") a.previewChoice = !a.previewShown
        else if (t === "b") a.acts.toggleBookmark()
        else return false
        return true
    }
}
