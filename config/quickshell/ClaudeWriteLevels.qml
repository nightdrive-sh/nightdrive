import QtQuick
import Quickshell
import Quickshell.Wayland

// The launcher's Settings › Claude writes (⌘⇧C, ClaudeWrite.qml): the model, whether it works in terminals, your own
// instructions, sent with every request, and apps of your own that it leaves out (Not in these apps: an open app is
// added with Enter, ⌘⌫ twice lets one back in; password managers and the like are always left out). Instructions are
// lines of ~/.config/nightdrive/claude-write.txt: type one and Enter adds it, an example is turned on with Enter, ⌘⌫
// twice turns one off; the file opens in the text editor too.
// hypr/scripts/claude-write reads and writes them all (set, instructions, add, remove, edit, block, unblock, always).
// The Claude menu's Claude writes settings… button opens this level.
Item {
    id: w
    property var launcher: null

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/claude-write"
    readonly property var inputs: ["claudewriteinstr"]   // text fields: ⌘⇧V pastes into them (ClipPicker)
    readonly property var levels: ["claudewrite", "claudewritemodel", "claudewriteinstr", "claudewriteapps"]
    readonly property var titles: ({ claudewrite: "Settings › Claude writes", claudewritemodel: "Claude writes › Model",
                                     claudewriteinstr: "Claude writes › Your instructions", claudewriteapps: "Claude writes › Not in these apps" })
    readonly property var parents: ({ claudewrite: "settings", claudewritemodel: "claudewrite", claudewriteinstr: "claudewrite",
                                      claudewriteapps: "claudewrite" })
    readonly property bool armsItself: true   // the rows' armKey is for ⌘⌫ (deleteSelected), not for Enter

    readonly property var models: [["sonnet", "Sonnet", "Fast, and good for most text"], ["opus", "Opus", "The best writing, slower"],
                                   ["haiku", "Haiku", "The fastest"]]
    property string model: "sonnet"
    property bool terminals: false
    property var blocked: []                 // your own left-out apps: window classes
    property var on: []                      // the instructions in use
    property var examples: []                // the template's, still commented out
    property bool loaded: false

    Sh {
        id: settingsProc
        script: 'cat "$HOME/.local/state/nightdrive/claude-write.json" 2>/dev/null'
        onResult: text => {
            let v = {}
            try { v = JSON.parse(text) || {} } catch (e) {}
            w.model = v.model || "sonnet"
            w.terminals = v.terminals === true
            w.blocked = v.blocked || []
        }
    }
    Sh {
        id: instrProc
        command: [w.script, "instructions"]
        onResult: text => {
            let v = {}
            try { v = JSON.parse(text) || {} } catch (e) {}
            w.on = v.on || []; w.examples = v.examples || []; w.loaded = true
        }
    }

    function modelName(id) { const f = models.find(m => m[0] === id); return f ? f[1] : id }
    // Changes show at once; the script writes them, and the list is read again after it
    function change(what, line) {
        if (what === "add") { on = on.concat([line]); examples = examples.filter(e => e !== line) }
        else on = on.filter(l => l !== line)
        Quickshell.execDetached(["bash", "-c", '"$1" "$2" "$3"', "_", script, what, line])
        reread.restart()
    }
    Timer { id: reread; interval: 300; onTriggered: instrProc.running = true }

    // An app by its window class: the .desktop entry's name and icon (as SharePicker finds them), else the class itself
    function appOf(cls) {
        const c = cls.toLowerCase()
        const all = DesktopEntries.applications.values
        const e = all.find(d => (d.startupClass || "").toLowerCase() === c)
               || all.find(d => d.id.replace(/\.desktop$/, "").toLowerCase() === c)
               || DesktopEntries.heuristicLookup(cls)
        return { name: e ? e.name : cls, icon: e ? e.icon : "" }
    }
    // The apps that are always left out (the script's regex): not offered as open apps
    property var always: null
    Sh {
        id: alwaysProc
        command: [w.script, "always"]
        onResult: text => { try { w.always = new RegExp(text.trim(), "i") } catch (e) { w.always = null } }
    }
    function block(what, cls) {
        blocked = what === "block" ? blocked.filter(b => b !== cls).concat([cls]) : blocked.filter(b => b !== cls)
        Quickshell.execDetached([script, what, cls])
    }

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "cwterm") return "Enter: on/off"
        if (cur.kind === "cwon") return "Cmd+Backspace: turn off"
        if (cur.kind === "cwex") return "Enter: use it"
        if (cur.kind === "cwadd") return "Enter: add"
        if (cur.kind === "cwblocked") return "Cmd+Backspace: let it back in"
        if (cur.kind === "cwapp") return "Enter: leave it out"
        if (level === "claudewriteinstr" && query === "") return "Type an instruction to add it"
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level === "settings" || level === "claudewrite" || level === "claudewritemodel" || level === "claudewriteapps") settingsProc.running = true
        if (level === "claudewriteapps" && always === null) alwaysProc.running = true
        if (level === "settings" || level === "claudewrite" || level === "claudewriteinstr") instrProc.running = true
        if (level === "claudewritemodel") Qt.callLater(() => launcher.selectWhere(r => r.value === w.model))
    }

    function items(level, q) {
        const l = launcher
        if (level === "claudewrite") {
            return [{ kind: "nav", name: "Model", glyph: "cpu", target: "claudewritemodel", summary: modelName(model) },
                    { kind: "nav", name: "Your instructions", glyph: "pen-line", target: "claudewriteinstr",
                      summary: on.length === 0 ? "none" : on.length + " in use" },
                    { kind: "cwterm", name: "In terminals", glyph: "terminal", switchOn: terminals,
                      sub: "Select what you want done: the command goes on the command line, Enter runs it" },
                    { kind: "nav", name: "Not in these apps", glyph: "eye-off", target: "claudewriteapps",
                      summary: blocked.length === 0 ? "none" : blocked.length + (blocked.length === 1 ? " app" : " apps") },
                    { kind: "note", name: "Select text in any app and press ⌘⇧C: Claude writes it out" }]
        }
        if (level === "claudewritemodel") {
            return models.map(m => ({ kind: "cwmodel", value: m[0], name: m[1], sub: m[2], glyph: m[0] === model ? "check" : "cpu",
                                      summary: m[0] === model ? "current" : (m[0] === "sonnet" ? "default" : undefined) }))
        }
        if (level === "claudewriteinstr") {
            if (!loaded) return l.hint("Loading…")
            const rows = on.map(t => ({ kind: "cwon", name: t, glyph: "check", value: t, armKey: "cwoff:" + t, armHint: "⌘⌫ again to turn off" }))
            const ex = examples.map(t => ({ kind: "cwex", name: t, glyph: "plus", value: t }))
            const edit = { kind: "cwedit", name: "Open in text editor", glyph: "external-link" }
            const typed = l.query.trim()
            if (typed !== "") {
                const add = on.indexOf(typed) < 0 ? [{ kind: "cwadd", name: "Add “" + typed + "”", glyph: "plus", value: typed }] : []
                return { all: add.concat(rows, ex).map(r => ({ item: r, text: r.kind === "cwadd" ? typed : r.name })) }
            }
            return [{ kind: "header", name: "In use" }]
                .concat(rows.length ? rows : [{ kind: "note", name: "None yet: type one, or turn on an example" }],
                        ex.length ? [{ kind: "header", name: "Examples" }].concat(ex) : [], [{ kind: "header", name: "File" }, edit])
        }
        if (level === "claudewriteapps") {
            const lower = blocked.map(b => b.toLowerCase())
            const rows = blocked.map(c => { const a = appOf(c)
                return { kind: "cwblocked", name: a.name, sub: c, iconFile: a.icon || undefined, glyph: a.icon ? undefined : "app-window",
                         value: c, armKey: "cwunblock:" + c, armHint: "⌘⌫ again to let it back in" } })
            // The open apps' windows, one row per app (not Quickshell's own: the launcher, Mail)
            const seen = {}
            const open = ToplevelManager.toplevels.values.map(t => t.appId || "")
                .filter(c => c && c !== "org.quickshell" && lower.indexOf(c.toLowerCase()) < 0 && !(always && always.test(c))
                           && !seen[c] && (seen[c] = true))
                .map(c => { const a = appOf(c)
                    return { kind: "cwapp", name: a.name, sub: c, iconFile: a.icon || undefined, glyph: a.icon ? undefined : "app-window", value: c } })
                .sort((a, b) => a.name.localeCompare(b.name))
            const alwaysNote = { kind: "note", name: "Password managers and private windows are always left out" }
            if (l.query.trim() !== "") return { all: rows.concat(open).map(r => ({ item: r, text: r.name, extra: r.value })) }
            return [{ kind: "header", name: "Left out" }]
                .concat(rows.length ? rows : [{ kind: "note", name: "None of your own yet" }],
                        open.length ? [{ kind: "header", name: "Open apps" }].concat(open) : [], [alwaysNote])
        }
        return []
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "cwterm") {
            l.keepSelection()
            terminals = !terminals
            Quickshell.execDetached([script, "set", "terminals", terminals ? "true" : "false"])
            return true
        }
        if (it.kind === "cwmodel") {
            model = it.value
            Quickshell.execDetached([script, "set", "model", it.value])
            l.go("claudewrite")
            return true
        }
        if (it.kind === "cwadd" || it.kind === "cwex") {
            change("add", it.value)
            l.search("claudewriteinstr", "")
            Qt.callLater(() => l.selectWhere(r => r.kind === "cwon" && r.value === it.value))
            return true
        }
        if (it.kind === "cwon" || it.kind === "cwblocked") { l.shakeNow(); return true }   // ⌘⌫ does it: Enter does nothing by mistake
        if (it.kind === "cwapp") {
            block("block", it.value)
            l.search("claudewriteapps", "")
            Qt.callLater(() => l.selectWhere(r => r.kind === "cwblocked" && r.value === it.value))
            return true
        }
        if (it.kind === "cwedit") {
            l.open = false
            Quickshell.execDetached([script, "edit"])
            return true
        }
        return false
    }
    // ⌘⌫ (IPC deleteSelected) or Delete with an empty search: a second press turns the selected instruction off, or lets
    // the selected app back in
    function deleteSelected() {
        const l = launcher
        if ((l.level !== "claudewriteinstr" && l.level !== "claudewriteapps") || l.query !== "") return false
        const it = l.results[l.selIndex]
        if (!it || (it.kind !== "cwon" && it.kind !== "cwblocked")) { l.shakeNow(); return true }
        if (l.armed !== it.armKey) { l.armed = it.armKey; disarmTimer.restart(); return true }
        l.armed = ""
        if (it.kind === "cwon") change("remove", it.value)
        else block("unblock", it.value)
        return true
    }
    Timer { id: disarmTimer; interval: 4000; onTriggered: if (w.launcher) w.launcher.armed = "" }
}
