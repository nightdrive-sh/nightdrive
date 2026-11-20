import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit
import "Format.js" as Format

// One of Files' windows (shell.qml keeps them): the places in the sidebar (Places, Sidebar), the folder's files in a
// list (Folder, FileList), the picked one in the preview at the right (Preview) and over the window on Space
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
    onClosed: manager.closed(win)
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
    Folder { id: folder; path: win.path; onRebuilt: win.settle() }
    property alias showHidden: folder.showHidden
    property alias sortBy: folder.sortBy
    property alias reversed: folder.reversed
    property alias filter: folder.filter
    property bool filtering: false
    property string placeDrag: ""         // the sidebar folder being dragged to another place in it
    readonly property bool loading: !trashShown && folder.loading
    readonly property var rows: trashShown ? trashRows : folder.rows

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
        path = p
        // To the top, its margin in: positionViewAtBeginning() leaves the margin out, and the list jumped up by it and
        // back as a folder not read before came
        list.view.contentY = list.view.originY - list.view.topMargin
    }
    function back() { if (history.length) { const p = history[history.length - 1]; history = history.slice(0, -1); future = [trashShown ? "" : path].concat(future); p ? enter(p, path) : showTrash() } }
    function forward() { if (future.length) { const p = future[0]; future = future.slice(1); history = history.concat([trashShown ? "" : path]); p ? enter(p, "") : showTrash() } }
    function up() { if (trashShown) go(home, ""); else if (path !== "/") go(Format.parent(path), path) }
    function goDownloads() { if (places.data.downloads) go(places.data.downloads, "") }
    function goEntry(e) {
        if (e.kind === "trash") { if (!trashShown) history = history.concat([path]); showTrash() }
        else if (e.kind === "device" && !e.path) acts.mount(e, p => go(p, ""))
        else go(e.path, "")
    }
    function showTrash() { trashShown = true; endFilter(); marks = ({}); current = -1; loadTrash() }
    function loadTrash() { trashReader.running = true }
    Process {
        id: trashReader
        command: ["python3", win.helper, "trash-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d
                try { d = JSON.parse(text) } catch (e) { return }
                win.trashRows = d.items.map(r => ({ name: r.name, path: r.path, dir: r.dir, size: r.size, modified: r.deleted, origin: r.origin, id: r.id }))
                win.settle()
            }
        }
    }
    function reload() { if (trashShown) loadTrash(); else folder.rebuild(); places.refresh() }

    // The rows came (again): the same file stays picked, or the one asked for, or the row at the same place
    function settle() {
        const want = keep || (picked ? picked.path : "")
        const i = want ? rows.findIndex(r => r.path === want) : -1
        if (i >= 0 || !keep) keep = ""
        current = i >= 0 ? i : rows.length ? Math.max(0, Math.min(current, rows.length - 1)) : -1
        if (current >= 0) list.view.positionViewAtIndex(current, ListView.Contain)
        // Marks of files gone stay out of what the keys act on (marked only counts the rows there)
        preview.again()
    }
    function pick(p) { keep = p; settle() }
    function move(d) { moveTo((current < 0 ? 0 : current) + d) }
    function moveTo(i) {
        if (!rows.length) return
        current = Math.max(0, Math.min(rows.length - 1, i))
        list.view.positionViewAtIndex(current, ListView.Contain)
    }
    function page() { return Math.max(1, Math.floor(list.view.height / (rowHeight + 1)) - 1) }
    function openAt(i) { current = i; openPicked() }
    function openPicked() {
        const f = picked
        if (!f || trashShown) return
        if (f.dir) go(f.path, "")
        else Quickshell.execDetached(["gio", "open", f.path])
    }

    // Marks (v, ⇧↑ ⇧↓, ⌘-click, ⇧-click): the files the keys act on, else the picked one
    function setMark(p, on) { const m = Object.assign({}, marks); if (on) m[p] = true; else delete m[p]; marks = m }
    function toggleMarkAt(i) { const r = rows[i]; if (r) setMark(r.path, marks[r.path] !== true) }
    function toggleMark() { toggleMarkAt(current); move(1) }
    function markMove(d) { if (picked) setMark(picked.path, true); move(d); if (picked) setMark(picked.path, true) }
    function markRange(a, b) {
        const m = Object.assign({}, marks)
        for (let i = Math.min(a, b); i <= Math.max(a, b); i++) if (rows[i]) m[rows[i].path] = true
        marks = m
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

    // The filter (/, ⌘F): the field in the header narrows the rows as it is typed into
    function startFilter() { if (trashShown) return; filtering = true; header.field.text = filter; pane = "list"; header.field.forceActiveFocus() }
    function endFilter() { filtering = false; filter = ""; header.field.text = ""; toList() }

    // s goes through the orders, S (or the same column's title again) turns it round
    readonly property var sorts: ["name", "modified", "size", "type"]
    function cycleSort() { sortBy = sorts[(sorts.indexOf(sortBy) + 1) % sorts.length]; reversed = false; say("By " + sortBy) }
    function sortOn(field) { if (sortBy === field) reversed = !reversed; else { sortBy = field; reversed = false } }

    function tilde(p) { return p === home ? "~" : p.startsWith(home + "/") ? "~" + p.slice(home.length) : p }
    function say(t, danger) { toast.show(t, { danger: !!danger }) }
    function offer(t, undo) { toast.show(t, { action: "Undo", run: undo }) }

    Ops { id: ops; app: win }
    Clip { id: clip; app: win; shared: win.manager }
    Places { id: places; app: win }
    FileActions { id: acts; app: win; prompt: prompt; confirm: confirm }
    FileKeys { id: keys; app: win }
    FileDrag { id: dragger }
    readonly property alias ops: ops
    readonly property alias clip: clip
    readonly property alias places: places
    readonly property alias acts: acts
    readonly property alias drag: dragger
    readonly property alias quick: quick
    readonly property alias toast: toast
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

    Shortcut { sequence: "Ctrl+Z"; enabled: !prompt.visible && !confirm.visible; onActivated: if (!toast.act()) ops.undo() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    // A new window in the same folder, as Nautilus does (⌘ reaches the app as Ctrl)
    Shortcut { sequences: ["Ctrl+N", "Meta+N"]; onActivated: win.manager.open(win.trashShown ? "" : win.path, "") }
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
                FileList { id: list; Layout.fillWidth: true; Layout.fillHeight: true; c: win.look; app: win }
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

    QuickLook { id: quick; anchors.fill: parent; c: win.look; app: win }

    KeySheet {
        id: sheet
        c: win.look
        groups: [
            { title: "Moving", keys: [["↑ ↓  j k", "Previous, next"], ["→ ⏎  l", "Open: into a folder, a file in its app"], ["← ⌫  h", "Up a folder"], ["gg  G", "First, last"], ["⌥← ⌥→", "Back, forward"], ["~  gh  gd", "Home, home, Downloads"], ["⌘L", "Go to a folder by its path"]] },
            { title: "Looking", keys: [["Space", "The big preview (↑ ↓ through the files, Space closes)"], ["i", "The preview at the right"], ["/  ⌘F", "Filter by name (Esc: all again)"], [".", "Hidden files"], ["s  S", "Sort by name, time, size, type; turn round"], ["⌘B", "The sidebar"], ["⌘,", "Settings: Normal or Compact rows"]] },
            { title: "Marking", keys: [["v", "Mark, and on to the next"], ["⇧↑ ⇧↓", "Mark on the way"], ["⌘A", "Mark all"], ["⌘-click  ⇧-click", "Mark one, mark up to it"], ["Esc", "No marks"]] },
            { title: "Changing", keys: [["y  ⌘C", "Copy"], ["x  ⌘X", "Cut"], ["p  ⌘V", "Paste here"], ["d  ⌘⌫", "To the trash"], ["r  F2", "Rename"], ["a", "New file (end with / for a folder)"], ["⌘⇧N", "New folder"], ["⌘Z", "Undo"]] },
            { title: "Places", keys: [["Tab", "Sidebar, list"], ["⌘N", "A new window, in this folder"], ["b  ⌘D", "Bookmark the picked folder, or not"], ["Drag", "Onto a folder or the sidebar: moved; from another app: copied"], ["Drag in the sidebar", "A folder to another place, or to the other group"]] },
            { title: "Trash", keys: [["u", "Put back"], ["d", "Delete for good"], ["⌘⇧⌫", "Empty the trash"]] }
        ]
    }

    SettingsPanel { win: win; behind: content; onVisibleChanged: if (!visible) win.toList() }
    AppPrompt { id: prompt; c: win.look; behind: content; onClosed: win.toList() }
    AppConfirm { id: confirm; c: win.look; behind: content; visible: false; onAnswered: ok => acts.answered(ok) }
    AppToast { id: toast; c: win.look }
}
