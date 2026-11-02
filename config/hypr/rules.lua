-- Window and layer rules: which windows float, at what size, and the like. Required from hyprland.lua's
-- WINDOW RULES section; its own file so hyprland.lua stays small.

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})
hl.window_rule({
    name  = "float-small-tools",
    match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol|blueman-manager|nm-connection-editor)$" },
    float = true,
})
-- Solaar (Logitech devices): GTK 3 asks for at least 1076×537 (xdg_toplevel min_size) and draws at that size even in
-- a smaller tile, which Hyprland's tiling ignores (misc.size_limits_tiled only shrinks the picture): clicks missed and
-- old frames stayed on screen (#1890). Floating, it opens at a size it fits; ⌘⇧T tiles it.
hl.window_rule({
    name  = "float-solaar",
    match = { class = "^solaar$" },
    float = true,
    size  = "1100 640",
    center = true,
})
-- Thunderbird's calendar reminder: a small dialog, not a window to split the workspace with. It opens titled "Calendar
-- Reminders" and renames itself "1 Reminder", "2 Reminders"…
hl.window_rule({
    name  = "float-thunderbird-reminders",
    match = { class = "^(net\\.thunderbird\\.Thunderbird|thunderbird)$", title = "^(Calendar Reminders|\\d+ Reminders?)$" },
    float = true,
    size  = "600 400",
    center = true,
})
-- File picker (Settings › Background › Add new…, Ferry's +) and the apps' Open/Save dialogs: zenity 4 asks the portal,
-- whose dialog is xdg-desktop-portal-gtk's window
hl.window_rule({
    name  = "float-zenity",
    match = { class = "^(zenity|org.gnome.Zenity|xdg-desktop-portal-gtk)$" },
    float = true,
    size  = "1000 650",
    center = true,
})
-- Image preview (Files' Space preview Sushi, image viewer Loupe): on top of the windows instead of splitting them, like
-- Quick Look and Preview; ⌘⇧T moves it into the tiling layout
-- Theme Editor (quickshell/ThemeEditor.qml): floats at the right edge next to the windows it styles; ⌘⇧T tiles it
hl.window_rule({
    name  = "float-theme-editor",
    match = { class = "^org\\.quickshell$", title = "^Theme Editor$" },
    float = true,
    size  = "460 monitor_h-57",             -- the screen's height under the bar; it scrolls
    move  = "monitor_w-470 47",
})
-- Welcome to Nightdrive (config/welcome): its window rules, and what it opens comes over it
require("welcome")
hl.window_rule({
    name  = "float-preview",
    match = { class = "^org\\.gnome\\.Loupe$" },
    float = true,
    size  = "monitor_w*0.85 monitor_h*0.85",
    center = true,
})
-- Sushi sizes itself too small at scale 2 (a GTK3 bug, docs/known-issues.md), so it gets the size too; it briefly
-- flashes a zoomed frame as it opens, until Sushi 51 (GTK4)
hl.window_rule({
    name  = "float-quicklook",
    match = { class = "^org\\.gnome\\.NautilusPreviewer$" },
    float = true,
    size  = "monitor_w*0.85 monitor_h*0.85",
    center = true,
})
hl.window_rule({
    name  = "float-tui",
    match = { class = "^(sh\\.nightdrive\\.)?floating-tui$" },   -- Ghostty's prefix: scripts/terminal
    float = true,
    size  = "700 500",
})
-- Network Connections (Wi-Fi menu › Network settings…): a settings dialog, floating like the TUI it replaced
hl.window_rule({
    name  = "float-network",
    match = { class = "^nm-connection-editor$" },
    float = true,
    size  = "760 520",
})
-- A Claude session opened in the background (nightdrive ask --background, scripts/terminal-or-claude): tiled on the
-- workspace as usual, but the keyboard stays where you are typing; a notification says it opened
hl.window_rule({
    name  = "claude-background",
    match = { class = "^(sh\\.nightdrive\\.)?claude-background$" },
    no_initial_focus = true,
})
hl.window_rule({
    name  = "float-help",
    match = { class = "^(sh\\.nightdrive\\.)?floating-help$" },
    float = true,
    size  = "900 750",
})
-- Polkit password prompt (hyprpolkitagent; its size: hyprpolkitagent/hyprpolkitagent.conf): centred over everything,
-- on whatever workspace is shown, with the keyboard, since a prompt left unseen times out. Over the launcher and the
-- bar's menus too: those are overlay layers no window gets above, so they hide while it is open (quickshell/PolkitWatch.qml).
hl.window_rule({
    name  = "polkit-prompt",
    match = { class = "^hyprpolkitagent$" },
    float = true,
    size  = "600 window_h",   -- its own width (window_width) is only a preference: floating, it opened at its minimum, 460
    center = true,
    pin = true,
    stay_focused = true,
})
-- 1Password: floating window centred on screen, hidden from screen sharing. Here rather than in plugins/1password: the app
-- may run while the plugin is off (it starts at login), and it must stay out of a shared screen then too.
hl.window_rule({
    name  = "1password",
    match = { class = "^(1[pP]assword|com\\.onepassword\\.OnePassword)$" },
    float = true,
    size  = "1000 700",
    center = true,
    no_screen_share = true,
    suppress_event = "activate activatefocus",   -- must not raise itself (otherwise the special:bg background workspace shows up and covers the windows); ⌘P brings it up
})
-- Telegram: same reason as 1Password, a background app that raises itself (opening it again, links); the launcher and ⌘W handle it
hl.window_rule({
    name  = "telegram",
    match = { class = "^org\\.telegram\\.desktop$" },
    suppress_event = "activate activatefocus",
})

-- Notifications (quickshell/NotificationPopups.qml): what's behind the translucent cards is blurred. ignore_alpha: only
-- where a card is (not the gaps between them or the rounded corners' outside)
-- The bar's menus too (shell.qml): the notification menu is cards like the popups; the other menus are opaque
hl.layer_rule({
    name  = "notifications-blur",
    match = { namespace = "^nightdrive-(notifications|menu)$" },
    blur  = true,
    ignore_alpha = 0.1,
})

-- Thunderbird: slightly translucent (values: active, inactive)
hl.window_rule({
    name  = "thunderbird-opacity",
    match = { class = "^(net\\.thunderbird\\.Thunderbird|thunderbird)$" },
    opacity = "0.97 0.94",
})
