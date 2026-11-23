-- Whether a layer has the keyboard: the launcher, a top bar menu, a dialog, a toast that takes keys (#3206).
--
-- What runs on Hyprland's events (pm-space.lua's arranging) checks this before it focuses a window, or does anything
-- that may (a group's tab shown again): any focus dispatch, even to the window that is already active, takes the
-- keyboard from an on-demand layer, and the next keys went to the window under the open launcher.
--
-- Hyprland doesn't say which surface has the keyboard. A mapped layer that asks for it has it: an exclusive one always,
-- an on-demand one (the launcher and the menus, #2039) as it maps, until a click elsewhere, which closes ours.
-- (A layer that asks for none, as the top bar and the shelf, is left out.)

local M = {}

local NONE = 0   -- keyboard_interactivity: 0 none, 1 exclusive, 2 on demand

function M.held()
    for _, l in ipairs(hl.get_layers() or {}) do
        if l.mapped and (l.keyboard_interactivity or NONE) ~= NONE then return true end
    end
    return false
end

return M
