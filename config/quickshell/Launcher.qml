import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Launcher (⌘Space). A plugin's row above the search field (Deck's player: Ctrl+Space = play/pause). Root level: Apps, Passwords, Clipboard, Screenshot, Keybindings, Settings, Install, Remove, Update, Power. Enter opens an item, Esc/Backspace (with an empty query) goes back,
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
PanelWindow {
    id: win

    // A key in the footer: Lucide glyph (Enter, Ctrl, ...) or its name (Esc). A footer part's keys share one frame (footer, below).
    component Keycap: Item {
        property string key: ""
        readonly property string glyph: win.keyGlyphs[key] || ""
        width: label.implicitWidth; height: 19
        Text {
            id: label
            anchors.centerIn: parent
            // a letter (⌘C) and a function key (F3) stay capitals, and Hyper, a modifier with no symbol, is in capitals like
            // the bar's tags
            text: parent.glyph !== "" ? Icons.g(parent.glyph) : letter ? parent.key
                : parent.key === "Hyper" ? "HYPER" : parent.key.toLowerCase()
            color: Theme.dim
            // a capital as big and heavy as the glyphs next to it (⌘ ⇧ V); a key name (esc) stays small
            readonly property bool letter: parent.glyph === "" && (parent.key.length === 1 || /^F\d+$/.test(parent.key))
            font { family: parent.glyph !== "" ? Icons.family : Theme.font; pixelSize: parent.glyph !== "" ? 12 : letter ? 14 : 11
                   weight: letter ? Font.Medium : Font.Normal }
        }
    }

    // --- Tunables ---
    readonly property int iconSize: 28        // icon size (px)
    readonly property int rowHeight: 52       // row height (px)
    readonly property int rowGap: 2           // space under every row, so neighbouring highlights / fills don't merge
    readonly property int maxRows: 10         // how many rows are visible at once
    readonly property int cardWidth: 660
    readonly property int fontSize: 17
    readonly property int fontWeight: Font.Light   // text weight (headers in bold)
    readonly property real topPosition: 0.189  // card top edge as a fraction of screen height (0 = top)
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
    property var syncHidden: []               // apps hidden by sync-apps: [{ path, name, icon, extra }]
    property var keyList: []                  // [{ name, sub, keys, section }]
    property var keyIndex: ({})               // lower-case name → keys (shortcutFor)
    property string armed: ""                 // action awaiting confirmation
    readonly property var detail: details.item   // Install / Remove: the row whose details are shown (DetailCard.qml), null = none
    readonly property int detailWidth: 860    // the card's width while showing them
    // Settings › Launcher: { fuzzy, shortcuts, deck, comma, contacts } in ~/.local/state/nightdrive/launcher.json (missing = on;
    // deck, the music player's albums and artists in the search, and comma, the calculator's decimal comma, only when asked for)
    property var prefs: ({ fuzzy: true, shortcuts: true, deck: false, comma: false, contacts: true })
    readonly property string prefsFile: Quickshell.env("HOME") + "/.local/state/nightdrive/launcher.json"
    FileView {
        path: win.prefsFile; watchChanges: true; onFileChanged: reload(); printErrors: false
        onLoaded: {
            let v = {}
            try { v = JSON.parse(text()) || {} } catch (e) {}
            const n = { fuzzy: v.fuzzy !== false, shortcuts: v.shortcuts !== false, deck: v.deck === true, comma: v.comma === true, contacts: v.contacts !== false }
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
    // Background's wallpapers as a grid once they're read (ThemeLevels.qml), other levels as a list
    readonly property bool grid: level === "background" && themes.wallLoaded
    readonly property int gridCols: 2
    property bool topFocused: false           // a plugin's row above the search field is selected (up arrow from the first list row)
    // Personal additions from a private overlay: local/LauncherExtension.qml (not in the repo, see README).
    // It may add root items and whole levels; see the functions it is asked for below (extItems, activate, ...).
    property string extSource: ""             // shell.qml sets this when the file exists
    readonly property var ext: extLoader.item
    // Levels from other files, which answer the same questions (items, activate, footer, entered; the optional ones below):
    // SystemLevels (Wi-Fi, Bluetooth, Sound, Tailscale, Status), HomeLevels (Home Assistant), DefaultAppsLevels, AppKeyLevels
    // (App shortcuts), BehaviourLevels (Mouse, Launcher, Firefox, Computer name, Remote login, Notifications, Crash reports, Update channel), InstallLevels,
    // ToolsLevels (Clipboard, Emoji, Snippets), AppearanceLevels (Top bar, Screensaver), DisplayLevels (Display, Battery),
    // RemoveLevels, PasswordLevels (with 1Password), ThemeLevels (Theme, Background), ClaudeWriteLevels, AboutLevels, the plugins' and the private
    // extension. A new file goes in this list, not in each question's code
    // The installed plugins' level files (their <Name>Levels.qml, TopBar.plugin.levels: Deck's Music) come after the core's
    property var pluginExts: []
    readonly property var exts: [sys, home, defs, akeys, behave, inst, tools, look, disp, rm, pw, themes, cwrite, about].concat(pluginExts, ext ? [ext] : [])
    // A plugin's row above the search field (topRow; Deck's player): the first file that has one. ↑ from the list's first
    // row selects it, its keys then go to topKey(event), and Ctrl+Space anywhere to topPress()
    readonly property var topExt: exts.find(e => e.topRow) || null
    function extOf(l) { return exts.find(e => e.levels.indexOf(l) >= 0) || null }
    readonly property bool extLevel: extOf(level) !== null
    readonly property int selIndex: list.currentIndex
    function shakeNow() { shake.restart() }
    function search(target, text) { go(target); input.text = text }   // a level with its query typed (Default apps › Find more)
    function insertText(text) { input.insert(input.cursorPosition, text) }   // at the cursor (Snippets: Shift+Enter → ↵)
    property alias field: input                                         // the search / text field (ClipPicker keeps its text and cursor)
    readonly property var swCats: inst.swCats                          // Install › Software's categories (Default apps › Find more)
    function openCategory(key, name) { inst.openCategory(key, name) }
    readonly property var parents: Object.assign({ install: "system", screenshot: "tools", startup: "appsettings", appsettings: "settings" }, ...exts.map(e => e.parents))
    // Search found nothing: hint below ⌘⌥⏎ (icons) → send the text to Claude
    readonly property bool noHit: (level === "root" || level === "apps") && query.trim() !== "" && results.length === 0
    // The selected row is an app: ⌃Enter shows it in Apps (the list with an empty query) or hides it from there.
    // "Hide", not "remove": removing sounded like uninstalling.
    readonly property var selApp: { const c = results[list.currentIndex]; return (level === "apps" || level === "root") && c && c.kind === "app" ? c : null }
    readonly property string footer: detail !== null ? details.footer
        : selApp ? "Enter: open  ·  Ctrl+Enter: " + (selApp.shown ? "hide from Apps" : "show in Apps")
                                              + "  ·  Alt+Enter: " + (autostartIds.indexOf(appId(selApp)) >= 0 ? "don’t start at login" : "start at login")
        : level === "startup" ? "Enter: start at login on/off  ·  background apps start hidden"
        : (results[list.currentIndex] || {}).kind === "brightness" ? "Left+Right: brightness"
        : (results[list.currentIndex] || {}).kind === "mirrordev" ? sys.footer(level, query)
        : (results[list.currentIndex] || {}).kind === "haent" ? home.footer(level, query)
        : (results[list.currentIndex] || {}).kind === "nightlight" ? "Enter: night light on/off"
        : (results[list.currentIndex] || {}).kind === "calc" ? "Enter: copy the result"
        : extOf(level) ? extOf(level).footer(level, query)   // not extLevel: it can lag a level change by one update
        : ""
    // The footer as key caps: "Ctrl+Enter: show in Apps  ·  Esc: back" → [{ keys: ["Ctrl", "Enter"], text: "show in Apps" }, ...].
    // "Enter creates …" (no colon) works too, and a letter alone with a colon ("C: set up"); a part that doesn't start with a
    // key is plain text.
    readonly property var keyGlyphs: ({ Enter: "corner-down-left", Ctrl: "chevron-up", Shift: "arrow-big-up", Alt: "option", Cmd: "command",
                                        Up: "arrow-up", Down: "arrow-down", Left: "arrow-left", Right: "arrow-right",
                                        Backspace: "delete", Space: "space" })
    readonly property var keySymbolNames: ({ "⌘": "Cmd", "⇧": "Shift", "⌥": "Alt", "⌃": "Ctrl", "⌫": "Backspace" })   // SHORTCUTS.md symbols → keyGlyphs
    readonly property var footerParts: footer === "" ? [] : footer.split(/\s+·\s+/).map(part => {
        const m = part.match(/^((?:Ctrl|Shift|Alt|Cmd|Enter|Esc|Tab|Space|Backspace|Up|Down|Left|Right|[A-Z](?=:))(?:\+(?:Ctrl|Shift|Alt|Cmd|Enter|Esc|Tab|Space|Backspace|Up|Down|Left|Right|[A-Z]))*)(?::\s*|\s+)(.*)$/)
        return m ? { keys: m[1].split("+"), text: m[2] } : { keys: [], text: part }
    })
    property var lastMouse: null              // last mouse position (window coordinates); null = not seen yet since opening
    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    signal openMenu(string name)              // Settings: opens a Quickshell menu (wifi, bluetooth, ...)

    readonly property var titles: Object.assign({ apps: "Apps", keys: "Keybindings", screenshot: "Tools › Screenshot", settings: "Settings", startup: "Apps › Startup", appsettings: "Settings › Apps", theme: "Settings › Theme", themecolor: "Settings › Theme › Color", background: "Settings › Theme › Background",
                                     system: "System", install: "System › Install", power: "Power",
                                     tools: "Tools" }, ...exts.map(e => e.titles))

    // Reference at startup: the app list only loads on first reference
    property var apps: DesktopEntries.applications.values

    // Terminal window that runs a command and waits for Enter (sudo asks for the password here)
    function term(script, arg) {
        return [scripts + "/terminal", "--class", "floating-tui", "--", "bash", "-c",
                script + "; echo; read -rp 'Done. Press Enter to close…'", "_", arg || ""]
    }
    function shot(mode) { return ["bash", "-c", "sleep 0.4; \"$HOME/.config/hypr/scripts/screenshot\" \"$1\"", "_", mode] }

    // Passwords only with 1Password; the plugins' level files add their own (rootItems: Deck's Music)
    readonly property var rootItems: [
        { kind: "nav", name: "Apps", glyph: "layout-grid", target: "apps" },
    ].concat(Plugins.has("1password") ? [{ kind: "nav", name: "Passwords", glyph: "key-round", target: "passwords" }] : [], [
        { kind: "nav", name: "Clipboard", glyph: "clipboard-list", target: "clipboard" },
    ], ...pluginExts.map(e => e.rootItems || []), home.rootItems, ext ? ext.rootItems : [], [
        { kind: "nav", name: "Tools", glyph: "wrench", target: "tools" },
        { kind: "nav", name: "Keybindings", glyph: "keyboard", target: "keys" },
        { kind: "nav", name: "Settings", glyph: "settings", target: "settings" },
        // System: Install, Remove, Update, Status and About Nightdrive (the update count shows here too)
        { kind: "nav", name: "System", glyph: "monitor-cog", target: "system", summary: updates > 0 ? updates + " new" : undefined },
        { kind: "nav", name: "Power", glyph: "power", target: "power" }
    ])

    // Static sublevels
    readonly property var statics: ({
        system: [
            { kind: "nav", name: "Install", glyph: "package-plus", target: "install", extra: "software package app flatpak dnf" },
            { kind: "nav", name: "Remove", glyph: "package-minus", target: "remove", extra: "uninstall delete package app" },
            { kind: "action", name: "Update", glyph: "refresh-cw", confirm: true, cmd: term('"$HOME/.local/bin/nightdrive" update'),
              summary: updates > 0 ? updates + " new" : undefined, extra: "upgrade dnf flatpak nightdrive" },
            // Welcome to Nightdrive (config/welcome): the first login's window, again
            { kind: "action", name: "Set up Nightdrive", glyph: "sparkles", cmd: [Quickshell.env("HOME") + "/.local/bin/nightdrive", "welcome"],
              extra: "welcome first run start setup claude sign in login tailscale mail deck" },
            { kind: "nav", name: "Status", glyph: "activity", target: "status", extra: "cpu memory processes temperature claude usage" },
            { kind: "nav", name: "About Nightdrive", glyph: "info", target: "about", extra: "version release channel info website github" }
        ],
        tools: [
            { kind: "nav", name: "Screenshot", glyph: "camera", target: "screenshot" },
            { kind: "nav", name: "Emoji", glyph: "smile", target: "emoji" },
            { kind: "nav", name: "Snippets", glyph: "text-cursor-input", target: "snippets", extra: "text expansion replacement abbreviation autotext" },
            { kind: "action", name: "Color Picker", glyph: "pipette", cmd: ["bash", "-c", "sleep 0.4; \"$HOME/.config/hypr/scripts/color-picker\""] }
        ].concat(Plugins.has("localsend") ? [   // to a phone running LocalSend (plugins/localsend); several: picked from a list
            { kind: "action", name: "Send clipboard with LocalSend", glyph: "smartphone", cmd: [Quickshell.env("HOME") + "/.local/bin/localsend", "send-clipboard"],
              extra: "phone iphone share airdrop text link" },
            { kind: "action", name: "Send files with LocalSend", glyph: "smartphone", cmd: [Quickshell.env("HOME") + "/.local/bin/localsend", "send-pick"],
              extra: "phone iphone share airdrop" }
        ] : [], ...pluginExts.map(e => e.toolItems || [])),   // the plugins' level files add theirs (toolItems: Keep Awake)
        screenshot: [
            { kind: "action", name: "Region", glyph: "crop", cmd: shot("region") },
            { kind: "action", name: "Window", glyph: "app-window", cmd: shot("window") },
            { kind: "action", name: "Full screen", glyph: "monitor", cmd: shot("full") }
        ],
        install: [
            { kind: "nav", name: "Software", glyph: "package-plus", target: "software", summary: "dnf + Flatpak" },
            { kind: "nav", name: "Webapp", glyph: "app-window", target: "webapp", summary: "website as an app" },
            { kind: "nav", name: "Recommended", glyph: "star", target: "recommended", summary: "apps set up for Nightdrive" },
            { kind: "nav", name: "Plugins", glyph: "puzzle", target: "plugins", summary: "desktop features" }
        ],
        // In groups like macOS's System Settings: the often used first (connections, hardware), then the look, the apps' own
        // settings (one row, as on iOS: appsettings), Claude, and what is set once (system)
        settings: [
            { kind: "header", name: "Connections" },
            { kind: "nav", name: "Wi-Fi", glyph: "wifi", target: "wifi" },
            { kind: "nav", name: "Bluetooth", glyph: "bluetooth", target: "bluetooth" }
        ].concat(Plugins.has("tailscale") ? [{ kind: "nav", name: "Tailscale", glyph: "shield-check", target: "tailscale" }] : [], [
            { kind: "header", name: "Hardware" },
            { kind: "nav", name: "Sound", glyph: "volume-2", target: "sound" },   // Headphones are a row there, while connected
            { kind: "nav", name: "Display", glyph: "monitor", target: "display" },
            { kind: "nav", name: "Mouse", glyph: "mouse", target: "mousescroll", summary: behave.mouseScroll ? behave.mouseScroll + "× scroll" : undefined }
        ], disp.hasBattery ? [{ kind: "nav", name: "Battery", glyph: "battery-medium", target: "battery" }] : [], [
            { kind: "header", name: "Appearance" },
            { kind: "nav", name: "Theme", glyph: "palette", target: "theme" },
            { kind: "nav", name: "Top bar", glyph: "panel-top", target: "topbar" },   // its look and what it shows
            { kind: "nav", name: "Screensaver", glyph: "monitor-pause", target: "screensaver" },
            { kind: "nav", name: "Notifications", glyph: "bell-ring", target: "sounds" },
            { kind: "header", name: "Apps" },
            { kind: "nav", name: "App settings", glyph: "layout-grid", target: "appsettings" },
            { kind: "header", name: "Claude" },
            { kind: "nav", name: "Claude writes", glyph: "sparkles", target: "claudewrite", summary: cwrite.modelName(cwrite.model) }
        ], behave.crashReportItems, [
            { kind: "header", name: "System" },
            { kind: "nav", name: "Launcher", glyph: "text-search", target: "launcherprefs" },
            { kind: "nav", name: "Computer name", glyph: "laptop", target: "compname", summary: behave.compName }   // what phones see
        ], behave.remoteLoginItems, [
            { kind: "nav", name: "Update channel", glyph: "git-branch", target: "channel",
              summary: behave.channel === "dev" ? "development" : (behave.channel === "custom" ? behave.channelBranch || "custom" : behave.channel || undefined) }
        ]),
        // Settings › Apps: what is about apps in general first, then each app's own settings (only those installed)
        appsettings: defs.settingsItems.concat(akeys.settingsItems, [
            { kind: "nav", name: "Startup", glyph: "rocket", target: "startup" },
            { kind: "nav", name: "Nightdrive apps", glyph: "app-window", target: "ndapps", summary: "on or off" }   // InstallLevels.qml
        ], behave.browserItems.length || home.settingsItems.length || Plugins.has("mail") || Plugins.has("contacts") ? [{ kind: "header", name: "Installed apps" }] : [],
           behave.browserItems.concat(home.settingsItems,
               Plugins.has("contacts") ? [{ kind: "action", name: "Contacts", glyph: "contact", cmd: [Quickshell.env("HOME") + "/.local/bin/contacts", "settings"] }] : [],
               Plugins.has("mail") ? [{ kind: "action", name: "Mail", glyph: "mail", cmd: [Quickshell.env("HOME") + "/.local/bin/nightmail", "settings"] }] : [])
               .map(t => Object.assign({}, t, { appName: t.name }))),   // an app's own: "Mail settings" in the root search
        power: [
            { kind: "action", name: "Lock", glyph: "lock", cmd: ["loginctl", "lock-session"] },
            { kind: "action", name: "Sleep", glyph: "moon", cmd: ["systemctl", "suspend"] },
            { kind: "action", name: "Log out", glyph: "log-out", cmd: [Quickshell.env("HOME") + "/.config/hypr/scripts/session-end", "logout"] },
            { kind: "action", name: "Restart", glyph: "rotate-cw", confirm: true, cmd: [Quickshell.env("HOME") + "/.config/hypr/scripts/session-end", "reboot"] },
            { kind: "action", name: "Shut down", glyph: "power", confirm: true, cmd: [Quickshell.env("HOME") + "/.config/hypr/scripts/session-end", "poweroff"] }
        ]
    })

    readonly property var settingsAliases: ({ "Wi-Fi": "wifi wlan network internet", "Sound": "audio volume output speakers headphones airpods noise cancelling equalizer", "Battery": "power charge charging health cycles",
                                              "Display": "brightness keyboard backlight night light warm scale scaling resolution monitor screen retina hidpi zoom size bigger smaller",
                                              "Notifications": "notification sounds alert chime beep ping tone urgent critical popup timeout seconds duration",
                                              "Crash reports": "crash crashes bug report claude app quit coredump",
                                              "Tailscale": "vpn", "Mouse": "scroll scrolling wheel speed fast slow",
                                              "Claude writes": "ai write rewrite polish text draft reply tone instructions prompt model",
                                              "Default apps": "browser email mail files folders text editor terminal images photos video music player pdf calendar open with",
                                              "App shortcuts": "keyboard shortcuts hyper caps lock keys keybindings hotkeys open app", "Theme": "appearance style look colors",
                                              "Color": "theme accent violet purple blue teal green amber rose graphite gray",
                                              "Background": "wallpaper desktop image picture",
                                              "Theme Editor…": "window background terminal kitty opacity transparency border frame shadow inactive",
                                              "Top bar": "waybar panel menu bar",
                                              "Firefox": "browser tabs tab bar links new window",
                                              "Launcher": "search fuzzy typos shortcuts hints spotlight",
                                              "Computer name": "hostname rename device localsend airplay ferry phone",
                                              "Remote login": "ssh sshd server remote access terminal sharing",
                                              "Update channel": "stable development dev beta branch updates",
                                              "Home Assistant": "home automations buttons lights types",
                                              "App settings": "apps applications preferences",
                                              "Mail": "email settings preferences",
                                              "Opacity": "top bar waybar panel transparency transparent",
                                              "Icon colors": "top bar waybar panel white black light dark text",
                                              "Highlight": "top bar waybar panel active workspace",
                                              "Items": "top bar panel modules icons show hide clock date battery",
                                              "Brightness": "screen dim dimmer brighter backlight",
                                              "Keyboard backlight": "keyboard light lit illumination brightness dim",
                                              "Night light": "night shift warm yellow blue light evening",
                                              "Scale": "scaling resolution monitor screen retina hidpi zoom size bigger smaller",
                                              "Screen Mirroring": "airplay cast mirror apple tv share screen" })
    // Settings › Theme: sub-items (Color with its current value)
    // Settings › Display for the root search: the brightness slider row itself (←/→ work there too), the night light toggle
    // and Scale (opens Display)
    function displayItems() {
        return (disp.bright >= 0 ? [{ kind: "brightness", key: "screen", name: "Brightness", glyph: "sun" }] : [])
            .concat(disp.keys >= 0 ? [{ kind: "brightness", key: "keys", name: "Keyboard backlight", glyph: "keyboard" }] : [])
            .concat([{ kind: "nightlight", name: "Night light", glyph: "moon" },
                     { kind: "nav", name: "Scale", glyph: "monitor", target: "display" }],
                    sys.mirrorAvail ? [{ kind: "nav", name: "Screen Mirroring", glyph: "screen-share", target: "display" }] : [])
    }
    readonly property var installAliases: ({ "Software": "package dnf rpm flatpak flathub app apps program store",
                                             "Webapp": "web app website site pwa url slack teams whatsapp youtube",
                                             "Recommended": "optional home assistant jottacloud deck vscode 1password tailscale thunderbird apostrophe",
                                             "Plugins": "plugin extension addon optional airplay screen mirroring" })
    readonly property var powerAliases: ({ "Lock": "screen", "Sleep": "suspend", "Log out": "logout sign out exit", "Restart": "reboot", "Shut down": "shutdown poweroff power off" })

    // Lower case without diacritics: "keittio" finds Keittiö, "ylavalo" Ylävalo
    function fold(s) { return s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "") }
    // 0 = the whole name, 0.5 = starts with query, 1 = word start, 2 = contains, -1 = no match (q folded). The whole name
    // first: "code" puts Code before Code - OSS, whatever their order in the list.
    function score(text, q) {
        const t = fold(text)
        if (t === q) return 0
        if (t.startsWith(q)) return 0.5
        if (t.split(/[\s\-_.\/]+/).some(w => w.startsWith(q))) return 1
        if (t.includes(q)) return 2
        return -1
    }
    // The last tier: q's letters in order, but not just anywhere (that would match nearly everything). Each letter is at a
    // word start, right after the previous match, or a letter or two after it in the same word: "vsc" → Visual Studio
    // Code, "kattovlo" → Kattovalo. Both folded.
    function fuzzy(t, q) {
        const start = i => i === 0 || /[\s\-_.\/›:]/.test(t[i - 1])
        const from = (qi, ti) => {        // q[qi..] matches from t[ti..]; prev match at ti - 1
            if (qi === q.length) return true
            for (let i = ti; i < t.length; i++) {
                if (t[i] !== q[qi]) continue
                const gap = i - ti
                const ok = qi === 0 ? start(i) : gap === 0 || start(i) || (gap <= 2 && !/[\s\-_.\/›:]/.test(t.slice(ti, i)))
                if (ok && from(qi + 1, i + 1)) return true
            }
            return false
        }
        return q.length >= 2 && from(0, 0)
    }

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
    // Rows that can't be selected: section headers, and notes (kind "note": a line of help in small text, e.g. Settings ›
    // App shortcuts' "the others are in the config files"), unlike a hint, which stands in for the rows ("Loading…")
    function fixedRow(it) { return it.kind === "header" || it.kind === "note" }
    function firstSelectable() {
        for (let i = 0; i < results.length; i++) if (!fixedRow(results[i])) return i
        return 0
    }
    // Moves the selection, skipping header and note rows
    function step(dir) {
        let i = list.currentIndex + dir
        while (i >= 0 && i < results.length && fixedRow(results[i])) i += dir
        if (i < 0 && dir < 0) { topFocused = topExt !== null; return }   // up from the top of the list: a plugin's row
        if (i >= 0 && i < results.length) {
            list.currentIndex = i
            // Up onto a section's first row: its header comes into view too (the list only scrolls to the row itself)
            if (dir < 0 && i > 0 && results[i - 1].kind === "header") Qt.callLater(() => list.positionViewAtIndex(i - 1, ListView.Contain))
            // Down onto the last row that can be selected: the notes below it come into view too
            if (dir > 0 && results.slice(i + 1).every(fixedRow)) Qt.callLater(() => list.positionViewAtEnd())
        }
    }
    readonly property int headerHeight: 40
    // A row's description (sub) wraps, up to subMaxLines (or the row's own subMax: a snippet's lines): each line after
    // the first makes the row this much taller. subPlain: in the name's font instead (a snippet's text, all of it alike)
    readonly property int subMaxLines: 3
    readonly property int subLineHeight: Math.ceil(subMetrics.height)
    readonly property int plainLineHeight: Math.ceil(plainMetrics.height)
    FontMetrics { id: subMetrics; font { family: Theme.font; pixelSize: win.fontSize - 5; weight: win.fontWeight } }
    FontMetrics { id: plainMetrics; font { family: Theme.font; pixelSize: win.fontSize; weight: win.fontWeight } }
    // The lines a row's description takes (an estimate from its width, for the list's height; the row measures its own)
    function subLines(it) {
        if (!it.sub || fixedRow(it)) return 1
        const room = Math.max(1, list.width - iconSize - 70)
        const m = it.subPlain ? plainMetrics : subMetrics
        const lines = keySpaced(it.sub).split("\n").reduce((n, l) => n + Math.max(1, Math.ceil(m.advanceWidth(l) / room)), 0)
        return Math.min(it.subMax || subMaxLines, lines)
    }
    function listHeight() {
        const cap = Math.min(maxRows * (rowHeight + rowGap), listRoom)
        let h = 0
        for (const it of results) {
            h += (fixedRow(it) ? headerHeight : rowHeight + (subLines(it) - 1) * (it.subPlain ? plainLineHeight : subLineHeight)) + rowGap
            if (h >= cap) return cap
        }
        return h
    }

    function hint(text) { return [{ kind: "hint", name: text }] }

    // App rows: with an empty query only allow-listed apps; when searching, also those hidden by sync-apps
    function appEntries(q) {
        const all = apps.filter(e => !e.noDisplay).map(e => ({
            item: { kind: "app", name: e.name, icon: e.icon, entry: e, shown: true },
            text: e.name,
            extra: (e.genericName || "") + " " + (e.keywords || []).join(" ")
        }))
        if (q !== "") for (const h of syncHidden) all.push({ item: { kind: "app", name: h.name, icon: h.icon, path: h.path, shown: false }, text: h.name, extra: h.extra })
        // An app just moved with ⌃Enter: the two sources (DesktopEntries, hidden-apps.sh) update at different moments, so
        // until its new place shows up the row is kept from the snapshot, and its old place is left out
        const out = all.filter(a => { const p = pinPending[appId(a.item)]; return !p || p.shown === a.item.shown })
        for (const id in pinPending) {
            const p = pinPending[id]
            if (!out.some(a => appId(a.item) === id) && (p.shown || q !== "")) out.push({ item: p, text: p.name, extra: "" })
        }
        return out
    }

    // Typed in the root search, a certain old command (only its hash is here) and Enter start hypr/shaders/warp
    readonly property string basicKey: "c6a812e51728d75227cd473fd4d23ff0"
    readonly property var basicRow: ({ kind: "action", name: "SEARCHING FOR *", sub: "LOADING", glyph: "save",
                                       cmd: ["bash", "-c", "pgrep -f '^qs -p .*/shaders/warp' >/dev/null || exec qs -p ~/.config/hypr/shaders/warp"] })

    // The next word boundary from `pos` in direction `dir` (-1 / 1): over any spaces and punctuation, then the word
    function wordPos(s, pos, dir) {
        const isWord = c => c.toLowerCase() !== c.toUpperCase() || /[0-9_]/.test(c)
        const at = i => s.charAt(dir < 0 ? i - 1 : i)
        const inside = i => dir < 0 ? i > 0 : i < s.length
        while (inside(pos) && !isWord(at(pos))) pos += dir
        while (inside(pos) && isWord(at(pos))) pos += dir
        return pos
    }

    function items() {
        const q = query.trim().toLowerCase()
        let all, tail = [], short = false
        if (level === "root" && Qt.md5(q.replace(/\s+/g, "").replace(/[“”„]/g, '"')) === basicKey) return [basicRow]
        if (level === "root") {
            all = rootItems.map(r => ({ item: r, text: r.name, extra: r.extra || "" }))
            // When searching, the root level also finds rows from the sublevels, so there's no need to open a menu first.
            // "from" tells which menu a row comes from; extra adds search words (aliases, alternative spellings).
            if (q !== "") for (const src of [
                // Tools entries ("color" → Color Picker)
                statics.tools.map(t => ({ item: t, text: t.name })),
                // Screenshot actions ("region", "screenshot", "capture")
                statics.screenshot.map(t => ({ item: Object.assign({}, t, { from: "Screenshot" }), text: t.name, extra: "screenshot capture screen" })),
                // Settings items ("wallpaper" → Background, "wifi" → Wi-Fi) plus Theme and Top bar sub-items ("opacity")
                statics.settings.filter(t => t.kind !== "header").map(t => ({ item: Object.assign({}, t, { from: "Settings" }), text: t.name, extra: "settings " + (settingsAliases[t.name] || "") })),
                // (an app's own settings named so, not to come before the app: "mail" finds Mail first, then Mail settings)
                statics.appsettings.filter(t => t.kind !== "header").map(t => {
                    const name = t.appName ? t.appName + " settings" : t.name
                    return { item: Object.assign({}, t, { from: "Settings", name: name }), text: name, extra: "settings apps " + (settingsAliases[t.name] || "") }
                }),
                themes.themeItems().map(t => ({ item: Object.assign({}, t, { from: "Theme", summary: undefined }), text: t.name, extra: "theme " + (settingsAliases[t.name] || "") })),
                look.topbarItems().map(t => ({ item: Object.assign({}, t, { from: "Top bar", summary: undefined }), text: t.name, extra: settingsAliases[t.name] || "" })),
                // Display and Screensaver sub-items ("night" → Night light, "dim" → Brightness, "saver" → Start after)
                displayItems().map(t => ({ item: Object.assign({}, t, { from: "Display" }), text: t.name, extra: "display " + (settingsAliases[t.name] || "") })),
                // Screen Mirroring's receivers ("mirror", "airplay", "olohuone"): Enter starts mirroring right from the search
                sys.mirrorRows().filter(t => t.kind === "mirrordev").map(t => ({ item: Object.assign({}, t, { from: "Screen Mirroring", summary: undefined }),
                                                                                  text: t.name, extra: "screen mirroring " + t.extra })),
                // AirPlay speakers ("airplay", "olohuone"): Enter makes it the sound output
                sys.sinks.filter(d => d.airplay).map(d => ({ item: { kind: "sounddev", id: d.id, name: d.name, glyph: "speaker", from: "Sound",
                                                                     trailGlyph: d.current ? "check" : undefined },
                                                             text: d.name, extra: "airplay sound audio output speaker" })),
                look.screensaverItems().map(t => ({ item: Object.assign({}, t, { from: "Screensaver", summary: undefined }), text: t.name, extra: "screensaver idle lock" })),
                // System's items ("upd" → Update, "cpu" → Status)
                statics.system.map(t => ({ item: Object.assign({}, t, { from: "System", summary: undefined }), text: t.name, extra: t.extra || "" })),
                // Install's sub-items ("flatpak", "webapp", "flathub" → Flatpak)
                statics.install.map(t => ({ item: Object.assign({}, t, { from: "Install", summary: undefined }), text: t.name,
                                            extra: "install " + (installAliases[t.name] || "") })),
                // Only found by searching: names the focused workspace (ToolsLevels › wsname)
                [{ item: { kind: "nav", name: "Rename current space", glyph: "pencil", target: "wsname" }, text: "Rename current space",
                   extra: "workspace name label" }],
                // Power actions ("shut" → Shut down)
                statics.power.map(t => ({ item: t, text: t.name, extra: powerAliases[t.name] || "" })),
                // Apps ("1pas" → 1Password), also one named like a root item (e.g. a webapp next to its menu): the APPS tag and
                // the open-window dot tell them apart
                appEntries(q).map(a => Object.assign({}, a, { item: Object.assign({}, a.item, { from: "Apps" }) })),
                // Home Assistant's devices ("olohuone" → its lights): Enter turns one on/off right from the search
                home.rootRows(),
                // The plugins' own rows (rootRows: Deck's albums, "fm-84" → Atlas)
                ...pluginExts.map(e => e.rootRows ? e.rootRows() : [])
            ]) all = all.concat(src)
            // Rows after the hits as they are, whatever was typed (rootTail: Deck's Search Spotify row, when Deck is in the search)
            if (q !== "") tail = [].concat(...pluginExts.map(e => e.rootTail ? e.rootTail(q) : []))
        } else if (level === "apps") {
            all = appEntries(q)
            if (q === "") all.sort((a, b) => a.text.localeCompare(b.text))
        } else if (level === "keys") {
            all = keyList.map(k => ({ item: { kind: "key", name: k.name, sub: k.sub || undefined, keys: k.keys, section: k.section }, text: k.name,
                                      extra: k.keys + " " + k.section + " " + k.sub }))
        } else if (extOf(level)) {
            const r = extOf(level).items(level, q)
            if (!r.all) return r          // ready-made rows (hints, etc.)
            all = r.all                   // [{ item, text, extra }], filtered by the query below
            tail = r.tail || []           // rows after a search's hits
            short = r.short === true      // thousands of short names (Emoji): no fuzzy matching, the shortest first
        } else if (level === "startup") {
            all = appEntries(q).map(a => {
                const on = autostartIds.indexOf(appId(a.item)) >= 0
                return Object.assign({}, a, { item: Object.assign({}, a.item, { summary: on ? (bgApps[a.item.name] !== undefined ? "at login, hidden" : "at login") : undefined }) })
            })
            if (q === "") return all.sort((a, b) => a.text.localeCompare(b.text)).map(x => x.item)   // a fixed order: toggling doesn't move rows
        } else {
            all = (statics[level] || []).map(r => ({ item: r, text: r.kind === "header" ? "" : r.name }))   // a search drops the headers
        }
        if (q === "") return level === "keys" ? grouped(all.map(x => x.item)) : all.map(x => x.item)
        const scored = []
        // Several words: each may hit the name or the search words ("olohuone kattovalo" → the room is in extra, the name in text)
        const fq = fold(q)
        const words = fq.split(/\s+/).filter(w => w !== "")
        const fuzzyOk = prefs.fuzzy && !short   // letters in order would hit too many of them
        all.forEach((x, i) => {
            let s = score(x.text, fq)
            // An app's own settings ("Firefox settings") right after the app while its name is being typed: "fire" hits
            // both as a start, and the settings come earlier in the list
            if (s >= 0 && s < 1 && x.item.appName && score(x.item.appName, fq) >= 0) s += 0.25
            const extra = x.extra ? fold(x.extra) : ""
            if (s < 0 && extra.includes(fq)) s = 3
            if (s < 0 && words.length > 1) {
                const hay = fold(x.text) + " " + extra
                if (words.every(w => hay.includes(w))) s = 4
                // 5: the same with typos and shortcuts, each word fuzzy ("olohuone kattovlo")
                else if (fuzzyOk && words.every(w => hay.includes(w) || fuzzy(hay, w))) s = 5
            }
            if (s < 0 && fuzzyOk && words.length === 1 && fuzzy(fold(x.text), fq)) s = 5
            if (s >= 0) scored.push({ x: x, s: s, i: i })
        })
        scored.sort((a, b) => (a.s - b.s) || (level === "apps" ? a.x.text.localeCompare(b.x.text) : short ? (a.x.text.length - b.x.text.length) || (a.i - b.i) : a.i - b.i))
        const res = scored.map(o => o.x.item).concat(tail)
        // The calculator's answer ("3*8" → "= 24") first, unless a name starts with what was typed: "7-zip" stays an app
        const sum = level === "root" ? calc.row(query) : null
        if (sum) res.splice(scored.filter(o => o.s <= 0.5).length, 0, sum)
        return level === "keys" ? grouped(res) : res
    }
    readonly property var results: items()

    // The row each level had selected when a sublevel was opened (by name: a search may have been on), so Esc returns to it
    property var lastSel: ({})
    // A level opened from a search ("update" → Update channel), by its name: the level, the search and the row it came from,
    // so Esc goes back to that search like Spotlight does, not to the level's parent (Settings)
    property var fromSearch: ({})
    // Opens a level with this already typed (Deck's Search Spotify row)
    function goSearch(target, text) { go(target); input.text = text }
    function go(target, goingBack) {
        const cur = results[list.currentIndex]
        if (cur && cur.name && target !== level && (parents[target] || "root") === level)   // going down one level
            lastSel[level] = { kind: cur.kind, name: cur.name }
        // back() keeps the record: a sublevel's Esc returns here and this level's Esc still to the search
        if (!goingBack && target !== level)
            fromSearch[target] = query.trim() !== "" ? { level: level, query: query, sel: cur ? { kind: cur.kind, name: cur.name } : null } : undefined
        level = target; input.text = ""; query = ""; armed = ""; topFocused = false; details.close()
        hiddenProc.running = true
        if (target === "keys") keysProc.running = true     // re-read SHORTCUTS.md: changes show up immediately
        list.currentIndex = firstSelectable()
        if (target === "settings" || target === "appsettings") behave.entered("settings")   // the computer name and channel on its rows, Firefox's
        if (target === "display") sys.entered("display")   // Screen Mirroring's rows there
        if (extOf(target)) extOf(target).entered(target)
    }
    // Background apps (⌘W hides them to special:bg, ⌘Q quits): app name -> window class regex, from hypr/background-apps(.local),
    // the same list close-or-hide uses. An open app (also a hidden one) gets a green dot at the right end of its row.
    property var bgApps: ({})
    Sh {
        id: bgAppsProc   // re-read on every open, so an app added to the list works without restarting the shell
        script: 'cd "$HOME/.config/hypr" && cat background-apps background-apps.local 2>/dev/null'
        running: true
        onResult: text => {
            const m = {}
            for (const l of text.split("\n")) {
                const i = l.indexOf(" = ")
                if (i > 0 && !l.startsWith("#")) m[l.slice(0, i).trim()] = l.slice(i + 3).trim()
            }
            win.bgApps = m
        }
    }
    property var runningClasses: []    // classes of all open windows (lowercase)
    // Whether an app has a window open (on any workspace, also in the background): background apps by their class list (bgApps),
    // others by the .desktop file's StartupWMClass or id
    function appRunning(item) { return item.kind === "app" && (item.entry !== undefined || item.path !== undefined) && appClassRe(item) !== "" }
    // The window class regex of a running app (for quit-app --class), "" when it has no window open. A row hidden by
    // sync-apps has only the .desktop file's path: its id is the file name.
    function appClassRe(item) {
        const re = bgApps[item.name]
        if (re !== undefined) return runningClasses.some(c => new RegExp(re, "i").test(c)) ? re : ""
        const wm = (item.entry && item.entry.startupClass || "").toLowerCase()
        const id = appId(item).replace(/\.desktop$/, "").toLowerCase()
        const c = [wm, id].find(c => c !== "" && runningClasses.includes(c))
        return c ? "^" + c.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$" : ""
    }
    // Apps quit with ⌘Q: class regex -> when. Their green dot pulses until the app is gone (or 10 s: it asked about unsaved
    // work or refused), the window list is re-read often meanwhile.
    property var quitting: ({})
    readonly property bool anyQuitting: Object.keys(quitting).length > 0
    function quitPending(item) { const re = appClassRe(item); return re !== "" && quitting[re] !== undefined }
    onRunningClassesChanged: {
        if (!anyQuitting) return
        const left = {}
        for (const re in quitting)
            if (Date.now() - quitting[re] < 10000 && runningClasses.some(c => new RegExp(re, "i").test(c))) left[re] = quitting[re]
        quitting = left
    }
    Timer { interval: 300; repeat: true; running: win.anyQuitting; onTriggered: bgProc.running = true }
    Sh {
        id: bgProc
        script: 'hyprctl -j clients | jq -r \'.[].class\''
        onResult: text => { win.runningClasses = text.split("\n").filter(l => l !== "" && !l.startsWith("__")).map(l => l.toLowerCase()) }
    }
    Timer { interval: 1500; repeat: true; running: win.open; onTriggered: bgProc.running = true }
    // ⌃Enter on an app: the choice goes to ~/.local/state/nightdrive/apps.json ({"shown": [ids], "hidden": [ids]}), then sync-apps
    // updates the overrides (fuzzel/sync-apps) and the list follows
    function appId(item) {
        const id = item.entry ? item.entry.id : item.path.split("/").pop()
        return id.endsWith(".desktop") ? id : id + ".desktop"
    }
    property var pinPending: ({})           // id -> the app's row in its new state, until both sources have caught up
    function togglePin(item) {
        keepSelection()
        const n = Object.assign({}, pinPending)
        n[appId(item)] = Object.assign({}, item, { shown: !item.shown })
        pinPending = n
        pinProc.environment = { "ID": appId(item), "TO": item.shown ? "hidden" : "shown" }
        pinProc.running = true
    }
    // A pending app is done once its new place is in the sources (and its old place is gone); the timer is a fallback
    function prunePins() {
        let changed = false
        const n = Object.assign({}, pinPending)
        for (const id in n) {
            const inApps = apps.some(e => !e.noDisplay && appId({ entry: e }) === id)
            const inHidden = syncHidden.some(h => appId({ path: h.path }) === id)
            if (n[id].shown ? inApps && !inHidden : inHidden && !inApps) { delete n[id]; changed = true }
        }
        if (changed) pinPending = n
    }
    onAppsChanged: prunePins()
    onSyncHiddenChanged: prunePins()
    Timer { id: pinSettle; interval: 5000; onTriggered: win.pinPending = ({}) }
    Sh {
        id: pinProc
        // The id moves to one list and out of the other; other keys in the file are kept (room for more settings later)
        script: 'f="$HOME/.local/state/nightdrive/apps.json"; mkdir -p "${f%/*}"; [ -s "$f" ] || echo "{}" > "$f"
jq --arg id "$ID" --arg to "$TO" \'.shown = ((.shown // []) - [$id]) | .hidden = ((.hidden // []) - [$id]) | .[$to] += [$id]\' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
"$HOME/.config/fuzzel/sync-apps" >/dev/null'
        onResult: { hiddenProc.running = true; pinSettle.restart() }   // (prunePins runs when the lists change)
    }

    // Login apps (Settings › Apps › Startup, ⌥Enter on an app): hypr/scripts/autostart keeps the list and starts them at login
    property var autostartIds: []
    Sh {
        id: autostartProc
        command: [win.scripts + "/autostart", "list"]
        onResult: text => { win.autostartIds = text.split("\n").filter(l => l !== "") }
    }
    function toggleAutostart(item) {
        keepSelection()
        const id = appId(item)
        autostartIds = autostartIds.indexOf(id) >= 0 ? autostartIds.filter(x => x !== id) : autostartIds.concat([id])   // shown at once
        Quickshell.execDetached([scripts + "/autostart", "toggle", id])
    }

    function activate(item) {
        if (!item) return
        if (item.switchBusy) { shake.restart(); return }   // its last change is still waiting (e.g. for the password)
        if (item.kind === "nav") go(item.target)
        else if (item.kind === "app" && level === "startup") toggleAutostart(item)
        else if (item.kind === "app") {
            win.open = false
            // Background app: bring the hidden window back (no second instance)
            if (item.entry && bgApps[item.name] !== undefined)
                Quickshell.execDetached([scripts + "/launch-or-focus", bgApps[item.name], "gtk-launch", item.entry.id + ".desktop"])
            // An app that runs in a terminal (htop, aerc) in the chosen one: execute() would start it without any
            else if (item.entry && item.entry.runInTerminal)
                Quickshell.execDetached([scripts + "/terminal", "--"].concat(item.entry.command))
            else if (item.entry) item.entry.execute(); else Quickshell.execDetached(["gio", "launch", item.path])
        }
        else if (item.kind === "stat" && item.copy !== undefined) sys.copyText(item.copy)   // Public IP, Local IP, Router: as ⌘C
        else if (item.kind === "stat") shake.restart()   // information only
        else if (item.kind === "calc") { sys.copyText(item.copy); win.open = false }   // ready to paste
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
    // ⌘⌫ / ⌥⌫ in the query: a selection goes first, otherwise to the line start (word = only the word before the cursor)
    function deleteBack(word) {
        if (input.selectedText !== "") { input.remove(input.selectionStart, input.selectionEnd); return }
        const end = input.cursorPosition
        let start = 0
        if (word) {
            start = end
            while (start > 0 && /\s/.test(input.text[start - 1])) start--
            while (start > 0 && !/\s/.test(input.text[start - 1])) start--
        }
        if (start < end) input.remove(start, end)
    }

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
    function back() {
        if (detail !== null) { details.close(); return }
        if (tools.picker.back()) return      // Clipboard as a text field's picker: back to the field, its text kept
        if (level === "root") { win.open = false; return }
        const s = fromSearch[level]
        if (s) {
            delete fromSearch[level]
            go(s.level, true)
            input.text = s.query
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
    else { lastMouse = null; lastSel = ({}); fromSearch = ({}); exts.forEach(e => e.opened()); Plugins.check(); go("root"); bgProc.running = true; bgAppsProc.running = true; autostartProc.running = true; updatesProc.running = true; sys.entered("display"); sys.soundRefresh(); input.forceActiveFocus() }
    Component.onCompleted: keysProc.running = true

    Timer { id: disarm; interval: 4000; onTriggered: win.armed = "" }


    // Install › Software's rows and a details card's Tab (the other source)
    function installCmd(src, id) {
        return src === "flatpak" ? term('flatpak install --user flathub "$1"', id) : term('sudo dnf install "$1"', id)
    }
    SystemLevels { id: sys; launcher: win }
    HomeLevels { id: home; launcher: win }
    DefaultAppsLevels { id: defs; launcher: win }
    AppKeyLevels { id: akeys; launcher: win }
    BehaviourLevels { id: behave; launcher: win }
    ClaudeWriteLevels { id: cwrite; launcher: win }
    InstallLevels { id: inst; launcher: win }
    ToolsLevels { id: tools; launcher: win }
    AppearanceLevels { id: look; launcher: win }
    DisplayLevels { id: disp; launcher: win }
    RemoveLevels { id: rm; launcher: win }
    PasswordLevels { id: pw; launcher: win }
    ThemeLevels { id: themes; launcher: win }
    AboutLevels { id: about; launcher: win }
    Calculator { id: calc; launcher: win }
    Instantiator {
        id: pluginLevels
        model: TopBar.plugin.levels
        delegate: Loader { source: "file://" + modelData; onLoaded: item.launcher = win }
        // later: while a file loads, the Instantiator doesn't list its Loader yet (objectAt is null)
        onObjectAdded: Qt.callLater(win.listPluginExts)
        onObjectRemoved: Qt.callLater(win.listPluginExts)
    }
    function listPluginExts() {
        const out = []
        for (let i = 0; i < pluginLevels.count; i++) { const o = pluginLevels.objectAt(i); if (o && o.item) out.push(o.item) }
        pluginExts = out
    }
    Loader {
        id: extLoader
        source: win.extSource
        onLoaded: item.launcher = win
    }
    function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    Sh {
        id: updatesProc
        script: 'cat "$HOME/.cache/nightdrive/updates" 2>/dev/null'
        onResult: text => { win.updates = parseInt(text, 10) || 0 }
    }
    function mirrorRows() { return sys.mirrorRows() }   // DisplayLevels: Screen Mirroring's rows under Display

    // overrides marked by sync-apps → ids of hidden apps
    Sh {
        id: hiddenProc
        command: [Quickshell.env("HOME") + "/.config/quickshell/hidden-apps.sh"]
        onResult: text => {
            win.syncHidden = text.split("\n").filter(l => l.includes("|")).map(l => {
                const f = l.split("|")
                return { path: f[0], name: f[1], icon: f[2], extra: f[3] || "" }
            })
        }
    }

    // A row's shortcut from SHORTCUTS.md ("" = none): apps and the launcher's own items, by name. Names that differ
    // between the launcher and SHORTCUTS.md: shortcutAliases.
    readonly property var shortcutAliases: ({ "kitty": "terminal", "firefox": "browser", "visual studio code": "vs code",
                                              "clipboard": "clipboard history", "emoji": "emoji picker", "keybindings": "this help" })
    function shortcutFor(it) {
        if (!it || !it.name || (it.kind !== "app" && it.kind !== "nav")) return ""
        if (level === "startup") return ""      // there the rows are switches, not apps to open
        // settings pages: "Notifications" is not the ⌘Esc panel, Apps › "Firefox" not Hyper B
        if (it.kind === "nav" && (parents[it.target] === "settings" || parents[it.target] === "appsettings")) return ""
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
    // in a key frame like a row's shortcut; between alternatives (" / ") and around a range (" … ") the separator stays
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
                const t = win.splitKeyText(m[2].trim())
                out.push({ keys: m[1].trim(), name: t[0], sub: t[1], section: section })
            }
            win.keyList = out
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
            win.keyIndex = idx
        }
    }

    // A hair space between key symbols in running text: JetBrains Mono's ⌘⌥⌫ are wider than their cell and overlap side
    // by side (the shortcut rows use letterSpacing instead)
    function keySpaced(t) { return t.replace(/([⌘⌥⇧⌃⌫⌦])(?=[⌘⌥⇧⌃⌫⌦])/g, "$1\u200A") }

    IpcHandler {
        target: "launcher"
        function toggle(): void { win.open = !win.open }
        function close(): void { win.open = false }
        // openLevel apps | keys | root: opens a sublevel directly
        // ⌘⇧V (clipboard) over a text field (a level in a Levels file's `inputs`) opens Clipboard as a picker for it
        function openLevel(level: string): void { if (level === "clipboard" && tools.picker.begin()) return; win.open = true; win.go(level) }
        function setQuery(text: string): void { input.text = text }
        // askClaude: ⌘⌥Enter with the launcher open and a non-empty query → sends the text to Claude Code (hypr/scripts/terminal-or-claude). Returns "ok" or "".
        function askClaude(): string {
            const q = win.query.trim()
            if (!win.open || q === "" || (win.level !== "root" && win.level !== "apps")) return ""
            win.open = false
            // the session's name (claude -n) is the question's start, to find it again in the Claude menu and /resume
            const name = q.length > 40 ? q.slice(0, 40).replace(/\s+\S*$/, "") + "…" : q
            Quickshell.execDetached([win.scripts + "/terminal-or-claude", "--name", name, "--", q])
            return "ok"
        }
        // rows: the open level's title, footer, selected index and rows as JSON, primitive fields only (automated testing)
        function rows(): string {
            const plain = r => { const o = {}; for (const k in r) if (r[k] === null || typeof r[k] !== "object" && typeof r[k] !== "function") o[k] = r[k]; return o }
            return JSON.stringify({ level: win.level, title: win.titles[win.level] || "", footer: win.footer, sel: list.currentIndex,
                                    rows: win.results.map(plain) })
        }
        // pick <index>: selects a row like Enter (automated testing)
        function pick(index: int): void { const r = win.results[index]; if (r) win.activate(r); else shake.restart() }
        // detailTab: Tab in a package's or plugin's details, e.g. a plugin's on/off switch (automated testing)
        function detailTab(): void { if (win.detail !== null) details.switchSource(); else shake.restart() }
        // ⌘⌫ (bindings.lua): in Background removes your own wallpaper, elsewhere deletes the query to the cursor's left (like macOS)
        function deleteSelected(): void {
            if (!win.open) return
            if (win.extDelete()) {}
            else win.deleteBack(false)
        }
        // ⌘Q (hypr/scripts/quit-app asks first): with the launcher open quits the selected app if it's running, otherwise
        // shakes. Returns "ok" when the launcher is open, so the window under it is never quit; "" when it's closed.
        function quitSelected(): string {
            if (!win.open) return ""
            const re = win.selApp ? win.appClassRe(win.selApp) : ""
            if (re === "") { shake.restart(); return "ok" }
            Quickshell.execDetached([win.scripts + "/quit-app", "--class", re])
            win.quitting = Object.assign({}, win.quitting, { [re]: Date.now() })
            bgProc.running = true
            return "ok"
        }
        // ⌥⌫: deletes the word to the cursor's left (Hyprland's binding takes the key, so the launcher does it here)
        function deleteWord(): void { if (win.open) win.deleteBack(true) }
        function stepUp(): void { win.detail !== null ? details.scroll(-win.rowHeight) : win.step(-1) }
        function stepDown(): void { win.detail !== null ? details.scroll(win.rowHeight) : win.topFocused ? (win.topFocused = false) : win.step(1) }
        function back(): void { win.back() }
    }

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
            Row {
                width: parent.width
                height: 44
                Text {
                    id: crumb
                    visible: win.level !== "root"
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 14
                    rightPadding: 6
                    text: (win.titles[win.level] || win.level) + "  ›"
                    color: Theme.dim
                    font { family: Theme.font; pixelSize: win.fontSize + 1; weight: win.fontWeight }
                }
                TextInput {
                    id: input
                    echoMode: win.level === "wifipw" ? TextInput.Password : TextInput.Normal   // Wi-Fi › Password
                    width: parent.width - (crumb.visible ? crumb.width : 0)
                    height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    leftPadding: crumb.visible ? 4 : 14
                    color: Theme.text
                    selectionColor: Theme.sel
                    font { family: Theme.font; pixelSize: win.fontSize + 2; weight: win.fontWeight }
                    focus: true
                    clip: true
                    onTextChanged: { if (win.detail !== null) details.close()   // a new search (IPC setQuery)
                                     win.query = text; win.armed = ""; win.topFocused = false; list.currentIndex = win.firstSelectable() }
                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier
                        if (win.topFocused && win.topExt && win.topExt.topKey(event)) { event.accepted = true; return }
                        // ⌘C (Hyprland sends Ctrl+Insert; Ctrl+C too) on a row with a `copy` value, e.g. an IP address;
                        // selected text in the search field is copied as usual
                        const copyRow = win.results[list.currentIndex]
                        if (ctrl && (event.key === Qt.Key_Insert || event.key === Qt.Key_C) && copyRow && copyRow.copy !== undefined && selectedText === "") {
                            sys.copyText(copyRow.copy); event.accepted = true; return
                        }
                        if (win.detail !== null) {         // details: Enter installs / removes, C sets up with Claude, arrows scroll, typing does nothing
                            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) win.back()
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) details.confirm()
                            else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) details.switchSource()
                            else if (event.key === Qt.Key_C && !ctrl) details.setup()
                            else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) details.scroll(win.rowHeight)
                            else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) details.scroll(-win.rowHeight)
                            else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Space) details.scroll(details.height - win.rowHeight)
                            else if (event.key === Qt.Key_PageUp) details.scroll(-(details.height - win.rowHeight))
                            event.accepted = true
                            return
                        }
                        // Esc with a search typed clears it first (on any level); with an empty one it goes back / closes
                        if (event.key === Qt.Key_Escape) { if (text !== "") text = ""; else win.back(); event.accepted = true }
                        else if (ctrl && event.key === Qt.Key_Space) { if (win.topExt) win.topExt.topPress(); event.accepted = true }
                        // Delete: removes your own wallpaper in Background, the selected snippet in Snippets (empty search). ⌘⌫
                        // arrives as ⇧Home + Delete with the keyd plugin (plugins/keyd/app.conf), so it does the same
                        else if (event.key === Qt.Key_Delete && win.extDelete()) event.accepted = true
                        // Backspace with an empty search goes back; Ctrl+⌫ (⌥⌫ with keyd: delete a word) doesn't
                        else if (event.key === Qt.Key_Backspace && !ctrl && text === "" && win.level !== "root") { win.back(); event.accepted = true }
                        // ⌥← / ⌥→ move by word, like in macOS (Hyprland sends them as Alt+arrows); ⇧ selects
                        else if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                            const pos = win.wordPos(text, cursorPosition, event.key === Qt.Key_Left ? -1 : 1)
                            if (event.modifiers & Qt.ShiftModifier) moveCursorSelection(pos, TextInput.SelectCharacters)
                            else { deselect(); cursorPosition = pos }
                            event.accepted = true
                        }
                        else if (win.grid && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                            win.step(event.key === Qt.Key_Left ? -1 : 1); event.accepted = true
                        } else if (win.grid && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
                            const i = list.currentIndex + (event.key === Qt.Key_Down ? win.gridCols : -win.gridCols)
                            if (i >= 0 && i < win.results.length) list.currentIndex = i
                            else if (i < 0) win.topFocused = win.topExt !== null
                            event.accepted = true
                        } else if (win.extLevel && ctrl && (event.key === Qt.Key_Up || event.key === Qt.Key_Down) && win.extMove(event.key === Qt.Key_Up ? -1 : 1)) {
                            event.accepted = true
                        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && (win.results[list.currentIndex] || {}).kind === "brightness") {
                            disp.stepBright(event.key === Qt.Key_Left ? -1 : 1, win.results[list.currentIndex].key); event.accepted = true
                        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && (win.results[list.currentIndex] || {}).kind === "slider") {
                            sys.stepSlider(win.results[list.currentIndex].key, event.key === Qt.Key_Left ? -1 : 1); event.accepted = true
                        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && (win.results[list.currentIndex] || {}).slider !== undefined) {
                            home.stepSlide(win.results[list.currentIndex], event.key === Qt.Key_Left ? -1 : 1); event.accepted = true
                        } else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
                            win.step(1); event.accepted = true
                        } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
                            win.step(-1); event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const cur = win.results[list.currentIndex]
                            if (win.selApp && ctrl) win.togglePin(cur)
                            else if (win.selApp && (event.modifiers & Qt.AltModifier)) win.toggleAutostart(cur)
                            else if (win.extLevel && cur && (event.modifiers & Qt.ShiftModifier)) win.extShift(cur)
                            else if (win.extLevel && cur && ctrl && win.extCtrl(cur)) {}
                            else if (win.results.length === 0) shake.restart()
                            else win.activate(cur)
                            event.accepted = true
                        }
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                // On the grid level the list is hidden, but its currentIndex is still the selection (keys, Enter)
                visible: !win.grid && win.detail === null
                height: visible ? win.listHeight() : 0
                model: win.results
                clip: true
                currentIndex: 0
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                spacing: win.rowGap
                TouchScroll { view: list; step: win.rowHeight + win.rowGap }
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isHeader: modelData.kind === "header"
                    readonly property bool isNote: modelData.kind === "note"
                    readonly property bool current: !isHeader && !isNote && !win.topFocused && index === list.currentIndex
                    readonly property bool noIcon: modelData.kind === "key" || modelData.kind === "hint" || isHeader || isNote
                    readonly property bool armedNow: (modelData.kind === "action" && modelData.confirm === true && win.armed === modelData.name)
                                                    || (modelData.armKey !== undefined && win.armed === modelData.armKey)
                    readonly property bool chevron: modelData.kind === "nav" || modelData.kind === "menu" || modelData.chevron === true
                    width: list.width
                    readonly property int extraLines: subText.visible ? Math.max(0, subText.lineCount - 1) : 0
                    // A taller row keeps its icon and right side at the name and the first line, not in the middle
                    readonly property bool plain: modelData.subPlain === true
                    readonly property int lineH: plain ? win.plainLineHeight : win.subLineHeight
                    readonly property real topShift: -extraLines * lineH / 2
                    height: isHeader || isNote ? win.headerHeight : win.rowHeight + extraLines * lineH
                    radius: 10
                    color: current ? Theme.sel : "transparent"

                    // Icon: app = image, root item = Lucide glyph, keybinding = no icon
                    Item {
                        id: slot
                        visible: !row.noIcon
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
                        width: win.iconSize; height: win.iconSize
                        LevelRing {      // row.slider (Home's lights): the brightness as a ring around the bulb
                            id: brightRing
                            anchors.centerIn: parent
                            visible: row.modelData.slider !== undefined
                            size: win.iconSize + 12
                            // while dragged the rows aren't rebuilt (Home.holdBright), so the ring follows the mouse itself
                            value: rowArea.sliding ? rowArea.dragV : row.modelData.slider || 0
                            strength: row.current ? 1 : 0.7
                        }
                        AppIcon {
                            anchors.fill: parent
                            visible: (row.modelData.kind === "app" || row.modelData.iconFile !== undefined) && row.modelData.glyph === undefined && source !== ""
                            sourceSize: Qt.size(win.iconSize * 2, win.iconSize * 2)
                            name: row.modelData.iconFile !== undefined ? row.modelData.iconFile    // Install › Software
                                : row.modelData.kind === "app" ? (row.modelData.icon || "") : ""
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: row.modelData.emoji !== undefined
                            text: row.modelData.emoji !== undefined ? row.modelData.emoji : ""
                            font.pixelSize: win.iconSize - 6
                        }
                        Rectangle {      // Theme › Color: swatch (selected = border)
                            anchors.centerIn: parent
                            visible: row.modelData.swatch !== undefined
                            width: 20; height: 20; radius: 10
                            color: row.modelData.swatch || "transparent"
                            border.width: row.modelData.summary === "current" ? 2 : 0
                            border.color: Theme.accent
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: row.modelData.glyph !== undefined
                            text: row.modelData.glyph !== undefined ? Icons.g(row.modelData.glyph) : ""
                            color: row.modelData.glyphColor !== undefined ? row.modelData.glyphColor   // Home: a light that's on is yellow
                                 : row.modelData.dimmed ? Theme.dim : row.current ? Theme.accent : Theme.text
                            font { family: Icons.familyLight; pixelSize: win.iconSize - 2 }
                        }
                    }
                    Text {
                        id: nameText
                        // A second line: an album's artist, or the description of an Install search result (row.modelData.sub)
                        readonly property bool twoLines: !!row.modelData.artist || !!row.modelData.sub
                        readonly property bool subLine: !!row.modelData.sub
                        anchors {
                            left: row.noIcon ? parent.left : slot.right; leftMargin: 16
                            right: keyFrames.visible ? keyFrames.left : shortcut.visible ? shortcut.left : trailing.left; rightMargin: (row.modelData.kind === "key" ? 24 : 12) + (dot.visible ? 19 : 0) + (badge.visible ? badge.implicitWidth + 10 : 0) + (note.visible ? note.implicitWidth + 10 : 0)   // keybindings get more room before the keys (description is elided with …)
                            verticalCenter: parent.verticalCenter
                            verticalCenterOffset: twoLines ? (subLine ? (row.plain ? -row.lineH / 2 : -9) - row.extraLines * row.lineH / 2 : -7) : 0
                        }
                        elide: Text.ElideRight
                        // liveName: a name that changes often (Status' processes), bound here instead of rebuilding the rows
                        text: row.modelData.liveName !== undefined ? sys.liveText(row.modelData.liveName)
                            : row.isHeader ? row.modelData.name.toUpperCase()
                            : row.modelData.name
                        color: row.armedNow ? Theme.primary : (row.isHeader ? Theme.primary : row.modelData.kind === "hint" || row.isNote || row.modelData.dimmed ? Theme.dim : (row.current ? Theme.accent : Theme.text))
                        font { family: Theme.font; pixelSize: row.isHeader ? win.fontSize - 5 : row.isNote ? win.fontSize - 4 : nameText.subLine && !row.plain ? win.fontSize - 2 : win.fontSize; weight: row.isHeader ? Font.Bold : win.fontWeight; letterSpacing: row.isHeader ? 1.5 : 0 }
                        topPadding: row.isHeader ? 10 : 0
                    }
                    Text {      // a row that asks first, asked: what a second Enter does (armHint), after the name in smaller text
                        id: armTag
                        visible: row.armedNow
                        anchors { left: nameText.left; leftMargin: nameText.contentWidth + 12; baseline: nameText.baseline }
                        width: Math.max(0, nameText.width - nameText.contentWidth - 12)
                        elide: Text.ElideRight
                        text: "— " + win.keySpaced(row.modelData.armHint || "Enter again to confirm")
                        color: Theme.primary
                        font { family: Theme.font; pixelSize: win.fontSize - 4 }
                    }
                    Text {      // EXPERIMENTAL after a plugin's name (Install › Plugins)
                        id: expTag
                        visible: !!row.modelData.experimental && !row.armedNow
                        anchors { left: nameText.left; leftMargin: nameText.contentWidth + 10; baseline: nameText.baseline }
                        text: "EXPERIMENTAL"
                        color: Theme.caution
                        font { family: Theme.font; pixelSize: win.fontSize - 7; letterSpacing: 1 }
                    }
                    Text {      // EXTERNAL: a plugin from elsewhere (nightdrive plugins add), not one of Nightdrive's own
                        id: extTag
                        visible: !!row.modelData.external && !row.armedNow
                        anchors { left: nameText.left; leftMargin: nameText.contentWidth + 10 + (expTag.visible ? expTag.implicitWidth + 10 : 0); baseline: nameText.baseline }
                        text: "EXTERNAL"
                        color: Theme.primary
                        font { family: Theme.font; pixelSize: win.fontSize - 7; letterSpacing: 1 }
                    }
                    Text {      // the other group's row in a Plugins or Recommended search (RECOMMENDED / PLUGINS): here, so the
                                // right side keeps its installed / off like the group's own rows
                        visible: row.modelData.groupTag !== undefined && !row.armedNow
                        anchors { left: nameText.left; baseline: nameText.baseline
                                  leftMargin: nameText.contentWidth + 10 + (expTag.visible ? expTag.implicitWidth + 10 : 0) + (extTag.visible ? extTag.implicitWidth + 10 : 0) }
                        text: visible ? row.modelData.groupTag.toUpperCase() : ""
                        color: Theme.primary
                        font { family: Theme.font; pixelSize: win.fontSize - 7; letterSpacing: 1 }
                    }
                    Text {      // the description wraps (subMaxLines at most): the row grows with it
                        id: subText
                        visible: nameText.twoLines
                        anchors { left: nameText.left; right: nameText.right; top: nameText.bottom; topMargin: nameText.subLine ? 0 : -1 }
                        wrapMode: nameText.subLine ? Text.Wrap : Text.NoWrap
                        maximumLineCount: row.modelData.subMax || win.subMaxLines
                        lineHeightMode: Text.FixedHeight
                        lineHeight: row.lineH
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: win.keySpaced(row.modelData.sub || (row.modelData.artist || "").toUpperCase())
                        color: row.plain ? nameText.color : row.modelData.sub ? Theme.dim : Theme.primary
                        font { family: Theme.font; pixelSize: row.plain ? win.fontSize : nameText.subLine ? win.fontSize - 5 : win.fontSize - 6; weight: nameText.subLine ? win.fontWeight : Font.Normal
                               letterSpacing: nameText.subLine ? 0 : 1 }
                    }
                    Rectangle {      // the row's shortcut (shortcutFor) in a key frame like the footer's, before the › of a submenu;
                        id: shortcut     // not where the right side is taken. capKeys: a row's own keys (Settings › Apps › App shortcuts)
                        readonly property string keys: row.modelData.capKeys !== undefined ? row.modelData.capKeys
                            : !win.prefs.shortcuts || trailing.tag || row.modelData.keys !== undefined || row.armedNow
                            || (row.modelData.summary !== undefined && row.modelData.summary !== "") ? "" : win.shortcutFor(row.modelData)
                        // On a narrow card only where the whole name still fits beside it
                        visible: keys !== "" && (!win.narrow || nameText.x + nameText.implicitWidth + width + trailing.width + 60 < row.width)
                        anchors { right: trailing.left; rightMargin: trailing.text !== "" ? 18 : 0; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
                        width: shortcutCaps.implicitWidth + 14; height: 24; radius: 6
                        color: "transparent"
                        border { width: 1; color: Theme.dim }
                        Row {        // the footer's keycaps: Lucide glyphs for ⌘ ⇧ ⌥ ⌃ (JetBrains Mono's ⇧ is a faint outline)
                            id: shortcutCaps
                            anchors.centerIn: parent
                            spacing: 4
                            Repeater {
                                model: shortcut.keys.split(/\s+/).filter(k => k !== "").map(k => win.keySymbolNames[k] || k)
                                Keycap { required property string modelData; key: modelData }
                            }
                        }
                    }
                    Row {            // Keybindings: a key's combinations in key frames like a row's shortcut (keyParts)
                        id: keyFrames
                        visible: row.modelData.keys !== undefined
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
                        spacing: 6
                        Repeater {
                            // On a narrow card only the first combination ("Hyper B / ⌘ B" → "Hyper B"): the name needs the room
                            model: !keyFrames.visible ? [] : win.narrow ? win.keyParts(row.modelData.keys).slice(0, 1) : win.keyParts(row.modelData.keys)
                            Rectangle {
                                id: part
                                required property var modelData
                                readonly property bool frame: modelData.caps !== undefined
                                width: frame ? partCaps.implicitWidth + 14 : partText.implicitWidth; height: 24; radius: 6
                                color: "transparent"
                                border { width: part.frame ? 1 : 0; color: Theme.dim }
                                Row {
                                    id: partCaps
                                    visible: part.frame
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Repeater {
                                        model: part.frame ? part.modelData.caps.map(k => win.keySymbolNames[k] || k) : []
                                        Keycap { required property string modelData; key: modelData }
                                    }
                                }
                                Text {
                                    id: partText
                                    visible: !part.frame
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: part.frame ? "" : part.modelData.text
                                    color: Theme.dim
                                    font { family: Theme.font; pixelSize: win.fontSize - 5 }
                                }
                            }
                        }
                    }
                    Toggle {         // row.switchOn: an on/off switch like the top bar menus' (MenuHeader), instead of "on"/"off"
                        id: rowSwitch    // row.switchBusy: still changing (rowArea above takes the clicks; activate() refuses it)
                        visible: row.modelData.switchOn !== undefined
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
                        checked: row.modelData.switchOn === true
                        busy: row.modelData.switchBusy === true
                    }
                    Text {
                        id: trailing
                        anchors { right: parent.right; rightMargin: 16 + (rowSwitch.visible ? 34 + 14 : 0); verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
                        width: Math.min(implicitWidth, row.width * 0.42)
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        // from = submenu a root-level search hit comes from (small violet tag)
                        readonly property bool tag: row.modelData.from !== undefined
                        readonly property bool glyphOnly: row.modelData.trailGlyph !== undefined
                            || (!tag && row.modelData.keys === undefined && !(row.modelData.summary !== undefined && row.modelData.summary !== "" && !row.armedNow) && row.chevron)
                        text: row.modelData.trailGlyph !== undefined ? Icons.g(row.modelData.trailGlyph)      // Top bar › Items: ✓ / – (hidden)
                            : row.modelData.live !== undefined ? sys.liveText(row.modelData.live)   // updates without rebuilding the rows
                            : tag ? row.modelData.from.toUpperCase() : row.modelData.keys !== undefined ? ""   // keyFrames
                            : (row.modelData.summary !== undefined && row.modelData.summary !== "" && !row.armedNow ? row.modelData.summary
                            : (row.chevron ? Icons.g("chevron-right") : ""))
                        color: row.modelData.trailGlyph !== undefined ? (row.modelData.dimmed ? Theme.dim : row.current ? Theme.accent : Theme.text)
                             : tag ? Theme.primary : (row.modelData.keys !== undefined && row.current ? Theme.accent : Theme.dim)
                        font { family: glyphOnly ? Icons.familyLight : Theme.font; pixelSize: glyphOnly ? win.iconSize - 6 : tag ? win.fontSize - 6 : row.modelData.kind === "album" ? win.fontSize - 5 : win.fontSize - 3
                               letterSpacing: tag ? 1 : 0 }   // tags: normal weight and spacing, the same as an album's artist
                    }
                    Rectangle {      // green dot right after the name: the app has a window open (including one hidden to the background by ⌘W)
                        id: dot
                        visible: win.appRunning(row.modelData)
                        x: nameText.x + Math.min(nameText.contentWidth, nameText.width) + 10
                        anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: row.topShift
                        width: 9; height: 9; radius: 5
                        color: Theme.ok
                        // ⌘Q pressed: pulses until the app is gone
                        readonly property bool quitting: visible && win.anyQuitting && win.quitPending(row.modelData)
                        SequentialAnimation on opacity {
                            running: dot.quitting; loops: Animation.Infinite
                            onRunningChanged: if (!running) dot.opacity = 1
                            NumberAnimation { to: 0.15; duration: 350; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 350; easing.type: Easing.InOutSine }
                        }
                    }
                    Text {           // row.modelData.note: small dim text after the name (Settings › Apps › Home Assistant: how many there are)
                        id: note
                        visible: row.modelData.note !== undefined
                        x: nameText.x + Math.min(nameText.contentWidth, nameText.width) + 10
                        anchors.baseline: nameText.baseline
                        text: visible ? row.modelData.note : ""
                        color: Theme.dim
                        opacity: 0.55   // further back than the summaries on the right: a side note
                        font { family: Theme.font; pixelSize: win.fontSize - 5 }
                    }
                    Text {           // a small mark after the name (and the dot): row.modelData.badge, a Lucide name (Home: "pin")
                        id: badge
                        visible: row.modelData.badge !== undefined
                        x: nameText.x + Math.min(nameText.contentWidth, nameText.width) + 10 + (dot.visible ? 19 : 0)
                        anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: row.topShift
                        text: visible ? Icons.g(row.modelData.badge) : ""
                        color: Theme.primary   // the theme colour, like section headers: it has to stand out
                        font { family: Icons.family; pixelSize: win.fontSize - 2 }
                    }
                    Slider {         // Settings › Display › Brightness, Sound: above the row's MouseArea, so it gets the drag
                        // Sound › Headphones › Battery: a meter (no knob, not draggable), green while charging, red when low
                        visible: row.modelData.kind === "brightness" || row.modelData.kind === "slider" || row.modelData.kind === "battery"
                        z: 1
                        // after the name ("Screen" in Display, "Brightness" in a search), lined up while the name is short
                        anchors { left: slot.right; leftMargin: Math.max(120, 16 + nameText.implicitWidth + 28); right: trailing.left; rightMargin: 20; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
                        value: row.modelData.kind === "slider" || row.modelData.kind === "battery" ? row.modelData.value : Math.max(0, row.modelData.key === "keys" ? disp.keys : disp.bright)
                        readOnly: row.modelData.kind === "battery"
                        fillColor: row.modelData.charging ? Theme.ok : row.modelData.low ? Theme.danger : Theme.accent
                        dimmed: !!row.modelData.dimmed
                        trackColor: Qt.rgba(1, 1, 1, 0.1)   // the same on and off the selected row (Theme.border nearly matches Theme.sel)
                        onMoved: v => { list.currentIndex = row.index; row.modelData.kind === "slider" ? sys.setSlider(row.modelData.key, v) : disp.setBright(v, row.modelData.key) }
                    }
                    MouseArea {
                        id: rowArea
                        cursorShape: Qt.PointingHandCursor
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !row.isHeader && !row.isNote
                        // row.slider (Home's lights): a sideways drag sets the brightness, a click still turns it on/off
                        property real pressX: -1
                        property bool sliding: false
                        property real dragV: 0
                        onPressed: mouse => { pressX = mouse.x; sliding = false }
                        onPositionChanged: mouse => {
                            if (pressed && row.modelData.slider !== undefined && (sliding || Math.abs(mouse.x - pressX) > 8)) {
                                if (!sliding) { sliding = true; list.currentIndex = row.index; Home.holdBright(true) }
                                // the drag spans from the name to the right edge (the ring shows it)
                                dragV = Math.max(0, Math.min(1, (mouse.x - nameText.x) / (row.width - 16 - nameText.x)))
                                home.slide(row.modelData, dragV)
                                return
                            }
                            win.hover(rowArea, mouse, row.index)
                        }
                        onReleased: if (sliding) Home.holdBright(false)
                        onCanceled: if (sliding) { sliding = false; Home.holdBright(false) }
                        onClicked: { if (sliding) { sliding = false; return } win.activate(row.modelData) }
                    }
                }
            }

            // Install / Remove: a package's or plugin's details (DetailCard.qml), in place of the list
            DetailCard { id: details; launcher: win; width: parent.width; onPluginToggled: inst.reloadPlugins() }

            // Settings › Background: previews in two columns, name below; current wallpaper marked with ✓
            GridView {
                id: wallGrid
                visible: win.grid
                width: parent.width
                readonly property int thumbH: Math.round((cellWidth - 12) * 390 / 600)
                cellWidth: width / win.gridCols
                cellHeight: thumbH + 40
                height: visible ? Math.min(Math.ceil(win.results.length / win.gridCols) * cellHeight, 2.2 * cellHeight) : 0
                model: visible ? win.results : []
                currentIndex: win.topFocused ? -1 : list.currentIndex
                highlightMoveDuration: 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                TouchScroll { view: wallGrid; step: wallGrid.cellHeight }
                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool current: !win.topFocused && index === list.currentIndex
                    readonly property bool active: modelData.path === themes.wallCurrent
                    width: wallGrid.cellWidth
                    height: wallGrid.cellHeight
                    Rectangle {
                        id: frame
                        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                        width: parent.width - 12
                        height: wallGrid.thumbH
                        radius: 8
                        color: Theme.bg
                        Text {
                            visible: cell.modelData.kind === "walladd"
                            anchors.centerIn: parent
                            text: Icons.g("plus")
                            color: cell.current ? Theme.accent : Theme.dim
                            font { family: Icons.family; pixelSize: 44 }
                        }
                        ClippingRectangle {      // preview with rounded corners (frame's inner radius)
                            anchors { fill: parent; margins: 3 }
                            radius: 6
                            color: "transparent"
                            Image {
                                anchors.fill: parent
                                source: cell.modelData.thumb ? "file://" + cell.modelData.thumb : ""
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 600
                            }
                        }
                        Rectangle {      // selection frame
                            anchors.fill: parent
                            radius: 8
                            color: "transparent"
                            border.width: cell.current ? 3 : 1
                            border.color: cell.current ? Theme.accent : Theme.border
                        }
                        Rectangle {      // current wallpaper
                            visible: cell.active
                            anchors { top: parent.top; right: parent.right; margins: 10 }
                            width: 26; height: 26; radius: 13
                            color: Theme.primary
                            Text {
                                anchors.centerIn: parent
                                text: Icons.g("check")
                                color: Theme.bg
                                font { family: Icons.family; pixelSize: 16 }
                            }
                        }
                    }
                    Text {
                        anchors { top: frame.bottom; topMargin: 6; left: frame.left; right: frame.right; leftMargin: 4; rightMargin: 4 }
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        readonly property bool armedNow: win.armed === "del:" + cell.modelData.path
                        text: armedNow ? "⌘⌫ again to delete" : cell.modelData.name + (cell.modelData.group ? "  ·  " + cell.modelData.group : "")
                        color: armedNow ? Theme.primary : cell.current ? Theme.accent : (cell.active ? Theme.text : Theme.dim)
                        font { family: Theme.font; pixelSize: win.fontSize - 3; weight: win.fontWeight }
                    }
                    MouseArea {
                        id: cellArea
                        cursorShape: Qt.PointingHandCursor
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: mouse => win.hover(cellArea, mouse, cell.index)
                        onClicked: win.activate(cell.modelData)
                    }
                }
            }

            Row {
                visible: win.noHit
                anchors.right: parent.right
                rightPadding: 6
                spacing: 6
                Repeater {
                    model: ["command", "option", "corner-down-left"]
                    Rectangle {
                        required property string modelData
                        width: 22; height: 19; radius: 5
                        color: "transparent"
                        border.color: Theme.dim
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: Icons.g(parent.modelData)
                            color: Theme.dim
                            font { family: Icons.family; pixelSize: 12 }
                        }
                    }
                }
                Text {
                    text: "Send to Claude"
                    color: Theme.dim
                    font { family: Theme.font; pixelSize: 12 }
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 3
                }
            }

            Flow {     // footer: the keys of this level, as key caps + what they do; on a narrow card in more lines
                id: footerFlow
                visible: win.footer !== ""
                anchors.right: parent.right
                // As wide as its parts in one line (right-aligned), at most the card's width
                readonly property real natural: children.reduce((w, c) => w + (c instanceof Row ? c.implicitWidth + spacing : 0), 0) - spacing
                width: Math.min(parent.width, natural + rightPadding)
                rightPadding: 6
                spacing: 6      // a part's leftPadding makes it 18 between parts
                Repeater {
                    model: win.footerParts
                    Row {
                        id: part
                        required property var modelData
                        required property int index
                        leftPadding: index > 0 ? 12 : 0
                        spacing: 4
                        Rectangle {      // one frame around the part's keys (⌃ ↵)
                            visible: part.modelData.keys.length > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: caps.implicitWidth + 12; height: 22; radius: 6
                            color: "transparent"
                            border { width: 1; color: Theme.dim }
                            Row {
                                id: caps
                                anchors.centerIn: parent
                                spacing: 4
                                Repeater {
                                    model: part.modelData.keys
                                    Keycap { required property string modelData; key: modelData }
                                }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: part.modelData.keys.length ? 3 : 0
                            text: part.modelData.text.charAt(0).toUpperCase() + part.modelData.text.slice(1)
                            color: Theme.dim
                            font { family: Theme.font; pixelSize: 12 }
                        }
                    }
                }
            }
        }
    }
}
