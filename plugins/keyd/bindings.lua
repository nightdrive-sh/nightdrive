-- Mac Keyboard Shortcuts' keys in Hyprland (plugins/README.md › Keys); the text keys are keyd's (default.conf, app.conf).
-- ⌘, = the app's settings (Ctrl+,), like in macOS. Not in terminals, as the core's ⌘S and ⌘F (config/hypr/bindings.lua).
-- 1Password raises its Settings window itself when it is already open, but its window rule (hypr/rules.lua:
-- suppress_event) blocks that and the window would stay behind the main window or hidden in special:bg: so the open one
-- is brought up here. Its main window is the oldest (as in hypr/scripts/close-or-hide).
local p = ...
local function is_onepassword(class)
    return class == "com.onepassword.OnePassword" or class:match("^1[pP]assword$") ~= nil
end
hl.bind(p.mod .. " + comma", function ()
    local w = hl.get_active_window()
    if NIGHTDRIVE_IS_TERMINAL(w) then return end   -- the core's bindings.lua
    if w and is_onepassword(w.class) then
        local main, other
        for _, o in ipairs(hl.get_windows()) do
            if o.pid == w.pid and is_onepassword(o.class) and (not main or o.stable_id < main.stable_id) then main = o end
        end
        for _, o in ipairs(hl.get_windows()) do
            if o.pid == w.pid and is_onepassword(o.class) and o.address ~= main.address then other = o end
        end
        if other then
            if other.workspace and other.workspace.name == "special:bg" and w.workspace then
                hl.dispatch(hl.dsp.window.move({ workspace = w.workspace.id, window = "address:" .. other.address }))
            end
            hl.dispatch(hl.dsp.focus({ window = "address:" .. other.address }))
            return
        end
    end
    hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL", key = "comma" }))
end)
