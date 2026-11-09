-- ⌘⇧T: toggle floating. A window floated with it is always centred, at a size it fits:
-- - A window Hyprland already has a float size for (it floated before: we saw ⌘⇧T tile it) gets that size back.
-- - Otherwise one that floats narrower or lower than SMALL of the screen grows to SIZE (#2523: a small tile floated
--   tiny), and a screen-sized one (a lone window: its geometry stays screen-sized and the border disappears off the
--   left/top) shrinks to it. One in between keeps its size. The size measured is the floating one Hyprland gives, not
--   the tile's: they differ (a 1488 × 454 tile floated at 746 × 926).
-- Deck has a size of its own: tiled -> floating at its default size, centred; floating but moved/resized -> back to
-- default size, centred; floating already at default position -> tiled. (Size: DECK_SIZE, which the Deck plugin's
-- hyprland.lua sets after this file has run, so it's read at the key press.)

local SIZE  = { w = 0.7, h = 0.75 }   -- of the screen, the same as ⌃⌘ + click on a link (float-link.lua)
local SMALL = 0.45                    -- a window floating narrower or lower than this share of the screen grows to SIZE
local FULL  = { w = 0.95, h = 0.9 }   -- a window floating at least this big counts as screen-sized and shrinks to SIZE

-- Windows whose float size Hyprland remembers. The Lua API doesn't expose it, so we note it when ⌘⇧T tiles a floating
-- window. A config reload forgets the notes: at worst such a window is sized to SIZE once more.
local remembered = {}   -- window address -> true

local function xy(t) return t.x or t[1], t.y or t[2] end
local function win(w) return "address:" .. w.address end

local function resize(w, width, height)
    hl.dispatch(hl.dsp.window.resize({ x = math.floor(width), y = math.floor(height), exact = true, window = win(w) }))
end

-- Called just after floating `w` (fresh from hl.get_active_window(), so its size is the floating one)
local function tame_float(w, known)
    if not (w and w.floating) then return end
    local m = w.monitor
    local mw, mh = m.width / m.scale, m.height / m.scale
    local sw, sh = xy(w.size)
    local small = sw < mw * SMALL or sh < mh * SMALL
    local full = sw >= mw * FULL.w and sh >= mh * FULL.h
    if full or (small and not known) then resize(w, mw * SIZE.w, mh * SIZE.h) end
    hl.dispatch(hl.dsp.window.center({ window = win(w) }))
end

local function deck_reset(w)
    resize(w, DECK_SIZE.w, DECK_SIZE.h)
    hl.dispatch(hl.dsp.window.center({ window = win(w) }))
end
local function deck_at_default(w)
    local sw, sh = xy(w.size)
    local x, y = xy(w.at)
    local m = w.monitor
    local cx, cy = (m.width / m.scale - DECK_SIZE.w) / 2, (m.height / m.scale - DECK_SIZE.h) / 2
    return sw == DECK_SIZE.w and sh == DECK_SIZE.h and math.abs(x - cx) <= 3 and math.abs(y - cy) <= 30   -- y: the bar shifts the centre a little
end

local function toggle_float()
    local w = hl.get_active_window()
    if not w then return end
    if w.class:gsub("^sh%.nightdrive%.", "") == "deck" and DECK_SIZE then
        if not w.floating then
            hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
            deck_reset(w)
        elseif deck_at_default(w) then
            hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
        else
            deck_reset(w)
        end
        return
    end
    if w.floating then remembered[w.address] = true end   -- being tiled: Hyprland keeps its float size
    local known = remembered[w.address]
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    tame_float(hl.get_active_window(), known)
end

hl.bind("SUPER + SHIFT + T", toggle_float)
hl.on("window.close", function (w) if w then remembered[w.address] = nil end end)

return { toggle = toggle_float }   -- for tests: hyprctl eval 'require("float-toggle").toggle()'
