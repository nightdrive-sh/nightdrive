import QtQuick
import Quickshell
import qs.kit

// Settings and Settings › Apps: their rows, titles and parents, the search words that find a setting from the root search,
// and Display's rows for it. In a file of its own because Settings is to become an app of its own (#1833): then this
// file goes, and the launcher keeps a way into the app.
Item {
    id: root
    required property var launcher
    readonly property var lv: launcher.levels

    readonly property var titles: ({ settings: "Settings", startup: "Apps › Startup", appsettings: "Settings › Apps", theme: "Settings › Theme",
                                     themecolor: "Settings › Theme › Color", background: "Settings › Theme › Background" })
    readonly property var parents: ({ startup: "appsettings", appsettings: "settings" })

    readonly property var statics: ({
        // In groups like macOS's System Settings: the often used first (connections, hardware), then the look, the apps' own
        // settings (one row, as on iOS: appsettings), Claude, and what is set once (system)
        settings: [
            { kind: "header", name: "Connections" },
            { kind: "nav", name: "Wi-Fi", glyph: "wifi", target: "wifi" },
            { kind: "nav", name: "Bluetooth", glyph: "bluetooth", target: "bluetooth" }
        ].concat(Plugins.has("tailscale") ? [{ kind: "nav", name: "Tailscale", glyph: "shield-check", target: "tailscale" }] : [], [
            { kind: "header", name: "Hardware" },
            { kind: "nav", name: "Sound", glyph: "volume-2", target: "sound" },   // Headphones are a row there, while connected
            { kind: "nav", name: "Display", glyph: "monitor", target: "display" }
        ], lv.disp.hasOthers() ? [{ kind: "nav", name: "Other displays", glyph: "monitor-smartphone", target: "otherdisplays", summary: lv.disp.othersSummary() }] : [], [
            { kind: "nav", name: "Mouse", glyph: "mouse", target: "mousescroll", summary: lv.behave.mouseScroll ? lv.behave.mouseScroll + "× scroll" : undefined }
        ], lv.disp.hasBattery ? [{ kind: "nav", name: "Battery", glyph: "battery-medium", target: "battery" }] : [], [
            { kind: "header", name: "Appearance" },
            { kind: "nav", name: "Theme", glyph: "palette", target: "theme" },
            { kind: "nav", name: "Top bar", glyph: "panel-top", target: "topbar" },   // its look and what it shows
            { kind: "nav", name: "Screensaver", glyph: "monitor-pause", target: "screensaver" },
            { kind: "nav", name: "Notifications", glyph: "bell-ring", target: "sounds" },
            { kind: "header", name: "Apps" },
            { kind: "nav", name: "App settings", glyph: "layout-grid", target: "appsettings" },
            { kind: "header", name: "Claude" },
            { kind: "nav", name: "Claude writes", glyph: "sparkles", target: "claudewrite", summary: lv.cwrite.modelName(lv.cwrite.model) },
            { kind: "nav", name: "Access", glyph: "shield-half", target: "claudeaccess", summary: lv.caccess.summary,
              extra: "claude access mcp tools privacy" }   // what Claude Code may use of the desktop (ClaudeAccessLevels)
        ], lv.behave.crashReportItems, [
            { kind: "header", name: "System" },
            { kind: "nav", name: "Launcher", glyph: "text-search", target: "launcherprefs" },
            { kind: "nav", name: "Region", glyph: "calendar-clock", target: "region", summary: Regional.name },   // dates and times (RegionLevels)
            { kind: "nav", name: "Computer name", glyph: "laptop", target: "compname", summary: lv.behave.compName }   // what phones see
        ], lv.behave.remoteLoginItems, [
            { kind: "nav", name: "Update channel", glyph: "git-branch", target: "channel",
              summary: lv.behave.channel === "dev" ? "development" : (lv.behave.channel === "custom" ? lv.behave.channelBranch || "custom" : lv.behave.channel || undefined) }
        ]),
        // Settings › Apps: what is about apps in general first, then each app's own settings (only those installed)
        appsettings: lv.defs.settingsItems.concat(lv.akeys.settingsItems, [
            { kind: "nav", name: "Startup", glyph: "rocket", target: "startup" },
            { kind: "nav", name: "Nightdrive apps", glyph: "app-window", target: "ndapps", summary: "on or off" }   // InstallLevels.qml
        ], lv.behave.browserItems.length || lv.home.settingsItems.length || Plugins.has("mail") || Plugins.has("contacts") ? [{ kind: "header", name: "Installed apps" }] : [],
           lv.behave.browserItems.concat(lv.home.settingsItems,
               Plugins.has("contacts") ? [{ kind: "action", name: "Contacts", glyph: "contact", cmd: [Quickshell.env("HOME") + "/.local/bin/contacts", "settings"] }] : [],
               Plugins.has("mail") ? [{ kind: "action", name: "Mail", glyph: "mail", cmd: [Quickshell.env("HOME") + "/.local/bin/nightmail", "settings"] }] : [])
               .map(t => Object.assign({}, t, { appName: t.name })))   // an app's own: "Mail settings" in the root search
    })

    readonly property var settingsAliases: ({ "Wi-Fi": "wifi wlan network internet", "Sound": "audio volume output speakers headphones airpods noise cancelling equalizer", "Battery": "power charge charging health cycles",
                                              "Display": "brightness keyboard backlight night light warm scale scaling resolution monitor screen retina hidpi zoom size bigger smaller",
                                              "Other displays": "ipad iphone tablet phone android second screen extra extend sidecar vnc airplay apple tv mirror cast",
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
                                              "Region": "date format time clock 24 hour 12 hour am pm week starts monday sunday locale lc_time country",
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
        return (lv.disp.bright >= 0 ? [{ kind: "brightness", key: "screen", name: "Brightness", glyph: "sun" }] : [])
            .concat(lv.disp.keys >= 0 ? [{ kind: "brightness", key: "keys", name: "Keyboard backlight", glyph: "keyboard" }] : [])
            .concat([{ kind: "nightlight", name: "Night light", glyph: "moon" },
                     { kind: "nav", name: "Scale", glyph: "monitor", target: "display" }],
                    lv.mirror.mirrorAvail ? [{ kind: "nav", name: "Screen Mirroring", glyph: "screen-share", target: "otherdisplays" }] : [])
    }
}
