import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit
import "Format.js" as Format
import "Settle.js" as Settle

// One of Files' windows (shell.qml keeps them): the places in the sidebar (Places, Sidebar), the folder's files in a
// list (Folder, FileList), the picked one in the preview at the right (Preview) and over the screen on Space
// (QuickLook). The keys are yazi's letters with the desktop's ⌘ keys beside them (FileKeys); the changes run
// lib/cli.py (Ops), each with Undo, and the clipboard is the desktop's (Clip). Files go out and come in by dragging too
// (FileDrag, the rows' DropAreas).
FloatingWindow {
    id: win
    required property var manager        // shell.qml: the windows, the cut they share, the one IPC goes to
    required property int key            // this window's in manager.windows
    property string startPath: ""         // where it opens (home when empty), and the file picked there
    property string startSelect: ""
    title: "Files"
    implicitWidth: 1100
    implicitHeight: 720
    color: c.bg
    onClosed: { archive.leave(); manager.closed(win) }
    Component.onCompleted: if (startPath) enter(startPath, startSelect)

    // The window last active is the one a folder from another app (IPC) goes to
    readonly property bool active: content.Window.active
    onActiveChanged: if (active) manager.last = win

    AppLook { id: c }
    readonly property QtObject look: c

    // The settings are the manager's, the same in every window (SettingsPanel)
    readonly property var settings: manager.settings
    function setting(key, value) { manager.setting(key, value) }
    property bool showSettings: false
    readonly property bool compact: settings.layout === "compact"
    readonly property int rowHeight: compact ? 30 : 40     // FileRow's; normal is near Nautilus's, easy to click

    // The grid (t, FileGrid): a folder's own choice (Views); the trash is always a list. tile is the thumbnails'
    // square, + and − step it, the same in every window
    Views { id: views; dir: win.manager.configDir }
    readonly property bool gridShown: !trashShown && !inArchive && views.isGrid(path)
    function toggleView() { if (!trashShown && !inArchive) views.set(path, !gridShown) }
    readonly property var tiles: [96, 128, 192]
    readonly property int tile: tiles.indexOf(settings.tile) >= 0 ? settings.tile : 128
    function tileStep(d) { const i = tiles.indexOf(tile) + d; if (i >= 0 && i < tiles.length) setting("tile", tiles[i]) }
    Thumbs { id: thumbs; helperDir: Quickshell.shellDir + "/../lib"; rows: win.rows; on: win.gridShown; size: win.tile > 128 ? "x-large" : "large" }
    readonly property alias thumbs: thumbs
    readonly property var view: gridShown ? grid.view : list.view

    readonly property string helper: Quickshell.shellDir + "/../lib/cli.py"
    readonly property string home: Quickshell.env("HOME")
    readonly property int headerHeight: 30
    // Above and below the header's row: 12 + 30 + 12, as high as Mail's bar over a message (54) with its line under it
    readonly property int headerPad: 12

    // Where the window is: a folder, or the trash (its own rows, from cli.py trash-list)
    property string path: home
    property bool trashShown: false
    property var trashRows: []
    property var history: []             // folders before this one, for ⌥← (⌃⌘←)
    property var future: []              // and after it, for ⌥→
    Folder { id: folder; path: win.inArchive ? "" : win.path; onChanging: win.hold(); onRebuilt: win.settle() }
    // Inside an archive (→ on one): its folders, read-only, the path going on below the archive's (Archive)
    Archive { id: archive; app: win; onChanging: win.hold(); onRebuilt: win.settle() }
    readonly property alias archive: archive
    readonly property bool inArchive: archive.file !== ""
    property alias showHidden: folder.showHidden
    property alias sortBy: folder.sortBy
    property alias reversed: folder.reversed
    property alias filter: folder.filter
    property bool filtering: false
    // The filter's scope, as the Mac's Finder has it: this folder (Folder narrows its rows), or all of home (Search, fd).
    // Outside home (a USB stick, /etc) home wouldn't help: there it is the folder and every one below it
    readonly property bool inHome: path === home || path.startsWith(home + "/")
    readonly property string searchRoot: inHome ? home : path
    Search { id: search; app: win; folder: win.searchRoot; words: win.filter; hidden: win.showHidden; onChanging: win.hold(); onRebuilt: win.settle() }
    property alias below: search.on
    readonly property bool searching: !trashShown && search.active
    readonly property alias search: search
    property string placeDrag: ""         // the sidebar folder being dragged to another place in it
    readonly property bool loading: !trashShown && (inArchive ? archive.loading : searching ? search.running : folder.loading)
    readonly property var rows: trashShown ? trashRows : inArchive ? archive.rows : searching ? search.rows : folder.rows

    property int current: -1
    property string keep: ""             // the path to pick once the rows come (one just made, the folder come up from)
    readonly property var picked: rows[current] || null
    property var marks: ({})            // path → true
    readonly property var marked: rows.filter(r => marks[r.path] === true)
    readonly property real markedSize: marked.reduce((n, r) => n + (r.dir ? 0 : r.size), 0)

    function go(p, select) {
        if (!p) return
        if (!trashShown && p === path) { if (select) pick(select); return }
        history = history.concat([trashShown ? "" : path]).slice(-100)
        future = []
        enter(p, select)
    }
    function enter(p, select) {
        trashShown = false
        endFilter()
        marks = ({})
        keep = select || ""
        current = -1
        shown = []
        archive.show(p)
        path = p
        // To the top, its margin in: positionViewAtBeginning() leaves the margin out, and the list jumped up by it and
        // back as a folder not read before came
        view.contentY = view.originY - view.topMargin
    }
    function back() { if (history.length) { const p = history[history.length - 1]; history = history.slice(0, -1); future = [trashShown ? "" : path].concat(future); p ? enter(p, path) : showTrash() } }
    function forward() { if (future.length) { const p = future[0]; future = future.slice(1); history = history.concat([trashShown ? "" : path]); p ? enter(p, "") : showTrash() } }
    // Up from a search's result is the folder it is in, with it picked
    function up() {
        if (trashShown) go(home, "")
        else if (searching && picked) go(Format.parent(picked.path), picked.path)
        else if (path !== "/") go(Format.parent(path), path)
    }
    function goDownloads() { if (places.data.downloads) go(places.data.downloads, "") }
    function goEntry(e) {
        if (e.kind === "trash") { if (!trashShown) history = history.concat([path]); showTrash() }
        else if (e.kind === "device" && !e.path) acts.mount(e, p => go(p, ""))
        else go(e.path, "")
    }
    function showTrash() { archive.leave(); trashShown = true; endFilter(); marks = ({}); current = -1; shown = []; loadTrash() }
    function loadTrash() { trashReader.running = true }
    Process {
        id: trashReader
        command: ["python3", win.helper, "trash-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d
                try { d = JSON.parse(text) } catch (e) { return }
                win.hold()
                win.trashRows = d.items.map(r => ({ name: r.name, path: r.path, dir: r.dir, size: r.size, modified: r.deleted, origin: r.origin, id: r.id }))
                win.settle()
            }
        }
    }
    function reload() { if (trashShown) loadTrash(); else if (inArchive) archive.read(); else folder.rebuild(); places.refresh() }

    // The rows came (again): the one asked for (keep), else the same file stays picked, else the next row still there
    // in the place of those gone (Settle.place), and the view stays where it was (#3415). shown is the rows' paths as
    // last settled, which current indexes until then: by now rows is already the new set, so picked can't say what
    // was picked. A folder entered starts with none, and at the top.
    property var shown: []
    property real heldY: NaN
    property real heldAt: NaN            // the picked row's distance from the view's top, while it is in sight
    // Before the rows are set again (Folder, Search, the trash): a new model takes the view to the top. The picked
    // row keeps its place on screen (files added above it don't push it down), else the view its own
    function hold() {
        if (!isNaN(heldY)) return
        heldY = view.contentY
        const item = current >= 0 ? view.itemAtIndex(current) : null
        const at = item ? item.y - view.contentY : NaN
        heldAt = at >= 0 && at + item.height <= view.height ? at : NaN    // a row kept beyond the edge isn't in sight
    }
    function settle() {
        const paths = rows.map(r => r.path)
        const i = Settle.place(shown, current, paths, keep)
        if (!keep || paths[i] === keep) keep = ""
        let y = heldY
        const at = heldAt
        heldY = NaN; heldAt = NaN
        const again = shown.length > 0
        shown = paths
        current = i
        if (again && !isNaN(y)) {
            view.forceLayout()
            if (current >= 0 && !isNaN(at)) {
                view.positionViewAtIndex(current, ListView.Beginning)
                const item = view.itemAtIndex(current)
                if (item) y = item.y - at
            }
            const top = view.originY - view.topMargin
            view.contentY = Settle.scrollBack(y, top, view.contentHeight + view.topMargin + view.bottomMargin - view.height)
        }
        if (current >= 0) view.positionViewAtIndex(current, ListView.Contain)
        // Marks of files gone stay out of what the keys act on (marked only counts the rows there)
        preview.again()
    }
    function pick(p) { keep = p; settle() }
    function move(d) { moveTo((current < 0 ? 0 : current) + d) }
    function moveTo(i) {
        if (!rows.length) return
        current = Math.max(0, Math.min(rows.length - 1, i))
        view.positionViewAtIndex(current, ListView.Contain)
    }
    function page() { return gridShown ? grid.perPage : Math.max(1, Math.floor(list.view.height / (rowHeight + 1)) - 1) }
    function openAt(i) { current = i; openPicked() }
    // An archive extracts beside itself (Ops, lib/unpack.py) on ⏎, e and a double click; → and l (look) go into it as
    // into a folder (Archive), and ⌘O (inApp) opens it in its app. A file in an archive shows in the big preview: it
    // isn't on disk to open, and y and p take it out
    function openPicked(inApp, look) {
        const f = picked
        if (!f || trashShown) return
        if (f.dir) go(f.path, "")
        else if (inArchive) { if (!quick.open) quick.toggle() }
        else if (look && Format.isArchive(f.name)) { archive.look(f.path); go(f.path, "") }
        else if (!inApp && Format.isArchive(f.name)) ops.extract(f.path)
        else launch.open(f.path)           // a program asks first, a file no app opens says so (Launch)
    }
    function extractPicked() {
        if (readOnly()) return
        if (picked && !picked.dir && !trashShown && Format.isArchive(picked.name)) ops.extract(picked.path)
    }
    // What would change the folder on show, refused in words inside an archive
    function readOnly() { if (inArchive) archive.refuse(); return inArchive }

    // Marks (v, ⇧↑ ⇧↓, Ctrl-click, ⇧-click): the files the keys act on, else the picked one
    function setMark(p, on) { const m = Object.assign({}, marks); if (on) m[p] = true; else delete m[p]; marks = m }
    function toggleMarkAt(i) { const r = rows[i]; if (r) setMark(r.path, marks[r.path] !== true) }
    function toggleMark() { toggleMarkAt(current); move(1) }
    function markMove(d) { if (picked) setMark(picked.path, true); move(d); if (picked) setMark(picked.path, true) }
    function markRange(a, b) {
        const m = Object.assign({}, marks)
        for (let i = Math.min(a, b); i <= Math.max(a, b); i++) if (rows[i]) m[rows[i].path] = true
        marks = m
    }
    // ⇧-click marks the rows from the anchor to row i in place of the marks before, ⌘⇧-click (add) beside them, as
    // Finder and Nautilus do. The anchor is the row last picked by a click or the keys, and a ⇧-click leaves it, so a
    // second one changes the span. Indexes are the shown rows', so in a filter or a search's results only those count.
    property string anchor: ""
    property bool holdAnchor: false
    // rows[current], not picked: its binding may not have caught up yet when this runs
    onCurrentChanged: if (!holdAnchor) anchor = rows[current] ? rows[current].path : ""
    function markTo(i, add) {
        let a = rows.findIndex(r => r.path === anchor)
        if (a < 0) a = current >= 0 ? current : i
        if (!add) marks = ({})
        markRange(a, i)
        holdAnchor = true; current = i; holdAnchor = false
    }
    function markAll() { const m = {}; for (const r of rows) m[r.path] = true; marks = m }
    function selection() { return marked.length ? marked.map(r => r.path) : picked ? [picked.path] : [] }
    function selectionIds() { return marked.length ? marked.map(r => r.id) : picked ? [picked.id] : [] }
    function dragPaths(p) { return marks[p] === true ? marked.map(r => r.path) : [p] }
    function letGo() {
        if (filter || filtering) endFilter()
        else if (marked.length) marks = ({})
        else if (clip.cut.length) manager.cut = []
    }

    // The filter (/, ⌘F): the field in the header narrows the rows as it is typed into. Its scope is this folder, or with
    // below all of home (f starts there; Tab, ⌘F again or a click on the scope in the field turns it)
    function startFilter(deep) {
        if (trashShown) return
        if (inArchive) deep = false        // an archive's folder is filtered, there's no search below it
        if (deep !== undefined) below = deep
        else if (filtering && header.field.activeFocus) below = !below
        filtering = true; header.field.text = filter; pane = "list"; header.field.forceActiveFocus()
    }
    readonly property bool fieldFocused: header.field.activeFocus
    // The field keeps the keys: Tab's own move to the next item comes after this handler, so focus goes back once it has
    function toggleScope() { if (inArchive) return; below = !below; if (filtering) { header.field.forceActiveFocus(); Qt.callLater(() => { if (filtering) header.field.forceActiveFocus() }) } }
    function endFilter() { filtering = false; filter = ""; below = false; header.field.text = ""; toList() }

    // s goes through the orders, S (or the same column's title again) turns it round
    readonly property var sorts: ["name", "modified", "size", "type"]
    function cycleSort() { sortBy = sorts[(sorts.indexOf(sortBy) + 1) % sorts.length]; reversed = false; say("By " + sortBy) }
    function sortOn(field) { if (sortBy === field) reversed = !reversed; else { sortBy = field; reversed = false } }

    function tilde(p) { return p === home ? "~" : p.startsWith(home + "/") ? "~" + p.slice(home.length) : p }
    function say(t, danger) { toast.show(t, { danger: !!danger }) }
    function offer(t, undo) { toast.show(t, { action: "Undo", run: undo }) }

    Ops { id: ops; app: win }
    OpenWith { id: openWith; app: win }
    MailFiles { id: mailFiles; app: win }
    Clip { id: clip; app: win; shared: win.manager }
    Places { id: places; app: win }
    FileActions { id: acts; app: win; prompt: prompt; confirm: confirm }
    FileKeys { id: keys; app: win }
    FileDrag { id: dragger; c: win.look }
    readonly property alias ops: ops
    readonly property alias clip: clip
    readonly property alias places: places
    readonly property alias acts: acts
    readonly property alias drag: dragger
    readonly property alias quick: quick
    readonly property alias grid: grid
    readonly property alias toast: toast
    readonly property alias compress: compressPanel
    readonly property alias openWith: openWith
    readonly property alias mailFiles: mailFiles
    function changed(d) { acts.changed(d) }

    // Tab moves the keys between the sidebar and the list
    property string pane: "list"
    property int sideIndex: 0
    readonly property bool listFocused: listScope.activeFocus && pane === "list"
    // The filter's field is in the same focus scope: it lets go first, or the scope would hand the keys back to it
    // (and the next letters would filter by themselves)
    function toList() { pane = "list"; header.field.focus = false; listScope.forceActiveFocus() }
    function switchPane() {
        if (pane === "list" && sidebarShown) {
            const i = places.entries.findIndex(e => trashShown ? e.kind === "trash" : e.path === path)
            sideIndex = Math.max(0, i); pane = "side"
        } else pane = "list"
    }
    function sideMove(d) { sideIndex = Math.max(0, Math.min(places.entries.length - 1, sideIndex + d)) }
    function sideOpen() { const e = places.entries[sideIndex]; if (e) goEntry(e); pane = "list" }

    Shortcut { sequence: "Ctrl+Z"; enabled: !prompt.visible && !confirm.visible && !launch.visible; onActivated: if (!toast.act()) ops.undo() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    // A new window in the same folder, as Nautilus does: ⌘N is FileKeys'. Not a Shortcut: Qt matches "Ctrl+N" on
    // Ctrl+Shift+N too, which took ⌘⇧N (a new folder) from the keys
    function newWindow() { if (inArchive) manager.open(Format.parent(archive.file), archive.file); else manager.open(trashShown ? "" : path, "") }
    Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.sidebarChoice = !win.sidebarShown }
    Shortcut { sequences: ["Ctrl+,", "Meta+,"]; enabled: !win.showSettings; onActivated: win.showSettings = true }

    property var sidebarChoice: null
    readonly property bool sidebarShown: sidebarChoice !== null ? sidebarChoice : width >= 640
    property var previewChoice: null
    readonly property bool previewShown: previewChoice !== null ? previewChoice : width >= 900
    onSidebarShownChanged: if (!sidebarShown) pane = "list"
    // The columns the list has room for (FileRow, FileList): the size, then the time, give way first
    readonly property int listWidth: list.width
    readonly property int secondWidth: listWidth >= 520 ? (trashShown ? 180 : 72) : 0
    readonly property int thirdWidth: listWidth >= 400 ? 96 : 0

    RowLayout {
        id: content
        anchors.fill: parent
        spacing: 0
        AppPointer { c: win.look }

        Sidebar {
            Layout.preferredWidth: win.width < 800 ? 176 : 212
            visible: win.sidebarShown
            c: win.look
            app: win
            headerHeight: 2 * win.headerPad + win.headerHeight
            contentTop: 2 * win.headerPad + win.headerHeight + 16
            bottomMargin: 18
        }

        FocusScope {
            id: listScope
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            Keys.onPressed: e => {
                win.look.moved(e)
                sheet.pressed(e)
                if (e.accepted) return
                if (keys.press(e)) e.accepted = true
            }
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                PathHeader {
                    id: header
                    Layout.fillWidth: true
                    Layout.leftMargin: 10; Layout.rightMargin: 16      // the back arrow near the sidebar's edge
                    Layout.topMargin: win.headerPad
                    Layout.preferredHeight: win.headerHeight
                    Layout.fillHeight: false        // a layout in a layout fills by default
                    c: win.look
                    app: win
                }
                // The header's line, under the list's part only: the sidebar has none
                Item { Layout.preferredHeight: win.headerPad - 1 }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.look.divider }
                Item { Layout.preferredHeight: 10 }
                FileList { id: list; visible: !win.gridShown; Layout.fillWidth: true; Layout.fillHeight: true; c: win.look; app: win }
                FileGrid { id: grid; visible: win.gridShown; Layout.fillWidth: true; Layout.fillHeight: true; c: win.look; app: win }
            }
        }

        Preview {
            id: preview
            visible: win.previewShown
            Layout.preferredWidth: Math.min(340, Math.max(240, win.width * 0.26))
            Layout.fillHeight: true
            c: win.look
            app: win
        }
    }

    QuickLook { id: quick; c: win.look; app: win }       // a layer over the screen, not in the window

    KeySheet {
        id: sheet
        c: win.look
        groups: [
            { title: "Moving", keys: [["↑ ↓  j k", "Previous, next"], ["→ ⏎  l  o", "Open: into a folder, a file in its app"], ["→  l on an archive", "Look into it, read-only (⏎ extracts it)"], ["⏎ on a program", "Asks: Run, Run in Terminal (⌘⏎)"], ["O", "Open with: pick the app (⌘⏎: always)"], ["← ⌫  h", "Up a folder"], ["gg  G", "First, last"], ["⌥← ⌥→", "Back, forward"], ["~  gh  gd", "Home, home, Downloads"], ["⌘L", "Go to a folder by its path"]] },
            { title: "Looking", keys: [["Space", "The big preview (↑ ↓ through the files, Space closes)"], ["p  ←  →", "In it, a sound: play or pause, 5 s back or on"], ["i", "The preview at the right"], ["/  ⌘F", "Filter by name (Esc: all again)"], ["f  Tab", "Search all of home (Tab: back to this folder)"], [".", "Hidden files"], ["s  S", "Sort by name, time, size, type; turn round"], ["t", "Thumbnails in a grid, or the list (hjkl move in it)"], ["+  −", "Larger, smaller thumbnails"], ["⌘B", "The sidebar"], ["⌘,", "Settings: Normal or Compact rows"]] },
            { title: "Marking", keys: [["v", "Mark, and on to the next"], ["⇧↑ ⇧↓", "Mark on the way"], ["⌘A", "Mark all"], ["Ctrl-click", "Mark one (⌘-click moves the window)"], ["⇧-click  ⌘⇧-click", "Mark up to it, add up to it"], ["Esc", "No marks"]] },
            { title: "Changing", keys: [["y  ⌘C", "Copy (pastes as the paths in a terminal)"], ["x  ⌘X", "Cut"], ["p  ⌘V", "Paste here"], ["d  ⌘⌫", "To the trash"], ["r  F2", "Rename"], ["a", "New file (end with / for a folder)"], ["⌘⇧N", "New folder"], ["c", "Compress: zip, tar.gz, tar.xz, tar"], ["m", "Mail: attached to a new message"], ["⏎  e", "Extract an archive here (⌘O: open it in its app)"], ["y, then p", "In an archive: take files out, into a folder"], ["⌘Z", "Undo"]] },
            { title: "Places", keys: [["Tab", "Sidebar, list"], ["⌘N", "A new window, in this folder"], ["b  ⌘D", "Bookmark the picked folder, or not"], ["Drag", "Onto a folder or the sidebar: moved; from another app: copied"], ["Drag in the sidebar", "A folder to another place, or to the other group"]] },
            { title: "Trash", keys: [["u", "Put back"], ["d", "Delete for good"], ["⌘⇧⌫", "Empty the trash"]] }
        ]
    }

    SettingsPanel { win: win; behind: content; onVisibleChanged: if (!visible) win.toList() }
    CompressPanel { id: compressPanel; app: win; behind: content }
    AppPrompt { id: prompt; c: win.look; behind: content; onClosed: win.toList() }
    AppConfirm { id: confirm; c: win.look; behind: content; visible: false; onAnswered: ok => acts.answered(ok) }
    Launch { id: launch; app: win; c: win.look; behind: content }
    AppToast { id: toast; c: win.look }
}
