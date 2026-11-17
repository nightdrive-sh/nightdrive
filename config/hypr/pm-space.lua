-- A project manager's own space (#3042): a Claude Code session named "… Project Manager" or "… PM" (ndpm, cspm) is the
-- left column of a workspace of its own, full height, PM_WIDTH of the width, and the sessions it opens with `nightdrive
-- ask --background` (terminal-or-claude puts them on its workspace) are a grid on the right, all in sight, up to
-- MAX_GRID of them (#3060); past that they are one window group there, tabs, one shown, and a grid again once they are
-- MAX_GRID or fewer. Every other workspace keeps dwindle, and a session no PM opened opens as before.
--
-- Only the sessions' names say which window is a PM, and Quickshell has them (claude-sessions): Claude.qml calls
-- NightdrivePmSpaces with the PMs it sees, and the rest happens here. The PM's workspace gets a layout of its own by a
-- workspace rule (pm-grid.lua: the PM left, the rest a grid, the PM alone the whole width), and Hyprland's events keep
-- it so: the sessions group past MAX_GRID and ungroup at it, and a workspace that is gone takes its rule with it, so
-- its number is an ordinary workspace again.
-- A PM seen for the first time on a workspace with other windows moves to the first empty workspace (focus follows
-- when it had it). One restarted (a new window, the same name) goes back to its space, where its sessions are. A PM the
-- user moves to another workspace makes that one its space, in place, and the old one is ordinary again.
-- A reload starts Lua afresh and drops the rules (groups survive): the spaces are kept in STATE and made again.

local PM_WIDTH = 0.50   -- the PM's column, a share of the width (1/3, then 40 %, too narrow, #3042)
local SESSION_CLASS = "claude-background"   -- terminal-or-claude's --background sessions (Ghostty prefixes sh.nightdrive.)
local STATE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/nightdrive-pm-spaces"   -- "ws<TAB>address<TAB>name" lines
local SETTLE_MS = 120   -- events come in bursts (a window opens, joins a group, moves): arrange once they settle
local MAX_GRID = 4      -- sessions in the grid, each in sight; more are one group of tabs (#3060)
local LAYOUT = "pmgrid" -- pm-grid.lua; a workspace rule names it "lua:pmgrid"

local spaces = {}   -- workspace id → { ws, pm = address, sid = its stable_id, name, rule, ruleKey }

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

require("pm-grid").register(LAYOUT, PM_WIDTH, function(ws)
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

local function open_space(id, pm, sid, name)
    local s = { ws = id, pm = pm, sid = sid, name = name }
    set_rule(s, "lua:" .. LAYOUT)
    spaces[id] = s
    return s
end
-- Its last rule gives the workspace the default layout and gaps back (and stays, as harmless as the defaults: a
-- disabled one would leave its gaps)
local function close_space(s)
    set_rule(s, hl.get_config("general.layout") or "dwindle")
    spaces[s.ws] = nil
end

-- Puts a space in order: the PM out of any group, the background sessions loose in the grid up to MAX_GRID, past it
-- in one group (the layout itself, pm-grid.lua, puts the PM left)
local function arrange(s)
    local pm = pm_of(s)
    -- A restarted PM opened over the group's focused tab lands in the group (group.auto_group)
    if pm and pm.group and pm.workspace and pm.workspace.id == s.ws and tiled(pm) then
        pm.group:remove(pm); pm = pm_of(s)
    end
    local sessions = {}
    for _, w in ipairs(hl.get_workspace_windows(s.ws) or {}) do
        if tiled(w) and is_session(w) and w.address ~= (pm and pm.address) then sessions[#sessions + 1] = w end
    end
    if #sessions <= MAX_GRID then
        -- Back to the grid: toggling a grouped window disbands its whole group (fetched anew, as it changes)
        for _, w in ipairs(sessions) do
            local now = window(w.address)
            if now and now.group then hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. w.address })) end
        end
        return
    end
    local group, loose = nil, {}
    for _, w in ipairs(sessions) do
        if w.group then group = group or w.group else loose[#loose + 1] = w end
    end
    if #loose == 0 then return end
    if not group then
        hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. loose[1].address }))
        group = (window(loose[1].address) or {}).group
        table.remove(loose, 1)
    end
    if group then for _, w in ipairs(loose) do group:add(w) end end
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

local pending = nil
local function settle()
    if pending then return end
    pending = hl.timer(function() pending = nil; arrange_all() end, { timeout = SETTLE_MS, type = "oneshot" })
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

for _, ev in ipairs({ "window.open", "window.close", "window.destroy", "window.move_to_workspace", "workspace.removed" }) do
    hl.on(ev, function() if next(spaces) then settle() end end)
end
