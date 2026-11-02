import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.kit as Kit
import "Words.js" as Words

// Launcher (⌘Space). A plugin's row above the search field (Deck's player: Ctrl+Space = play/pause). Root level: Apps, Passwords, Clipboard, Screenshot, Keybindings, Settings, Install, Remove, Update, Power. Enter opens an item, Esc/Backspace (with an empty query, not in a form's field) goes back,
// at the root level Esc closes. Up/down arrows or Ctrl+N/P/J/K move the selection.
// Apps: with an empty query, the allow-listed apps; when searching, also those hidden by sync-apps (hidden-apps.sh). See fuzzel/sync-apps, apps-allow.txt.
// ⌃Enter shows the selected app in Apps or hides it from there; a hidden app is still found by searching, and nothing is
// uninstalled (your choice, ~/.local/state/nightdrive/apps.json).
// Keybindings: read from ~/.config/hypr/SHORTCUTS.md (the same file as the ⌘⇧K cheat sheet).
// Install › Software: Fedora's packages and Flathub's apps in one search (hypr/scripts/pkg-search): apps first, one row per
// app (Fedora's if both have it), then command-line tools. That search is its own level (Software › Search, level
// swsearch); Software itself has Search and Browse: Popular and the categories, lists from data/software.json
// (hypr/scripts/software-catalog) for this machine's architecture (pkg-search --list). Typing on Software filters those,
// and the last row takes the words to Search. Install › Software and Remove: Enter on a row opens its details
// in a wider card (hypr/scripts/pkg-info); there Enter installs or removes it, Tab takes the app from the other source,
// Esc goes back to the results. Install › Recommended and Plugins open the same card (hypr/scripts/plugin-info: the long
// text and screenshot from a plugin folder's README.md, or docs/plugins/<id>.md for a plugins.txt line); there Enter runs
// the installer, an installed one's again, and Tab (or its switch) turns an installed one off or on (`nightdrive plugins
// off|on`).
// This file is the window, its state and navigation, and the card that puts the parts together. The parts, each in a
// file of its own: LauncherLevels (the Levels files), LauncherMenus and LauncherSettings (the fixed menus),
// LauncherSearch (the rows and their ranking), LauncherApps (apps' state), LauncherShortcuts (SHORTCUTS.md),
// LauncherSearchField (the keys), LauncherList and LauncherRow (the rows), LauncherWallGrid, LauncherIpc. Other files use
// the launcher only through the properties and functions here (launcher.go, launcher.results, launcher.levels.disp …).
PanelWindow {
    id: win

    // --- Tunables ---
    readonly property int iconSize: 28        // icon size (px)
    readonly property int rowHeight: 52       // row height (px)
    readonly property int rowGap: 2           // space under every row, so neighbouring highlights / fills don't merge
    readonly property int maxRows: 10         // how many rows are visible at once
    readonly property int cardWidth: 660
    readonly property int fontSize: 17
    readonly property int fontWeight: Font.Light   // text weight (headers in bold)
    readonly property real topPosition: Theme.cardTop  // card top edge as a fraction of screen height (0 = top)
    // A narrow or low screen (a VM's window): the card keeps this far from its edges, narrower, with fewer rows
    readonly property int edge: 12
    readonly property bool narrow: width < cardWidth + 2 * edge
    // The card's height without its list: padding, search field, footer (in more lines on a narrow card), a plugin's top
    // row. Summed from the parts: the list's room can't depend on the card's height, which depends on the list
    readonly property int chromeHeight: 36 + 44 + 12 + (footerFlow.visible ? footerFlow.height + 12 : 0) + (topRow.height > 0 ? topRow.height + 12 : 0)
    readonly property int listRoom: Math.max(3 * (rowHeight + rowGap), height - Theme.barHeight - 2 * edge - chromeHeight)

    property bool open: false
    property bool stepAside: false            // a polkit password prompt is open (PolkitWatch): hidden, not closed
    property string level: "root"             // root | apps | keys
    property string query: ""
    property string armed: ""                 // action awaiting confirmation
    // A form's text field (a level file's row with `field: true`, drawn by FieldBox.qml): while it is selected, typing
    // goes into its box instead of the search line, and the selection stays on it. The file's activate() reads `query`
    // on Enter and calls clearQuery() once it has taken it; leaving the row (↑/↓, the mouse) hands what was typed to the
    // file's commitField(row, text), or drops it if the file has none.
    readonly property var fieldRow: { const r = results[list.currentIndex]; return r && r.field === true ? r : null }
    property int fieldAt: -1                  // the field row typed into, while there is one
    property bool holdIndex: false            // clearing the field's text keeps the selection where it is
    function clearQuery() { holdIndex = true; field.text = ""; holdIndex = false }
    function leaveField() {
        if (fieldAt >= 0 && fieldAt !== list.currentIndex && field.text !== "") {
            const row = results[fieldAt], t = extOf(level), text = field.text
            // Cleared before the commit: a value that changes the rows resets the list's selection, which calls this
            // again, and with the text still there it committed twice, its keepSelection() keeping the reset row
            clearQuery()
            if (row && row.field === true && t && t.commitField) t.commitField(row, text)
        }
        fieldAt = fieldRow ? list.currentIndex : -1
    }
    // Tab / ⇧Tab in a form: on to the next / previous field row, round the end (leaving the row hands over what was typed).
    // False on a level without fields, where Tab does what it did before
    function stepField(dir) {
        const n = results.length
        for (let k = 1; k <= n; k++) {
            const i = ((list.currentIndex + dir * k) % n + n) % n
            if (results[i].field === true) { if (i !== list.currentIndex) list.currentIndex = i; return true }
        }
        return false
    }
    readonly property var detail: details.item   // Install / Remove: the row whose details are shown (DetailCard.qml), null = none
    readonly property int detailWidth: 860    // the card's width while showing them
    property alias detailCard: details
    // Settings › Launcher: { fuzzy, shortcuts, deck, comma, contacts, light } in ~/.local/state/nightdrive/launcher.json (missing = on;
    // deck, the music player's albums and artists in the search, comma, the calculator's decimal comma, and light, only
    // when asked for)
    property var prefs: ({ fuzzy: true, shortcuts: true, deck: false, comma: false, contacts: true, light: false })
    readonly property string prefsFile: Quickshell.env("HOME") + "/.local/state/nightdrive/launcher.json"
    FileView {
        path: win.prefsFile; watchChanges: true; onFileChanged: reload(); printErrors: false
        onLoaded: {
            let v = {}
            try { v = JSON.parse(text()) || {} } catch (e) {}
            const n = { fuzzy: v.fuzzy !== false, shortcuts: v.shortcuts !== false, deck: v.deck === true, comma: v.comma === true, contacts: v.contacts !== false, light: v.light === true }
            if (JSON.stringify(n) !== JSON.stringify(win.prefs)) win.prefs = n
        }
    }
    function setPref(key, on) {
        const n = Object.assign({}, prefs); n[key] = on
        prefs = n
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$2")" && printf "%s\\n" "$1" > "$2.tmp" && mv "$2.tmp" "$2"',
                                 "_", JSON.stringify(n), prefsFile])
    }
    property int updates: 0                   // Update: new Nightdrive commits waiting (nightdrive update check, every 6 h)
    Sh {
        id: updatesProc
        script: 'cat "$HOME/.cache/nightdrive/updates" 2>/dev/null'
        onResult: text => { win.updates = parseInt(text, 10) || 0 }
    }
    // Background's wallpapers as a grid once they're read (ThemeLevels.qml), other levels as a list
    readonly property bool grid: level === "background" && lv.themes.wallLoaded
    readonly property int gridCols: 2
    property bool topFocused: false           // a plugin's row above the search field is selected (up arrow from the first list row)
    // Light launcher (Settings › Launcher › Light, #1998): at the root with nothing typed, only the search field and a
    // plugin's row (Deck's player) show, for less to look at. ↓ reveals the rows, ↑ from the top row hides them
    // again, Esc closes as before (whoever opened the rows is done with the launcher); typing searches as before. Not on a level a key opened, which has its rows to show
    property bool revealed: false
    readonly property bool collapsed: prefs.light && level === "root" && query === "" && !revealed && keyLevel === "" && detail === null

    // --- The parts (see the top) ---
    property string extSource: ""             // shell.qml sets this when local/LauncherExtension.qml exists (LauncherLevels)
    LauncherLevels { id: lv; launcher: win }
    LauncherMenus { id: menusPart; launcher: win }
    LauncherSettings { id: settingsPart; launcher: win }
    LauncherSearch { id: searchPart; launcher: win }
    LauncherApps { id: appsPart; launcher: win }
    LauncherShortcuts { id: shortcutsPart; launcher: win }
    LauncherIpc { launcher: win }
    RowCopy { id: copier; launcher: win }
    property alias levels: lv                 // launcher.levels.disp, .sound, .ask …: a Levels file by its short name
    property alias menus: menusPart
    property alias settingsRows: settingsPart
    property alias appState: appsPart
    property alias shortcuts: shortcutsPart
    property alias rowCopy: copier   // Wi-Fi's and Tailscale's rows say "copied" (RowCopy.qml)

    readonly property var ext: lv.ext
    readonly property var pluginExts: lv.pluginExts
    readonly property var exts: lv.exts
    readonly property var topExt: lv.topExt
    function extOf(l) { return lv.extOf(l) }
    readonly property bool extLevel: extOf(level) !== null
    readonly property var titles: Object.assign({}, menusPart.titles, settingsPart.titles, ...exts.map(e => e.titles))
    readonly property var parents: Object.assign({}, menusPart.parents, settingsPart.parents, ...exts.map(e => e.parents))
    readonly property var statics: Object.assign({}, menusPart.statics, settingsPart.statics)
    readonly property var settingsAliases: settingsPart.settingsAliases
    readonly property var results: searchPart.items()
    function fold(s) { return searchPart.fold(s) }
    function mirrorRows() { return lv.mirror.mirrorRows() }   // DisplayLevels: Screen Mirroring's rows under Display

    readonly property int selIndex: list.currentIndex
    function shakeNow() { shake.restart() }
    function search(target, text) { go(target); field.text = text }   // a level with its query typed (Default apps › Find more)
    function insertText(text) { field.insert(field.cursorPosition, text) }   // at the cursor (Snippets: Shift+Enter → ↵)
    property alias field: searchField.input                             // the search / text field (ClipPicker keeps its text and cursor)
    readonly property var swCats: lv.inst.swCats                        // Install › Software's categories (Default apps › Find more)
    function openCategory(key, name) { lv.inst.openCategory(key, name) }
    // The selected row is an app: ⌃Enter shows it in Apps (the list with an empty query) or hides it from there.
    // "Hide", not "remove": removing sounded like uninstalling.
    readonly property var selApp: { const c = results[list.currentIndex]; return (level === "apps" || level === "root") && c && c.kind === "app" ? c : null }
    // The level's or the row's keys, then ⌘Enter when the search looks like a request for Claude (AskClaudeHint.qml); on
    // the Ask Claude row its own. Not while that row is listed: it says so itself, and the hint stood in for the keys of
    // a row without any (Deck's Search Spotify, #1895)
    readonly property string footer: collapsed ? ""
        : (results[list.currentIndex] || {}).kind === "askclaude" ? lv.ask.rowFooter(query)
        : lv.askHint.shows(level, query, results) && !results.some(r => r.kind === "askclaude")
            ? [levelFooter, lv.askHint.text].filter(f => f !== "").join("  ·  ") : levelFooter
    readonly property string levelFooter: detail !== null ? details.footer
        : selApp ? "Enter: open  ·  Ctrl+Enter: " + (selApp.shown ? "hide from Apps" : "show in Apps")
                                              + "  ·  Alt+Enter: " + (appsPart.autostartIds.indexOf(appsPart.appId(selApp)) >= 0 ? "don’t start at login" : "start at login")
        : level === "startup" ? "Enter: start at login on/off  ·  background apps start hidden"
        : typeof (results[list.currentIndex] || {}).footer === "string" ? results[list.currentIndex].footer   // a row's own keys
        : (results[list.currentIndex] || {}).kind === "brightness" ? "Left+Right: brightness"
        : (results[list.currentIndex] || {}).kind === "mirrordev" ? lv.mirror.footer(level, query)
        : (results[list.currentIndex] || {}).kind === "haent" ? lv.home.footer(level, query)
        : (results[list.currentIndex] || {}).kind === "nightlight" ? "Enter: night light on/off"
        : (results[list.currentIndex] || {}).kind === "calc" ? "Enter: copy the result"
        : extOf(level) ? extOf(level).footer(level, query)   // not extLevel: it can lag a level change by one update
        : ""
    property var lastMouse: null              // last mouse position (window coordinates); null = not seen yet since opening
    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    signal openMenu(string name)              // Settings: opens a Quickshell menu (wifi, bluetooth, ...)

    // Terminal window that runs a command and waits for Enter (sudo asks for the password here)
    function term(script, arg) {
        return [scripts + "/terminal", "--class", "floating-tui", "--", "bash", "-c",
                script + "; echo; read -rp 'Done. Press Enter to close…'", "_", arg || ""]
    }
    // Install › Software's rows and a details card's Tab (the other source)
    function installCmd(src, id) {
        return src === "flatpak" ? term('flatpak install --user flathub "$1"', id) : term('sudo dnf install "$1"', id)
    }

    // Rows that can't be selected: section headers, and notes (kind "note": a line of help in small text, e.g. Settings ›
    // App shortcuts' "the others are in the config files"), unlike a hint, which stands in for the rows ("Loading…"), and
    // quotes (kind "quote": lines of what something holds, in a darker box: Send to Claude's preview)
    function fixedRow(it) { return it.kind === "header" || it.kind === "note" || it.kind === "quote" }
    function firstSelectable() {
        for (let i = 0; i < results.length; i++) if (!fixedRow(results[i])) return i
        return 0
    }
    // Moves the selection, skipping header and note rows
    function step(dir) {
        if (collapsed) { if (dir > 0) { revealed = true; selectFirst() } else topFocused = topExt !== null; return }
        let i = list.currentIndex + dir
        while (i >= 0 && i < results.length && fixedRow(results[i])) i += dir
        // Up from the top of the list: the light launcher hides its rows again, else a plugin's row
        if (i < 0 && dir < 0) { if (prefs.light && revealed && level === "root" && query === "") revealed = false; else topFocused = topExt !== null; return }
        if (i >= 0 && i < results.length) {
            list.currentIndex = i
            // Up onto a section's first row: its header comes into view too (the list only scrolls to the row itself)
            if (dir < 0 && i > 0 && results[i - 1].kind === "header") Qt.callLater(() => list.positionViewAtIndex(i - 1, ListView.Contain))
            // Down onto the last row that can be selected: the notes below it come into view too
            if (dir > 0 && results.slice(i + 1).every(fixedRow)) Qt.callLater(() => list.positionViewAtEnd())
        }
    }

    function hint(text) { return [{ kind: "hint", name: text }] }

    // The next word boundary from `pos` in direction `dir` (-1 / 1): over any spaces and punctuation, then the word
    function wordPos(s, pos, dir) { return Words.pos(s, pos, dir) }

    // The row each level had selected when a sublevel was opened (by name: a search may have been on), so Esc returns to it
    property var lastSel: ({})
    // A level opened from a search ("update" → Update channel), by its name: the level, the search and the row it came from,
    // so Esc goes back to that search like Spotlight does, not to the level's parent (Settings)
    property var fromSearch: ({})
    // The level openLevel opened (a key, a menu, a script), "" when the launcher was opened as itself: back() closes there
    property string keyLevel: ""
    // Opens a level with this already typed (Deck's Search Spotify row)
    function goSearch(target, text) { go(target); field.text = text }
    function go(target, goingBack) {
        const cur = results[list.currentIndex]
        if (cur && cur.name && target !== level && (parents[target] || "root") === level)   // going down one level
            lastSel[level] = { kind: cur.kind, name: cur.name }
        // back() keeps the record: a sublevel's Esc returns here and this level's Esc still to the search
        if (!goingBack && target !== level)
            fromSearch[target] = query.trim() !== "" ? { level: level, query: query, sel: cur ? { kind: cur.kind, name: cur.name } : null } : undefined
        level = target; field.text = ""; query = ""; armed = ""; topFocused = false; details.close()
        revealed = goingBack === true   // back from a sublevel to the rows it was opened from
        appsPart.rescan()
        if (target === "keys") shortcutsPart.reload()     // re-read SHORTCUTS.md: changes show up immediately
        list.currentIndex = firstSelectable()
        if (target === "settings" || target === "appsettings") lv.behave.entered("settings")   // the computer name and channel on its rows, Firefox's
        if (target === "display" || target === "otherdisplays") lv.mirror.entered("display")   // Screen Mirroring's rows (Other displays)
        if (extOf(target)) extOf(target).entered(target)
    }

    function activate(item) {
        if (!item) return
        if (item.switchBusy) { shake.restart(); return }   // its last change is still waiting (e.g. for the password)
        if (item.kind === "nav") go(item.target)
        else if (item.kind === "app" && level === "startup") appsPart.toggleAutostart(item)
        else if (item.kind === "app") {
            win.open = false
            // Background app: bring the hidden window back (no second instance)
            if (item.entry && appsPart.bgApps[item.name] !== undefined)
                Quickshell.execDetached([scripts + "/launch-or-focus", appsPart.bgApps[item.name], "gtk-launch", item.entry.id + ".desktop"])
            // An app that runs in a terminal (htop, aerc) in the chosen one: execute() would start it without any
            else if (item.entry && item.entry.runInTerminal)
                Quickshell.execDetached([scripts + "/terminal", "--"].concat(item.entry.command))
            else if (item.entry) item.entry.execute(); else Quickshell.execDetached(["gio", "launch", item.path])
        }
        else if (item.kind === "stat" && item.copy !== undefined) copier.copyText(item.copy, item.sensitive === true)   // Public IP, Local IP, Router: as ⌘C
        else if (item.kind === "stat") shake.restart()   // information only
        else if (item.kind === "calc") { copier.copyText(item.copy); win.open = false }   // ready to paste
        else if (exts.some(e => e.activate(item))) {}
        else if (item.kind === "menu") { win.open = false; win.openMenu(item.target) }
        else if (item.src && detail === null) details.show(item)
        else if (item.kind === "action") {
            if (item.confirm && armed !== item.name) { armed = item.name; disarm.restart(); return }
            armed = ""; win.open = false
            Quickshell.execDetached(item.cmd)
        }
    }
    // Shift+Enter on an extension row; rows with armKey need a second press to confirm
    // (a file that arms its rows itself, armsItself, gets them as they are: Snippets' armKey is for ⌘⌫)
    function extShift(item) {
        const target = extOf(level) || ext
        if (target.armsItself !== true && item.armKey !== undefined && armed !== item.armKey) { armed = item.armKey; disarm.restart(); return }
        armed = ""
        target.shiftActivate(item)
    }
    // Ctrl+Enter, ⌘⌫ / Delete and Ctrl+Up/Down on an extension level, if its file has them (ctrlActivate, deleteSelected,
    // moveSelected); true = done
    function extCtrl(item) { const t = extOf(level); return !!(t && t.ctrlActivate && t.ctrlActivate(item)) }
    function extDelete() { const t = extOf(level); return !!(t && t.deleteSelected && t.deleteSelected()) }
    function extMove(dir) { const t = extOf(level); return !!(t && t.moveSelected && t.moveSelected(dir)) }   // Ctrl+Up/Down
    // ⌘⌫ / ⌥⌫ in the query (or Ask Claude's field): a selection goes first, otherwise to the line start (word = only the
    // word before the cursor)
    function deleteBack(word) { Words.deleteBack(win.field, word) }

    // The selection changes only when the mouse actually moves. Merely "mouse is over a row" isn't enough,
    // because a stationary cursor left under the launcher (or a scrolling list) would trigger it.
    function hover(area, mouse, index) {
        const p = area.mapToItem(null, mouse.x, mouse.y)
        if (lastMouse === null) { lastMouse = Qt.point(p.x, p.y); return }   // first event = cursor position
        // Threshold: a sub-pixel jitter from scaling (e.g. 520 → 519.9) isn't movement
        if (Math.abs(p.x - lastMouse.x) + Math.abs(p.y - lastMouse.y) < 3) return
        lastMouse = Qt.point(p.x, p.y)
        topFocused = false
        list.currentIndex = index
    }
    // The current value is part of the rows (✓, "current"), so changing it rebuilds the list and the selection would jump to the top:
    // restore the selection to the same row after the update
    // Rebuilding the rows resets both the selection and the scroll position: put both back (a scrolled list jumped to the top)
    function keepSelection() {
        const i = list.currentIndex, y = list.contentY
        // The scroll position only after the list has settled on the new rows (in the same call it was reset again)
        Qt.callLater(() => { list.currentIndex = i; Qt.callLater(() => { list.contentY = Math.min(y, Math.max(0, list.contentHeight - list.height)) }) })
    }
    // Selects the first row matching pred (e.g. a setting's current value), if any
    function select(i) { list.currentIndex = i }
    function selectFirst() { list.currentIndex = firstSelectable() }
    function selectWhere(pred) { const i = results.findIndex(pred); if (i >= 0) list.currentIndex = i }
    // Back to the list's top after the selection moved down to a row (Send to Claude: its preview stays in view)
    function showTop() { Qt.callLater(() => list.positionViewAtBeginning()) }
    function back() {
        if (detail !== null) { details.close(); return }
        if (lv.tools.picker.back()) return      // Clipboard as a text field's picker: back to the field, its text kept
        if (level === "root") { win.open = false; return }
        // The level a key or a menu opened the launcher on (openLevel: ⌘⇧E Emoji, ⌘⌃C Send to Claude): there's nothing
        // in the launcher to go back to, so Esc closes it, as that key's own card would
        if (level === keyLevel) { win.open = false; return }
        const s = fromSearch[level]
        if (s) {
            delete fromSearch[level]
            go(s.level, true)
            field.text = s.query
            reselect(s.sel)
            return
        }
        go(parents[level] || "root", true)
        reselect(lastSel[level])
    }
    // Selects the row Esc returns to (by kind and name), if the level still has it
    function reselect(sel) {
        const i = sel ? results.findIndex(r => r.kind === sel.kind && r.name === sel.name) : -1
        if (i >= 0) list.currentIndex = i
    }

    // Closing leaves the details right away (after the Behavior above has seen open = false), so the next open starts narrow
    onOpenChanged: if (!open) Qt.callLater(() => { if (!win.open) details.close() })
    else { lastMouse = null; lastSel = ({}); fromSearch = ({}); keyLevel = ""; exts.forEach(e => e.opened()); Plugins.check(); go("root"); appsPart.opened(); updatesProc.running = true; lv.mirror.entered("display"); lv.sound.soundRefresh(); field.forceActiveFocus() }

    Timer { id: disarm; interval: 4000; onTriggered: win.armed = "" }

    function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    // A hair space between key symbols in running text: JetBrains Mono's ⌘⌥⌫ are wider than their cell and overlap side
    // by side (the shortcut rows use letterSpacing instead)
    function keySpaced(t) { return t.replace(/([⌘⌥⇧⌃⌫⌦])(?=[⌘⌥⇧⌃⌫⌦])/g, "$1 ") }

    visible: open && !stepAside
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea { anchors.fill: parent; onClicked: win.open = false }

    Rectangle {
        id: card
        // Only the details' widening is animated, not the screen's cap: on the first open the window's width is 0 until
        // Hyprland sizes it, and the card would grow from nothing
        property real wantWidth: win.detail !== null ? win.detailWidth : win.cardWidth
        width: Math.min(wantWidth, parent.width - 2 * win.edge)
        // Animated only while open: a closed launcher drops back to the normal width at once (onOpenChanged)
        Behavior on wantWidth { enabled: win.open; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        height: col.implicitHeight + 36
        x: (parent.width - width) / 2
        // Higher up when the screen is too low for it, but never over the top bar
        y: Math.max(Theme.barHeight + win.edge, Math.min(parent.height * win.topPosition, parent.height - height - win.edge))
        radius: 12
        color: Theme.launcherBg
        border.color: Theme.primary
        border.width: 2
        // Enter with no results: the card shakes side to side ("no match"), with the error sound (hypr/scripts/sounds)
        transform: Translate { id: shakeShift }
        SequentialAnimation {
            id: shake
            onStarted: Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "event", "error"])
            NumberAnimation { target: shakeShift; property: "x"; to: -16; duration: 45; easing.type: Easing.OutQuad }
            NumberAnimation { target: shakeShift; property: "x"; to: 16; duration: 80; easing.type: Easing.InOutQuad }
            NumberAnimation { target: shakeShift; property: "x"; to: -10; duration: 70; easing.type: Easing.InOutQuad }
            NumberAnimation { target: shakeShift; property: "x"; to: 6; duration: 60; easing.type: Easing.InOutQuad }
            NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 50; easing.type: Easing.OutQuad }
        }
        MouseArea { anchors.fill: parent }

        Column {
            id: col
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
            spacing: 12

            // A plugin's row (topExt.topRow: Deck's player)
            Loader {
                id: topRow
                active: win.topExt !== null
                visible: active
                width: parent.width
                height: item ? item.implicitHeight : 0
                sourceComponent: win.topExt ? win.topExt.topRow : null
            }

            // Search field (+ path when in a sublevel)
            LauncherSearchField { id: searchField; launcher: win }

            LauncherList { id: list; launcher: win; width: parent.width }

            // Install / Remove: a package's or plugin's details (DetailCard.qml), in place of the list
            DetailCard { id: details; launcher: win; width: parent.width; onPluginToggled: lv.inst.reloadPlugins() }

            LauncherWallGrid { launcher: win; width: parent.width }

            KeyFooter {     // footer: each action's key caps, then what it does; on a narrow card in more lines
                id: footerFlow
                anchors.right: parent.right
                maxWidth: parent.width
                text: win.footer
            }
        }
    }
}
