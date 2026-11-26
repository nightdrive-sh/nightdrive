-- ⌘⌥− / ⌘⌥+: the active window narrower or wider by STEP of its screen's width, repeating while held (#3130).
-- Bound to minus and plus (Finnish: keys of their own), equal (US: + is ⇧=, so ⌘⌥= is the same key unshifted, and
-- ⌘⌥⇧= too) and the keypad's − and +.
-- - Tiled (dwindle): Hyprland moves the split, the neighbour gives or takes the room, on either side.
-- - Floating: it grows or shrinks about its centre, so it stays where it was (a centred one stays centred).
-- - A project manager's space (pm-layout.lua): its own layout has no resize, it places the PM at its share of the width
--   on each recalculation, so a plain resize would snap back. The key sends that layout a message instead, which moves
--   the share for that workspace: on the PM it grows the PM, on its sessions it grows the sessions.
-- A lone tiled window or a fullscreen one has nothing to give room to: the key does nothing there.

local STEP = 0.05         -- of the screen's width
local MIN_WIDTH = 0.15    -- a floating window gets no narrower than this share of the screen
local PM_LAYOUT = "lua:pmspace"   -- pm-space.lua's layout, as a workspace reports it

local function xy(t) return t.x or t[1], t.y or t[2] end

local function width(sign)
    local w = hl.get_active_window()
    if not w or (w.fullscreen and w.fullscreen > 0) then return end
    local win = "address:" .. w.address
    if not w.floating and w.workspace and w.workspace.tiled_layout == PM_LAYOUT then
        hl.dispatch(hl.dsp.layout("width " .. (sign * STEP)))
        return
    end
    local m = w.monitor
    local mw = m.width / m.scale
    local step = math.floor(mw * STEP) * sign
    if not w.floating then
        -- dwindle moves the window's right edge; one at the screen's right edge has none to move, so the split (its
        -- left edge) goes the same way and + made it narrower: the other way round there
        local x = xy(w.at)
        local right_gap = (m.x + mw) - (x + xy(w.size))
        if right_gap < x - m.x then step = -step end
        hl.dispatch(hl.dsp.window.resize({ x = step, y = 0, relative = true, window = win }))
        return
    end
    local sw = xy(w.size)
    local new = math.max(math.floor(mw * MIN_WIDTH), math.min(math.floor(mw), sw + step))
    if new == sw then return end
    hl.dispatch(hl.dsp.window.resize({ x = new - sw, y = 0, relative = true, window = win }))
    -- half the change to the left keeps the centre; odd pixels may drift by one, nothing to see
    hl.dispatch(hl.dsp.window.move({ x = -math.floor((new - sw) / 2), y = 0, relative = true, window = win }))
end

local function narrower() width(-1) end
local function wider() width(1) end
for _, key in ipairs({ "minus", "KP_Subtract" }) do
    hl.bind("SUPER + ALT + " .. key, narrower, { repeating = true })
end
for _, key in ipairs({ "plus", "equal", "SHIFT + equal", "SHIFT + plus", "KP_Add" }) do
    hl.bind("SUPER + ALT + " .. key, wider, { repeating = true })
end
