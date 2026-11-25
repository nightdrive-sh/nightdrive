import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit
import "Fmt.js" as Fmt

// Disk Usage: what takes up the space in a place (Home, the system disk, a folder you choose), folder by folder, biggest
// first. lib/scan.py walks it and keeps the result, so the window opens on the last scan at once; Clean up empties what
// is safe to (CleanPanel, lib/clean.py). This file holds the tree on show, where in it you are, and the keys.
ShellRoot {
    FloatingWindow {
        id: win
        title: "Disk Usage"
        implicitWidth: 1060
        implicitHeight: 720
        color: c.bg
        onClosed: Qt.quit()

        AppLook { id: c }
        readonly property QtObject look: c
        readonly property alias scanner: scanner

        // The split bar's five colours, in this order (checked for colour blindness against the window's dark ground),
        // and the rest's. They name the entries, not their sizes, so they stay out of the theme's state colours.
        readonly property var colours: ["#338ced", "#e76624", "#00a888", "#d28e05", "#e24d8b"]
        readonly property color rest: Qt.rgba(c.dim.r, c.dim.g, c.dim.b, 0.4)
        readonly property real closerShare: 0.25     // a folder whose smaller items are this much of it gets a closer look
        readonly property real closerMin: 1e6        // …if it is at least this big (bytes)

        property var place: null            // the place on show: { name, path, glyph, disk, total?, scanned? }
        property string placePath: ""
        readonly property string placeName: place ? place.name : placePath.split("/").pop() || "/"
        property var scan: null             // its scan (scan.py): { path, scanned, took, total, files, unreadable, disk, tree }
        readonly property var tree: scan ? scan.tree : null
        property var trail: []              // the folders from the place down to the one on show
        readonly property var here: trail.length ? trail[trail.length - 1] : null
        // The tree's folders change in place (a closer look's detail, an entry gone to the Trash): changed() tells the
        // bindings, which would otherwise see the same folder and not look again
        property int revision: 0
        function changed() { revision++ }
        readonly property var rows: { revision; return here && here.c ? here.c.slice() : [] }
        readonly property real hereSize: { revision; return here ? here.s : 0 }
        property int current: 0
        property int hot: -1                // the row whose split bar segment is under the pointer
        property var graftNode: null        // the folder a closer look is for
        readonly property bool scanning: scanner.busy && (scanner.graft || scanner.path === placePath)

        // The five biggest entries take the palette's colours (the folded smaller items never do), the rest the quiet one
        readonly property var tints: {
            let n = 0
            return rows.map(r => r.k === "o" || n >= colours.length ? rest : colours[n++])
        }
        readonly property var parts: {
            const p = []
            let shown = 0
            rows.forEach((r, i) => { if (tints[i] !== rest) { p.push({ s: r.s, color: tints[i], index: i }); shown += r.s } })
            if (hereSize - shown > 0) p.push({ s: hereSize - shown, color: rest, index: -1 })
            return p
        }
        property int tick: 0                // the minutes, for "scanned 5 min ago"
        Timer { interval: 60000; running: true; repeat: true; onTriggered: win.tick++ }
        readonly property string summary: {
            revision
            if (!here || !scan) return ""
            const files = Fmt.plural(here.i, "file", "files")
            if (trail.length > 1) return files + "  ·  " + Fmt.percent(here.s, tree.s) + " of " + placeName
            const d = scan.disk
            return files + "  ·  " + Fmt.percent(here.s, d.size) + " of the " + Fmt.bytes(d.size) + " disk, " + Fmt.bytes(d.free) + " free"
        }
        readonly property string scanNote: {
            tick
            if (!scan || scanning) return ""
            return "Scanned " + Fmt.ago(scan.scanned) + (scan.took >= 1 ? " in " + Math.round(scan.took) + " s" : "")
                + (scan.unreadable ? "  ·  " + Fmt.plural(scan.unreadable, "folder", "folders") + " couldn't be read (not yours)" : "")
        }

        // A quiet line under the list for what just happened
        property string note: ""
        function say(t) { note = t; noteTimer.restart() }
        Timer { id: noteTimer; interval: 5000; onTriggered: win.note = "" }

        // The path of the folder at depth d of the trail, or of an entry of the folder on show
        function pathAt(d) {
            let p = scan.path
            for (let i = 1; i <= d; i++) p = (p === "/" ? "" : p) + "/" + trail[i].n
            return p
        }
        function pathOf(i) {
            const base = pathAt(trail.length - 1), r = rows[i]
            return i < 0 || !r || r.k === "o" ? base : (base === "/" ? "" : base) + "/" + r.n
        }

        function openPlace(p) {
            if (!p || p.path === placePath && scan) return
            scanner.cancel()
            place = p; placePath = p.path
            scan = null; trail = []; current = 0
            scanner.load(p.path)
        }
        function pickPlace(i) { if (i >= 0 && i < scanner.places.length) openPlace(scanner.places[i]) }
        function stepPlace(d) { pickPlace(scanner.places.findIndex(p => p.path === placePath) + d) }
        // A path from outside (`disk-usage PATH`, Choose a folder): its place if it is one, else a folder of your own
        function openPath(path) {
            const p = scanner.places.find(x => x.path === path)
            if (p) { openPlace(p); return }
            scanner.remember(path)
            openPlace({ name: path.split("/").pop() || "/", path: path, glyph: "folder", chosen: true })
        }
        // How far it is: by the last scan's size, or a whole disk's used space; a folder's first scan can't tell
        function scanPlace() {
            const disk = placePath === "/" && place && place.disk ? place.disk.used : 0
            scanner.scan(placePath, false, scan ? scan.total : disk)
        }
        function rescan() { if (placePath && !scanner.graft) scanPlace() }
        function stopScan() { scanner.cancel(); if (!scan) say("Stopped: ⌘R scans again") }

        function parse(json) {
            try { return json ? JSON.parse(json) : null } catch (e) { console.warn("scan.py: " + e); return null }
        }
        // A new scan of the place keeps you in the same folder, as far as it is still there
        function show(d) {
            const names = trail.slice(1).map(n => n.n), keep = here ? (rows[current] || {}).n : undefined
            scan = d
            const t = [d.tree]
            for (const n of names) {
                const next = (t[t.length - 1].c || []).find(k => k.k === "d" && k.n === n)
                if (!next) break
                t.push(next)
            }
            trail = t
            current = Math.max(0, rows.findIndex(r => r.n === keep))
        }

        Scanner {
            id: scanner
            onLoaded: (path, json) => {
                if (path !== win.placePath) return
                const d = win.parse(json)
                if (d) win.show(d)
                else win.scanPlace()
            }
            onFinished: (path, json, graft) => {
                const d = win.parse(json)
                if (!d) return
                if (graft && win.graftNode) {
                    win.graftNode.c = d.tree.c
                    win.graftNode = null
                    win.changed()
                } else if (!graft && path === win.placePath) win.show(d)
            }
            onPlacesChanged: {
                const p = places.find(x => x.path === win.placePath)
                if (p) win.place = p
            }
        }

        // Into a folder, or a file's place in Files. A folder whose detail the place's scan folded away is scanned again
        // on its own (a closer look), and what it finds is grafted into the tree.
        function enter(i) {
            const r = rows[i]
            if (!r || r.k === "o") return
            if (r.k !== "d") { showInFiles(i); return }
            trail = trail.concat([r])
            current = 0; hot = -1
            const fold = (r.c || []).find(k => k.k === "o")
            if (fold && fold.i > 1 && fold.s >= r.s * closerShare && r.s >= closerMin && !r.looked && !scanner.busy) {
                r.looked = true
                graftNode = r
                scanner.scan(pathAt(trail.length - 1), true, r.s)
            }
        }
        function goTo(d) {
            if (d < 0 || d >= trail.length - 1) return
            if (scanner.graft) scanner.cancel()
            const child = trail[d + 1]
            trail = trail.slice(0, d + 1)
            current = Math.max(0, rows.indexOf(child)); hot = -1
            folder.listView.positionViewAtIndex(current, ListView.Contain)
        }
        function up() { goTo(trail.length - 2) }
        function move(d) {
            if (!rows.length) return
            current = Math.max(0, Math.min(rows.length - 1, current + d))
            folder.listView.positionViewAtIndex(current, ListView.Contain)
        }

        // Files: the entry selected in its folder (the file manager's ShowItems), or the folder opened
        function showInFiles(i) {
            const p = pathOf(i), dir = i < 0 || !rows[i] || rows[i].k === "o"
            if (dir) { Quickshell.execDetached(["xdg-open", p]); return }
            Quickshell.execDetached(["sh", "-c", 'gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 '
                + '--method org.freedesktop.FileManager1.ShowItems "[\'$1\']" "" >/dev/null 2>&1 || xdg-open "$2"',
                "_", Fmt.fileUrl(p), pathAt(trail.length - 1)])
        }
        function copyPath(i) { Quickshell.execDetached(["wl-copy", pathOf(i)]); say("Copied: " + pathOf(i)) }

        // Delete: an entry to the Trash, after asking. The tree loses it at once (its folders get smaller), and Clean up
        // has it in the Trash's size.
        function trashItem(i) {
            const r = rows[i]
            if (!r || r.k === "o" || scanning) return
            const node = here, path = pathOf(i)
            confirm.ask("Move " + r.n + " to the Trash?",
                        "It takes " + Fmt.bytes(r.s) + ". The space comes free once the Trash is emptied (Clean up), and until then it can come back from the Trash in Files.",
                        "Move to Trash", () => {
                            trashProc.node = node; trashProc.item = r
                            trashProc.command = ["gio", "trash", "--", path]
                            trashProc.running = true
                        })
        }
        Process {
            id: trashProc
            property var node: null
            property var item: null
            stderr: StdioCollector { id: trashErr }
            onExited: code => {
                if (code !== 0) { win.say(trashErr.text.trim() || "It couldn't be moved to the Trash"); return }
                const r = item, at = node.c.indexOf(r)
                if (at >= 0) node.c.splice(at, 1)
                // The folders it was in are that much smaller, up to the place
                for (const n of win.trail.slice(0, win.trail.indexOf(node) + 1)) { n.s -= r.s; n.i -= r.k === "d" ? r.i : 1 }
                win.changed()
                win.current = Math.max(0, Math.min(win.current, win.rows.length - 1))
                win.say("Moved to the Trash: " + r.n)
                cleanPanel.refresh()
            }
        }

        // Choose a folder (⌘O): the file manager's dialog, as Mail's attachments (zenity)
        Process {
            id: chooser
            command: ["zenity", "--file-selection", "--directory", "--title=Choose a folder", "--filename=" + Quickshell.env("HOME") + "/"]
            stdout: StdioCollector { onStreamFinished: { const p = text.trim(); if (p) win.openPath(p) } }
        }
        function chooseFolder() { chooser.running = true }
        function cleanUp() { cleanPanel.open() }

        IpcHandler {
            target: "diskusage"
            // `disk-usage PATH`
            function open(path: string): void { win.openPath(path) }
            function rescan(): void { win.rescan() }
            function cleanUp(): void { win.cleanUp() }
        }

        Shortcut { sequences: ["Ctrl+R", "Meta+R"]; onActivated: win.rescan() }
        Shortcut { sequences: ["Ctrl+O", "Meta+O"]; onActivated: win.chooseFolder() }
        Shortcut { sequences: ["Ctrl+Shift+Backspace", "Meta+Shift+Backspace"]; onActivated: win.cleanUp() }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.sidebarChoice = !win.sidebarShown }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }

        // The list's keys (KeySheet below lists them)
        function pressed(e) {
            const k = e.key, ctrl = e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
            c.moved(e)                         // the arrows show the keys' frame (AppPointer)
            if (sheet.shown && k !== Qt.Key_Question) { sheet.pressed(e); e.accepted = true; return }
            if (ctrl && k === Qt.Key_Down) stepPlace(1)
            else if (ctrl && k === Qt.Key_Up) stepPlace(-1)
            else if (ctrl && k === Qt.Key_C) copyPath(current)
            else if (ctrl) return
            else if (k === Qt.Key_Down || k === Qt.Key_J) move(1)
            else if (k === Qt.Key_Up || k === Qt.Key_K) move(-1)
            else if (k === Qt.Key_PageDown) move(10)
            else if (k === Qt.Key_PageUp) move(-10)
            else if (k === Qt.Key_Home) move(-rows.length)
            else if (k === Qt.Key_End) move(rows.length)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right || k === Qt.Key_L) enter(current)
            else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Backspace) up()
            else if (k === Qt.Key_Escape) { if (scanning) stopScan(); else up() }
            else if (k === Qt.Key_O) showInFiles(current)
            else if (k === Qt.Key_C) copyPath(current)
            else if (k === Qt.Key_Delete) trashItem(current)
            else if (k >= Qt.Key_1 && k <= Qt.Key_9) pickPlace(k - Qt.Key_1)
            else { sheet.pressed(e); return }
            e.accepted = true
        }

        // A narrow window hides the sidebar (⌘B shows it all the same)
        readonly property int sidebarMin: 760
        property var sidebarChoice: null
        readonly property bool sidebarShown: sidebarChoice !== null ? sidebarChoice : width >= sidebarMin

        Component.onCompleted: {
            openPlace({ name: "Home", path: Quickshell.env("HOME"), glyph: "house" })
            cleanPanel.refresh()
            folder.list.forceActiveFocus()
        }

        RowLayout {
            id: content          // what a panel turns off while it shows (AppPanel.behind)
            anchors.fill: parent
            spacing: 0
            AppPointer { c: win.look }

            PlaceList {
                Layout.preferredWidth: win.width < 900 ? 190 : 220
                visible: win.sidebarShown
                c: win.look
                headerHeight: 58
                contentTop: 70
                bottomMargin: 18
                places: scanner.places
                current: win.placePath
                cleanable: cleanPanel.total
                onPicked: index => { win.pickPlace(index); folder.list.forceActiveFocus() }
                onChoose: win.chooseFolder()
                onCleanUp: win.cleanUp()
            }
            FolderView {
                id: folder
                Layout.fillWidth: true
                Layout.fillHeight: true
                c: win.look
                app: win
            }
        }

        CleanPanel {
            id: cleanPanel
            behind: content
            c: win.look
            onCleaned: freed => win.say("Freed " + Fmt.bytes(freed) + ". ⌘R scans " + win.placeName + " again.")
            onClosed: folder.list.forceActiveFocus()
        }
        ConfirmPanel {
            id: confirm
            behind: content
            c: win.look
            onClosed: folder.list.forceActiveFocus()
        }

        KeySheet {
            id: sheet
            c: win.look
            groups: [
                { title: "Folders", keys: [["↑ ↓  j k", "Previous, next"], ["⏎  →  l", "Open the folder (a file: show it in Files)"], ["←  h  ⌫  Esc", "Up a folder"],
                                          ["PgUp PgDn", "Ten up, down"], ["o", "Show in Files"], ["c  ⌘C", "Copy the path"], ["Delete", "Move to the Trash (asks first)"]] },
                { title: "Window", keys: [["1 – 9", "A place in the sidebar"], ["Ctrl ↑ ↓", "Previous, next place"], ["⌘O", "Choose a folder"], ["⌘R", "Scan again"],
                                         ["Esc", "Stop a scan"], ["⌘⇧⌫", "Clean up"], ["⌘B", "Hide or show the sidebar"]] }
            ]
        }
    }
}
