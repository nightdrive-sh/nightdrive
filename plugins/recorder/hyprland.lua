-- Recorder's window (plugins/README.md › Hyprland settings): floating, centred, at its tall size. While it records the
-- window makes itself a low strip and back (app/WindowSize.qml), so the rule only gives the first size.
local WINDOW_W, WINDOW_H = 720, 520    -- app/WindowSize.qml's TALL_W, TALL_H
hl.window_rule({
    name  = "float-recorder",
    match = { class = "^org\\.quickshell$", title = "^Recorder$" },
    float = true,
    size  = WINDOW_W .. " " .. WINDOW_H,
    center = true,
})
