-- ⌥ as Alt in Nightdrive's own windows and layers (Dashboard #3525, after #3507).
-- With a Mac layout that makes ⌥ level 3 (fi(mac) with lv3:lalt_switch), ⌥ is Mod5, and Qt reads Mod5 as no modifier
-- at all: Files' ⌥← ⌥→ (back, forward) arrived as plain arrows and moved in the list, the launcher's and Ask Claude's
-- ⌥← ⌥→ moved by a character, the launcher's ⌥⏎ (start an app at login) opened the app. While a Quickshell window or
-- layer has the keyboard, these send Alt instead; other apps keep ⌥ as it was pressed.
--
-- The binds are on only then (set_enabled on focus and layer changes, and after a key, as layer-keys.lua does), so no
-- other app's ⌥ arrows go through send_shortcut, whose held arrow repeats as a plain one in the app.
-- ⌥↑ ⌥↓ are bindings.lua's (FILES_OPTION_KEYS: Nautilus wants other keys). ⌥ + a character key stays the app's: ⌥2 is
-- @ with a Mac layout, so the apps read those themselves (kit/AppOption.qml).
-- Without the Mac Keyboard Shortcuts plugin (keyd), bindings.lua's ⌥← ⌥→ already send Alt to every app (their MOD5
-- copies), so only ⌥⏎ is bound here then.

local AFTER_KEY_MS = 60   -- a key may have opened or closed a layer (the launcher) by then
local OWN_CLASS = "org.quickshell"
local BAR_NAMESPACE = "nightdrive-bar"   -- a layer of Nightdrive's own Quickshell: the launcher, menus, Ask Claude

return function (keyd)
    local keys = { "Return" }
    if keyd then
        keys = { "Return", "left", "right" }
    end

    -- The Quickshell that draws the bar draws the launcher and the menus too: its layers are known by its pid
    local function own_layer(l)
        if (l.namespace or ""):match("^nightdrive") then return true end
        for _, o in ipairs(hl.get_layers() or {}) do
            if o.namespace == BAR_NAMESPACE then return o.pid == l.pid end
        end
        return false
    end

    -- Who has the keyboard: a layer that asks for it (keyboard-layer.lua), else the active window
    local function own()
        for _, l in ipairs(hl.get_layers() or {}) do
            if l.mapped and (l.keyboard_interactivity or 0) ~= 0 then return own_layer(l) end
        end
        local w = hl.get_active_window()
        return w ~= nil and w.class == OWN_CLASS
    end

    local binds = {}
    for _, key in ipairs(keys) do
        for _, shift in ipairs({ "", " SHIFT" }) do
            local b = hl.bind("MOD5" .. (shift ~= "" and " +" .. shift or "") .. " + " .. key, function ()
                hl.dispatch(hl.dsp.send_shortcut({ mods = "ALT" .. shift, key = key }))
            end, { repeating = key ~= "Return" })
            if b then
                b:set_enabled(false)
                binds[#binds + 1] = b
            end
        end
    end

    local on = false
    local function look()
        local want = own()
        if want == on then return end
        on = want
        for _, b in ipairs(binds) do b:set_enabled(want) end
    end

    hl.on("window.active", look)
    hl.on("layer.opened", look)
    hl.on("layer.closed", look)
    hl.on("input.keyboard.key", function () hl.timer(look, { timeout = AFTER_KEY_MS, type = "oneshot" }) end)
    look()
end
