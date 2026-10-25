import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Welcome to Nightdrive: what a new install still needs from you (Tailscale, Mail, Deck…). First a question (Question):
// Claude Code? Then the list (TaskList): with Claude, signing in first and each thing set up in a Claude session of its
// own; without, each by hand here, a step at a time (StepView); or "I'll do it myself", each app's README in Apostrophe.
// The list is `tasks`, a plugin's steps its steps.md (`steps`); `welcome` opens this at the first login and owns its
// state, the answer too (`path`).
ShellRoot {
    id: shell
    FloatingWindow {
        id: win
        title: "Welcome to Nightdrive"
        // Wide rather than tall (the VM test), so it never grows past a small screen. hypr/welcome.lua's float-welcome gives
        // it the same size.
        implicitWidth: 960
        implicitHeight: 600
        color: c.bg
        // Closed by the window manager: on the self path that is its Finish, as Jari asked; else the next login reminds
        onClosed: { if (selfPath) Quickshell.execDetached([dir + "/welcome", "off"]); Qt.quit() }

        AppLook { id: c }
        readonly property QtObject look: c
        readonly property string dir: Quickshell.shellDir
        readonly property string setupCmd: Quickshell.env("HOME") + "/.config/hypr/scripts/claude-setup"

        // The list, read again every few seconds: a session that ends, or a setup done elsewhere, shows by itself
        property var tasks: []
        property int current: 0
        // The first question's answer: "claude", "manual" (guided), "self", "" while unanswered; null until read
        property var path: null
        readonly property bool manual: path === "manual"
        readonly property bool selfPath: path === "self"
        readonly property var rows: manual || selfPath ? tasks.filter(t => t.id !== "claude") : tasks
        readonly property bool claudeIn: tasks.length > 0 && tasks[0].id === "claude" && tasks[0].done
        readonly property bool finished: rows.length > 0 && rows.every(t => t.done || t.mark === "skipped")
        property string openId: ""                      // the task whose steps are on show
        readonly property string view: path === null ? "" : path === "" ? "question" : openId !== "" ? "steps" : "list"

        Process {
            id: lister
            command: [win.dir + "/tasks"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try { win.tasks = JSON.parse(text) } catch (e) { return }
                    if (!win.picked) win.current = win.firstOpen()
                    win.picked = true
                }
            }
        }
        Process {
            running: true
            command: [win.dir + "/welcome", "path"]
            stdout: StdioCollector { onStreamFinished: win.path = text.trim() }
        }
        function refresh() { if (!lister.running) lister.running = true }
        Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: win.refresh() }
        // After an action, its result soon rather than at the next round
        Timer { id: soon; interval: 800; onTriggered: win.refresh() }

        // The first open row is picked once, at the start and on a change of path; after that the keyboard's place
        // stays where you put it
        property bool picked: false
        function firstOpen() {
            const i = rows.findIndex(t => !t.done && t.mark !== "skipped")
            return i < 0 ? 0 : i
        }

        function run(argv) { Quickshell.execDetached(argv); soon.restart() }
        function takeKeys() { keys.forceActiveFocus() }
        // An answer to the first question, or "" to ask it again (the list's Back)
        function choose(p) {
            path = p
            openId = ""
            current = firstOpen()
            Quickshell.execDetached([dir + "/welcome", "path", p || "none"])
        }
        // Enter on a row: its terminal to the front while it runs; by hand (the No path, or before signing in to
        // Claude), its steps, or its page without them; else its setup with Claude
        function activate(i) {
            const t = rows[i]
            if (!t) return
            current = i
            if (t.id === "claude" && t.done) return
            if (selfPath) run(t.readme ? [dir + "/welcome", "readme", t.readme] : ["xdg-open", t.help])
            else if (t.running) run([setupCmd, "focus", t.id])
            else if (t.id !== "claude" && (manual || !claudeIn)) {
                if (t.steps) openId = t.id
                else if (t.help) run(["xdg-open", t.help])
            } else {
                if (t.mark === "skipped") run([setupCmd, "mark", t.id])
                run(t.setup)
            }
        }
        function closeSteps() { openId = ""; takeKeys() }
        // Finish on the last step: the row counts as started (as a Claude session's does), so without a `configured`
        // test it shows Done, and with one Not finished until the test passes
        function finishSteps(id) {
            const t = tasks.find(t => t.id === id)
            if (t && !t.done) run([setupCmd, "mark", id, "started"])
            closeSteps()
        }
        // Ctrl+Enter (and Esc on the first question): Skip for now (what isn't done is put aside) or, all done or
        // skipped, Finish. Either way logins stop asking. On the self path it is Finish: nothing is marked, the READMEs
        // were the help asked for.
        function close() {
            Quickshell.execDetached([dir + "/welcome", selfPath ? "off" : "skip-rest"])
            Qt.quit()
        }

        IpcHandler {
            target: "welcome"
            function refresh(): void { win.refresh() }
            function rows(): string { return JSON.stringify(win.rows) }
            function view(): string { return win.view }
            function choose(path: string): void { win.choose(path) }
            function back(): void { win.choose("") }
            function steps(id: string): void { win.openId = id }
            function go(n: int): void { stepView.go(n) }
            function fill(key: string, text: string): void { stepView.setValue(key, text) }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                const finish = (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && e.modifiers === Qt.ControlModifier
                if (!finish && e.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier)) {
                    if (e.key === Qt.Key_Q || e.key === Qt.Key_W) Qt.quit()     // later: the next login reminds
                    return
                }
                const v = win.view === "question" ? question : win.view === "list" ? list : win.view === "steps" ? stepView : null
                e.accepted = v !== null && v.key(e)
            }

            Question {
                id: question
                anchors.fill: parent
                visible: win.view === "question"
                app: win; c: win.look
                onChosen: path => win.choose(path)
            }
            TaskList {
                id: list
                anchors.fill: parent
                visible: win.view === "list"
                app: win; c: win.look
            }
            StepView {
                id: stepView
                anchors.fill: parent
                visible: win.view === "steps"
                app: win; c: win.look
                taskId: win.openId
            }
        }
    }
}
