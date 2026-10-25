import QtQuick
import Quickshell
import Quickshell.Hyprland

// The launcher's Clipboard (cliphist's history), and Tools › Emoji and Snippets (add, edit with Ctrl+Enter, remove with
// ⌘⌫). Enter pastes the row into the window that had the focus, Shift+Enter only copies it. Tools and Screenshot
// themselves are static lists in Launcher.qml (the root search finds their rows).
// Launcher.qml asks it like DefaultAppsLevels (levels, titles, parents, items, activate, footer, entered), and also
// ctrlActivate (Ctrl+Enter) and deleteSelected (⌘⌫, Delete). ⌘⇧V over a text field opens Clipboard as its picker (ClipPicker).
Item {
    id: t
    property var launcher: null

    property var clipItems: []                // Clipboard: cliphist history
    property bool clipLoaded: false
    property var emojiList: []                // Emoji: [{ ch, name, kw }] (data/emoji.tsv, CLDR names in English and Finnish)
    property bool emojiLoaded: false
    property var snipList: []                 // Snippets: [{ trigger, text }] (hypr/scripts/snippets list)
    property bool snipLoaded: false
    property string snipAuto: ""              // auto-expand: on | off | no-access (snippets status)
    property string snipTrigger: ""           // Snippets › Add / edit: the trigger being given a text
    property int wsId: 0                      // Rename current space: the workspace the launcher was opened over

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    readonly property var levels: ["clipboard", "emoji", "snippets", "snipkey", "sniptext", "wsname"]
    readonly property var inputs: ["snipkey", "sniptext", "wsname"]   // text fields: ⌘⇧V pastes into them (ClipPicker)
    readonly property var titles: ({ clipboard: picker.active ? "Paste into the field" : "Clipboard", emoji: "Tools › Emoji", snippets: "Tools › Snippets", snipkey: "Snippets › Trigger",
                                     sniptext: "Snippets › “" + snipTrigger + "”", wsname: "Rename space " + wsId })
    readonly property var parents: ({ emoji: "tools", snippets: "tools", snipkey: "snippets", sniptext: "snippets" })
    readonly property bool armsItself: true   // a snippet's armKey is for ⌘⌫ (deleteSelected), not for Shift+Enter

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (level === "clipboard" && picker.active) return "Enter: paste into the field  ·  Esc: back to it"
        if (level === "clipboard") return "Enter: paste  ·  Shift+Enter: copy only"
        if (level === "emoji") return "Enter: paste  ·  Shift+Enter: copy only  ·  search in English or Finnish"
        if (level === "snippets" && cur.kind === "snippet") return "Enter: paste  ·  Shift+Enter: copy only  ·  Ctrl+Enter: edit  ·  Cmd+Backspace: remove"
        if (level === "snippets" && cur.kind === "snipauto") return snipAuto === "off" ? "Enter: turn on in a terminal (asks for your password once)" : "Enter: turn off in a terminal"
        if (level === "snipkey" && query.trim() !== "") return "Enter: continue to the text"
        if (level === "sniptext") return query !== "" ? "Enter: save  ·  Shift+Enter: new line" : "Shift+Enter: new line"
        if (level === "wsname") return "Enter: rename  ·  Esc: back"
        return ""
    }
    function opened() { picker.reset() }
    function entered(level) {
        if (level === "emoji" && !emojiLoaded) emojiProc.running = true
        if (level === "clipboard") { clipLoaded = false; clipProc.running = true }
        if (level === "snippets") snipProc.running = true
        if (level === "wsname") {
            const m = Hyprland.focusedMonitor
            wsId = m && m.activeWorkspace ? m.activeWorkspace.id : 0
        }
    }

    function items(level, q) {
        const l = launcher
        if (level === "clipboard") {
            if (!clipLoaded) return [{ kind: "hint", name: "Loading clipboard history…" }]
            if (clipItems.length === 0) return [{ kind: "hint", name: "Clipboard history is empty" }]
            return { all: clipItems.map(c => ({ item: c, text: c.name })) }
        }
        if (level === "emoji") {
            if (!emojiLoaded) return [{ kind: "hint", name: "Loading emoji…" }]
            // short: thousands of short names, so no fuzzy matching (letters in order would hit too many) and the shortest first
            return { short: true, all: emojiList.map(e => ({ item: { kind: "emoji", name: e.name, emoji: e.ch }, text: e.name, extra: e.kw })) }
        }
        if (level === "snippets") {
            if (!snipLoaded) return l.hint("Loading snippets…")
            const auto = { kind: "snipauto", name: "Auto-expand", glyph: "zap",
                           summary: snipAuto === "on" ? "on" : snipAuto === "no-access" ? "no keyboard access: log out and in" : "off" }
            const add = { kind: "nav", name: "Add snippet", glyph: "plus", target: "snipkey" }
            // A text of several lines: the first is the name, the rest under it as they are, in the same font (up to subMax)
            const rows = snipList.map(s => ({ kind: "snippet", name: s.text.split("\n")[0], sub: s.text.split("\n").slice(1).join("\n"),
                                               subMax: 8, subPlain: true, summary: s.trigger, glyph: "text-cursor-input",
                                               trigger: s.trigger, text: s.text, armKey: "snipdel:" + s.trigger,
                                               armHint: "⌘⌫ again to remove" }))
            if (q === "") return [auto, { kind: "header", name: "Snippets" }, add].concat(rows)
            return { all: rows.map(r => ({ item: r, text: r.trigger, extra: r.text })) }
        }
        if (level === "snipkey") {
            const typed = l.query.trim()
            if (typed === "") return l.hint("Type the trigger, e.g. @@ or f#")
            const old = snipList.find(s => s.trigger === typed)
            return [{ kind: "snipk", name: "Trigger: " + typed, summary: old ? "replaces “" + oneLine(old.text) + "”" : "next: text",
                      glyph: "arrow-right", value: typed }]
        }
        if (level === "sniptext") {
            if (l.query === "") return l.hint("Type the text that “" + snipTrigger + "” expands to")
            return [{ kind: "snipadd", name: "Save “" + snipTrigger + "”", summary: oneLine(l.query), glyph: "text-cursor-input",
                      value: l.query.replace(/↵/g, "\n") }]
        }
        // Experimental: Hyprland's own name, so it's gone when the workspace empties (the bar shows the number again)
        if (level === "wsname") {
            const typed = l.query.trim()
            if (typed === "") return [{ kind: "wsrename", name: "Show the number " + wsId, glyph: "hash", value: "" }]
            return [{ kind: "wsrename", name: "Name it “" + typed + "”", glyph: "pencil", value: typed }]
        }
        return []
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "clip") { picker.active ? picker.pick(it) : clipPick(it, true); return true }
        if (it.kind === "emoji") { emojiPick(it, true); return true }
        if (it.kind === "snippet") { snipPick(it, true); return true }
        if (it.kind === "snipauto") {
            l.open = false
            Quickshell.execDetached(l.term('"$HOME/.local/bin/nightdrive" snippets ' + (snipAuto === "off" ? "enable" : "disable")))
            return true
        }
        if (it.kind === "wsrename") {
            l.open = false
            const name = it.value || String(wsId)
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.workspace.rename({ workspace = " + wsId + ", name = " + JSON.stringify(name) + " })"])
            return true
        }
        if (it.kind === "snipk") { snipTrigger = it.value; l.go("sniptext"); return true }
        if (it.kind === "snipadd") {
            snipList = snipList.filter(s => s.trigger !== snipTrigger).concat([{ trigger: snipTrigger, text: it.value }])
                               .sort((a, b) => a.trigger.localeCompare(b.trigger))
            Quickshell.execDetached([scripts + "/snippets", "set", snipTrigger, it.value])
            const tr = snipTrigger
            l.go("snippets")
            Qt.callLater(() => l.selectWhere(r => r.kind === "snippet" && r.trigger === tr))
            return true
        }
        return false
    }
    function shiftActivate(it) {
        if (launcher.level === "sniptext") { launcher.insertText("↵"); return }   // a new line in the text
        if (it.kind === "clip" && picker.active) picker.pick(it)   // the field's picker: as Enter
        else if (it.kind === "clip") clipPick(it, false)
        else if (it.kind === "emoji") emojiPick(it, false)
        else if (it.kind === "snippet") snipPick(it, false)
        else launcher.activate(it)    // other rows (Add snippet, Auto-expand): as Enter
    }
    // Ctrl+Enter on a snippet: its text in the input, to change it
    function ctrlActivate(it) {
        if (it.kind !== "snippet") return false
        snipTrigger = it.trigger
        launcher.search("sniptext", oneLine(it.text))
        return true
    }
    // ⌘⌫ (IPC deleteSelected) or Delete in Snippets with an empty search: a second press removes the selected snippet
    function deleteSelected() {
        const l = launcher
        if (l.level !== "snippets" || l.query !== "") return false
        const it = l.results[l.selIndex]
        if (!it || it.kind !== "snippet") { l.shakeNow(); return true }
        if (!arm(it.armKey)) return true
        snipList = snipList.filter(s => s.trigger !== it.trigger)
        if (l.selIndex >= l.results.length) l.select(l.results.length - 1)
        Quickshell.execDetached([scripts + "/snippets", "remove", it.trigger])
        return true
    }
    // The search field has one line, so a snippet's line breaks show (and are typed with Shift+Enter) as ↵
    function oneLine(text) { return text.replace(/\r?\n/g, "↵") }
    function arm(key) {
        if (launcher.armed !== key) { launcher.armed = key; disarmTimer.restart(); return false }
        launcher.armed = ""
        return true
    }
    ClipPicker { id: picker; launcher: t.launcher }
    property alias picker: picker
    Timer { id: disarmTimer; interval: 4000; onTriggered: if (t.launcher) t.launcher.armed = "" }

    // Pastes into the active window by sending Shift+Insert (same as ⌘V; kitty etc. treat it as a clipboard paste).
    // The launcher closes first, so the short sleep lets focus return to the previous window.
    readonly property string pasteCmd: 'sleep 0.2; hyprctl dispatch \'hl.dsp.send_shortcut({ mods = "SHIFT", key = "Insert" })\' >/dev/null'
    // Clipboard: copies the selection to the clipboard and (paste) pastes it into the active window
    function clipPick(it, paste) {
        launcher.open = false
        Quickshell.execDetached(["bash", "-c",
            'cliphist decode "$1" | wl-copy; [ "$2" = 1 ] && { ' + pasteCmd + '; }',
            "_", it.id, paste ? "1" : "0"])
    }
    // Emoji: copies to the clipboard and (paste) pastes into the active window like clipPick; copy-only shows a notification
    function emojiPick(it, paste) {
        launcher.open = false
        Quickshell.execDetached(["bash", "-c",
            'printf %s "$1" | wl-copy; if [ "$3" = 1 ]; then ' + pasteCmd + '; else notify-send -e -a Emoji -t 1500 "Copied $1" "$2"; fi',
            "_", it.emoji, it.name, paste ? "1" : "0"])
    }
    // Snippets: pasted like an emoji (also works with auto-expand off)
    function snipPick(it, paste) {
        launcher.open = false
        Quickshell.execDetached(["bash", "-c",
            'printf %s "$1" | wl-copy; if [ "$3" = 1 ]; then ' + pasteCmd + '; else notify-send -a Snippets -t 1500 "Copied" "$2"; fi',
            "_", it.text, it.trigger, paste ? "1" : "0"])
    }

    // Clipboard: cliphist list ("<id>\t<preview>", newest first). Sensitive entries (passwords) don't end up in history.
    Sh {
        id: clipProc
        command: ["bash", "-c", "cliphist list 2>/dev/null | head -300"]
        onResult: text => {
            const out = []
            for (const line of text.split("\n")) {
                const i = line.indexOf("\t")
                if (i < 0) continue
                const raw = line.slice(i + 1)
                const binary = /^\[\[ binary data/.test(raw)
                out.push({ kind: "clip", id: line.slice(0, i), name: raw.replace(/\s+/g, " ").trim().slice(0, 200) || "(blank)",
                           glyph: binary ? "image" : "clipboard" })
            }
            t.clipItems = out
            t.clipLoaded = true
        }
    }
    // Snippets: the list and whether auto-expand is on, read again each time the level opens (a change in the file shows up)
    Sh {
        id: snipProc
        script: 's="$HOME/.config/hypr/scripts/snippets"; "$s" status; "$s" list'
        onResult: text => {
            const i = text.indexOf("\n")
            t.snipAuto = text.slice(0, i).trim()
            try { t.snipList = JSON.parse(text.slice(i + 1)) } catch (e) { t.snipList = [] }
            t.snipLoaded = true
        }
    }
    // Emoji: data/emoji.tsv ("char<TAB>name<TAB>keywords", generated from CLDR annotations)
    Sh {
        id: emojiProc
        command: ["cat", Quickshell.env("HOME") + "/.config/quickshell/data/emoji.tsv"]
        onResult: text => {
            const out = []
            for (const line of text.split("\n")) {
                const f = line.split("\t")
                if (f.length >= 2) out.push({ ch: f[0], name: f[1], kw: f[2] || "" })
            }
            t.emojiList = out
            t.emojiLoaded = true
        }
    }
}
