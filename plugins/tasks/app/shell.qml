import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Nightdrive Tasks: Today, Scheduled and the lists in the sidebar, their tasks on the right. New (n) adds one in a panel
// (TaskEditor); the other changes come from Claude (mcp.json), the `tasks` command and the notifications' Done and
// Later, which all ask it to read them again (`tasks …` calls refresh). lib/cli.py reads and writes the VTODO files.
ShellRoot {
    id: shell
    FloatingWindow {
        id: win
        title: "Tasks"
        implicitWidth: 960
        implicitHeight: 720
        color: c.bg
        // Closing the window (⌘W) quits Tasks, as Contacts: a process left without its window would only look open
        onClosed: Qt.quit()

        AppLook { id: c }
        readonly property QtObject look: c

        IpcHandler {
            target: "tasks"
            function refresh(): void { win.load() }
            function openSettings(): void {}     // the kit's `tasks settings`: Tasks has none yet
            // `tasks new [LIST]`: the new task panel, in that list (its name or id) when there is one
            function newTask(list: string): void {
                const l = win.lists.find(x => x.id === list || x.name.toLowerCase() === list.toLowerCase())
                win.newTask(l ? l.id : "")
            }
            // A row of the sidebar by its name (Today, Scheduled, a list, Done), and a task in it by number from 1
            function pick(name: string, row: int): void {
                const i = win.sources.findIndex(s => s.name.toLowerCase() === name.toLowerCase())
                if (i >= 0) win.pickSource(i)
                if (row > 0) win.move(row - 1)
            }
        }

        readonly property int headerHeight: 22
        readonly property int headerGap: 30
        readonly property string helper: Quickshell.shellDir + "/../lib/cli.py"
        readonly property int doneMax: 100   // Done shows the newest: a list kept for years would be long

        property var tasks: []              // every task, open and done (cli.py list --view all), soonest first
        property var lists: []              // [{ id, name, open }]
        property string today: ""           // YYYY-MM-DD, from the same read
        property bool loaded: false
        readonly property var sources: {
            const open = tasks.filter(t => !t.done)
            const rows = [{ kind: "today", name: "Today", glyph: "sun", count: open.filter(t => t.due && t.due.slice(0, 10) <= today).length },
                          { kind: "scheduled", name: "Scheduled", glyph: "calendar", count: open.filter(t => t.due).length }]
            for (const l of lists) rows.push({ kind: "list", id: l.id, name: l.name, glyph: "list", count: l.open })
            rows.push({ kind: "done", name: "Done", glyph: "circle-check", count: "" })
            return rows
        }
        property int source: 0
        readonly property var view: sources[source] || sources[0]
        readonly property bool mixed: view.kind !== "list"   // rows say their list
        property var shown: []
        property int current: -1

        property string keepNext: ""        // a task to pick once the next read is in (the one just added)
        function load() { loader.running = true }
        Process {
            id: loader
            command: ["python3", win.helper, "list", "--json", "--view", "all"]
            stdout: StdioCollector {
                onStreamFinished: {
                    let d
                    try { d = JSON.parse(text) } catch (e) { console.warn("cli.py list: " + e); return }
                    const keep = win.keepNext || (win.shown[win.current] ? win.shown[win.current].id : "")
                    win.keepNext = ""
                    const was = win.view.kind === "list" ? win.view.id : ""
                    win.tasks = d.tasks
                    win.lists = d.lists
                    win.today = d.now.slice(0, 10)
                    win.loaded = true
                    // The same list stays picked when one before it comes or goes
                    if (was) { const i = win.sources.findIndex(s => s.id === was); if (i >= 0) win.source = i }
                    win.source = Math.min(win.source, win.sources.length - 1)
                    win.filter(keep)
                }
            }
        }
        Component.onCompleted: { load(); list.forceActiveFocus() }
        // Today moves on with the clock, and a sync or another app may change the files: read them again each minute
        Timer { interval: 60000; running: true; repeat: true; onTriggered: win.load() }

        function dayOf(iso) { return Qt.formatDate(new Date(iso.slice(0, 10) + "T12:00"), "d MMM") }
        // The heading a row comes under: late ones first, then by day in Scheduled
        function sectionOf(t) {
            if (view.kind === "today" || view.kind === "scheduled") {
                if (t.overdue) return "Overdue"
                return view.kind === "today" ? "Today" : t.due_label.replace(/ \d\d:\d\d$/, "")
            }
            return ""
        }
        function filter(keep) {
            let rows
            if (view.kind === "done")
                rows = tasks.filter(t => t.done).sort((a, b) => (b.completed || "").localeCompare(a.completed || "")).slice(0, doneMax)
            else {
                rows = tasks.filter(t => !t.done)
                if (view.kind === "today") rows = rows.filter(t => t.due && t.due.slice(0, 10) <= today)
                else if (view.kind === "scheduled") rows = rows.filter(t => t.due)
                else rows = rows.filter(t => t.list_id === view.id)
            }
            // Late ones together at the top (a timed one from this morning sorts after today's all-day ones otherwise)
            if (view.kind === "today" || view.kind === "scheduled")
                rows = rows.filter(t => t.overdue).concat(rows.filter(t => !t.overdue))
            shown = rows.map(t => Object.assign({}, t, { section: sectionOf(t) }))
            const i = keep ? shown.findIndex(t => t.id === keep) : -1
            current = i >= 0 ? i : shown.length ? 0 : -1
            if (shown.length) listView.positionViewAtIndex(current, ListView.Contain)
        }
        function pickSource(i) {
            if (i < 0 || i >= sources.length) return
            source = i; filter("")
        }
        // The new task panel: in the list the window shows, or listId; due today when the view is Today, where a task
        // without a day wouldn't show
        function newTask(listId) {
            editor.open(listId || (view.kind === "list" ? view.id : ""), view.kind === "today" ? "today" : "")
        }
        // What just happened, at the top of the window (the kit's toast)
        function say(t, danger) { toast.show(t, { danger: !!danger }) }
        function move(d) {
            if (!shown.length) return
            current = Math.max(0, Math.min(shown.length - 1, current + d))
            listView.positionViewAtIndex(current, ListView.Contain)
        }

        // Tab moves the keys between the sidebar (↑ ↓ pick a row there) and the tasks, as in Contacts
        property string pane: "list"
        readonly property bool listFocused: list.activeFocus && pane === "list"
        function toList() { pane = "list"; list.forceActiveFocus() }

        Shortcut { sequence: "Ctrl+R"; onActivated: win.load() }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.sidebarChoice = !win.sidebarShown }

        readonly property int sidebarMin: 640
        property var sidebarChoice: null    // ⌘B's, over what the width says
        readonly property bool sidebarShown: sidebarChoice !== null ? sidebarChoice : width >= sidebarMin
        onSidebarShownChanged: if (!sidebarShown) pane = "list"

        RowLayout {
            id: content
            anchors.fill: parent
            spacing: 0
            AppPointer { c: win.look }

            AppSidebar {
                Layout.preferredWidth: win.width < 800 ? 168 : 208
                visible: win.sidebarShown
                c: win.look
                title: "Tasks"
                headerHeight: 2 * 18 + win.headerHeight
                contentTop: 18 + win.headerHeight + win.headerGap
                bottomMargin: 24
                Repeater {
                    model: win.sources
                    delegate: AppNavRow {
                        required property var modelData
                        required property int index
                        // A gap between Today and Scheduled and the lists, and before Done
                        Layout.topMargin: (modelData.kind === "list" && win.sources[index - 1].kind !== "list") || modelData.kind === "done" ? 14 : 0
                        c: win.look
                        glyph: modelData.glyph
                        label: modelData.name
                        count: modelData.count === 0 ? "" : modelData.count
                        countColor: modelData.kind === "today" && win.tasks.some(t => t.overdue) ? c.danger : c.faint   // something is late
                        selected: index === win.source
                        active: win.pane === "sources" && list.activeFocus
                        onClicked: { win.pickSource(index); win.toList() }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            FocusScope {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                focus: true
                Keys.onPressed: e => {
                    const k = e.key, ctrl = e.modifiers & Qt.ControlModifier
                    win.look.moved(e)
                    sheet.pressed(e)
                    if (e.accepted) return
                    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) win.pane = win.pane === "list" && win.sidebarShown ? "sources" : "list"
                    else if (win.pane === "sources" && (k === Qt.Key_Down || k === Qt.Key_J)) win.pickSource(win.source + 1)
                    else if (win.pane === "sources" && (k === Qt.Key_Up || k === Qt.Key_K)) win.pickSource(win.source - 1)
                    else if (win.pane === "sources" && (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right || k === Qt.Key_Escape)) win.pane = "list"
                    else if (ctrl && k === Qt.Key_Down) win.pickSource(win.source + 1)
                    else if (ctrl && k === Qt.Key_Up) win.pickSource(win.source - 1)
                    else if (k === Qt.Key_Down || k === Qt.Key_J) win.move(1)
                    else if (k === Qt.Key_Up || k === Qt.Key_K) win.move(-1)
                    else if (k === Qt.Key_PageDown) win.move(10)
                    else if (k === Qt.Key_PageUp) win.move(-10)
                    else if (k === Qt.Key_Home) win.move(-win.shown.length)
                    else if (k === Qt.Key_End) win.move(win.shown.length)
                    else if (k >= Qt.Key_1 && k <= Qt.Key_9 && !ctrl) win.pickSource(k - Qt.Key_1)
                    else if (k === Qt.Key_N && !ctrl) win.newTask("")
                    else return
                    e.accepted = true
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    // The view's name level with the sidebar's title
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 28
                        Layout.rightMargin: 28
                        Layout.topMargin: 18
                        Layout.preferredHeight: win.headerHeight
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: win.view.name
                            color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: win.shown.length ? win.shown.length + (win.view.kind === "done" ? " done" : " open") : ""
                            color: c.faint; font.family: c.font; font.pixelSize: 11
                        }
                        // Higher than the header's text (AppButton's 28): it reaches a little over and under it
                        AppButton {
                            Layout.leftMargin: 12
                            // The glyph alone in a narrow window, where the view's name needs the room
                            c: win.look; glyph: "plus"; label: win.width < 560 ? "" : "New"; tip: "New task"; keys: "n"; tipAlign: "right"
                            onClicked: win.newTask("")
                        }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 17; Layout.preferredHeight: 1; color: c.divider }

                    ListView {
                        id: listView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        clip: true
                        model: win.shown
                        currentIndex: win.current
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 0
                        TouchScroll { view: listView }
                        spacing: 2
                        topMargin: 4
                        bottomMargin: 12
                        section.property: "section"
                        section.delegate: Text {
                            required property string section
                            textFormat: Text.PlainText
                            visible: section !== ""
                            height: visible ? implicitHeight : 0
                            leftPadding: 16; topPadding: 12; bottomPadding: 4
                            text: section
                            color: section === "Overdue" ? c.danger : c.faint
                            font.family: c.font; font.pixelSize: 11; font.weight: Font.Medium
                        }
                        delegate: TaskRow { c: win.look; app: win }
                        Column {
                            visible: win.loaded && win.shown.length === 0
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: win.view.kind === "today" ? "Nothing due today" : win.view.kind === "done" ? "Nothing done yet" : "No tasks here"
                                color: c.faint; font.family: c.font; font.pixelSize: 12
                            }
                            Text {
                                visible: win.tasks.length === 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "n adds one, or ask Claude to"
                                color: c.faint; font.family: c.font; font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }

        KeySheet {
            id: sheet
            c: win.look
            groups: [
                { title: "Tasks", keys: [["↑ ↓  j k", "Previous, next (the picked task shows its whole note)"], ["PgUp PgDn", "Ten up, down"], ["Home End", "First, last"]] },
                { title: "Window", keys: [["Ctrl ↑ ↓", "Previous, next in the sidebar"], ["1 – 9", "Go to a row of the sidebar"], ["Tab", "Sidebar, tasks"], ["⌘R", "Read the tasks again"], ["⌘B", "Hide or show the sidebar"]] },
                { title: "Changing them", keys: [["n", "New task"], ["Claude", "Adds, moves, marks done"], ["tasks", "The same in a terminal: tasks help"], ["Notification", "Done, Later"]] },
                { title: "New task", keys: [["⏎  Ctrl ⏎", "Add it (⏎ is a new line in the note)"], ["Tab", "The next field"], ["← →", "Another list"], ["Space", "Important, on or off"], ["Esc", "Leave it"]] }
            ]
        }

        TaskEditor {
            id: editor
            behind: content
            c: win.look
            app: win
            onClosed: win.toList()
            // `cli.py add` doesn't ask the window to read again (only the `tasks` command does): read here, and pick it
            onAdded: task => {
                win.keepNext = task.id
                win.load()
                const here = win.view.kind === "list" ? win.view.id === task.list_id
                           : win.view.kind === "today" ? task.due && task.due.slice(0, 10) <= win.today
                           : win.view.kind === "scheduled" ? !!task.due : false
                win.say(here ? "Added" : "Added to " + task.list + (task.due ? ", " + task.due_label : ""))
            }
        }
        // Last, over the panel too
        AppToast { id: toast; c: win.look }
    }
}
