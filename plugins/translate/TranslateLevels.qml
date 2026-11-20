import QtQuick
import Quickshell
import qs

// Translate's part of the launcher (plugin-parts lists it while the plugin is on): Tools › Translate, where what is
// typed comes back in the pair's other language a moment after typing stops, and Enter copies it. The footer's Tab
// shows the mode, and Tab goes round the three: Detect language (the guess, shown once made), then each direction,
// which stays until Tab changes it (also over closing the launcher: someone who wants one direction has it). Translate › Engine
// (Shift+Tab: no row of its own, so the page is only the translation) picks what translates: the installed ones are used at once, the others install in a terminal. ⌘Enter translates what
// is typed with Claude instead, whatever the engine: the answer shows in the same rows.
// bin/translate does the work (`translate --json`, `translate engines --json`); this only shows it.
// Launcher.qml asks it like its own level files (levels, titles, parents, items, activate, footer, entered).
Item {
    id: t
    property var launcher: null               // Launcher.qml sets it once the file is loaded

    readonly property string cmdPath: Qt.resolvedUrl("bin/translate").toString().replace(/^file:\/\//, "")
    readonly property int typingPause: 350    // ms after the last key before translating

    property var engines: []                  // [{ id, name, summary, size, installed, current, live, online }]
    property var langs: []                    // the pair's codes, e.g. ["fi", "en"] (settings.json: `translate langs`)
    property var langNames: []                // and names, ["Finnish", "English"]
    property var result: null                 // { key, translation, alternatives, from, to, from_name, to_name } | { key, error }
    property string into: ""                  // Tab: the language to translate into; "" = detect the text's language
    property string via: ""                   // ⌘Enter: the engine asked for this once ("claude"), instead of the one in use
    readonly property var engine: engines.find(e => e.current) || null
    readonly property var claude: engines.find(e => e.id === "claude" && e.installed) || null
    readonly property bool live: via === "" && !!engine && engine.live   // translates while typing

    // A row in Tools (Launcher.qml's statics.tools), found by the root search too
    readonly property var toolItems: [{ kind: "nav", name: "Translate", glyph: "book-a", target: "translate",
                                        extra: "translation language dictionary käännä kääntäjä sanakirja" }]
    readonly property var levels: ["translate", "trengines"]
    readonly property var titles: ({ translate: "Tools › Translate", trengines: "Translate › Engine" })
    readonly property var parents: ({ translate: "tools", trengines: "translate" })
    readonly property var inputs: ["translate"]   // a text field, not a search: ⌘⇧V pastes from the clipboard history

    // The mode, as Tab's part of every footer here; the rows put their own keys before it
    readonly property string arrow: direction.length ? langNames[direction[0]] + " → " + langNames[direction[1]] : ""
    readonly property bool guessShown: !!result && !result.error && result.key === key()
    readonly property string tabKey: langs.length !== 2 ? ""
        : into !== "" ? "Tab: " + arrow : "Tab: detect language" + (guessShown ? " (" + arrow + ")" : "")
    function keys(own) { return [own, tabKey].filter(k => k !== "").join("  ·  ") }
    readonly property string engineKey: "Shift+Tab: change engine" + (engine ? " (" + engine.name + ")" : "")
    // With nothing typed there are no rows: the footer is the page's two choices
    function footer(level, query) { return level === "translate" ? keys("") + "  ·  " + engineKey : "" }
    function opened() { listProc.running = true }
    function entered(level) {
        listProc.running = true
        if (level === "translate") { result = null; via = "" }
    }
    function shiftActivate(it) {}

    function typed() { return launcher.query.trim() }
    function key() { return typed() + "\n" + into + "\n" + via }   // what a result belongs to: the text, the direction and the engine asked

    // The direction in effect, as [from, to] indexes into the pair: Tab's, else the shown result's guess, else the pair's order
    readonly property var direction: {
        if (langs.length !== 2) return []
        const to = into !== "" ? into : (guessShown ? result.to : langs[1])
        return langs[1] === to ? [0, 1] : [1, 0]
    }
    // Tab: detect → the pair's first into its second → the other way → detect, translating what is typed again.
    // Shift+Tab opens the engines
    function tabPressed(dir) {
        if (launcher.level !== "translate") return false
        if (dir < 0) { launcher.go("trengines"); return true }
        if (langs.length !== 2) return false
        into = into === "" ? langs[1] : into === langs[1] ? langs[0] : ""
        if (typed() !== "" && (live || via !== "")) { pause.stop(); run() }
        return true
    }

    function items(level, q) {
        const hint = launcher.hint
        if (level === "trengines") {
            if (engines.length === 0) return hint("Loading…")
            return engines.map(e => {
                const about = [e.summary, e.size].filter(x => x).join(" · ")
                if (e.installed) return { kind: "truse", name: e.name, sub: about, glyph: e.online ? "cloud" : "hard-drive",
                                          id: e.id, summary: e.current ? "in use" : undefined,
                                          trailGlyph: e.current ? "check" : undefined, footer: "Enter: translate with this" }
                // Its installer may ask for the password and shows the download: a terminal, as plugins install
                const cmd = shq(cmdPath)
                return { kind: "action", name: e.name, sub: about, glyph: "download", summary: "not installed",
                         footer: "Enter: install in a terminal",
                         cmd: launcher.term(cmd + ' engine install "$1" && ' + cmd + ' engine use "$1"', e.id) }
            })
        }
        if (level !== "translate") return []
        // Only where there is nothing to translate with: otherwise the engines are behind Shift+Tab
        const engineRow = { kind: "nav", name: "Choose an engine", glyph: "cpu", target: "trengines", footer: "Enter: open" }
        if (typed() === "") return engine && engine.installed ? [] : [engineRow]
        if (via === "" && (!engine || !engine.installed)) return hint("No engine installed yet").concat([engineRow])
        // An engine that costs time or usage per request (Claude) translates on Enter, not on every pause
        if (!result || result.key !== key())
            return live || proc.running ? hint(via !== "" ? "Claude is translating…" : "Translating…")
                : [{ kind: "trgo", name: "Translate with " + engine.name, glyph: "book-a", footer: keys("Enter: translate") }]
        if (result.error) return hint(result.error).concat([engineRow])
        const copyKeys = keys("Enter: copy" + (claude && result.engine !== "claude" ? "  ·  Cmd+Enter: translate with Claude" : ""))
        const row = (text, glyph, summary) => ({ kind: "trcopy", name: text, glyph: glyph, summary: summary, value: text,
                                                 footer: copyKeys })
        // Whose translation it is, when it isn't the engine in use (⌘Enter's)
        const by = engine && result.engine !== engine.id ? " · " + result.engine_name : ""
        const rows = [row(result.translation, "book-a", result.to_name + by)]
        if (result.alternatives.length)
            rows.push({ kind: "header", name: "Also" }, ...result.alternatives.map(a => row(a, "copy", undefined)))
        return rows
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "trcopy") {
            l.open = false
            Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy; notify-send -e -a Translate -t 1500 "Copied" "$1"', "_", it.value])
            return true
        }
        if (it.kind === "trgo") { run(); return true }
        if (it.kind === "truse") { l.keepSelection(); useProc.command = [cmdPath, "engine", "use", it.id]; useProc.running = true; return true }
        return false
    }

    // ⌘Enter (LauncherIpc's askClaude): what is typed, translated by Claude this once
    function cmdEnter() {
        if (launcher.level !== "translate" || typed() === "") return false
        if (!claude) { launcher.shakeNow(); return true }
        pause.stop(); via = "claude"; run()
        return true
    }

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function run() {
        if (typed() === "" || (via === "" && (!engine || !engine.installed))) return
        if (proc.running) return                       // the running one notices its text went stale and starts again
        proc.forKey = key()
        proc.command = [cmdPath, "--json"].concat(via !== "" ? ["--engine", via] : [], into !== "" ? ["--to", into] : [], ["--", typed()])
        proc.running = true
    }

    Connections {
        target: t.launcher
        function onQueryChanged() {
            if (t.launcher.level !== "translate") return
            t.via = ""                                 // new text: the engine in use again
            if (t.live) pause.restart()
        }
    }
    Timer { id: pause; interval: t.typingPause; onTriggered: t.run() }

    Sh {
        id: proc
        property string forKey: ""
        onResult: text => {
            if (t.launcher.level !== "translate") return   // left the level while translating
            if (t.key() !== forKey) { if (t.live || t.via !== "") t.run(); return }
            let r
            try { r = JSON.parse(text.trim().split("\n")[0]) } catch (e) { r = { error: "Translate failed" } }
            r.key = forKey
            if (!r.error && !r.alternatives) r.alternatives = []
            t.result = r
            t.launcher.selectFirst()
        }
    }
    Sh {
        id: listProc
        command: [t.cmdPath, "engines", "--json"]
        onResult: text => {
            try { const j = JSON.parse(text); t.engines = j.engines; t.langs = j.langs; t.langNames = j.lang_names } catch (e) { t.engines = [] }
        }
    }
    Sh { id: useProc; onResult: listProc.running = true }
}
