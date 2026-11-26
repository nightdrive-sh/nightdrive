-- Window groups by key (#3045): ⌘⇧G makes the active window a group of tabs or breaks its group up; ⌘⌥⇧ + an arrow
-- moves it into the group that way, or out of its own group; ⌃⌥⌘←/→ shows its previous / next tab (#3164: ⌘←/→ goes
-- to the next window, a group being one; ⌘⌥←/→ is the apps' own tabs, a browser's), and the tabs look as #3042 made
-- them (appearance.lua).
--
-- A submap (⌘⇧G, then an arrow) was the first idea, but ⌘⇧G must act at once: in a group it would break the group up
-- before the arrow came, or a plain ⌘⇧G would wait for a timeout. So the arrows have keys of their own.
-- Hyprland's Lua has no moveintogroup / moveoutofgroup dispatcher; the group's own add and remove do the same, as in
-- pm-space.lua. A lone window that way becomes a group with the moved one in it: moving towards a window means "tab
-- these", and saves a ⌘⇧G first.

local mod = "SUPER"

local function tiled(w) return w and w.mapped and not w.floating and not w.hidden end
local function window_of(addr) return addr and hl.get_window("address:" .. addr) or nil end

local function in_group(group, addr)
    for _, m in ipairs((group and group.members) or {}) do
        if m.address == addr then return true end
    end
    return false
end

-- The nearest visible tiled window on the active one's workspace in that direction, not of its own group: its centre
-- past the active window's edge, and overlapping it across (a window up and far to the side isn't "up")
local function neighbour(w, dir)
    local ax, ay, aw, ah = w.at.x, w.at.y, w.size.x, w.size.y
    local best, bestDist
    for _, o in ipairs(hl.get_workspace_windows(w.workspace.id) or {}) do
        if tiled(o) and o.address ~= w.address and not in_group(w.group, o.address) then
            local ox, oy, ow, oh = o.at.x, o.at.y, o.size.x, o.size.y
            local cx, cy = ox + ow / 2, oy + oh / 2
            local dist
            if dir == "left" and cx < ax and oy < ay + ah and oy + oh > ay then dist = ax - (ox + ow)
            elseif dir == "right" and cx > ax + aw and oy < ay + ah and oy + oh > ay then dist = ox - (ax + aw)
            elseif dir == "up" and cy < ay and ox < ax + aw and ox + ow > ax then dist = ay - (oy + oh)
            elseif dir == "down" and cy > ay + ah and ox < ax + aw and ox + ow > ax then dist = oy - (ay + ah) end
            if dist and (not bestDist or dist < bestDist) then best, bestDist = o, dist end
        end
    end
    return best
end

-- Takes w out of its group; a group left with one window isn't one any more (the counterpart of a lone window that
-- becomes a group when one moves into it). Returns w as it is now.
local function leave_group(w)
    local rest
    for _, m in ipairs(w.group.members or {}) do
        if m.address ~= w.address then rest = rest and "many" or m.address end
    end
    w.group:remove(w)
    if rest and rest ~= "many" then hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. rest })) end
    return hl.get_window("address:" .. w.address)
end

-- Global, as NIGHTDRIVE_SWAP: a test calls it over hyprctl
function NIGHTDRIVE_GROUP_MOVE(dir)
    local w = hl.get_active_window()
    if not tiled(w) or not w.workspace then return end
    local target = neighbour(w, dir)
    if target then
        if not target.group then
            hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. target.address }))
            target = hl.get_window("address:" .. target.address)
        end
        if target and target.group then
            -- Out of its own group first: a window is in one group at a time
            if w.group then w = leave_group(w) end
            if w then
                target.group:add(w)
                hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
            end
        end
    elseif w.group and w.group.size > 1 then
        -- Nothing that way: out of the group, beside it
        w = leave_group(w)
        if w then hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address })) end
    end
end

-- A tab alone (#3194, #3220): a key that sends the window elsewhere sends one tab, not its group (Hyprland's own move
-- takes a tab's whole group with it). The tab leaves its group and the tab after it is shown in its place (the one
-- before, when it was the last; Hyprland's remove would show the first); the other tabs stay. Returns w, alone (a
-- window in no group as it is), and where it left, for NIGHTDRIVE_TAB_BACK: { stay = a tab that stayed, index }.
-- Where it lands it doesn't join a group (auto_group is for windows that open, not ones moved), and a PM's space
-- (pm-space.lua) only gathers the sessions on its own workspace, so one moved out stays out. ⌘⇧D (bindings.lua)
-- sends a tab to the drawer through here too. Global, as NIGHTDRIVE_SWAP: a test calls it.
function NIGHTDRIVE_TAB_ALONE(w)
    if not (w and w.group and w.group.size > 1) then return w, nil end
    local addr, index = w.address, w.group.current_index
    local stay = nil   -- a tab that stays, to find the group by after the remove
    for _, m in ipairs(w.group.members or {}) do
        if m.address ~= addr then stay = stay or m.address end
    end
    w = leave_group(w)
    local g = (window_of(stay) or {}).group
    if g and g.size > 1 then
        hl.dispatch(hl.dsp.group.active({ index = math.min(index, g.size), window = "address:" .. stay }))
    end
    return w, { stay = stay, index = index }
end

-- Back from the drawer to the workspace it left (bindings.lua, #3220): a tab rejoins its group at its old place and is
-- the tab shown. The group is found by a tab that stayed, while that one is still on the workspace; when only it was
-- left (two tabs make no group of one) the two are a group again. One the user has since grouped elsewhere, or that
-- has gone, leaves w an ordinary window. ⌘⇧ + a number remembers nothing: a window moved back is an ordinary one.
function NIGHTDRIVE_TAB_BACK(addr, from)
    local w, stay = window_of(addr), from and window_of(from.stay)
    if not (w and stay and tiled(w) and tiled(stay) and w.workspace and stay.workspace
            and stay.workspace.id == w.workspace.id) or w.group then return end
    if not stay.group then
        hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. stay.address }))
        stay = window_of(stay.address)
        if not (stay and stay.group) then return end
    end
    local g = stay.group
    local index = math.min(from.index, g.size + 1)
    g:add(w, index)
    hl.dispatch(hl.dsp.group.active({ index = index, window = "address:" .. stay.address }))
    hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
end

-- ⌘⇧ + a number (bindings.lua), and ⌘W hiding a background app in special:bg (scripts/close-or-hide, follow = false):
-- the active window to that workspace, a tab alone
function NIGHTDRIVE_MOVE_TO_WORKSPACE(ws, follow)
    local w = NIGHTDRIVE_TAB_ALONE(hl.get_active_window())
    if w then hl.dispatch(hl.dsp.window.move({ workspace = ws, follow = follow, window = "address:" .. w.address })) end
end

hl.bind(mod .. " + SHIFT + G", hl.dsp.group.toggle())
-- Round from the last tab to the first. Outside a group nothing: Hyprland's own would warn that it isn't one.
-- (The bind wrapper in bindings.lua adds the same with MOD5, the ⌥ of a Mac layout.)
for dir, step in pairs({ left = hl.dsp.group.prev, right = hl.dsp.group.next }) do
    hl.bind(mod .. " + CTRL + ALT + " .. dir, function()
        local w = hl.get_active_window()
        if w and w.group and w.group.size > 1 then hl.dispatch(step()) end
    end)
end
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mod .. " + ALT + SHIFT + " .. dir, function() NIGHTDRIVE_GROUP_MOVE(dir) end)
end
