import QtQuick
import Quickshell
import Quickshell.Io

// Files as an Open or Save window for other apps (lib/portal.py, the portal's FileChooser): one FilesWindow in its pick
// mode (PickBar under the list), in a Quickshell process of its own that lib/pickrun.py starts for each request and
// that ends with the answer. $FILES_PICK is its folder: request.json in (lib/portal.py request_of), ready out once the
// window is made (without it in a few seconds pickrun.py stops this and GTK's window answers), answer.json out,
// {"paths": […], "filter": i} or {"cancel": true}; no answer means it failed.
//
// It stands in for shell.qml as the window's manager: the same settings, no other windows (⌘N does nothing here), and
// a cut that stays in this process.
ShellRoot {
    id: shell
    readonly property string dir: Quickshell.env("FILES_PICK") || ""
    property var cut: []
    property var last: null
    property bool answered: false

    // The settings are Files' own (shell.qml): the rows' size and the thumbnails' come along
    readonly property var defaults: ({ layout: "normal" })
    property var settings: defaults
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/nightdrive/files"
    FileView {
        path: shell.configDir + "/settings.json"
        blockLoading: true
        printErrors: false
        onLoaded: { try { shell.settings = Object.assign({}, shell.defaults, JSON.parse(text())) } catch (e) {} }
    }
    function setting(key, value) { const s = Object.assign({}, settings); s[key] = value; settings = s }

    FileView { id: requestFile; path: shell.dir ? shell.dir + "/request.json" : ""; blockLoading: true; printErrors: false }
    readonly property var request: { try { return JSON.parse(requestFile.text()) } catch (e) { return null } }
    FileView { id: readyFile; path: shell.dir ? shell.dir + "/ready" : ""; blockWrites: true; printErrors: false }
    FileView { id: answerFile; path: shell.dir ? shell.dir + "/answer.json" : ""; blockWrites: true; atomicWrites: true; printErrors: false }

    // The answer, once: the window's close after it says nothing more
    function answer(a) {
        if (answered) return
        answered = true
        answerFile.setText(JSON.stringify(a))
        Qt.quit()
    }
    function open(path, select) {}
    function closed(w) { answer({ cancel: true }) }
    function placesChanged() { if (win.item) win.item.places.refresh() }

    Component.onCompleted: if (!request) { console.warn("picker: no request in $FILES_PICK"); Qt.quit() }

    LazyLoader {
        id: win
        active: shell.request !== null
        FilesWindow {
            manager: shell
            key: 1
            pick: shell.request
            startPath: shell.request.folder || ""
            Component.onCompleted: readyFile.setText("1")
        }
    }

    // For tests, as the keys would do it (qs ipc --pid PID call picker …): every picker has the same path
    IpcHandler {
        target: "picker"
        function setName(name: string): void { const w = win.item; if (w) { w.pickBar.field.text = name } }
        function go(path: string): void { if (win.item) win.item.go(path, "") }
        function accept(): void { if (win.item) win.item.pickBar.accept() }
        function setFilter(i: int): void { if (win.item) win.item.pickBar.setFilter(i) }
        function chooseFilter(): void { if (win.item) win.item.pickBar.chooseFilter() }
        function cancel(): void { shell.answer({ cancel: true }) }
    }
}
