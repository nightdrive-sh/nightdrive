-- The screens: their scales, refresh rates and places (Settings › Display), the lid with an external display, and
-- which workspaces each screen has. Run at each load from hyprland.lua, with the machine's values from its top:
-- require("display")({ scale = MONITOR_SCALE, builtin = BUILTIN_DISPLAY }).

local HOME = os.getenv("HOME")
-- Where the screens are and which is the main one, as the Displays window saves it: the main display is the first
-- external one below, with workspaces 1–9
local Arrangement = require("arrangement")

-- A virtual screen (hyprctl output create headless: a phone or a tablet showing it over VNC) is not an external display:
-- it takes neither workspaces 1–9 from the laptop's own screen nor the place beside it
local function isVirtual(m) return m.name:match("^HEADLESS%-") ~= nil end

-- Chosen in the launcher (Settings › Display, hypr/scripts/display): "<output> <scale>" per line, "mode <output>
-- <width>x<height>@<hz>" for a refresh rate other than the display's preferred one (a TV's is often 60 Hz though it does
-- 120), and "builtin <side>" for where the laptop's own screen is next to the external one. A named output's rule wins
-- over the "" rule below and those in local.lua.
local scales, modes, builtinSide = {}, {}, nil
local state = io.open(HOME .. "/.local/state/nightdrive/display")
if state then
    for line in state:lines() do
        local output, scale = line:match("^(%S+)%s+([%d.]+)$")
        if output then scales[output] = tonumber(scale) end
        local mo, mode = line:match("^mode%s+(%S+)%s+(%S+)$")
        if mo then modes[mo] = mode end
        builtinSide = line:match("^builtin%s+(%a+)$") or builtinSide
    end
    state:close()
