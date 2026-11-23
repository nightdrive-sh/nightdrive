-- The screens' arrangement (#1800): where each is, which is the main display and which virtual screens are away, as the
-- Displays window (config/displays) and scripts/arrange save it in ~/.local/state/nightdrive/arrangement:
--
--     <x> <y> <screen>     its top left corner in layout pixels (after the scale)
--     away <screen>        a virtual screen out of the pointer's reach
--     main <screen>        the main display, which has workspaces 1–9
--
-- <screen> is an external display's "desc:<description>" (its make, model and serial: its place follows it to another
-- port), else its output's name (eDP-1, HEADLESS-IPAD). display.lua and virtual-display.lua read it at every load; a
-- screen it doesn't name keeps their places (display side, vnc-display place), and without the file nothing changes.

local STATE = os.getenv("HOME") .. "/.local/state/nightdrive/arrangement"

local M = {}

local places, away, main = {}, {}, nil
local f = io.open(STATE)
if f then
    for line in f:lines() do
        local x, y, key = line:match("^(%-?%d+) (%-?%d+) (.+)$")
        if x then places[key] = x .. "x" .. y end
        away[line:match("^away (.+)$") or ""] = true
        main = line:match("^main (.+)$") or main
    end
    f:close()
end
away[""] = nil

-- The names a monitor goes by in the file: its description first (an external display), then its output
local function keys(m)
    local k = {}
    if m.description and m.description ~= "" then k[#k + 1] = "desc:" .. m.description end
    k[#k + 1] = m.name
    return k
end

-- "XxY" for Hyprland's monitor rule, or nil when the file doesn't place it
function M.position(m)
    for _, k in ipairs(keys(m)) do
        if places[k] then return places[k] end
    end
    return nil
end

function M.isMain(m)
    if not main then return false end
    for _, k in ipairs(keys(m)) do
        if k == main then return true end
    end
    return false
end

-- Hyprland's monitors with the main display first, so code that takes "the first external display" takes it
function M.ordered(list)
    local out = {}
    for _, m in ipairs(list) do if M.isMain(m) then out[#out + 1] = m end end
    for _, m in ipairs(list) do if not M.isMain(m) then out[#out + 1] = m end end
    return out
end

-- virtual-display.lua's lines with the file's say: at = "XxY" for one it places, place = "away" for one it put away
-- (and one it placed is no longer away, whatever vnc-display's line says)
function M.virtual(list)
    for _, d in ipairs(list) do
        if away[d.name] then
            d.place = "away"
        elseif places[d.name] then
            d.at = places[d.name]
            if d.place == "away" then d.place = "right" end
        end
    end
    return list
end

return M
