-- The layout of a project manager's space (pm-space.lua, #3060): the PM the left column, its sessions a grid on the
-- right, every one of them in sight. Master can't make a 2×2 grid, so the space has a layout of its own (Hyprland's
-- Lua layouts, hl.layout.register). pm-space.lua keeps the sessions at four targets at most: a fifth turns them into
-- one window group, which is a single target here and so fills the right side.

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

-- name: the layout's name; width: the PM's share of the width; pm_of(ws): the PM's window address on workspace ws
function M.register(name, width, pm_of)
    hl.layout.register(name, { recalculate = function(ctx)
        local pm, rest = nil, {}
        for _, t in ipairs(ctx.targets) do
            local w = t.window
            local here = w and w.workspace and pm_of(w.workspace.id)
            if here and w.address == here and not pm then pm = t else rest[#rest + 1] = t end
        end
        local right = ctx.area
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
