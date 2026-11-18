-- The layout of a project manager's space (pm-space.lua): the PM the left column, its sessions on the right. They are
-- one window group (pm-space.lua keeps them so), a single target that fills the right side; the PM alone fills the
-- width. A layout of its own (Hyprland's Lua layouts, hl.layout.register) rather than master: it places the PM left by
-- its address, whichever window came first, so nothing has to swap it there.
-- (Sessions in a grid, #3060 and #3066, were dropped for tabs in #3124: the PM's sessions as tabs, however many.)

local M = {}

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
            if #rest == 0 then pm:place(ctx.area); return end
            pm:place(ctx:split(ctx.area, "left", width))
            right = ctx:split(ctx.area, "right", 1 - width)
        end
        -- Normally one target (the group); a moment before a new session joins it, or windows no PM opened: even rows
        for i, t in ipairs(rest) do
            t:place({ x = right.x, y = right.y + right.h * (i - 1) / #rest, w = right.w, h = right.h / #rest })
        end
    end })
end

return M
