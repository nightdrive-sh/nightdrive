-- A VM's screen follows its window, as in UTM and Parallels: qemu (Garage) gives the virtio GPU's output a new preferred
-- mode, the window's size in pixels, each time the window changes size. Hyprland reads an output's modes only when it is
-- plugged in (aquamarine), so "preferred" stays the size the VM booted with and the window stretches that picture. The
-- kernel has the new one, the first line of the connector's modes in sysfs, and an output takes a mode outside its list.
-- Run at each load (hyprland.lua: a reload mustn't go back to the old size) and by scripts/vm-display, which watches the
-- GPU's hotplug events. A mode picked in Settings › Display (the state's "mode" line) stays as it is.
--
-- The window's size is any number of pixels (on a host screen at 1.5 a window 1261 wide is 1891), and Hyprland takes a
-- fractional scale only when it divides the size into whole pixels: 1.5 on 1891 falls back to 1, tiny text (#1629). So the
-- mode is cut to the next size down that the scale divides, a pixel or a few that SDL's stretch to the window hides.

-- The scale until one is picked in Settings › Display: the installer's for a VM, right in a window on a Retina screen
-- (2 pixels to a point there). A guest that came with another local.lua (a converted desktop's "auto" gives 1) gets it too.
local VM_SCALE = 2.0

-- The virtual GPU's outputs and their preferred modes, from sysfs: { name = { w, h } }. Not hl.get_monitors(): at
-- Hyprland's start the config is read before the output is plugged in, so that list is empty, and the output would get
-- "preferred" at a scale that doesn't divide it (1.5 on 1892x1023 falls back to 11/8 = 1.375, 2 to 11/6 = 1.83, with a
-- warning) until the next reload (#1732).
local function virtualOutputs()
    local found = {}
    for card = 0, 7 do
        for n = 1, 8 do
            local name = "Virtual-" .. n
            local f = io.open("/sys/class/drm/card" .. card .. "-" .. name .. "/modes")
            if f then
                local w, h = (f:read("*l") or ""):match("^(%d+)x(%d+)$")
                f:close()
                if w then found[name] = { tonumber(w), tonumber(h) } end
            end
        end
    end
    return found
end

-- The smallest step of pixels the scale divides into whole ones: 3 for 1.5 (3/2), 5 for 1.25, 4 for 4/3, 2 for 2
local function step(scale)
    for n = 1, 12 do
        local d = n / scale
        if math.abs(d - math.floor(d + 0.5)) < 0.01 then return n end
    end
    return 1
end

-- At a load the rule is made whether the size has changed or not: without it, the "" rule's "preferred" would be
-- Hyprland's old one again. From the watcher, only an output whose size has changed is set.
return function(scales, modes)
    function NightdriveVmDisplay(changedOnly)
        local current = {}
        for _, m in ipairs(hl.get_monitors()) do current[m.name] = m.width .. "x" .. m.height end
        for name, size in pairs(virtualOutputs()) do
            if not modes[name] then
                local scale = scales[name] or VM_SCALE
                local n = step(scale)
                local mode = (size[1] - size[1] % n) .. "x" .. (size[2] - size[2] % n)
                if not (changedOnly and mode == current[name]) then
                    hl.monitor({ output = name, mode = mode, position = "auto", scale = scale })
                end
            end
        end
    end
    NightdriveVmDisplay(false)
end
