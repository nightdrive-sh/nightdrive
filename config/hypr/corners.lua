-- The screen's rounded corners and the night light, both drawn by one screen shader. Run at each load from
-- hyprland.lua: require("corners")(BAR_HEIGHT, session), session being autostart.lua's. Returns update_corners,
-- which hyprland.lua runs once more at the end, after local.lua (NIGHTDRIVE.corners).

local HOME = os.getenv("HOME")

return function(BAR_HEIGHT, session)
    -- The screen's rounded corners: off by default (square edges look cleaner); `NIGHTDRIVE = { corners = true }` in local.lua
    -- turns them on. The shader is tuned for the MacBook's 3024×1964 display (scale 2.0). Even then they are off when a window
    -- is fullscreen (bar hidden), and under the login screen (no bar either).
    -- Top bar opacity (Settings › Top bar opacity, hypr/scripts/bar-style): below 100 % we use a copy of the shader written by
    -- the script, in which the top corners are as transparent as the bar. The change is applied with NightdriveShaderRefresh below.
    local function corner_shader_path()
        local f = io.open(HOME .. "/.local/state/bar-opacity")
        local v = f and tonumber(f:read("l"))
        if f then f:close() end
        if v and v < 100 then
            local p = HOME .. "/.cache/hypr/corners-" .. v .. ".frag"
            local g = io.open(p)
            if g then g:close(); return p end
        end
        return HOME .. "/.config/hypr/shaders/rounded-corners.frag"
    end
    local corner_shader = corner_shader_path()
    -- Night light (launcher › Settings › Display, hypr/scripts/nightlight): the same shader tints the screen warm, so it stays
    -- on under a fullscreen window too (with the corners off). The copies go to ~/.cache/hypr, rewritten only when they change.
    local NIGHT_TINT = "vec3(1.0, 0.80, 0.60)"   -- about 4000 K
    local function night_on()
        local f = io.open(HOME .. "/.local/state/nightdrive/nightlight")
        local v = f and f:read("l")
        if f then f:close() end
        return v == "on"
    end
    local night = night_on()
    -- bar-style opacity and nightlight apply their change with `hyprctl eval "NightdriveShaderRefresh()"`, not a config
    -- reload: a reload takes the keyboard from the launcher (a layer surface), so the next value couldn't be tried (#3702)
    local update_corners   -- below
    function NightdriveShaderRefresh()
        corner_shader = corner_shader_path()
        night = night_on()
        update_corners()
    end
    local function night_shader(corners)
        local f = io.open(corner_shader)
        if not f then return "" end
        local src = f:read("a")
        f:close()
        src = src:gsub("const float CORNERS = [%d.]+;", "const float CORNERS = " .. (corners and "1.0" or "0.0") .. ";")
                 :gsub("const vec3 WARM = [^;]+;", "const vec3 WARM = " .. NIGHT_TINT .. ";")
        local p = HOME .. "/.cache/hypr/" .. corner_shader:match("([^/]+)%.frag$") .. (corners and "" or "-flat") .. "-night.frag"
        local g = io.open(p)
        local old = g and g:read("a")
        if g then g:close() end
        if old ~= src then
            local w = io.open(p .. ".tmp", "w")      -- the directory: nightlight creates it
            if not w then return "" end
            w:write(src); w:close()
            os.rename(p .. ".tmp", p)                 -- whole, never half-written while Hyprland compiles it
        end
        return p
    end
    -- The lock (greeter/lock.qml, also after boot: hypr/scripts/lock) and `nightdrive preview login` hide them too while
    -- they show, as the real login screen does:
    -- hyprctl eval "NightdriveCornersHidden(true)"; a config reload brings them back
    local corners_hidden = false
    function NightdriveCornersHidden(on)
        corners_hidden = on
        update_corners()
    end
    -- The top corners start at the bar's bottom edge, which in physical pixels depends on each screen's scale. One shader
    -- draws every screen and knows only which one (wl_output = the monitor's id), so the copy in use gets a height per screen.
    local function per_screen(path)
        if path == "" then return path end
        local f = io.open(path)
        if not f then return path end
        local src = f:read("a")
        f:close()
        local expr = src:match("const float TOP = ([%d.]+);")
        if not expr then return path end
        for _, m in ipairs(hl.get_monitors()) do
            expr = string.format("(wl_output == %d ? %.1f : %s)", m.id, math.floor(BAR_HEIGHT * m.scale + 0.5), expr)
        end
        src = src:gsub("const float TOP = [%d.]+;", "uniform int wl_output;\n#define TOP " .. expr)
        local p = HOME .. "/.cache/hypr/" .. path:match("([^/]+)%.frag$") .. "-screens.frag"
        local g = io.open(p)
        local old = g and g:read("a")
        if g then g:close() end
        if old ~= src then
            local w = io.open(p .. ".tmp", "w")
            if not w then return path end
            w:write(src); w:close()
            os.rename(p .. ".tmp", p)                 -- whole, never half-written while Hyprland compiles it
        end
        return p
    end
    update_corners = function()
        local ws = hl.get_active_workspace()
        local fullscreen = ws ~= nil and ws.has_fullscreen and ws.fullscreen_mode == 2
        local corners = not fullscreen and not session.locked() and not corners_hidden and NIGHTDRIVE ~= nil and NIGHTDRIVE.corners == true
        hl.config({ decoration = { screen_shader = per_screen(night and night_shader(corners) or (corners and corner_shader or "")) } })
    end
    hl.on("window.fullscreen", update_corners)
    hl.on("workspace.active",  update_corners)
    hl.on("config.reloaded",   update_corners)
    session.unlocked = update_corners   -- the login screen's gone: the corners as they should be
    return update_corners
end
