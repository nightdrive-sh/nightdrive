-- While a layer holds the keyboard (the launcher, Ask Claude's toast, a top bar menu in key navigation, a dialog), the
-- window under it looks inactive: the keys go to the layer, and a blue border would say they go to the window
-- (Dashboard #1918). Hyprland keeps that window active and gives no event when a layer takes the keyboard, so this
-- looks at the layers themselves: one place for every layer, whichever program draws it.
--
-- A layer asking for the keyboard exclusively (interactivity 1) has it. On-demand ones (2) have it only once clicked,
-- which Hyprland doesn't tell, so they are left out. A layer's ask can change while it stays open (a top bar menu
-- entering key navigation, a toast that takes keys), with no event either, so besides opening and closing a layer and
-- after a key, a short timer looks again.
--
-- The look: the active border and shadow take the inactive ones' colours, and get theirs back when the layer lets go.
-- A Quickshell crash closes its layers, so the colours come back then too; a config reload starts from hyprland.lua
-- and the theme's look.lua again. look.lua calls NightdriveLayerKeys(true) after setting the colours (`theme set`
-- while the launcher is open), so the new ones are what comes back.

local POLL_MS = 250      -- how soon a layer's changed ask shows; one look is a loop over a handful of layers
local AFTER_KEY_MS = 60  -- the key's program has changed its layer by then

local EXCLUSIVE = 1
local ACTIVE   = { "general.col.active_border", "decoration.shadow.color" }
local INACTIVE = { "general.col.inactive_border", "decoration.shadow.color_inactive" }

-- The theme's active colours while the inactive ones stand in for them, nil otherwise
local saved = nil

local function held()
    for _, l in ipairs(hl.get_layers()) do
        if l.mapped and l.interactivity == EXCLUSIVE then return true end
    end
    return false
end

-- hl.config wants a nested table for a dotted option name
local function set(name, value)
    local root = {}
    local t = root
    local parts = {}
    for p in name:gmatch("[^.]+") do parts[#parts + 1] = p end
    for i = 1, #parts - 1 do
        t[parts[i]] = {}
        t = t[parts[i]]
    end
    t[parts[#parts]] = value
    hl.config(root)
end

-- fresh: look.lua has just set the theme's colours, so nothing stands in for them any more
function NightdriveLayerKeys(fresh)
    if fresh then saved = nil end
    local want = held()
    if want and not saved then
        saved = {}
        for i, name in ipairs(ACTIVE) do
            saved[i] = hl.get_config(name)
            set(name, hl.get_config(INACTIVE[i]))
        end
    elseif not want and saved then
        for i, name in ipairs(ACTIVE) do set(name, saved[i]) end
        saved = nil
    end
end

local function look() NightdriveLayerKeys(false) end

hl.on("layer.opened", look)
hl.on("layer.closed", look)
hl.on("input.keyboard.key", function () hl.timer(look, { timeout = AFTER_KEY_MS, type = "oneshot" }) end)
hl.timer(look, { timeout = POLL_MS, type = "repeat" })
