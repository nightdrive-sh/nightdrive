import QtQuick
import Quickshell

// The launcher's search field, with the level's path before it, and the keys typed there: Enter, Esc, the arrows, Tab
// in a form, ⌥←/→, ⌘C on a row with a value, and the details card's keys. All of the launcher's keyboard handling is
// here, so a new key is added in one place.
Row {
    id: root
    required property var launcher
    property alias input: textInput   // the launcher's `field`
    width: parent.width
    height: 44
    Text {
        id: crumb
        visible: root.launcher.level !== "root"
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: 14
        rightPadding: 6
        text: (root.launcher.titles[root.launcher.level] || root.launcher.level) + "  ›"
        color: Theme.dim
        font { family: Theme.font; pixelSize: root.launcher.fontSize + 1; weight: root.launcher.fontWeight }
    }
    TextInput {
        id: textInput
        echoMode: root.launcher.level === "wifipw" ? TextInput.Password : TextInput.Normal   // Wi-Fi › Password
        opacity: root.launcher.fieldRow ? 0 : 1      // a form's field shows the text in its own box (FieldBox.qml)
        width: parent.width - (crumb.visible ? crumb.width : 0)
        height: parent.height
        verticalAlignment: TextInput.AlignVCenter
        leftPadding: crumb.visible ? 4 : 14
        color: Theme.text
        selectionColor: Theme.sel
        font { family: Theme.font; pixelSize: root.launcher.fontSize + 2; weight: root.launcher.fontWeight }
        focus: true
        clip: true
        onTextChanged: { if (root.launcher.detail !== null) root.launcher.detailCard.close()   // a new search (IPC setQuery)
                         root.launcher.query = text; root.launcher.armed = ""; root.launcher.topFocused = false
                         if (root.launcher.fieldRow) root.launcher.fieldAt = root.launcher.selIndex   // typed into: leaving it hands the text over
                         else if (!root.launcher.holdIndex) root.launcher.selectFirst() }
        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier
            if (root.launcher.topFocused && root.launcher.topExt && root.launcher.topExt.topKey(event)) { event.accepted = true; return }
            // ⌘C (Hyprland sends Ctrl+Insert; Ctrl+C too) on a row with a `copy` value, e.g. an IP address;
            // selected text in the search field is copied as usual
            const copyRow = root.launcher.results[root.launcher.selIndex]
            if (ctrl && (event.key === Qt.Key_Insert || event.key === Qt.Key_C) && copyRow && copyRow.copy !== undefined && selectedText === "") {
                root.launcher.rowCopy.copyText(copyRow.copy, copyRow.sensitive === true); event.accepted = true; return
            }
            if (root.launcher.detail !== null) {         // details: Enter installs / removes, C sets up with Claude, arrows scroll, typing does nothing
                if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) root.launcher.back()
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.launcher.detailCard.confirm(ctrl)
                else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) root.launcher.detailCard.switchSource()
                else if (event.key === Qt.Key_C && !ctrl) root.launcher.detailCard.setup()
                else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) root.launcher.detailCard.scroll(root.launcher.rowHeight)
                else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) root.launcher.detailCard.scroll(-root.launcher.rowHeight)
                else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Space) root.launcher.detailCard.scroll(root.launcher.detailCard.height - root.launcher.rowHeight)
                else if (event.key === Qt.Key_PageUp) root.launcher.detailCard.scroll(-(root.launcher.detailCard.height - root.launcher.rowHeight))
                event.accepted = true
                return
            }
            // Esc with a search typed clears it first (on any level); with an empty one it goes back / closes
            if (event.key === Qt.Key_Escape) { if (text !== "") text = ""; else root.launcher.back(); event.accepted = true }
            else if (ctrl && event.key === Qt.Key_Space) { if (root.launcher.topExt) root.launcher.topExt.topPress(); event.accepted = true }
            // Delete: removes your own wallpaper in Background, the selected snippet in Snippets (empty search). ⌘⌫
            // arrives as ⇧Home + Delete with the keyd plugin (plugins/keyd/app.conf), so it does the same
            else if (event.key === Qt.Key_Delete && root.launcher.extDelete()) event.accepted = true
            // Tab / ⇧Tab: a form's next / previous field
            else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && root.launcher.stepField(event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier) ? 1 : -1)) event.accepted = true
            // Backspace with an empty search goes back; Ctrl+⌫ (⌥⌫ with keyd: delete a word) doesn't. In a form's
            // field it only deletes: one Backspace too many after clearing a value mustn't leave the form
            else if (event.key === Qt.Key_Backspace && !ctrl && text === "" && root.launcher.fieldRow) event.accepted = true
            else if (event.key === Qt.Key_Backspace && !ctrl && text === "" && root.launcher.level !== "root") { root.launcher.back(); event.accepted = true }
            // ⌥← / ⌥→ move by word, like in macOS (Hyprland sends them as Alt+arrows); ⇧ selects
            else if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                const pos = root.launcher.wordPos(text, cursorPosition, event.key === Qt.Key_Left ? -1 : 1)
                if (event.modifiers & Qt.ShiftModifier) moveCursorSelection(pos, TextInput.SelectCharacters)
                else { deselect(); cursorPosition = pos }
                event.accepted = true
            }
            else if (root.launcher.grid && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                root.launcher.step(event.key === Qt.Key_Left ? -1 : 1); event.accepted = true
            } else if (root.launcher.grid && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
                const i = root.launcher.selIndex + (event.key === Qt.Key_Down ? root.launcher.gridCols : -root.launcher.gridCols)
                if (i >= 0 && i < root.launcher.results.length) root.launcher.select(i)
                else if (i < 0) root.launcher.topFocused = root.launcher.topExt !== null
                event.accepted = true
            } else if (root.launcher.extLevel && ctrl && (event.key === Qt.Key_Up || event.key === Qt.Key_Down) && root.launcher.extMove(event.key === Qt.Key_Up ? -1 : 1)) {
                event.accepted = true
            } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && (root.launcher.results[root.launcher.selIndex] || {}).kind === "brightness") {
                root.launcher.levels.disp.stepBright(event.key === Qt.Key_Left ? -1 : 1, root.launcher.results[root.launcher.selIndex].key); event.accepted = true
            } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && (root.launcher.results[root.launcher.selIndex] || {}).kind === "slider") {
                root.launcher.levels.sound.stepSlider(root.launcher.results[root.launcher.selIndex].key, event.key === Qt.Key_Left ? -1 : 1); event.accepted = true
            } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && (root.launcher.results[root.launcher.selIndex] || {}).slider !== undefined) {
                root.launcher.levels.home.stepSlide(root.launcher.results[root.launcher.selIndex], event.key === Qt.Key_Left ? -1 : 1); event.accepted = true
            } else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
                root.launcher.step(1); event.accepted = true
            } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
                root.launcher.step(-1); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                const cur = root.launcher.results[root.launcher.selIndex]
                if (root.launcher.selApp && ctrl) root.launcher.appState.togglePin(cur)
                else if (root.launcher.selApp && (event.modifiers & Qt.AltModifier)) root.launcher.appState.toggleAutostart(cur)
                else if (root.launcher.extLevel && cur && (event.modifiers & Qt.ShiftModifier)) root.launcher.extShift(cur)
                else if (root.launcher.extLevel && cur && ctrl && root.launcher.extCtrl(cur)) {}
                else if (root.launcher.collapsed) root.launcher.step(1)   // the light launcher: Enter on nothing typed shows the rows
                else if (root.launcher.results.length === 0) root.launcher.shakeNow()
                else root.launcher.activate(cur)
                event.accepted = true
            }
        }
    }
}
