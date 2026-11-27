import QtQuick
import Quickshell
import Quickshell.Io
import "Format.js" as Format

// Nightdrive Files: its windows (FilesWindow), one at the start and another on ⌘N, all in one Quickshell. They share the
// last cut (Clip), so files cut in one window and pasted in another move. Hyper F, the Launcher, `files DIR` and
// FileManager1 each open a new window (IPC newWindow), which Hyprland puts on the workspace the user is on, rather than
// bringing up one on another workspace (#3427). Closing the last one ends Files. The settings (⌘,) are
// here too, for every window: ~/.config/nightdrive/files/settings.json.
ShellRoot {
    id: shell
    property var cut: []                  // the paths of the last cut, while the clipboard still holds them (Clip)
    property var windows: []              // [{ id, path, select, launch }]: what Variants makes a window for
    property int made: 0
    property var last: null               // the window last active

    readonly property var defaults: ({ layout: "normal" })
    property var settings: defaults
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/nightdrive/files"
    FileView {
        id: settingsFile
        path: shell.configDir + "/settings.json"
        watchChanges: true
        printErrors: false                // none yet: the defaults
        onFileChanged: reload()
        onLoaded: { try { shell.settings = Object.assign({}, shell.defaults, JSON.parse(text())) } catch (e) {} }
    }
    function setting(key, value) {
        const s = Object.assign({}, settings); s[key] = value; settings = s
        settingsFile.setText(JSON.stringify(s, null, 2) + "\n")
    }

    function open(path, select, launch) {
        made++
        windows = windows.concat([{ id: made, path: path || "", select: select || "", launch: !!launch }])
    }
    function closed(w) {
        if (last === w) last = null
        windows = windows.filter(x => x.id !== w.key)
        if (!windows.length) Qt.quit()
    }
    // Where IPC goes: the window last active, else the newest; with none open (closed while Quickshell stayed), a new one
    function go(path, select) {
        const all = instances.instances
        const w = last || (all.length ? all[all.length - 1] : null)
        if (w) w.go(path, select); else open(path, select)
    }
    // The same for a file to open as ⏎ would: no-app's, for a document no app opens (#3715)
    function goOpening(path) {
        const all = instances.instances
        const w = last || (all.length ? all[all.length - 1] : null)
        if (w) { w.go(Format.parent(path), path); w.openFile(path) } else open(Format.parent(path), path, true)
    }
    // A change to the sidebar's folders (a bookmark, one moved) reaches every window's
    function placesChanged() { for (const w of instances.instances) w.places.refresh() }
    // The settings' folder made before the first write could need it (FileView doesn't make it)
    Component.onCompleted: { Quickshell.execDetached(["mkdir", "-p", configDir]); open("", "") }

    Variants {
        id: instances
        model: shell.windows
        FilesWindow {
            required property var modelData
            manager: shell
            key: modelData.id
            startPath: modelData.path
            startSelect: modelData.select
            startOpen: modelData.launch || false
        }
    }

    IpcHandler {
        target: "files"
        // A new window, home or the folder given (`files`, `files DIR` while Files runs)
        function newWindow(path: string): void { shell.open(path, "") }
        // A new window on the folder a file is in, the file picked (`files show FILE`, FileManager1's ShowItems)
        function newWindowShowing(path: string): void { shell.open(Format.parent(path), path) }
        // Into the window last active: for the first window, just started, which a new one would sit beside
        function openFolder(path: string): void { shell.go(path || Quickshell.env("HOME"), "") }
        // The folder a file is in, with the file picked (FileManager1's ShowItems, `files show`). Not "show" or
        // "open": qs ipc takes those for its own subcommands
        function showFile(path: string): void { shell.go(Format.parent(path), path) }
        // A new window with the file picked and opened as ⏎ would (`files open-file`: no-app, for a document no app
        // opens, so the window says so with Open with… and the app to install); openFileHere into the first window
        function newWindowOpening(path: string): void { shell.open(Format.parent(path), path, true) }
        function openFileHere(path: string): void { shell.goOpening(path) }
        function refresh(): void { for (const w of instances.instances) w.reload() }
        function openSettings(): void {       // the kit's `files settings`
            const all = instances.instances
            const w = shell.last || all[all.length - 1]
            if (w) w.showSettings = true
        }
        // The window last active as a list, grid or columns, as t turns it (for tests and screenshots)
        function setView(view: string): void {
            const all = instances.instances
            const w = shell.last || all[all.length - 1]
            if (w) w.showView(view)
        }
    }
}
