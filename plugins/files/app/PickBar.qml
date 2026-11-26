import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.kit
import "Format.js" as Format

// The bar under Files' window when it is another app's Open or Save window (picker.qml, win.pick): Save's name field,
// and Cancel and the app's button (Open, Save, or its own word). The rest is Files as it is: the sidebar, the keys, the
// preview. A narrow window puts the buttons on a line of their own under the name.
//
// Save: the name is picked without its ending, as Rename does; ⏎ in it saves into the folder on show, and a name
// that is there already asks first. A name with a / in it is a path (from the folder, or ~ and / as they are), and one
// that is a folder goes into it. Open: ⏎ on a file (or the button) takes the marked files, else the picked one; for a
// folder (directory) the picked folder, else the one on show.
//
// The app's file types (its filters: lib/pickfilters.py gives each a regex) are a button at the buttons' left, a menu on
// a click (or ⌘T): the list shows the folders and the files of the type picked. In Save a new type takes the name's
// ending along when the type has one (*.png), as the Mac's Save does.
Rectangle {
    id: bar
    required property QtObject c
    required property var app             // the FilesWindow
    required property Item behind         // what the question to replace a file dims and holds back
    readonly property var req: app.pick
    readonly property bool saving: req !== null && req.mode !== "open"
    readonly property bool naming: req !== null && req.mode === "save"
    readonly property bool small: width < 560
    readonly property alias field: input
    readonly property var filters: req && req.filters ? req.filters : []
    property int filterIndex: 0
    readonly property var filter: filters[filterIndex] || null
    readonly property var filterRe: filter && filter.regex ? new RegExp(filter.regex, "i") : null
    // The rows the window shows (FilesWindow.rows): a folder always, a file when it is of the type picked
    function narrow(rows) { return filterRe ? rows.filter(r => r.dir || filterRe.test(r.name)) : rows }
    function setFilter(i) {
        if (i < 0 || i >= filters.length || i === filterIndex) return
        filterIndex = i
        const ending = filters[i].ending, name = input.text       // lib/pickfilters.py ending()
        if (naming && ending && name && !(filterRe && filterRe.test(name))) {
            const dot = name.lastIndexOf(".")
            input.text = (dot > 0 ? name.slice(0, dot) : name) + "." + ending
        }
    }
    function chooseFilter() {
        if (filters.length < 2) return
        types.open(typeButton, filters.map((f, i) => ({ text: f.name, detail: i === filterIndex ? "✓" : "", index: i })))
    }
    AppMenu {
        id: types
        c: bar.c
        title: "Show files of the type"
        menuWidth: 300
        onPicked: item => bar.setFilter(item.index)
        onClosed: if (bar.naming) bar.focusName(); else bar.app.toList()
    }
    Shortcut { sequences: ["Ctrl+T", "Meta+T"]; enabled: bar.filters.length > 1 && !types.shown; onActivated: bar.chooseFilter() }
    visible: req !== null
    implicitHeight: visible ? grid.implicitHeight + 2 * 12 : 0
    color: c.bg

    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: bar.c.divider }

    GridLayout {
        id: grid
        anchors.fill: parent
        anchors.margins: 12
        anchors.leftMargin: 16; anchors.rightMargin: 16
        columns: bar.small ? 1 : 2
        columnSpacing: 16; rowSpacing: 10

        RowLayout {
            visible: bar.naming
            Layout.fillWidth: true
            Layout.maximumWidth: 640          // a name, not a line across a wide window
            spacing: 10
            Text { text: "Name"; color: bar.c.title; font.family: bar.c.font; font.pixelSize: 13 }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30; radius: 7
                color: "transparent"
                border.color: input.activeFocus ? bar.c.primary : bar.c.line
                TextInput {
                    id: input
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: bar.c.text; font.family: bar.c.font; font.pixelSize: 13
                    selectionColor: bar.c.sel; selectByMouse: true
                    Keys.onPressed: e => {
                        const k = e.key
                        if (k === Qt.Key_Return || k === Qt.Key_Enter) { bar.accept(); e.accepted = true }
                        else if (k === Qt.Key_Escape) { bar.cancel(); e.accepted = true }
                        else if (k === Qt.Key_Tab || k === Qt.Key_Down) { bar.app.toList(); e.accepted = true }
                    }
                }
            }
        }
        Item { visible: !bar.naming; Layout.fillWidth: true }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 10
            AppButton {
                id: typeButton
                visible: bar.filters.length > 1
                c: bar.c; glyph: "filter"; tipAlign: "left"
                // A long name ("Images (*.png, *.jpg, …)") is cut, so the buttons stay on one line
                readonly property string full: bar.filter ? bar.filter.name : ""
                label: full.length > (bar.small ? 16 : 28) ? full.slice(0, bar.small ? 15 : 27) + "…" : full
                tip: "File type: " + full; keys: "⌘T"
                onClicked: bar.chooseFilter()
            }
            AppButton { c: bar.c; label: "Cancel"; tip: "Cancel"; keys: "Esc"; onClicked: bar.cancel() }
            AppButton {
                c: bar.c; strong: true
                label: bar.req && bar.req.accept ? bar.req.accept.replace("_", "") : bar.saving ? "Save" : "Open"
                tip: label; keys: "⏎"
                onClicked: bar.accept()
            }
        }
    }

    // The name to start with, picked up to its ending, and the keys in the field
    Component.onCompleted: {
        const i = filters.findIndex(f => f.name === req.filter)
        if (i > 0) filterIndex = i
        if (naming) { input.text = req.name || ""; Qt.callLater(() => { focusName() }) }
    }
    // The answer with the type that was on, which the app may use for the file's format
    function answer(paths) { app.manager.answer(filters.length ? { paths: paths, filter: filterIndex } : { paths: paths }) }
    function focusName() {
        if (!naming) return false
        input.forceActiveFocus()
        const dot = input.text.lastIndexOf(".")       // a hidden file's leading dot isn't an ending
        input.select(0, dot > 0 ? dot : input.text.length)
        return true
    }

    function cancel() { app.manager.answer({ cancel: true }) }
    // Where the files go: the folder on show, which the trash, an archive or a search's results aren't
    function folderOk() {
        if (app.trashShown || app.inArchive) { app.say("Pick a folder to save in", true); return false }
        return true
    }
    function accept() {
        if (!req) return
        if (req.mode === "open") return open(app.selection())
        if (!folderOk()) return
        if (req.mode === "saveFiles") return answer([app.path])
        const name = input.text.trim()
        if (!name) { focusName(); return }
        const p = name.startsWith("/") ? name : name.startsWith("~/") ? app.home + name.slice(1) : Format.join(app.path, name)
        checker.target = p
        checker.running = true
    }
    // What is at the name already: a folder goes in, a file asks first, nothing saves
    Process {
        id: checker
        property string target
        command: ["sh", "-c", '[ -d "$1" ] && echo dir || { [ -e "$1" ] && echo file; }; true', "-", target]
        stdout: StdioCollector {
            onStreamFinished: {
                const what = text.trim(), p = checker.target
                if (what === "dir") { bar.app.go(p, ""); bar.input.text = ""; bar.focusName() }
                else if (what === "file") bar.askReplace(p)
                else bar.answer([p])
            }
        }
    }
    function askReplace(p) {
        replace.target = p
        replace.question = "Replace " + Format.base(p) + "?"
        replace.detail = "A file of that name is in " + app.tilde(Format.parent(p)) + ". Saving writes over it."
        replace.visible = true
    }
    AppConfirm {
        id: replace
        property string target
        parent: bar.app.contentItem
        c: bar.c; behind: bar.behind
        visible: false; action: "Replace"; glyph: "replace"
        onAnswered: ok => { visible = false; if (ok) bar.answer([target]); else bar.focusName() }
    }

    // Open: the files marked, else the one picked; a folder is gone into unless folders are what is asked for
    function open(paths) {
        const rows = app.rows.filter(r => paths.indexOf(r.path) >= 0)
        if (req.directory) {
            const dirs = rows.filter(r => r.dir).map(r => r.path)
            return answer(dirs.length ? (req.multiple ? dirs : dirs.slice(0, 1)) : [app.path])
        }
        if (rows.length === 1 && rows[0].dir) return app.go(rows[0].path, "")
        const files = rows.filter(r => !r.dir && r.member === undefined).map(r => r.path)
        if (!files.length) return
        answer(req.multiple ? files : files.slice(0, 1))
    }
    // ⏎ or a double click on a file (FilesWindow.openRow): Save takes its name, Open takes it
    function take(f) {
        if (f.member !== undefined) { app.say("Files in an archive can't be picked: take them out first (y, p)", true); return }
        if (naming) { input.text = f.name; focusName() }
        else if (req.mode === "open") open(app.selection().indexOf(f.path) >= 0 ? app.selection() : [f.path])
    }
}
