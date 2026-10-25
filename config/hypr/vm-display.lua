-- A VM's screen follows its window, as in UTM and Parallels: qemu (Garage) gives the virtio GPU's output a new preferred
-- mode, the window's size in pixels, each time the window changes size. Hyprland reads an output's modes only when it is
-- plugged in (aquamarine), so "preferred" stays the size the VM booted with and the window stretches that picture. The
-- kernel has the new one, the first line of the connector's modes in sysfs, and an output takes a mode outside its list.
-- Run at each load (hyprland.lua: a reload mustn't go back to the old size) and by scripts/vm-display, which watches the
-- GPU's hotplug events. A mode picked in Settings › Display (the state's "mode" line) stays as it is.

-- The connector's preferred mode, "WIDTHxHEIGHT", or nil (not a virtual GPU's output, or none yet)
local function preferred(output)
    if not output:match("^Virtual%-%d+$") then return nil end
    for card = 0, 7 do
        local f = io.open("/sys/class/drm/card" .. card .. "-" .. output .. "/modes")
        if f then
            local mode = f:read("*l")
            f:close()
            return mode and mode:match("^%d+x%d+$") and mode or nil
        end
    end
    return nil
end

-- At a load the rule is made whether the size has changed or not: without it, the "" rule's "preferred" would be
-- Hyprland's old one again. From the watcher, only an output whose size has changed is set.
return function(scales, modes)
    function NightdriveVmDisplay(changedOnly)
        for _, m in ipairs(hl.get_monitors()) do
            local mode = not modes[m.name] and preferred(m.name)
            if mode and not (changedOnly and mode == m.width .. "x" .. m.height) then
                hl.monitor({ output = m.name, mode = mode, position = "auto", scale = scales[m.name] or m.scale })
            end
        end
    end
    NightdriveVmDisplay(false)
end
