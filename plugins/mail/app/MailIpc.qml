import QtQuick
import Quickshell.Io

// `nightmail sync` asks for a reload once new mail is indexed; `nightmail new` opens an empty message.
// Apart from shell.qml: what `nightmail` and the notifications ask of the open Mail, over IPC.
// The handler takes only what it can pass over IPC, so what it acts on lives on this object around it.
QtObject {
    id: root
    required property var win
    required property var writer        // Writing.qml
    required property var fetchWatch
    readonly property IpcHandler handler: IpcHandler {
        target: "mail"
        function refresh(): void { root.win.reload(true) }
        // A fetch has started (`nightmail fetching`, from its fetch())
        function fetching(): void { root.fetchWatch.check() }
        function compose(): void { root.win.compose("new") }
        // Settings › Apps › Mail (`nightmail settings`)
        function openSettings(): void { root.win.showSettings = true }
        // "shown" when the window was hidden (see visible), for `nightmail`: the kit's focus() wouldn't find it and
        // would start Mail again, losing the message being written.
        function reveal(): string { if (root.win.visible) return ""; root.win.visible = true; return "shown" }
        // A mailto: link (`nightmail mailto:…`, when Mail is the email app: launcher › Settings › Apps › Default apps)
        function mailto(url: string): void { root.win.compose("new", null, root.win.mailtoFields(url)) }
        // A notification's click and Reply button (lib/notify.py, through `nightmail show` and `reply`).
        // (Not "show": `qs ipc call` takes that word for its own command.)
        function openMessage(id: string): void { root.win.openMessage(id, null) }
        function replyTo(id: string): void { root.win.openMessage(id, () => root.win.compose("all")) }
        function claudeReply(id: string): void { root.win.openMessage(id, () => root.win.compose("claude")) }
        // The Claude writes card's Enter and Esc (`nightmail claude-reply`, `claude-cancel`)
        function claudeAnswer(json: string): void { const a = JSON.parse(json); root.writer.composer.answered(a.gen, a.text, a.read) }
        function claudeCancel(gen: string): void { if (parseInt(gen) === root.writer.composer.gen) root.writer.composer.bodyEdit.forceActiveFocus() }
    }
}
