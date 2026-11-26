-- A drag that ends over another window leaves the keyboard where it was (#3540). Selecting text with the mouse past a
-- window's edge, or dragging a scrollbar or a slider beyond it, let go over the window beside it: with follow_mouse the
-- next move gave that window the keyboard and the selection was gone.
--
-- Why it happens: while a button is held Hyprland keeps the pointer on the window the drag began in and never records
-- the window under it, so after the release the first move looks like entering a new window, and mouse_refocus = false
-- (input.lua) doesn't stop that. No setting covers it: follow_mouse = 2 would end focus-follows-mouse altogether.
--
-- So when the left button is let go outside the window that has the keyboard (or over a floating window above it),
-- a no_follow_mouse rule is on for every window until the pointer first moves. That move records the window under it
-- without focusing it; after it focus follows the mouse as before: going on into another window, or a click, focuses
-- that one, while moving about the window it was let go over doesn't. Layers (the launcher, the bar's menus) aren't
-- windows and take the keyboard as before; ⌘-drag ends with the pointer in the window it moved, so it isn't held.

local POLL_MS = 30   -- how often the pointer is read while held: one move is enough, so a short tick

local hold = hl.window_rule({
    name = "drag-focus-hold",
    match = { class = ".*" },
    no_follow_mouse = true,
    enabled = false,
})

local function inside(w, p)
    return p.x >= w.at.x and p.y >= w.at.y and p.x < w.at.x + w.size.x and p.y < w.at.y + w.size.y
end

-- Let go somewhere the keyboard's window doesn't show: outside it, or on another floating window over it (a dialog,
-- the picker). A floating window below it counts too: holding then costs nothing, as the move records that window.
local function elsewhere(active, p)
    if not inside(active, p) then return true end
    for _, w in ipairs(hl.get_windows()) do
        if w.address ~= active.address and w.floating and w.visible and w.mapped and inside(w, p) then return true end
    end
    return false
end

local poll
local function release()
    if poll then poll:set_enabled(false); poll = nil end
    hold:set_enabled(false)
end

hl.bind("mouse:272", function ()
    local p, active = hl.get_cursor_pos(), hl.get_active_window()
    if poll then release() end
    if not (p and active) or not elsewhere(active, p) then return end
    hold:set_enabled(true)
    -- Hyprland has no pointer-motion event for Lua: the pointer is read until it has moved. A locked pointer (a game,
    -- Garage's VM with the mouse caught) never moves it, which only keeps this rule on until the next release.
    poll = hl.timer(function ()
        local q = hl.get_cursor_pos()
        if q and (q.x ~= p.x or q.y ~= p.y) then release() end
    end, { timeout = POLL_MS, type = "repeat" })
end, { non_consuming = true, release = true, transparent = true, ignore_mods = true })
