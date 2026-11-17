-- The layout of a project manager's space (pm-space.lua, #3060): the PM the left column, its sessions a grid on the
-- right, every one of them in sight. Master can't make a 2×2 grid, so the space has a layout of its own (Hyprland's
-- Lua layouts, hl.layout.register). pm-space.lua keeps the sessions at four targets at most: a fifth turns them into
-- one window group, which is a single target here and so fills the right side.
-- A small display (a MacBook's own, #3066) can't fit four terminals of a usable size: the layout works out from the
-- area it is given how many cells still hold MIN_COLS × MIN_ROWS characters, and tells pm-space.lua, which groups
-- the sessions past that. The area is the display's, so this follows a display plugged in or out, a scale change or
-- the space moving to another display by itself.

-- The smallest terminal worth a cell of its own. Not 80 columns: a 4K display at 1.5 (2560 logical) gives a 2×2
-- cell ~79, and the grid is right there; a MacBook's half-width cell is ~44, far from either.
local MIN_COLS, MIN_ROWS = 75, 20
-- A terminal cell per point of font size, measured from Ghostty with JetBrains Mono (9.5 pt: 7.6 × 17.1 px)
local CELL_W_PER_PT, CELL_H_PER_PT = 0.8, 1.8
local FONT_PT = 9.5   -- when Ghostty's config doesn't say
local GHOSTTY_CONFIG = (os.getenv("HOME") or "") .. "/.config/ghostty/config.ghostty"
-- What a cell loses before the text: gaps_in (5) and the border (2) on both sides, Ghostty's window-padding (10) too
local CHROME = 2 * (5 + 2 + 10)

local M = {}

-- Each count's cells as shares of the right side { x, y, w, h }, in the order the targets come (oldest first). Each
-- step moves as little as it can: a third splits the lower half, a fourth the upper one, the newest top right.
local CELLS = {
    { { 0, 0, 1, 1 } },
    { { 0, 0, 1, .5 }, { 0, .5, 1, .5 } },
    { { 0, 0, 1, .5 }, { 0, .5, .5, .5 }, { .5, .5, .5, .5 } },
    { { 0, 0, .5, .5 }, { 0, .5, .5, .5 }, { .5, .5, .5, .5 }, { .5, 0, .5, .5 } },
}

local function cell(box, c)
    return { x = box.x + box.w * c[1], y = box.y + box.h * c[2], w = box.w * c[3], h = box.h * c[4] }
end

-- The terminal's cell size in logical pixels, from its font size (read once: a reload reads it again)
local function char_size()
    local pt = FONT_PT
    local f = io.open(GHOSTTY_CONFIG, "r")
    if f then
        for line in f:lines() do
            local v = tonumber(line:match("^%s*font%-size%s*=%s*([%d.]+)"))
            if v then pt = v end
        end
        f:close()
    end
    return pt * CELL_W_PER_PT, pt * CELL_H_PER_PT
end
local CHAR_W, CHAR_H = char_size()

-- How many sessions fit a grid on the right side `right` ({ w, h }): the most whose every cell holds a usable terminal
-- (1 even when none does: one session is never grouped anyway)
function M.fits(right)
    local n = 1
    for count = 2, #CELLS do
        for _, c in ipairs(CELLS[count]) do
            if (right.w * c[3] - CHROME) / CHAR_W < MIN_COLS or (right.h * c[4] - CHROME) / CHAR_H < MIN_ROWS then
                return n
            end
        end
        n = count
    end
    return n
end

-- name: the layout's name; width: the PM's share of the width; pm_of(ws): the PM's window address on workspace ws;
-- on_fit(ws, n): called when the number of sessions that fit workspace ws's grid changes
function M.register(name, width, pm_of, on_fit)
    local fit = {}   -- workspace id → the last count told
    hl.layout.register(name, { recalculate = function(ctx)
        local pm, rest = nil, {}
        for _, t in ipairs(ctx.targets) do
            local w = t.window
            local here = w and w.workspace and pm_of(w.workspace.id)
            if here and w.address == here and not pm then pm = t else rest[#rest + 1] = t end
        end
        local right = ctx.area
        local any = ctx.targets[1] and ctx.targets[1].window
        local ws = any and any.workspace and any.workspace.id
        if ws then
            -- The right side as it is with a PM, whether or not the PM is placed yet
            local n = M.fits({ w = ctx.area.w * (1 - width), h = ctx.area.h })
            if fit[ws] ~= n then fit[ws] = n; if on_fit then on_fit(ws, n) end end
        end
        if pm then
            -- Alone it fills the width
            if #rest == 0 then pm:place(ctx.area); return end
            pm:place(ctx:split(ctx.area, "left", width))
            right = ctx:split(ctx.area, "right", 1 - width)
        end
        local cells = CELLS[#rest]
        for i, t in ipairs(rest) do
            -- More than four (a moment before they group, or windows no PM opened): even rows
            t:place(cells and cell(right, cells[i]) or
                { x = right.x, y = right.y + right.h * (i - 1) / #rest, w = right.w, h = right.h / #rest })
        end
    end })
end

return M
