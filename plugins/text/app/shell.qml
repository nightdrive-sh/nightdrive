import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Text, Nightdrive's editor for plain text: what opens a .txt, .csv, .json, a config file or a script that no code
// editor was chosen for (Settings › Apps › Default apps). The files open beside each other, listed in the sidebar once
// there are two; each keeps its own text, undo and place (Doc.qml). Saved on ⌘S only, never by itself (Doc.qml says why),
// and nothing unsaved is lost: closing a file or quitting asks first, and a closed window keeps it for the next time.
ShellRoot {
    FloatingWindow {
        id: win
        title: "Text"
        implicitWidth: 860
        implicitHeight: 640
        color: c.bg
        // ⌘W closes the window before anything can ask (Quickshell can't refuse a close, nor show the window again):
        // what isn't saved is kept (lib/kept.py) and comes back, still unsaved, when Text opens next
        onClosed: {
            const left = win.unsaved()
            if (!left.length) { Qt.quit(); return }
            keeper.run(["python3", lib + "/kept.py", "keep"],
                       JSON.stringify(left.map(d => ({ path: d.path, text: d.area.text, base: Qt.md5(d.base) }))),
                       () => Qt.quit())
        }
        Component.onCompleted: keeper.run(["python3", lib + "/kept.py", "take"], null, (code, out) => {
            let kept = []
            try { kept = JSON.parse(out) } catch (e) {}
            kept.forEach(k => win.open(k.path, k))
        })

        AppLook { id: c }
        KeyHelp { id: keyHelp }
        readonly property QtObject look: c
        readonly property string lib: Quickshell.shellDir + "/../lib"
        readonly property string script: lib + "/textfile.py"

        property var docs: []
        property int current: -1
        readonly property QtObject doc: current >= 0 && current < docs.length ? docs[current] : null
        property var sidebarChoice: null           // ⌘B's; by itself the list shows from two files up
        readonly property bool sidebarShown: sidebarChoice !== null ? sidebarChoice : docs.length > 1
        readonly property string home: Quickshell.env("HOME") || ""

        function show(i) {
            current = i
            if (doc) doc.focusText()
        }
        function step(d) { if (docs.length) show((current + d + docs.length) % docs.length) }
        function unsaved() { return docs.filter(d => d.dirty || d.gone) }
        function failed(text) { toast.show(text, { danger: true }) }

        // Open: each path in turn (one read at a time); one open already is shown instead
        property var queue: []
        // kept: the unsaved text the window had when it was closed (onClosed), put back over the file's
        function open(path, kept) { queue.push({ path: path, kept: kept || null }); next() }
        function next() {
            if (opener.busy || !queue.length) return
            const job = queue.shift()
            const i = docs.findIndex(d => d.path === job.path)
            if (i >= 0) { show(i); next(); return }
            opener.run(["python3", script, "read", job.path], null, (code, out, err) => {
                if (code === 0) add(JSON.parse(out), job.kept)
                else failed(job.kept ? err + ": what you wrote in it was lost" : err)
                next()
            })
        }
        function add(info, kept) {
            const d = docComp.createObject(stack, { c: c, script: script })
            d.load(info)
            if (kept) {
                d.restore(kept.text, kept.base)
                toast.show("Not saved when the window closed: " + info.name + " is as you left it")
            }
            d.message.connect((t, danger) => toast.show(t, { danger: danger }))
            docs = docs.concat([d])
            show(docs.length - 1)
        }

        // ⌘O and ⌘N ask the desktop's Open and Save window (lib/pick.py: Files' picker when it is on), from the open
        // file's folder
        function pickOpen() {
            picker.run(["python3", lib + "/pick.py", "open", doc ? doc.dir : home], null, (code, out) => {
                if (code === 0) out.split("\n").filter(p => p).forEach(p => win.open(p))
            })
        }
        function pickNew() {
            picker.run(["python3", lib + "/pick.py", "save", "Untitled.txt", doc ? doc.dir : home], null, (code, out) => {
                const path = out.split("\n")[0]
                if (code !== 0 || !path) return
                // The picker asked before choosing a file that is there: it opens as it is
                opener.run(["python3", script, "new", path], null, (c2, o2, e2) => {
                    if (c2 === 0) add(JSON.parse(o2)); else if (c2 === 3) win.open(path); else failed(e2)
                })
            })
        }

        // Close a file: asked first when it isn't saved (Save, Don't save, Cancel)
        function close(d) {
            if (!d) return
            if (d.dirty || d.gone) ask("Save the changes to " + d.name + "?", "", ok => {
                if (ok) d.save(saved => { if (saved) win.drop(d) })
                else win.drop(d)
            })
            else drop(d)
        }
        function drop(d) {
            const i = docs.indexOf(d)
            docs = docs.filter(x => x !== d)
            d.destroy()
            if (current >= docs.length || i < current) current = Math.max(-1, current - 1)
            show(Math.max(docs.length ? 0 : -1, current))
        }

        // Quit (⌘Q through quit-commands, or the window closed): asked first when anything isn't saved; Save writes
        // each file and quits once all are written (one that can't be stays open, saying why)
        function quit() {
            const left = unsaved()
            if (!left.length) { Qt.quit(); return }
            ask(left.length === 1 ? "Save the changes to " + left[0].name + "?" : "Save the changes to " + left.length + " files?",
                left.length === 1 ? "" : left.map(d => d.name).join(", "), ok => {
                if (!ok) { Qt.quit(); return }
                let waiting = left.length, all = true
                left.forEach(d => d.save(saved => { all = all && saved; if (--waiting === 0 && all) Qt.quit() }))
            })
        }

        // The question: then(true) Save, then(false) Don't save; Cancel does nothing
        property var answer: null
        function ask(question, detail, then) {
            confirm.question = question; confirm.detail = detail; answer = then
            confirm.visible = true
        }
        function answered(how) {
            const then = answer
            answer = null
            confirm.visible = false
            if (doc) doc.focusText()
            if (then && how !== null) then(how)
        }

        function find(back) { if (finder.open) finder.next(back); else finder.show() }

        Run { id: opener; onBusyChanged: win.next() }
        Run { id: picker }
        Run { id: keeper }
        Component { id: docComp; Doc {} }

        IpcHandler {
            target: "text"
            function open(path: string): void { win.open(path) }
            function quit(): void { win.quit() }
        }

        Shortcut { sequences: ["Ctrl+S", "Meta+S"]; enabled: !!win.doc && !confirm.visible; onActivated: win.doc.conflicted ? win.doc.keepMine() : win.doc.save() }
        Shortcut { sequences: ["Ctrl+O", "Meta+O"]; enabled: !confirm.visible; onActivated: win.pickOpen() }
        Shortcut { sequences: ["Ctrl+N", "Meta+N"]; enabled: !confirm.visible; onActivated: win.pickNew() }
        Shortcut { sequences: ["Ctrl+Shift+W", "Meta+Shift+W"]; enabled: !confirm.visible; onActivated: win.close(win.doc) }
        Shortcut { sequences: ["Ctrl+F", "Meta+F"]; enabled: !!win.doc && !confirm.visible; onActivated: finder.show() }
        Shortcut { sequences: ["Ctrl+G", "Meta+G"]; enabled: !!win.doc && !confirm.visible; onActivated: win.find(false) }
        Shortcut { sequences: ["Ctrl+Shift+G", "Meta+Shift+G"]; enabled: !!win.doc && !confirm.visible; onActivated: win.find(true) }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.sidebarChoice = !win.sidebarShown }
        Shortcut { sequences: ["Ctrl+Tab"]; onActivated: win.step(1) }
        Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab"]; onActivated: win.step(-1) }
        Shortcut { sequences: ["Ctrl+Q", "Meta+Q"]; onActivated: win.quit() }
        Shortcut { sequences: ["Ctrl+?", "Ctrl+Shift+/"]; onActivated: sheet.shown = !sheet.shown }

        RowLayout {
            id: content
            anchors.fill: parent
            spacing: 0
            AppPointer { c: win.look }

            AppSidebar {
                id: side
                visible: win.sidebarShown
                Layout.preferredWidth: 220
                c: win.look
                title: "Text"
                spacing: 2
                Repeater {
                    model: win.docs
                    AppNavRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        c: win.look
                        glyph: "file-text"
                        label: modelData.name
                        count: modelData.dirty || modelData.gone ? "•" : ""
                        countColor: win.look.primary
                        selected: index === win.current
                        onClicked: win.show(index)
                    }
                }
                Item { Layout.fillHeight: true }    // the rows at the top
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                DocBar {
                    Layout.fillWidth: true
                    c: win.look
                    doc: win.doc
                    onOpen: win.pickOpen()
                    onNewFile: win.pickNew()
                    onSave: win.doc.save()
                    onKeepMine: win.doc.keepMine()
                    onKeepTheirs: win.doc.keepTheirs()
                    onClose: win.close(win.doc)
                }
                FindBar {
                    id: finder
                    Layout.fillWidth: true
                    c: win.look
                    doc: win.doc
                    onClosed: if (win.doc) win.doc.focusText()
                }
                Item {
                    id: stack
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Only the file shown is visible; the others keep their state behind it
                    onChildrenChanged: win.currentChanged()
                    Connections {
                        target: win
                        function onCurrentChanged() {
                            for (const d of win.docs) { d.anchors.fill = stack; d.visible = d === win.doc }
                        }
                        function onDocsChanged() { win.currentChanged() }
                    }
                    Column {
                        anchors.centerIn: parent
                        visible: !win.doc
                        spacing: 14
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Open a file from Files, or here"
                            color: win.look.dim; font.family: win.look.font; font.pixelSize: 14
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8
                            AppButton { c: win.look; glyph: "folder-open"; label: "Open"; onClicked: win.pickOpen() }
                            AppButton { c: win.look; glyph: "file-plus"; label: "New"; onClicked: win.pickNew() }
                        }
                    }
                }
            }
        }

        AppConfirm {
            id: confirm
            behind: content
            c: win.look
            visible: false
            action: "Save"
            glyph: "save"
            other: "Don't save"
            onAnswered: ok => win.answered(ok ? true : null)
            onOtherChosen: win.answered(false)
        }
        KeySheet { id: sheet; c: win.look; groups: keyHelp.groups }
        AppToast { id: toast; c: win.look }
    }
}
