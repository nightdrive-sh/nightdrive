-- A project manager's own space (#3042): a Claude Code session named "… Project Manager" or "… PM" (ndpm, cspm) is the
-- left column of a workspace of its own, full height, PM_WIDTH of the width, and the sessions it opens with `nightdrive
-- ask --background` (terminal-or-claude puts them on its workspace) are one window group on the right: tabs, one shown,
-- however many there are (a grid, #3060, gave way to tabs again in #3124). Every other workspace keeps dwindle, and a
-- session no PM opened opens as before.
--
-- Only the sessions' names say which window is a PM, and Quickshell has them (claude-sessions): Claude.qml calls
-- NightdrivePmSpaces with the PMs it sees, and the rest happens here. The PM's workspace gets a layout of its own by a
-- workspace rule (pm-layout.lua: the PM left, the group right, the PM alone the whole width), and Hyprland's events
-- keep it so: a background session opened or moved there joins the group, and a workspace that is gone takes its rule
-- with it, so its number is an ordinary workspace again.
-- A PM seen for the first time on a workspace with other windows moves to the first empty workspace (focus follows
-- when it had it). One restarted (a new window, the same name) goes back to its space, where its sessions are. A PM the
-- user moves to another workspace makes that one its space, in place, and the old one is ordinary again.
-- A reload starts Lua afresh and drops the rules (groups survive): the spaces are kept in STATE and made again.
-- Nothing happens while a layer has the keyboard (the launcher, a menu: keyboard-layer.lua, #3206): putting a space in
-- order focuses windows and shows tabs, which took the keyboard from under the open launcher when a PM opened a session.
-- It waits until the layer closes; a session that opened meanwhile is a window beside the group until then.

local PM_WIDTH = 0.50   -- the PM's column, a share of the width (1/3, then 40 %, too narrow, #3042)
local SESSION_CLASS = "claude-background"   -- terminal-or-claude's --background sessions (Ghostty prefixes sh.nightdrive.)
local STATE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/nightdrive-pm-spaces"   -- "ws<TAB>address<TAB>name" lines
local SETTLE_MS = 120   -- events come in bursts (a window opens, joins a group, moves): arrange once they settle
local HELD_MS = 250     -- while a layer has the keyboard, how often to look whether it has let go
local LAYOUT = "pmspace" -- pm-layout.lua; a workspace rule names it "lua:pmspace"

local held = require("keyboard-layer").held
local spaces = {}   -- workspace id → { ws, pm = address, sid = its stable_id, name, rule, ruleKey }
local queued = nil  -- the PMs Claude.qml last sent while a layer had the keyboard, handled once it lets go

local function is_session(w)
    return (w.class or ""):gsub("^sh%.nightdrive%.", "") == SESSION_CLASS
end
local function window(addr) return addr and hl.get_window("address:" .. addr) or nil end
local function tiled(w) return w.mapped and not w.floating end
-- A space's PM window while it lives: by address and stable id, as Hyprland gives a new window a closed one's address
local function pm_of(s)
    local w = window(s.pm)
    return w and w.stable_id == s.sid and w or nil
end

require("pm-layout").register(LAYOUT, PM_WIDTH, function(ws)
    local w = spaces[ws] and pm_of(spaces[ws])
    return w and w.address
end)

local function save()
    local f = io.open(STATE, "w")
    if not f then return end
    for id, s in pairs(spaces) do f:write(id, "\t", s.pm, "\t", s.sid, "\t", s.name, "\n") end
    f:close()
end

-- A space's workspace rule: its layout and every outer gap. Made anew on each change, never toggled: disabling a
-- rule turns its workspace back to the default layout even with another rule for it enabled, and the gaps it set
-- stay, so each rule says all. (The disabled ones stay in Hyprland until a reload: a space changes a few times a day.)
local function set_rule(s, layout)
    if s.ruleKey == layout then return end
    if s.rule then s.rule:set_enabled(false) end
    local go = hl.get_config("general.gaps_out") or {}
    s.rule = hl.workspace_rule({ workspace = tostring(s.ws), layout = layout, gaps_out = {
        top = go.top or 10, right = go.right or 10, bottom = go.bottom or 10, left = go.left or 10 } })
    s.ruleKey = layout
end

-- No window joins the space's group by itself (#3168): group.auto_group put any window that opened while you were in a
-- tab into the group, shown, the keyboard with it (from the launcher too), a session's test window or an app's preview
-- as well. Only arrange() adds to it: the background sessions, last. A window rule by workspace, as a space's number
-- changes; disabled with the space (a rule can't be taken away until a reload).
local function bar_groups(s)
    s.bar = hl.window_rule({ match = { workspace = tostring(s.ws) }, group = "barred" })
end

local function open_space(id, pm, sid, name)
    local s = { ws = id, pm = pm, sid = sid, name = name }
    set_rule(s, "lua:" .. LAYOUT)
    bar_groups(s)
    spaces[id] = s
    return s
end
-- Its last rule gives the workspace the default layout and gaps back (and stays, as harmless as the defaults: a
-- disabled one would leave its gaps)
local function close_space(s)
    set_rule(s, hl.get_config("general.layout") or "dwindle")
    if s.bar then s.bar:set_enabled(false) end
    spaces[s.ws] = nil
end

-- Puts a space in order: the PM out of any group, the background sessions in one group (the layout itself,
-- pm-layout.lua, puts the PM left)
local function arrange(s)
    local pm = pm_of(s)
    -- A PM in the group (moved in by hand: the space bars group.auto_group, bar_groups, and a restarted one opens loose)
    if pm and pm.group and pm.workspace and pm.workspace.id == s.ws and tiled(pm) then
        pm.group:remove(pm); pm = pm_of(s)
    end
    local sessions = {}
    for _, w in ipairs(hl.get_workspace_windows(s.ws) or {}) do
        if tiled(w) and is_session(w) and w.address ~= (pm and pm.address) then sessions[#sessions + 1] = w end
    end
    local group, loose = nil, {}
    for _, w in ipairs(sessions) do
        if w.group then group = group or w.group else loose[#loose + 1] = w end
    end
    if #loose == 0 then return end
    if not group then
        -- The PM alone: the first session makes the group, and is the tab shown
        hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. loose[1].address }))
        group = (window(loose[1].address) or {}).group
        table.remove(loose, 1)
    end
    if not group or #loose == 0 then return end
    -- A new session is a tab in the background, the last (#3158): add() puts it after the tab shown and shows it, which
    -- took the tab you were reading, and the keyboard with it when you were in it. So it goes last and the tab shown
    -- before is shown again; the keyboard is given back to whichever window had it. (rules.lua bars the sessions from
    -- group.auto_group, which would have put them in the group as they opened, shown, before this runs.)
    local focused = hl.get_active_window()
    local shown, anchor = group.current_index, group.current.address
    for _, w in ipairs(loose) do
        local g = (window(anchor) or {}).group
        if g then g:add(w, g.size + 1) end
    end
    hl.dispatch(hl.dsp.group.active({ index = shown, window = "address:" .. anchor }))
    local now = hl.get_active_window()
    if focused and (not now or now.address ~= focused.address) and window(focused.address) then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. focused.address }))
    end
