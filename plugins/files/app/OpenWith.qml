import QtQuick
import Quickshell
import Quickshell.Io
import qs.kit

// Open with (O): the apps that open the picked file's type, in a small menu at its row (the kit's AppMenu), with a
// search that finds every other app too. ⏎ opens the file, or the marked files, in the app once; ⌘⏎ also makes it the
// type's default, as Settings › Default apps would for its kind. lib/apps.py reads the apps from GIO and opens them.
Item {
    id: root
    required property var app
    readonly property string helper: app.helper.replace(/cli\.py$/, "apps.py")
    property var files: []
    property string kind: ""             // the type's name ("PDF document") for the hint and the toast

    function start() {
        if (app.trashShown || lister.running) return
        const fs = app.selection()
        if (!fs.length) return
        files = fs
        lister.command = ["python3", "-I", helper, "list", fs[0]]
        lister.running = true
    }
    function show(d) {
        // "Folder" reads "every folder"; "PDF document" stays as it is
        const k = d.description || d.type
        kind = /^[A-Z][a-z]/.test(k) ? k[0].toLowerCase() + k.slice(1) : k
        const name = files[0].slice(files[0].lastIndexOf("/") + 1)
        menu.title = files.length > 1 ? "Open " + files.length + " files with…" : "Open " + name + " with…"
        menu.hintKeys = "⌘⏎"
        menu.hint = "Set as default"              // the toast says for which type: a long one cut the line short
        const items = d.apps.map(a => ({ id: a.id, text: a.name, icon: a.icon, detail: a.default ? "default" : "",
                                        section: a.kind === "other" ? "Other apps" : "" }))
        if (!items.length) { app.say("No app to open it with", true); return }
        // At the picked row, so the eyes stay where they were (the middle of the window when it's out of sight)
        const v = app.view                   // the list's or the grid's (FilesWindow)
        const row = v && app.current >= 0 ? v.itemAtIndex(app.current) : null
        menu.open(row, items)
    }
    function run(item, always) {
        Quickshell.execDetached(["python3", "-I", helper, "open", item.id].concat(always ? ["--default"] : []).concat(files))
        if (always) app.say(item.text + " opens every " + kind + " now")
    }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                let d
                try { d = JSON.parse(text) } catch (e) { root.app.say("Couldn't read the apps", true); return }
                root.show(d)
            }
        }
    }

    AppMenu {
        id: menu
        c: root.app.look
        placeholder: "Search apps"
        onPicked: (item, modifiers) => root.run(item, (modifiers & (Qt.ControlModifier | Qt.MetaModifier)) !== 0)
    }
}
