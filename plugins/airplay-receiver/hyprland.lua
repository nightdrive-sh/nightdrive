-- AirPlay Receiver's window (plugins/README.md › Hyprland settings): UxPlay (app id uxplay with waylandsink) floats along
-- the right edge, full height below the top bar, a phone's width (19.5:9 portrait). Floating so it can be moved anywhere.
local MIRROR_TOP = 36 + 10   -- the top bar's reserved height (hyprland.lua BAR_HEIGHT) + gaps_out
hl.window_rule({
    name  = "float-uxplay",
    match = { class = "^uxplay$" },
    float = true,
    size  = "(monitor_h-" .. MIRROR_TOP + 10 .. ")*0.462 monitor_h-" .. MIRROR_TOP + 10,
    move  = "monitor_w-window_w-10 " .. MIRROR_TOP,
})
