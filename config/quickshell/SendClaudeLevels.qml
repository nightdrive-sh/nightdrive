import QtQuick
import Quickshell

// The launcher's Send to Claude (⌘⌃C): what was gathered from the window (SendCapture.qml, from hypr/scripts/send-capture),
// shown first, then New session and the Claude Code sessions on this desktop (Claude.qml: the ones that want you first,
// then the newest). Enter puts it at that session's prompt and doesn't send it (hypr/scripts/claude-send-paste): you
// write your question after it. Below them, the other things there were to send (Instead): Enter on one sends that
// instead. Only the target is here: another Send level would use SendCapture the same way.
Item {
    id: s
    property var launcher: null

    readonly property string pasteScript: Quickshell.env("HOME") + "/.config/hypr/scripts/claude-send-paste"
    readonly property var levels: ["sendclaude"]
    readonly property var titles: ({ sendclaude: "Send to Claude" })
    readonly property var parents: ({ sendclaude: "tools" })   // its row there gathers as ⌘⌃C does
    // How Claude gets what isn't text: the preview's last line
    readonly property var how: ({ files: "As paths: Claude reads them", image: "As a file: Claude looks at it",
                                  screenshot: "As a file: Claude looks at it" })

    SendCapture { id: capture }

    // As claude-send-paste picks it: the first file's folder (a folder itself when one is selected), else ~/Projects
    function newDir() {
        const f = capture.files
        if (capture.source !== "files" || !f.length) return "~/Projects"
        return capture.home(capture.meta.firstIsDir ? f[0] : capture.folderOf(f[0]))
    }
    function sessionRows() {
        return Claude.sessions.map(c => ({ kind: "scsess", name: c.topic || c.project, value: c.address, glyph: "bot",
                                           sub: c.project + " · " + (c.state === "working" ? "working" : "waiting for you"),
                                           summary: c.wants ? "wants you" : undefined }))
    }
    // The first place to send to, with the preview above it still in view
    function selectTarget() { Qt.callLater(() => { launcher.selectWhere(r => r.kind === "scsess" || r.kind === "scnew"); launcher.showTop() }) }

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "scsess") return "Enter: paste at its prompt, not sent"
        if (cur.kind === "scnew") return "Enter: open a session and paste at its prompt"
        if (cur.kind === "sendsrc") return "Enter: send this instead"
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level !== "sendclaude") return
        capture.load()
        selectTarget()
    }

    function items(level, q) {
        if (level !== "sendclaude") return []
        const sess = sessionRows()
        const fresh = { kind: "scnew", name: "New session", glyph: "plus", sub: "in " + newDir() }
        const other = capture.otherRows()
        if (launcher.query.trim() !== "")
            return { all: [fresh].concat(sess).map(r => ({ item: r, text: r.name, extra: r.sub })) }
        return capture.preview(how).concat([{ kind: "header", name: "To" }, fresh], sess,
                                           other.length ? [{ kind: "header", name: "Instead" }].concat(other) : [])
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "sendsrc" && l.level === "sendclaude") { capture.pick(it.value); selectTarget(); return true }
        if (it.kind !== "scsess" && it.kind !== "scnew") return false
        if (capture.kind === "") { l.shakeNow(); return true }
        l.open = false
        Quickshell.execDetached([pasteScript, capture.dir, capture.kind, it.kind === "scnew" ? "new" : it.value])
        return true
    }
}
