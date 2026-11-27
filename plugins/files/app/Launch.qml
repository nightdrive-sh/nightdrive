import QtQuick
import Quickshell
import Quickshell.Io
import qs.kit

// Opening a file (⏎, a double click, ⌘O): lib/launch.py opens it in its default app, or answers that it is a program
// or that no app opens it (#3417; before, gio open did nothing at all for either). A program runs only from this
// question, every time: a download must never start from a stray double click, and there is no setting to skip it.
// Run starts it in its own folder, apart from Files, so it stays when Files closes; Run in Terminal shows what it
// prints. One without its execute bit (as a download comes) gets Make Executable and Run instead. A file no app opens
// says so in the toast, with Open with… (O) as its button, and Install <the app> first where one is known (#3715: an
// .xlsx with no spreadsheet app is no app's, not the archive's file manager's). The install goes through Software
// (`nightdrive software install`: dnf asks for the password in the system's dialog), and the file opens after it.
AppConfirm {
    id: root
    required property var app
    readonly property string helper: app.helper.replace(/cli\.py$/, "launch.py")
    property var prog: null              // launch.py's {kind, executable, name, path} while the question shows
    visible: false
    cardWidth: 520                      // the three answers in one line where there is room

    function open(path) {
        if (opener.running) return
        opener.command = ["python3", "-I", helper, "open", path]
        opener.running = true
    }
    function ask(p) {
        prog = p
        const what = p.kind === "appimage" ? "an AppImage, a program" : p.kind === "script" ? "a script" : "a program"
        question = "Run “" + p.name + "”?"
        const trust = " Run only what you trust: a program can do anything you can."
        if (p.executable) {
            detail = "It is " + what + ". It runs in its own folder, apart from Files." + trust
            action = "Run"
            other = "Run in Terminal"
        } else {
            detail = "It is " + what + ", but not allowed to run yet: it has no execute permission, as a download "
                   + "comes. Make it executable and run it in its own folder?" + trust
            action = "Make Executable and Run"
            other = ""
        }
        glyph = "play"
        visible = true
    }
    function start(terminal) {
        const p = prog
        prog = null
        visible = false
        app.toList()
        if (!p) return
        const r = runner.createObject(root, { command: ["python3", "-I", helper, "run", p.path]
            .concat(terminal ? ["--terminal"] : []).concat(p.executable ? [] : ["--chmod"]), name: p.name })
        r.running = true
    }
    function noApp(n) {
        const acts = n.install ? [{ label: "Install " + n.install.name, run: () => install(n) }] : []
        acts.push({ label: "Open with…", run: () => app.openWith.start() })
        // Sticky with an install: reading which app it offers, and deciding, takes longer than a toast's few seconds
        app.toast.show("No app opens " + n.name + (n.type && n.type !== "Unknown" ? " (" + n.type + ")" : ""),
                       { actions: acts, sticky: !!n.install })
    }
    function install(n) {
        app.toast.show("Installing " + n.install.name + "…", { sticky: true })
        const r = installer.createObject(root, { command: [nightdrive, "software", "install", n.install.source,
                                                           n.install.id, "--json"], file: n })
        r.running = true
    }
    readonly property string nightdrive: Quickshell.env("HOME") + "/.local/bin/nightdrive"
    onAnswered: ok => { if (ok) start(false); else { prog = null; visible = false; app.toList() } }
    onOtherChosen: start(true)

    Process {
        id: opener
        stdout: StdioCollector { id: said }
        stderr: StdioCollector { id: why }
        onExited: code => {
            if (code !== 0) { root.app.say(why.text.trim().split("\n").pop() || "It didn't open", true); return }
            let d
            try { d = JSON.parse(said.text) } catch (e) { return }     // nothing printed: its app has it
            if (d.program) root.ask(d.program)
            else if (d.noapp) root.noApp(d.noapp)
        }
    }
    // Software's install: dnf may take a minute; the file opens in its new app when it is done
    readonly property Component installer: Component {
        Process {
            id: inst
            property var file
            stdout: StdioCollector { id: instOut }
            stderr: StdioCollector { id: instErr }
            onExited: code => {
                let d = {}
                try { d = JSON.parse(instOut.text) } catch (e) {}
                const name = inst.file.install.name
                if (code === 0 && d.state === "installed") { root.app.say("Installed " + name); root.open(inst.file.path) }
                else if (code === 0) root.app.say(name + " is still installing: open the file again when it is done")
                else root.app.say(instErr.text.trim().split("\n").pop() || "Couldn't install " + name, true)
                inst.destroy()
            }
        }
    }
    // One process a run: the helper exits as soon as the program has started (or couldn't), with the reason on stderr
    readonly property Component runner: Component {
        Process {
            id: r
            property string name
            stderr: StdioCollector { id: err }
            onExited: code => {
                root.app.say(code === 0 ? "Started " + r.name : err.text.trim().split("\n").pop() || "It didn't start", code !== 0)
                r.destroy()
            }
        }
    }
}
