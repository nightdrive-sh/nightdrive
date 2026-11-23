-- A window a Claude Code session opens itself (a test terminal, an app's preview, a demo: #3168) doesn't take the
-- keyboard from whoever is typing, on any workspace. It opens where it would, tiled, and you click it when you want it.
--
-- Such a window is known by its process: Claude Code runs its commands with CLAUDECODE=1, which a program started from
-- them inherits (setsid and nohup too). The sessions that terminal-or-claude opens clear it (they have rules of their own,
-- rules.lua), and so does anything started through Hyprland (hyprctl dispatch exec) or another program's running
-- instance (a browser's new window, Ghostty's): those still open as any window does.
--
-- Hyprland has no rule that matches a process, and window.open_early comes after the rules are read and the window is
-- mapped and focused. So it is undone here at once, before Hyprland reads the next key: this runs inside the map, and
-- no key can reach the new window in between. A group the window joined as it opened (group.auto_group, when you were
-- in one; never in a project manager's space, pm-space.lua) lets it go again, so its tab shown before shows again.
-- While a layer has the keyboard (the launcher, a menu: keyboard-layer.lua, #3206), Hyprland gave the window none, and
-- any focus dispatch here would take the keyboard from the layer: then nothing is focused.

local MARK = "\0CLAUDECODE=1\0"   -- in /proc/PID/environ, NUL-separated (a NUL is put before the first variable)

local held = require("keyboard-layer").held

local function from_claude(w)
    if not (w and w.pid and w.pid > 0) then return false end
    local f = io.open("/proc/" .. w.pid .. "/environ", "rb")
    if not f then return false end
    local env = f:read("a") or ""
    f:close()
    return ("\0" .. env):find(MARK, 1, true) ~= nil
end

-- The window that had the keyboard before w: the lowest focus history id but w's own
local function before(w)
    local prev
    for _, o in ipairs(hl.get_windows() or {}) do
        if o.address ~= w.address and o.mapped and o.focus_history_id
            and (not prev or o.focus_history_id < prev.focus_history_id) then prev = o end
    end
    return prev
end

hl.on("window.open", function (w)
    if not from_claude(w) then return end
    local prev = before(w)
    if w.group then w.group:remove(w) end
    local now = hl.get_active_window()
    if prev and now and now.address == w.address and not held() then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. prev.address }))
    end
end)
