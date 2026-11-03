import QtQuick
import Quickshell

// The launcher's levels from other files, in one place: each answers the same questions (items, activate, footer,
// entered; the optional ones in Launcher.qml: extShift, extCtrl, extDelete, extMove, topRow, liveText). Kept apart from
// Launcher.qml so a new Levels file goes in this list only, and the launcher's other parts reach one with
// launcher.levels.<name> (Settings moving to an app of its own, #1833, takes its files out of here).
// WifiLevels, BluetoothLevels, SoundLevels (Sound, Headphones), TailscaleLevels, StatusLevels, MirroringLevels, HomeLevels
// (Home Assistant), DefaultAppsLevels, AppKeyLevels (App shortcuts), BehaviourLevels (Mouse, Launcher, Firefox, Computer
// name, Remote login, Notifications, Crash reports, Update channel), RegionLevels, InstallLevels, ToolsLevels (Clipboard, Emoji,
// Snippets), AppearanceLevels (Top bar, Screensaver), DisplayLevels (Display, Battery), RemoveLevels, PasswordLevels (with
// 1Password), ThemeLevels (Theme, Background), ClaudeWriteLevels, ClaudeAccessLevels, SendClaudeLevels, AskClaudeLevels,
// AboutLevels, the plugins' and the private extension.
Item {
    id: root
    required property var launcher

    property alias wifi: wifiLv
    property alias bt: btLv
    property alias sound: soundLv
    property alias ts: tsLv
    property alias stats: statsLv
    property alias mirror: mirrorLv
    property alias home: homeLv
    property alias defs: defsLv
    property alias akeys: akeysLv
    property alias behave: behaveLv
    property alias region: regionLv
    property alias cwrite: cwriteLv
    property alias caccess: caccessLv
    property alias sendclaude: sendclaudeLv
    property alias askHint: askHintLv
    property alias ask: askLv
    property alias inst: instLv
    property alias tools: toolsLv
    property alias look: lookLv
    property alias disp: dispLv
    property alias rm: rmLv
    property alias pw: pwLv
    property alias themes: themesLv
    property alias about: aboutLv
    property alias calc: calcLv

    // The installed plugins' level files (their <Name>Levels.qml, TopBar.plugin.levels: Deck's Music) come after the core's
    property var pluginExts: []
    // Personal additions from a private overlay: local/LauncherExtension.qml (not in the repo, see README). It may add
    // root items and whole levels; shell.qml sets the launcher's extSource when the file exists
    readonly property var ext: extLoader.item
    readonly property var exts: [wifiLv, btLv, soundLv, tsLv, statsLv, mirrorLv, homeLv, defsLv, akeysLv, behaveLv, regionLv, instLv, toolsLv, lookLv, dispLv, rmLv, pwLv, themesLv, cwriteLv, caccessLv, sendclaudeLv, askLv, aboutLv].concat(pluginExts, ext ? [ext] : [])
    // A plugin's row above the search field (topRow; Deck's player): the first file that has one. ↑ from the list's first
    // row selects it, its keys then go to topKey(event), and Ctrl+Space anywhere to topPress()
    readonly property var topExt: exts.find(e => e.topRow) || null
    function extOf(l) { return exts.find(e => e.levels.indexOf(l) >= 0) || null }
    // A row's every-second value (its `live` / `liveName` key: Wi-Fi's rate, Status), from the Levels file that knows the key
    function liveText(key) { for (const e of exts) { const t = e.liveText ? e.liveText(key) : undefined; if (t !== undefined) return t } return "" }

    WifiLevels { id: wifiLv; launcher: root.launcher }
    BluetoothLevels { id: btLv; launcher: root.launcher }
    SoundLevels { id: soundLv; launcher: root.launcher }
    TailscaleLevels { id: tsLv; launcher: root.launcher }
    StatusLevels { id: statsLv; launcher: root.launcher }
    RegionLevels { id: regionLv; launcher: root.launcher }
    MirroringLevels { id: mirrorLv; launcher: root.launcher }
    HomeLevels { id: homeLv; launcher: root.launcher }
    DefaultAppsLevels { id: defsLv; launcher: root.launcher }
    AppKeyLevels { id: akeysLv; launcher: root.launcher }
    BehaviourLevels { id: behaveLv; launcher: root.launcher }
    ClaudeWriteLevels { id: cwriteLv; launcher: root.launcher }
    ClaudeAccessLevels { id: caccessLv; launcher: root.launcher }
    SendClaudeLevels { id: sendclaudeLv; launcher: root.launcher }
    AskClaudeHint { id: askHintLv; launcher: root.launcher }
    AskClaudeLevels { id: askLv; launcher: root.launcher; hint: askHintLv }
    InstallLevels { id: instLv; launcher: root.launcher }
    ToolsLevels { id: toolsLv; launcher: root.launcher }
    AppearanceLevels { id: lookLv; launcher: root.launcher }
    DisplayLevels { id: dispLv; launcher: root.launcher }
    RemoveLevels { id: rmLv; launcher: root.launcher }
    PasswordLevels { id: pwLv; launcher: root.launcher }
    ThemeLevels { id: themesLv; launcher: root.launcher; behave: behaveLv }
    AboutLevels { id: aboutLv; launcher: root.launcher }
    Calculator { id: calcLv; launcher: root.launcher }
    Instantiator {
        id: pluginLevels
        model: TopBar.plugin.levels
        delegate: Loader { source: "file://" + modelData; onLoaded: item.launcher = root.launcher }
        // later: while a file loads, the Instantiator doesn't list its Loader yet (objectAt is null)
        onObjectAdded: Qt.callLater(root.listPluginExts)
        onObjectRemoved: Qt.callLater(root.listPluginExts)
    }
    function listPluginExts() {
        const out = []
        for (let i = 0; i < pluginLevels.count; i++) { const o = pluginLevels.objectAt(i); if (o && o.item) out.push(o.item) }
        pluginExts = out
    }
    Loader {
        id: extLoader
        source: root.launcher.extSource
        onLoaded: item.launcher = root.launcher
    }
}