end
-- A scale or resolution on trial (display … --keep): Claude's change while the card asks whether to keep it, over the
-- saved one. It is in the runtime dir, which a restart empties, so a hard restart on a black screen comes back with the
-- saved value; Keep saves it (#1887). "auto" there is the default again.
local trial = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/nightdrive/display-trial")
if trial then
    for line in trial:lines() do
        local mo, mode = line:match("^mode%s+(%S+)%s+(%S+)$")
        if mo then
            modes[mo] = mode ~= "auto" and mode or nil
        else
            local output, scale = line:match("^(%S+)%s+(%S+)$")
            if output then scales[output] = tonumber(scale) end
        end
    end
    trial:close()
end

-- Lid closed with an external display (logind: docked, so it doesn't suspend): the built-in screen is turned off, so the
-- windows, workspaces and the pointer move to the external one instead of staying under the lid. scripts/lid follows
-- logind's LidClosed and reloads the config, which reads the state again.
local function login1(prop)
    local p = io.popen("busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "
                       .. prop .. " 2>/dev/null")
    if not p then return false end
    local out = p:read("*a") or ""
    p:close()
    return out:match("true") ~= nil
end

-- The first parse comes before Hyprland has its screens, so then they are read from the kernel's connectors: each screen
-- has to come up on its own workspace at once. Without rules a laptop with an external display came up with 1 on its
-- own screen and 2 on the external one, and moving 1 over afterwards left the external one showing 2.
-- Only on the DRM backend: a nested Hyprland (the sandbox, in KWin) has WAYLAND_DISPLAY from its host already, and the
-- connectors it would see are the host's, not its own window.
local function connectedScreens()
    local list = {}
    if os.getenv("WAYLAND_DISPLAY") then return list end
    local p = io.popen("grep -lx connected /sys/class/drm/card*-*/status 2>/dev/null")
    if not p then return list end
    for path in p:lines() do
        local name = path:match("/card%d+%-(.+)/status$")
        if name then list[#list + 1] = { name = name } end
    end
    p:close()
    return list
end

return function(machine)
    local MONITOR_SCALE, BUILTIN_DISPLAY = machine.scale, machine.builtin

    hl.monitor({
        output   = "",
        mode     = "preferred",
        position = "auto",
        scale    = MONITOR_SCALE,
    })
    -- The arrangement from the Displays window (arrangement.lua, scripts/arrange) first: each desk screen it places is
    -- where it says. Without it, the side: the external screen at 0,0 and the laptop's centred along its edge, in layout
    -- pixels (after the scale), so the pointer crosses where the screens really meet. Without one, or alone, Hyprland
    -- places them itself (auto: side by side).
    local positions = {}
    for _, m in ipairs(hl.get_monitors()) do
        local at = not isVirtual(m) and Arrangement.position(m)
        if at then positions[m.name] = { m = m, pos = at } end
    end
    do
        local builtin, ext
        for _, m in ipairs(Arrangement.ordered(hl.get_monitors())) do
            if m.name == BUILTIN_DISPLAY then builtin = m elseif not ext and not isVirtual(m) then ext = m end
        end
        if builtinSide and builtin and ext and next(positions) == nil then
            local function size(m)
                local s = scales[m.name] or m.scale
                local w, h = math.floor(m.width / s + 0.5), math.floor(m.height / s + 0.5)
                if m.transform % 2 == 1 then return h, w end   -- turned 90° or 270°
                return w, h
            end
            local ew, eh = size(ext)
            local bw, bh = size(builtin)
            local at = ({ left  = { -bw, (eh - bh) // 2 }, right = { ew, (eh - bh) // 2 },
                          above = { (ew - bw) // 2, -bh }, below = { (ew - bw) // 2, eh } })[builtinSide]
            if at then
                positions[ext.name] = { m = ext, pos = "0x0" }
                positions[builtin.name] = { m = builtin, pos = at[1] .. "x" .. at[2] }
            end
        end
        -- Otherwise side by side from 0,0, in Hyprland's order, as auto does, but written out: auto places a screen past
        -- all the others, a virtual one too (virtual-display.lua), and the laptop's screen would move behind an iPhone set
        -- to its right, leaving an iPad on its left unreachable
        if next(positions) == nil then
            local x = 0
            for _, m in ipairs(hl.get_monitors()) do
                if not isVirtual(m) and not m.disabled then
                    local s = scales[m.name] or m.scale
                    positions[m.name] = { m = m, pos = x .. "x0" }
                    x = x + math.floor((m.transform % 2 == 1 and m.height or m.width) / s + 0.5)
                end
            end
        end
    end
    -- An output with only a rate keeps the scale it has (MONITOR_SCALE or local.lua's), since its own rule replaces those
    local current = {}
    for _, m in ipairs(hl.get_monitors()) do current[m.name] = m.scale end
    local named = {}
    for output in pairs(scales) do named[output] = true end
    for output in pairs(modes) do named[output] = true end
    for output in pairs(named) do
        if not positions[output] then
            hl.monitor({ output = output, mode = modes[output] or "preferred", position = "auto",
                         scale = scales[output] or current[output] or "auto" })
        end
    end
    for output, p in pairs(positions) do
        hl.monitor({ output = output, mode = modes[output] or "preferred", position = p.pos, scale = scales[output] or p.m.scale })
    end
    -- In a VM, its screen follows its window (vm-display.lua, scripts/vm-display)
    require("vm-display")(scales, modes)
    -- The lid: as scripts/lid last saw it, and logind's before it has started
    local lidClosed
    local lid = io.open((os.getenv("XDG_RUNTIME_DIR") or "") .. "/nightdrive-lid")
    if lid then lidClosed = lid:read("*l") == "closed"; lid:close() else lidClosed = login1("LidClosed") end
    if lidClosed and login1("Docked") then hl.monitor({ output = BUILTIN_DISPLAY, disabled = true }) end

    -- Workspaces with an external display (like GNOME's "workspaces on the primary display only"): the laptop's own screen
    -- has one workspace, LAPTOP_WORKSPACE (⌘0, a laptop icon in the bar), and 1–9 are on the external display. Alone, the
    -- laptop's screen has them all, from 1 (an HDMI display that dropped out for a moment at boot left the MacBook on 3).
    -- The rules follow the screens at each reload; NightdriveArrangeWorkspaces moves the workspaces that already exist.
    LAPTOP_WORKSPACE = 10
    local function screens()
        local builtin, ext
        local list = Arrangement.ordered(hl.get_monitors() or {})
        if #list == 0 then list = connectedScreens() end   -- none in a headless sandbox either: then no rules at all
        for _, m in ipairs(list) do
            if m.name == BUILTIN_DISPLAY then builtin = m elseif not ext and not isVirtual(m) then ext = m end
        end
        return builtin, ext
    end
    do
        local builtin, ext = screens()
        if builtin and ext then
            hl.workspace_rule({ workspace = tostring(LAPTOP_WORKSPACE), monitor = BUILTIN_DISPLAY, default = true })
            for i = 1, 9 do hl.workspace_rule({ workspace = tostring(i), monitor = ext.name, default = i == 1 }) end
        elseif builtin or ext then
            -- 1 on the one screen there is. Never on a screen that isn't there (a VM's or a desktop's built-in one): 1 was
            -- kept for it and the real screen opened on 2
            hl.workspace_rule({ workspace = "1", monitor = (builtin or ext).name, default = true })
        end
    end
    function NightdriveArrangeWorkspaces()
        local builtin, ext = screens()
        if not (builtin and ext) then return end
        local was = hl.get_active_workspace()
        local shown = builtin.active_workspace and builtin.active_workspace.id
        -- The laptop's workspace on its screen first, so moving the others away leaves no gap there to fill
        local lw = hl.get_workspace(LAPTOP_WORKSPACE)
        if lw and lw.monitor and lw.monitor.name ~= BUILTIN_DISPLAY then
            hl.dispatch(hl.dsp.workspace.move({ workspace = LAPTOP_WORKSPACE, monitor = BUILTIN_DISPLAY }))
        end
        if not (builtin.active_workspace and builtin.active_workspace.id == LAPTOP_WORKSPACE) then
            hl.dispatch(hl.dsp.focus({ workspace = LAPTOP_WORKSPACE }))
        end
        for _, w in ipairs(hl.get_workspaces()) do
            if w.id >= 1 and w.id <= 9 and w.monitor and w.monitor.name == BUILTIN_DISPLAY then
                hl.dispatch(hl.dsp.workspace.move({ workspace = w.id, monitor = ext.name }))
            end
        end
        -- The external screen shows what the laptop's screen showed (it moved there), else what had the focus. Never an empty
        -- workspace Hyprland opened for the screen as it came, while 1 was bound elsewhere: 1 instead. That left it on 2 when
        -- plugged in at the login screen, and when it dropped out for a moment at boot (then 1, empty, was gone)
        local target = shown and shown >= 1 and shown <= 9 and shown or nil
        if not target and was and was.id >= 1 and was.id <= 9 then target = was.id end
        local showing = target or (ext.active_workspace and ext.active_workspace.id)   -- the focus stays on the laptop's
        local tw = showing and hl.get_workspace(showing)
        if not (tw and tw.windows > 0) then target = 1 end
        if target then hl.dispatch(hl.dsp.focus({ workspace = target })) end
    end
    -- A tablet or a phone over VNC: a screen with a workspace of its own (virtual-display.lua). After the rules above, as
    -- its rules take 9, 8… from the external display.
    require("virtual-display")(positions, scales)   -- the desk's screens' places as just set, which it counts from
    -- A screen that comes or goes: the rules again (reload), then the workspaces
    hl.on("monitor.added",   function ()
        hl.exec_cmd("hyprctl reload && hyprctl eval 'NightdriveArrangeWorkspaces(); NightdriveArrangeVirtual()'")
    end)
    hl.on("monitor.removed", function () hl.exec_cmd("hyprctl reload") end)
end
