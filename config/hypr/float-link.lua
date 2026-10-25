-- ⌃⌘ + click on a link opens it in a floating window, centred, instead of a tiled one.
-- The bind doesn't take the click (non_consuming): the app under the pointer still gets it, with ⌃⌘ held, and opens
-- the link as it would (kitty: config/kitty/kitty.conf has a mouse_map for it). The bind only arms a flag for a moment,
-- and the first window that opens while it's armed floats. A link that opens in a tab of an open browser window makes
-- no window, so nothing changes then (Firefox: launcher › Settings › Apps › Firefox › links from other apps).

local ARM_MS = 2000                 -- how long after the click a new window still counts as the link's
local SIZE   = { w = 0.7, h = 0.75 } -- of the screen, the same as ⌘⇧T gives a screen-sized window

local armed, clicks = false, 0   -- clicks: only the latest click's timer disarms, so a newer click restarts the wait

hl.bind("SUPER + CTRL + mouse:272", function ()
    armed, clicks = true, clicks + 1
    local mine = clicks
    hl.timer(function () if clicks == mine then armed = false end end, { timeout = ARM_MS, type = "oneshot" })
end, { non_consuming = true })

hl.on("window.open", function (w)
    if not armed or not (w and w.monitor) then return end
    armed = false
    local win = "address:" .. w.address
    if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "enable", window = win })) end
    local m = w.monitor
    hl.dispatch(hl.dsp.window.resize({ x = math.floor(m.width / m.scale * SIZE.w), y = math.floor(m.height / m.scale * SIZE.h),
                                       exact = true, window = win }))
    hl.dispatch(hl.dsp.window.center({ window = win }))
end)