end

-- Every space: one whose PM the user moved to another workspace follows it there, one whose workspace is gone
-- closes. (Changes are made after the loop: a table can't take new keys while it is being walked.)
local function arrange_all()
    local moves, gone = {}, {}
    for id, s in pairs(spaces) do
        local pm = pm_of(s)
        local at = pm and pm.workspace
        if at and not at.special and at.id ~= id and not spaces[at.id] then moves[#moves + 1] = { s = s, to = at.id }
        elseif not hl.get_workspace(id) then gone[#gone + 1] = s end
    end
    for _, s in ipairs(gone) do close_space(s) end
    for _, m in ipairs(moves) do
        close_space(m.s)
        if not spaces[m.to] then open_space(m.to, m.s.pm, m.s.sid, m.s.name) end
    end
    if #gone + #moves > 0 then save() end
    for _, sp in pairs(spaces) do arrange(sp) end
end

-- Once events settle, and no layer has the keyboard: until it lets go, looked at again every HELD_MS (Hyprland has
-- layer.closed, but a layer can also stop asking for the keyboard while it stays mapped)
local pending = nil
local function settle(ms)
    if pending then return end
    pending = hl.timer(function()
        pending = nil
        if held() then settle(HELD_MS)
        elseif queued then
            local list = queued
            queued = nil
            NightdrivePmSpaces(list)   -- settles again itself
        else arrange_all() end
    end, { timeout = ms or SETTLE_MS, type = "oneshot" })
end

-- The first empty workspace for a PM (not the laptop's own, display.lua)
local function free_workspace()
    for i = 1, 99 do
        local ws = hl.get_workspace(i)
        if i ~= LAPTOP_WORKSPACE and (not ws or ws.windows == 0) then return i end
    end
end

-- Whether a workspace has windows a PM shouldn't take over: tiled ones that are neither it nor a background session
local function crowded(id, pm)
    for _, w in ipairs(hl.get_workspace_windows(id) or {}) do
        if tiled(w) and w.address ~= pm and not is_session(w) then return true end
    end
    return false
end

-- Claude.qml: list = { { a = "0x…", n = "Nightdrive Project Manager" }, … }, the PMs running now
function NightdrivePmSpaces(list)
    -- A new PM may be moved to a space of its own, focus following it: not from under an open launcher
    if held() then queued = list; settle(); return end
    local known = {}
    for _, s in pairs(spaces) do
        local w = pm_of(s)
        if w then known[w.stable_id] = true end
    end
    for _, p in ipairs(list or {}) do
        local w = window(p.a)
        if w and not known[w.stable_id] and w.workspace and not w.workspace.special and not w.floating then
            local target
            -- Restarted: its space, kept by name while its old window is gone
            for id, s in pairs(spaces) do
                if s.name == p.n and not pm_of(s) then target = id; s.pm = p.a; s.sid = w.stable_id end
            end
            if not target then
                target = w.workspace.id
                if spaces[target] or crowded(target, p.a) then target = free_workspace() end
                if target then open_space(target, p.a, w.stable_id, p.n) end
            end
            if target and target ~= w.workspace.id then
                hl.dispatch(hl.dsp.window.move({ workspace = target, follow = w.active, window = "address:" .. p.a }))
            end
            known[w.stable_id] = true
        end
    end
    save()
    settle()
end

-- After a reload: the spaces whose workspaces are still there
local f = io.open(STATE, "r")
if f then
    for line in f:lines() do
        local id, pm, sid, name = line:match("^(-?%d+)\t([^\t]+)\t([^\t]+)\t(.*)$")
        id = tonumber(id)
        if id and hl.get_workspace(id) then open_space(id, pm, sid, name) end
    end
    f:close()
    settle()
end

-- A background session joins its space's group as it opens (#3297), inside the map: the layout placed it a row of its
-- own beside the group, and waiting SETTLE_MS showed that, the right column's windows shrinking and growing back. Done
-- before the first frame, only the result is drawn. Not while a layer has the keyboard (settle waits for it then).
hl.on("window.open", function(w)
    local s = w and is_session(w) and w.workspace and spaces[w.workspace.id]
    if s and not held() then arrange(s) end
end)

for _, ev in ipairs({ "window.open", "window.close", "window.destroy", "window.move_to_workspace", "workspace.removed" }) do
    hl.on(ev, function() if next(spaces) then settle() end end)
end
