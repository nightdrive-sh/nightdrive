-- The keyboard, mouse and trackpad, and the trackpad's gestures. Run at each load from hyprland.lua, with the
-- machine's keyboard from its top: require("input")(KB_LAYOUT, KB_VARIANT).

local HOME = os.getenv("HOME")

-- The mouse wheel's speed (launcher › Settings › Mouse): a number in the state file, 1.0 without one. The trackpad has its
-- own (scroll_factor below)
local mouseScroll = 1.0
local ms = io.open(HOME .. "/.local/state/nightdrive/mouse-scroll")
if ms then mouseScroll = tonumber(ms:read("l") or "") or 1.0; ms:close() end

-- Three-finger swipe up shows the drawer, down hides it (like ⌘D). Only toggles when that changes something, so a
-- second swipe the same way doesn't undo the first
local function drawer_gesture(show)
    local special = hl.get_active_special_workspace()
    local open = special ~= nil and special.name == "special:drawer"
    if open ~= show then hl.dispatch(hl.dsp.workspace.toggle_special("drawer")) end
end

return function(KB_LAYOUT, KB_VARIANT)
    hl.config({
        input = {
            kb_layout  = KB_LAYOUT,
            kb_variant = KB_VARIANT,
            kb_options = "caps:hyper,hyper:mod3",  -- Caps Lock is Hyper, a modifier of its own (Mod3) that no app uses: Hyper + a
                                                   -- letter opens an app (bindings.lua); without hyper:mod3 it would be Super
            repeat_rate  = 40,
            repeat_delay = 250,
            follow_mouse = 1,
            mouse_refocus = false,   -- focus follows the mouse only when it crosses into another window (a jittery trackpad no longer steals focus from a new window)
            sensitivity  = 0,
            scroll_factor = mouseScroll,
            touchpad = {
                natural_scroll       = false,
                clickfinger_behavior = true,  -- two-finger click = right click
                tap_to_click         = false,  -- like the macOS default: only a physical press clicks
                scroll_factor        = 1.0,   -- libinput's own distance; per-app speeds in scroll.lua
            },
        },
    })

    -- Three-finger swipe switches workspace
    hl.gesture({
        fingers = 3,
        direction = "horizontal",
        action = "workspace",
    })
    -- A shorter swipe is enough to switch (defaults: half the way, or a fast flick)
    hl.config({
        gestures = {
            workspace_swipe_cancel_ratio     = 0.3,    -- switch after 30 % of the way across (default 0.5)
            workspace_swipe_min_speed_to_force = 15,   -- a quick flick switches regardless of distance (default 30)
        },
    })
    -- Four-finger swipe moves the window in the swipe direction (like ⌘⇧ + arrows)
    for _, dir in ipairs({ "left", "right", "up", "down" }) do
        hl.gesture({
            fingers = 4,
            direction = dir,
            action = function() NIGHTDRIVE_SWAP(dir) end,
        })
    end
    hl.gesture({ fingers = 3, direction = "up",   action = function() drawer_gesture(true) end })
    hl.gesture({ fingers = 3, direction = "down", action = function() drawer_gesture(false) end })
end
