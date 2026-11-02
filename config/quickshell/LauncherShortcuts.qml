import QtQuick
import Quickshell

// The launcher's keybindings, read from SHORTCUTS.md (the same file as the ⌘⇧K cheat sheet): the Keybindings level's
// rows and their key caps, and the shortcut shown on an app's or a launcher item's row. Apart from Launcher.qml as it is
// one source with its own parsing; the launcher reaches it as launcher.shortcuts.
Item {
    id: root
    required property var launcher

    property var keyList: []                  // [{ name, sub, keys, section }]
    property var keyIndex: ({})               // lower-case name → keys (shortcutFor)
    function reload() { keysProc.running = true }   // re-read SHORTCUTS.md: changes show up immediately
    Component.onCompleted: keysProc.running = true

    // Groups keybindings by section (sections in file order) and adds header rows
    function grouped(list) {
        const by = {}
        for (const it of list) (by[it.section] = by[it.section] || []).push(it)
        const out = []
        const seen = {}
        for (const k of keyList) {
            if (seen[k.section] || !by[k.section]) continue
            seen[k.section] = true
            out.push({ kind: "header", name: k.section })
            for (const it of by[k.section]) out.push(it)
        }
        return out
    }

    // A row's shortcut from SHORTCUTS.md ("" = none): apps and the launcher's own items, by name. Names that differ
    // between the launcher and SHORTCUTS.md: shortcutAliases.
    readonly property var shortcutAliases: ({ "kitty": "terminal", "firefox": "browser", "visual studio code": "vs code",
                                              "clipboard": "clipboard history", "emoji": "emoji picker", "keybindings": "this help" })
    function shortcutFor(it) {
        if (!it || !it.name || (it.kind !== "app" && it.kind !== "nav" && !it.keyHint)) return ""   // keyHint: an action with a key of its own
        if (launcher.level === "startup") return ""      // there the rows are switches, not apps to open
        // settings pages: "Notifications" is not the ⌘Esc panel, Apps › "Firefox" not Hyper B
        if (it.kind === "nav" && (launcher.parents[it.target] === "settings" || launcher.parents[it.target] === "appsettings")) return ""
        const n = it.name.toLowerCase()
        return keyIndex[n] || keyIndex[shortcutAliases[n] || ""] || ""
    }

    // A keybinding's text → [name, second line]: the row has no room for long texts. A note in parentheses at the end goes
    // on the second line ("Emoji picker (Enter pastes…)"), and so does what a long name has after its first ": " or "; "
    // outside parentheses ("Play/pause; starts Deck if…").
    function splitKeyText(text) {
        let name = text, sub = ""
        const p = name.match(/^(.*\S)\s*\(([^()]*)\)$/)
        if (p) { name = p[1]; sub = p[2] }
        if (name.length > 36) {
            let depth = 0
            for (let i = 0; i < name.length - 1; i++) {
                const c = name[i]
                if (c === "(") depth++
                else if (c === ")") depth--
                else if (depth === 0 && (c === ":" || c === ";") && name[i + 1] === " ") {
                    sub = name.slice(i + 2) + (sub ? " (" + sub + ")" : "")
                    name = name.slice(0, i)
                    break
                }
            }
        }
        return [name, sub.charAt(0).toUpperCase() + sub.slice(1)]
    }

    // A keybinding's keys → what Keybindings shows: [{ caps: ["⌘", "⇧", "S"] }, { text: "/" }, …]. Each combination goes
    // in key caps like a row's shortcut; between alternatives (" / ") and around a range (" … ") the separator stays
    // text, and so do the words after a combination's keys ("⌘ + drag", "Delete in Settings › Background").
    function keyParts(keys) {
        const key = (t, last) => /^[⌘⇧⌥⌃⌫A-Z0-9,.=\-]$/.test(t) || /^(Hyper|Ctrl|Alt|Shift|Cmd|Enter|Esc|Tab|Space|Delete|Home|End|F\d+)$/.test(t)
            || (last && /^(←\/→|[←→↑↓])$/.test(t))   // an arrow only at the end: "⌘ Space → Tools" is a path
        const out = []
        keys.replace(/← \/ →/g, "←/→").split(/ (\/|…) /).forEach((seg, i) => {
            if (i % 2) { out.push({ text: seg }); return }
            const t = seg.split(/\s+/).filter(x => x !== "")
            let n = 0
            while (n < t.length && key(t[n], n === t.length - 1)) n++
            if (n > 0) out.push({ caps: t.slice(0, n) })
            if (n < t.length) out.push({ text: t.slice(n).join(" ") })
        })
        return out
    }

    // SHORTCUTS.md → [{ name, sub, keys, section }], without the lines of optional parts that aren't installed (read again
    // when that list changes)
    Connections { target: Plugins; function onIdsChanged() { keysProc.running = true } }
    Sh {
        id: keysProc
        script: '"$HOME/.config/hypr/scripts/shortcuts"'
        onResult: text => {
            const out = []
            let section = ""
            for (const line of text.split("\n")) {
                const h = line.match(/^##\s+(.*)$/)
                if (h) { section = h[1]; continue }
                // Keys and description are split at the last run of two or more spaces
                const m = line.match(/^ {2}(\S.*) {2,}(\S.*)$/)
                if (!m || !section) continue
                const t = root.splitKeyText(m[2].trim())
                out.push({ keys: m[1].trim(), name: t[0], sub: t[1], section: section })
            }
            root.keyList = out
            // name → keys, for showing an app's or a launcher item's shortcut on its row: the row's name with and without
            // its parentheses, the names in them ("Music (Deck, Spotify)" → deck) and in its note ("Email (Thunderbird,
            // inbox)" → thunderbird). The first of alternatives ("⌘ ⇧ Enter / ⌘ ⇧ B").
            const idx = {}
            for (const k of out) {
                const keys = k.keys.split(" / ")[0]
                const inParens = (k.name.match(/\(([^()]*)\)/g) || []).map(p => p.slice(1, -1)).join(",")
                const names = [k.name, k.name.replace(/\s*\([^()]*\)/g, "")]
                for (const n of names.concat((inParens + "," + k.sub).split(/,\s*/))) {
                    const key = n.trim().toLowerCase()
                    if (key && idx[key] === undefined) idx[key] = keys
                }
            }
            root.keyIndex = idx
        }
    }
}
