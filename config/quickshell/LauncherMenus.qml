import QtQuick
import Quickshell

// The launcher's fixed menus: the root level and System, Tools, Screenshot, Install and Power, with their titles,
// parents and the search words that find their rows from the root search. Plain data apart from Launcher.qml's
// navigation; Settings has a file of its own (LauncherSettings.qml), as it will move to an app (#1833).
Item {
    id: root
    required property var launcher
    readonly property var lv: launcher.levels

    readonly property var titles: ({ apps: "Apps", keys: "Keybindings", screenshot: "Tools › Screenshot", system: "System",
                                     install: "System › Install", power: "Power", tools: "Tools" })
    readonly property var parents: ({ install: "system", screenshot: "tools" })

    function shot(mode) { return ["bash", "-c", "sleep 0.4; \"$HOME/.config/hypr/scripts/screenshot\" \"$1\"", "_", mode] }
    // Passwords only with 1Password; the plugins' level files add their own (rootItems: Deck's Music)
    readonly property var rootItems: lv.ask.rootRows().concat([
        { kind: "nav", name: "Apps", glyph: "layout-grid", target: "apps" },
    ], Plugins.has("1password") ? [{ kind: "nav", name: "Passwords", glyph: "key-round", target: "passwords" }] : [], [
        { kind: "nav", name: "Clipboard", glyph: "clipboard-list", target: "clipboard" },
    ], ...launcher.pluginExts.map(e => e.rootItems || []), lv.home.rootItems, launcher.ext ? launcher.ext.rootItems : [], [
        { kind: "nav", name: "Tools", glyph: "wrench", target: "tools" },
        { kind: "nav", name: "Keybindings", glyph: "keyboard", target: "keys" },
        { kind: "nav", name: "Settings", glyph: "settings", target: "settings" },
        // System: Install, Remove, Update, Status and About Nightdrive (the update count shows here too)
        { kind: "nav", name: "System", glyph: "monitor-cog", target: "system", summary: launcher.updates > 0 ? launcher.updates + " new" : undefined },
        { kind: "nav", name: "Power", glyph: "power", target: "power" }
    ])

    // Static sublevels
    readonly property var statics: ({
        system: [
            { kind: "nav", name: "Install", glyph: "package-plus", target: "install", extra: "software package app flatpak dnf" },
            { kind: "nav", name: "Remove", glyph: "package-minus", target: "remove", extra: "uninstall delete package app" },
            { kind: "action", name: "Update", glyph: "refresh-cw", confirm: true, cmd: launcher.term('"$HOME/.local/bin/nightdrive" update'),
              summary: launcher.updates > 0 ? launcher.updates + " new" : undefined, extra: "upgrade dnf flatpak nightdrive" },
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
            { kind: "action", name: "Color Picker", glyph: "pipette", cmd: ["bash", "-c", "sleep 0.4; \"$HOME/.config/hypr/scripts/color-picker\""] },
            // as ⌘⌃C, once the launcher is gone: the window under it is what's gathered, and its screenshot is without the launcher
            { kind: "action", name: "Send to Claude", glyph: "bot", keyHint: true, extra: "selection files picture screenshot prompt claude code",
              cmd: ["bash", "-c", "sleep 0.4; \"$HOME/.config/hypr/scripts/send-capture\" sendclaude"] }
        ].concat(Plugins.has("localsend") ? [   // to a phone running LocalSend (plugins/localsend); several: picked from a list
            { kind: "action", name: "Send clipboard with LocalSend", glyph: "smartphone", cmd: [Quickshell.env("HOME") + "/.local/bin/localsend", "send-clipboard"],
              extra: "phone iphone share airdrop text link" },
            { kind: "action", name: "Send files with LocalSend", glyph: "smartphone", cmd: [Quickshell.env("HOME") + "/.local/bin/localsend", "send-pick"],
              extra: "phone iphone share airdrop" }
        ] : [], ...launcher.pluginExts.map(e => e.toolItems || [])),   // the plugins' level files add theirs (toolItems: Keep Awake)
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
        power: [
            { kind: "action", name: "Lock", glyph: "lock", cmd: ["loginctl", "lock-session"] },
            { kind: "action", name: "Sleep", glyph: "moon", cmd: ["systemctl", "suspend"] },
            { kind: "action", name: "Log out", glyph: "log-out", cmd: [Quickshell.env("HOME") + "/.config/hypr/scripts/session-end", "logout"] },
            { kind: "action", name: "Restart", glyph: "rotate-cw", confirm: true, cmd: [Quickshell.env("HOME") + "/.config/hypr/scripts/session-end", "reboot"] },
            { kind: "action", name: "Shut down", glyph: "power", confirm: true, cmd: [Quickshell.env("HOME") + "/.config/hypr/scripts/session-end", "poweroff"] }
        ]
    })
    readonly property var installAliases: ({ "Software": "package dnf rpm flatpak flathub app apps program store",
                                             "Webapp": "web app website site pwa url slack teams whatsapp youtube",
                                             "Recommended": "optional home assistant jottacloud deck vscode 1password tailscale thunderbird apostrophe",
                                             "Plugins": "plugin extension addon optional airplay screen mirroring" })
    readonly property var powerAliases: ({ "Lock": "screen", "Sleep": "suspend", "Log out": "logout sign out exit", "Restart": "reboot", "Shut down": "shutdown poweroff power off" })
}
