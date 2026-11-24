-- Games' window (plugins/README.md › Hyprland settings): floating, centred, from the Launcher and from the controller's
-- Xbox button alike (the user's choice, #3530: a game goes full screen, the shelf of covers doesn't).
local WINDOW_W, WINDOW_H = 1240, 800    -- app/shell.qml's own size
hl.window_rule({
    name  = "float-games-window",
    match = { class = "^org\\.quickshell$", title = "^Games$" },
    float = true,
    size  = WINDOW_W .. " " .. WINDOW_H,
    center = true,
})
