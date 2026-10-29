-- Virtual screens: a tablet or a phone showing a headless output over VNC (hyprctl output create headless NAME, wayvnc
-- -o NAME). Each is a screen of its own with one workspace of its own, like the laptop's screen beside an external display.
-- The state is a file, as Settings › Display's is, because a rule set with hyprctl eval is gone at the next reload, and a
-- screen that comes or goes reloads the config (hyprland.lua: monitor.added). One line per screen:
--
--     <name> <width>x<height>@<hz> <scale> <place> [<workspace>]
--     HEADLESS-IPAD 2752x2064@60 2 beside 9
--
-- The name starts with HEADLESS- (hyprland.lua's isVirtual: not an external display). <place> is the side of the desk's
-- screens it is on, so the pointer slides over that edge as with Sidecar (a tablet): "right" (or "beside", the same),
-- "left", "above" or "below"; or "away": far off, so it never strays there (a phone, used away from the desk). Lines
-- starting with # are skipped.

local STATE = os.getenv("HOME") .. "/.local/state/nightdrive/virtual-displays"
-- Workspaces from the top down: the first screen gets 9 (⌘9), the next 8, then 7 and 6, so 1–5 stay on the desk's main
-- screen, and the laptop's own screen has its own (LAPTOP_WORKSPACE, ⌘0): a fifth virtual screen gets none. One chosen
-- in the file (vnc-display workspace) may be 2–9; never 1, the main screen's, where everything comes back to.
local FIRST_WORKSPACE, LAST_WORKSPACE, LOWEST_WORKSPACE = 9, 6, 2
-- "away": this far left of the desk, each next one a step further, so the pointer can't reach them by accident
local FAR_X, FAR_STEP = -10000, -5000
-- Hyprland's own placing for a side, only when there are no desk screens to count from (a headless sandbox)
local SIDES = { beside = "auto-right", right = "auto-right", left = "auto-left", above = "auto-up", below = "auto-down" }

-- The desk's screens' bounds in logical px, which the sides are counted from: where hyprland.lua has just put them
-- (deskPlaces: output -> { pos = "XxY" }), not where they were, as the same reload may move them
local function deskBounds(monitors, deskPlaces, scales)
    local b
    for _, m in ipairs(monitors) do
        if not m.name:match("^HEADLESS%-") and not m.disabled then
            local p = deskPlaces[m.name]
            local x, y = m.x, m.y
            if p then x, y = p.pos:match("^(-?%d+)x(-?%d+)$"); x, y = tonumber(x), tonumber(y) end
            local s = scales[m.name] or m.scale
            local w, h = m.width, m.height
            if m.transform % 2 == 1 then w, h = h, w end
            local x1, y1 = x + math.floor(w / s + 0.5), y + math.floor(h / s + 0.5)
            if not b then b = { x0 = x, y0 = y, x1 = x1, y1 = y1 }
            else b = { x0 = math.min(b.x0, x), y0 = math.min(b.y0, y), x1 = math.max(b.x1, x1), y1 = math.max(b.y1, y1) } end
        end
    end
    return b
end

-- Each screen's place as exact coordinates, side by side outwards in the file's order (the first added is next to the
-- desk). Not auto-left and the like: with two on one side Hyprland places one twice, and its top bar and wallpaper stay
-- where it was first, leaving the screen grey. Only the screens there now take a slot: one exists only while its device
-- is connected, and an empty slot between the desk and the next one out would keep the pointer from crossing to it. One
-- not there gets the place just past them, where it would come; its coming or going reloads this, moving the others.
local function positions(list, bounds, present)
    local out, used = {}, { right = 0, left = 0, above = 0, below = 0 }
    for _, d in ipairs(list) do
        local side = d.place == "beside" and "right" or d.place
        local w, h = d.mode:match("^(%d+)x(%d+)")
        if bounds and used[side] and w then
            w, h = math.floor(tonumber(w) / d.scale + 0.5), math.floor(tonumber(h) / d.scale + 0.5)
            local u = used[side]
            if side == "right" then out[d.name] = (bounds.x1 + u) .. "x" .. bounds.y0; u = u + w
            elseif side == "left" then u = u + w; out[d.name] = (bounds.x0 - u) .. "x" .. bounds.y0
            elseif side == "above" then u = u + h; out[d.name] = bounds.x0 .. "x" .. (bounds.y0 - u)
            else out[d.name] = bounds.x0 .. "x" .. (bounds.y1 + u); u = u + h end
            if present[d.name] then used[side] = u end
        else
            out[d.name] = SIDES[d.place] or "auto-right"
        end
    end
    return out
end

local function readState()
    local list = {}
    local f = io.open(STATE)
    if not f then return list end
    for line in f:lines() do
        if not line:match("^%s*#") then
            local name, mode, scale, place, ws = line:match("^(HEADLESS%-%S+)%s+(%S+)%s+([%d.]+)%s+(%a+)%s*(%d*)%s*$")
            if name then
                list[#list + 1] = { name = name, mode = mode, scale = tonumber(scale), place = place,
                                    workspace = tonumber(ws) }
            end
        end
    end
    f:close()
    return list
end

-- A workspace given in the file is kept if it is one of 2–9 and not taken; the others get the highest free one, in the
-- file's order (so the first screen added is 9, and one removed leaves the others where they were)
local function assignWorkspaces(list)
    local taken = {}
    for _, d in ipairs(list) do
        local w = d.workspace
        if w and w <= FIRST_WORKSPACE and w >= LOWEST_WORKSPACE and not taken[w] then taken[w] = true else d.workspace = nil end
    end
    for _, d in ipairs(list) do
        if not d.workspace then
            for w = FIRST_WORKSPACE, LAST_WORKSPACE, -1 do
                if not taken[w] then d.workspace = w; taken[w] = true; break end
            end
        end
    end
end

local displays = {}

-- Shows each virtual screen's workspace on it, moved there if it is elsewhere (its windows go with it). The workspace is
-- there: its rule is persistent, so the reload made it. Never by focusing it: the desk's focus stays where it is, as the
-- screen may be on a phone in another room (set_workspace shows it without the focus). All the moves first:
-- a screen may be showing another one's workspace, which Hyprland gave it as it came.
function NightdriveArrangeVirtual()
    local present = {}
    for _, m in ipairs(hl.get_monitors()) do present[m.name] = true end
    for _, d in ipairs(displays) do
        local w = present[d.name] and d.workspace and hl.get_workspace(d.workspace)
        if w and not (w.monitor and w.monitor.name == d.name) then
            hl.dispatch(hl.dsp.workspace.move({ workspace = d.workspace, monitor = d.name }))
        end
    end
    -- Moving the workspace the desk was on takes the focus with it (the persistent rule moves it in the reload already):
    -- back to the screen under the pointer, which stays where the user is, at the desk or on the tablet
    local now, here = hl.get_active_monitor(), hl.get_monitor_at_cursor()
    if now and here and now.name ~= here.name then hl.dispatch(hl.dsp.focus({ monitor = here.name })) end
    for _, d in ipairs(displays) do
        local m = present[d.name] and d.workspace and hl.get_monitor(d.name)
        if m and not (m.active_workspace and m.active_workspace.id == d.workspace) then
            m:set_workspace({ workspace = d.workspace })
        end
    end
end

-- Run at each load, after hyprland.lua's workspace rules: a later rule for the same workspace wins, so 9 and 8 leave the
-- external display for the virtual screens. A workspace rule only for a screen that is there: once it is gone, its
-- workspace goes back to the desk's main screen, and is no longer kept there once empty.
return function(deskPlaces, scales)
    displays = readState()
    assignWorkspaces(displays)
    local present = {}
    local monitors = hl.get_monitors() or {}
    for _, m in ipairs(monitors) do present[m.name] = true end
    local placed = positions(displays, deskBounds(monitors, deskPlaces or {}, scales or {}), present)
    local away = 0
    for _, d in ipairs(displays) do
        local position = placed[d.name]
        if d.place == "away" then
            position = (FAR_X + away * FAR_STEP) .. "x0"
            away = away + 1
        end
        hl.monitor({ output = d.name, mode = d.mode, position = position, scale = d.scale })
        if present[d.name] and d.workspace then
            hl.workspace_rule({ workspace = tostring(d.workspace), monitor = d.name, default = true, persistent = true })
        end
    end
end
