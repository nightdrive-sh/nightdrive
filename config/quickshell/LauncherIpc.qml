import QtQuick
import Quickshell
import Quickshell.Io

// `qs ipc call launcher …`: the launcher's keys bound in Hyprland (open, levels, ⌘⌫, ⌥⌫, ⌘Q, Ask Claude's ⌘Enter) and the
// calls tests use (rows, pick, detailTab). Apart from Launcher.qml so what other programs may call is in one place.
// The launcher is a property of the Item around the handler: IpcHandler offers its own properties over IPC too.
Item {
    id: root
    required property var launcher

    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.open = !launcher.open }
        function close(): void { launcher.open = false }
        // openLevel apps | keys | root: opens a sublevel directly
        // ⌘⇧V (clipboard) over a text field (a level in a Levels file's `inputs`) opens Clipboard as a picker for it
        function openLevel(level: string): void { if (level === "clipboard" && launcher.levels.tools.picker.begin()) return; launcher.open = true; launcher.go(level); launcher.keyLevel = level }
        function setQuery(text: string): void { launcher.field.text = text }
        // askClaude background|terminal|key: sends the text typed in the launcher to Ask Claude's toast (AskClaudeLevels.qml):
        // ⌘⌥Enter (hypr/scripts/ask-claude), ⌘Enter (key: the terminal on the Ask Claude row, where Enter asks), ⌘⌃Enter
        // in a terminal (hypr/scripts/terminal-or-claude). Over the toast (the launcher closed) ⌘Enter and ⌘⌃Enter go on
        // with its conversation in a terminal. Returns "ok", or "" when there's nothing to ask and the key does what it
        // does elsewhere.
        function askClaude(how: string): string {
            if (!launcher.open) {
                if (!AskClaudeSession.toastViewing || how === "background") return ""
                launcher.levels.ask.terminal(AskClaudeSession.draft, true)
                return "ok"
            }
            if (how === "key") how = (launcher.results[launcher.selIndex] || {}).kind === "askclaude" ? "terminal" : "background"
            if (["root", "apps"].indexOf(launcher.level) < 0) return ""
            if (how === "terminal") return launcher.query.trim() === "" ? "" : (launcher.levels.ask.terminal(launcher.query, false), "ok")
            return launcher.levels.ask.submit(launcher.query) ? "ok" : ""
        }
        // rows: the open level's title, footer, selected index and rows as JSON, primitive fields only (automated testing)
        function rows(): string {
            const plain = r => { const o = {}; for (const k in r) if (r[k] === null || typeof r[k] !== "object" && typeof r[k] !== "function") o[k] = r[k]; return o }
            return JSON.stringify({ level: launcher.level, title: launcher.titles[launcher.level] || "", footer: launcher.footer, sel: launcher.selIndex,
                                    rows: launcher.results.map(plain) })
        }
        // pick <index>: selects a row like Enter (automated testing)
        function pick(index: int): void { const r = launcher.results[index]; if (r) launcher.activate(r); else launcher.shakeNow() }
        // detailTab: Tab in a package's or plugin's details, e.g. a plugin's on/off switch (automated testing)
        function detailTab(): void { if (launcher.detail !== null) launcher.detailCard.switchSource(); else launcher.shakeNow() }
        // ⌘⌫ (bindings.lua): in Background removes your own wallpaper, elsewhere deletes the query to the cursor's left (like macOS)
        function deleteSelected(): void {
            if (!launcher.open) { if (AskClaudeSession.toastViewing) AskClaudeSession.deleteBackRequested(false); return }
            if (launcher.extDelete()) {}
            else launcher.deleteBack(false)
        }
        // ⌘Q (hypr/scripts/quit-app asks first): with the launcher open quits the selected app if it's running, otherwise
        // shakes. Returns "ok" when the launcher is open, so the window under it is never quit; "" when it's closed.
        function quitSelected(): string {
            if (!launcher.open) return ""
            const re = launcher.selApp ? launcher.appState.appClassRe(launcher.selApp) : ""
            if (re === "") { launcher.shakeNow(); return "ok" }
            Quickshell.execDetached([launcher.scripts + "/quit-app", "--class", re])
            launcher.appState.quitting = Object.assign({}, launcher.appState.quitting, { [re]: Date.now() })
            launcher.appState.refreshWindows()
            return "ok"
        }
        // ⌥⌫: deletes the word to the cursor's left (Hyprland's binding takes the key, so the launcher does it here)
        function deleteWord(): void {
            if (launcher.open) launcher.deleteBack(true)
            else if (AskClaudeSession.toastViewing) AskClaudeSession.deleteBackRequested(true)
        }
        function stepUp(): void { launcher.detail !== null ? launcher.detailCard.scroll(-launcher.rowHeight) : launcher.step(-1) }
        function stepDown(): void { launcher.detail !== null ? launcher.detailCard.scroll(launcher.rowHeight) : launcher.topFocused ? (launcher.topFocused = false) : launcher.step(1) }
        function back(): void { launcher.back() }
    }
}
