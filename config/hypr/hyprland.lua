-- Hyprland – Omarchy-style setup for a MacBook (Fedora Asahi)
-- ⌘ = SUPER. Cheat sheet: ~/.config/hypr/SHORTCUTS.md

-----------------
---- MACHINE ----
-----------------
-- Settings for the MacBook's built-in display and a Finnish Mac keyboard. On a PC or a VM, or with another keyboard layout,
-- install.sh writes the machine's own in local.lua (docs/pc.md), which overrides these.
-- MacBook display with the notch, 3024x1964 → scale 2.0 (= 1512x982)
-- (1.75 doesn't divide it evenly; the only clean values are 2.0 and 1.333)
local MONITOR_SCALE = 2.0
local KB_LAYOUT     = "fi"
local KB_VARIANT    = "mac"
local BUILTIN_DISPLAY = "eDP-1"   -- a laptop's own screen (a desktop has none)
local BAR_HEIGHT    = 36      -- the top bar in logical px (Theme.barHeight in quickshell/Theme.qml): the top corners start under it

local HOME = os.getenv("HOME")
require("region")   -- LC_TIME of Settings › Region for what starts here: region.lua

-- Each load of this config (a reload, a screen that comes or goes, the lid) leaves its time here: Hyprland announces the
-- screens again, which crashes GStreamer's waylandsink in UxPlay, and its restart loop doesn't count those crashes
-- (plugins/airplay-receiver/bin/airplay-receiver)
do
    local f = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/nightdrive-hypr-loaded", "w")
    if f then f:close() end
end

-- Each part is a file of its own beside this one; the order below is the order they ran in when they were one file.
require("display")({ scale = MONITOR_SCALE, builtin = BUILTIN_DISPLAY })   -- screens, the lid, workspaces: display.lua
local session = require("autostart")   -- what starts with the session, the autologin start: autostart.lua

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
-- Qt apps (EasyEffects) follow the GTK settings, which setup-user.sh makes dark. Not "kde": that needs plasma-integration,
-- which --no-kde removes, and even with it the apps are light unless Plasma's own colour scheme was set dark
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("MOZ_ENABLE_WAYLAND", "1")
-- QML's JIT before Qt 6.12 leaves the setter's raw return value in the accumulator after a property assignment
-- (`a.b = x`); a block that follows saves it into the JS stack, and a garbage collection then crashes on it. It took
-- Quickshell down (the top bars, menus, notifications) as a display moved. The interpreter alone runs our QML well
-- enough, so it's forced until Qt has the fix (6.12, qtdeclarative 4c1054b); an unknown version counts as unfixed.
local qml = io.popen("readlink /usr/lib64/libQt6Qml.so.6 2>/dev/null")
local qtMinor = qml and tonumber(((qml:read("*l") or ""):match("%.so%.6%.(%d+)")))
if qml then qml:close() end
if not qtMinor or qtMinor < 12 then hl.env("QV4_FORCE_INTERPRETER", "1") end
-- NVIDIA's own driver (a PC, install.sh): video decoding and GLX through it (Hyprland wiki › NVIDIA). Checked at start
-- rather than written by install.sh, so a driver added or removed later is followed.
local nvidia = io.open("/proc/driver/nvidia/version")
if nvidia then
    nvidia:close()
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
end

require("appearance")   -- gaps, borders, animations, the drawer, misc: appearance.lua
require("input")(KB_LAYOUT, KB_VARIANT)   -- keyboard, mouse, trackpad and gestures: input.lua

------------------------
---- KEYBINDINGS → bindings.lua ----
------------------------
require("bindings")
require("scroll")
require("float-link")   -- ⌃⌘ + click on a link: the window it opens floats
require("last-key")     -- when the last key was pressed: Claude doesn't move the focus while you type
require("layer-keys")   -- the window under a layer that holds the keyboard looks inactive

-----------------------
---- WINDOW RULES ----
-----------------------
require("rules")   -- which windows float and at what size: rules.lua

local update_corners = require("corners")(BAR_HEIGHT, session)   -- the screen's rounded corners, night light: corners.lua

-- A background app that raises itself (a notification click, a link) gets focus inside special:bg, and Hyprland shows the
-- whole background workspace over the windows. Bring just that window to the current workspace instead, as its shortcut does.
-- Hyprland first focuses the background workspace's last window and only then the one that asked, so wait a moment and
-- take the window that ends up active. Only while special:bg is shown: after ⌘W hides a window, focus can fall back to a
-- hidden one without showing it.
local raise_pending = false
local function raise_from_background()
    raise_pending = false
    local win = hl.get_active_window()
    local ws = hl.get_active_workspace()
    local special = hl.get_active_special_workspace()
    if not (win and win.workspace and win.workspace.name == "special:bg" and ws
            and special and special.name == "special:bg") then return end
    local target = "address:" .. win.address
    hl.dispatch(hl.dsp.window.move({ workspace = ws.id, follow = false, window = target }))
    hl.dispatch(hl.dsp.workspace.toggle_special("bg"))
    hl.dispatch(hl.dsp.focus({ window = target }))
end
hl.on("window.active", function ()
    local special = hl.get_active_special_workspace()
    if raise_pending or not (special and special.name == "special:bg") then return end
    raise_pending = true
    hl.timer(raise_from_background, { timeout = 50, type = "oneshot" })
end)

-----------------
---- PLUGINS ----
-----------------
-- The plugin folders that are on (plugins/<id>/, ~/.local/share/nightdrive/plugins/<id>/; `nightdrive plugins installed`
-- lists them in plugins.d/active): their hyprland.lua, with window rules and the like. It gets { id, dir, scripts, start }
-- as its ...: start(cmd) runs cmd once when the session starts, with autostart.lua's programs (NightdriveLocked). One that
-- fails is left out with a line in Hyprland's log. Their keys are in bindings.lua.
do
    local f = io.open(HOME .. "/.local/state/nightdrive/plugins.d/active")
    if f then
        for line in f:lines() do
            local id, dir = line:match("^([^\t]+)\t(.+)$")
            local path = dir and dir .. "/hyprland.lua"
            local exists = path and io.open(path)
            if exists then
                exists:close()
                local chunk, err = loadfile(path)
                local ok = chunk and true
                local p = { id = id, dir = dir, scripts = HOME .. "/.config/hypr/scripts",
                            start = function (cmd) table.insert(session.starts, cmd) end }
                if chunk then ok, err = pcall(chunk, p) end
                if not ok then print("nightdrive: plugin " .. id .. ": " .. tostring(err)) end
            end
        end
        f:close()
    end
end

-- Per-machine overrides: ~/.config/hypr/local.lua (not in the repo, see .gitignore). `./install.sh --vm` creates it for a virtual machine.
pcall(require, "local")
-- Personal additions from a private overlay: every ~/.config/hypr/local.d/*.lua, in name order (not in the repo, see README)
local extras = io.popen('ls "' .. HOME .. '/.config/hypr/local.d/"*.lua 2>/dev/null')
for f in extras:lines() do dofile(f) end
extras:close()
update_corners()
