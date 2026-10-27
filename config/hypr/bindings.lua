-- All Hyprland keybindings (⌘ = SUPER).
-- Edit this file; Hyprland reloads changes automatically.
-- App-specific keys live in each app's own config (e.g. ~/.config/kitty/kitty.conf).

---------------------
---- PROGRAMS ----
---------------------
local scripts     = os.getenv("HOME") .. "/.config/hypr/scripts"
-- The terminal chosen in Default apps (kitty unless changed): scripts/terminal
local terminal    = scripts .. "/terminal --dir " .. os.getenv("HOME") .. "/Projects"
-- The default apps (launcher › Settings › Apps › Default apps, nightdrive defaults): a new choice is used at the next press
local browser     = scripts .. "/default-apps open browser"
local fileManager = scripts .. "/default-apps open files"
local email       = scripts .. "/default-apps open email --focus"   -- one mail window: brought up when it's open
-- A terminal's window (the keys below that would do something else there; plugins' too): the terminals' own classes, and
-- the ones scripts/terminal gives its windows (Ghostty's with a sh.nightdrive. prefix)
TERMINAL_CLASSES = { ["kitty"] = true, ["foot"] = true, ["footclient"] = true, ["Alacritty"] = true,
                     ["com.mitchellh.ghostty"] = true, ["org.wezfurlong.wezterm"] = true,
                     ["floating-tui"] = true, ["floating-help"] = true, ["deck"] = true, ["claude-background"] = true }
function NIGHTDRIVE_IS_TERMINAL(w)
    return w ~= nil and TERMINAL_CLASSES[(w.class:gsub("^sh%.nightdrive%.", ""))] == true
end

-- A layer surface with the keyboard (the launcher, a menu): it gets the keys, not the active window behind it
function NIGHTDRIVE_LAYER_HAS_KEYBOARD()
    for _, l in ipairs(hl.get_layers()) do
        if l.mapped and l.interactivity == 1 then return true end   -- 1: exclusive keyboard focus
    end
    return false
end

-- Installed optional parts (plugins.txt, plugins/): a part's keys are bound only when it is there. `nightdrive plugins
-- installed` writes the list and reloads Hyprland when it changes (an installer from launcher › Install › Plugins).
local plugins = {}
do
    local f = io.open(os.getenv("HOME") .. "/.cache/nightdrive/plugins")
        or (io.popen and io.popen(os.getenv("HOME") .. "/.local/bin/nightdrive plugins installed 2>/dev/null"))
    if f then
        for id in f:lines() do plugins[id] = true end
        f:close()
    end
end


------------------------
---- KEYBINDINGS ----
------------------------
local mod = "SUPER"

-- Every binding (also local.lua's and local.d's) is recorded, so that the top bar menu's submap (qsmenu, below) can repeat
-- them: inside a submap only its own keys work, and ⌘Enter, the volume keys etc. would be dead while a menu is open.
NIGHTDRIVE_BINDS = {}
-- Your own Hyper keys (launcher › Settings › Apps › App shortcuts, scripts/app-keys): KEY<TAB>app.desktop, or - for a key
-- that does nothing. They win over every other Hyper + KEY binding, Nightdrive's, a plugin's or local.lua's, which are
-- left out here: those are the defaults.
local appKeys = {}
do
    local f = io.open(os.getenv("HOME") .. "/.local/state/nightdrive/app-keys")
    if f then
        for line in f:lines() do
            local key, app = line:match("^(%w)\t([%w%._-]+)$")
            if key then appKeys[key:upper()] = app end
        end
        f:close()
    end
end
local bind = hl.bind
local ownKey = false
-- ⌥ is Alt (Mod1) or, when it types characters like the right ⌥ on a Mac keyboard (or both, with a layout that makes the
-- left one level 3 too), Mod5. An ⌥ binding works with either, unless it is ⌥ (+ ⇧) + a character key: AltGr types those.
local function option_copy(keys)
    if not keys:match("%f[%w]ALT%f[^%w]") then return nil end
    local key = keys:match("([^%s+]+)%s*$")
    local others = keys:gsub("%f[%w]ALT%f[^%w]", ""):gsub("%f[%w]SHIFT%f[^%w]", ""):gsub("[%s+]", "")
    if others == key and (#key == 1 or key:match("^code:")) then return nil end
    return (keys:gsub("%f[%w]ALT%f[^%w]", "MOD5"))
end
hl.bind = function (keys, action, opts)
    local hyper = keys:match("^%s*MOD3%s*%+%s*(%w)%s*$")
    if hyper and appKeys[hyper:upper()] and not ownKey then return end
    if not NIGHTDRIVE_IN_SUBMAP then table.insert(NIGHTDRIVE_BINDS, { keys, action, opts }) end
    local copy = option_copy(keys)
    if copy then bind(copy, action, opts) end
    return bind(keys, action, opts)
end

-- Programs
hl.bind(mod .. " + RETURN",      hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + ALT + RETURN", hl.dsp.exec_cmd(scripts .. "/terminal-or-claude"))   -- Claude Code; text typed in the launcher becomes the prompt
hl.bind(mod .. " + SPACE",       hl.dsp.exec_cmd("qs ipc call launcher toggle"))   -- Quickshell launcher
hl.bind("XF86Search",               hl.dsp.exec_cmd("qs ipc call launcher toggle"))   -- F4 (magnifier): launcher, like ⌘Space
hl.bind("XF86LaunchA",              hl.dsp.exec_cmd("qs ipc call menu toggle notifications"))   -- F3 (Mission Control, KEY_SCALE): notification centre
hl.bind(mod .. " + XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ; qs ipc call osd mic"), { locked = true })   -- ⌘F5: mic on/off + toast
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(scripts .. "/dictate start"), { locked = true })               -- F5 (sends KEY_MICMUTE): hold -> speech to text (Voxtype, Parakeet)
-- The releases are transparent: a mouse click while the key is held "shadows" the binds of every held key (Hyprland's
-- shadowKeybinds), and the release would be skipped, so dictation kept recording until the key was pressed again.
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(scripts .. "/dictate stop"),  { locked = true, release = true, transparent = true })    -- release -> transcribe and type
hl.bind("XF86Fn", hl.dsp.exec_cmd(scripts .. "/dictate fn-down"), { locked = true })                       -- Fn held (over 0.3 s) -> dictation, like F5
hl.bind("XF86Fn", hl.dsp.exec_cmd(scripts .. "/dictate fn-up"),   { locked = true, release = true, transparent = true })
hl.bind("F19",    hl.dsp.exec_cmd(scripts .. "/dictate fn-down"), { locked = true })                       -- Fn when keyd (Mac Keyboard Shortcuts) runs: keyd sends F19 for it
hl.bind("F19",    hl.dsp.exec_cmd(scripts .. "/dictate fn-up"),   { locked = true, release = true, transparent = true })
-- Apps open with Hyper (Caps Lock, Mod3: hyprland.lua's kb_options) + a letter: the browser, Files, Email, and the optional
-- parts' apps below and in the plugins' bindings.lua (Deck M, 1Password P). ⌘ stays for the desktop and the apps' own keys.
-- These are defaults: your own keys (appKeys, above) replace them.
hl.bind("MOD3 + B",              hl.dsp.exec_cmd(browser))
hl.bind(mod .. " + SHIFT + RETURN", hl.dsp.exec_cmd(browser))   -- next to ⌘Enter (terminal) and ⌘⌥Enter (Claude Code)
hl.bind("MOD3 + F",              hl.dsp.exec_cmd(fileManager))
hl.bind("MOD3 + E",              hl.dsp.exec_cmd(email))
ownKey = true
for key, app in pairs(appKeys) do
    if app ~= "-" then hl.bind("MOD3 + " .. key, hl.dsp.exec_cmd(scripts .. "/app-keys open " .. app)) end
end
ownKey = false
-- Optional parts' apps (plugins.txt ids; SHORTCUTS.md tags the same lines with {id}), Hyper + the letter
local optional = {
    { "whatsapp",    "W", "'^chrome-web\\.whatsapp\\.com' gtk-launch webapp-whatsapp" },   -- WhatsApp webapp
    { "slack",       "S", "'^chrome-app\\.slack\\.com' gtk-launch webapp-slack" },         -- Slack webapp
    { "teams",       "T", "'^chrome-teams\\.microsoft\\.com' gtk-launch webapp-teams" },  -- Teams webapp
    { "youtube",     "Y", "'^chrome-www\\.youtube\\.com' gtk-launch webapp-youtube" },     -- YouTube webapp
}
for _, o in ipairs(optional) do
    if plugins[o[1]] then hl.bind("MOD3 + " .. o[2], hl.dsp.exec_cmd(scripts .. "/launch-or-focus " .. o[3])) end
end
-- Installed plugin folders (plugins/<id>/, ~/.local/share/nightdrive/plugins/<id>/): their own bindings.lua, which gets
-- { id, dir, mod, scripts } as its ... (`nightdrive plugins installed` lists them in plugins.d/active). One that fails is
-- left out with a line in Hyprland's log, so it can't take the rest of the keys with it.
do
    local f = io.open(os.getenv("HOME") .. "/.cache/nightdrive/plugins.d/active")
    if f then
        for line in f:lines() do
            local id, dir = line:match("^([^\t]+)\t(.+)$")
            local path = dir and dir .. "/bindings.lua"
            local exists = path and io.open(path)
            if exists then
                exists:close()
                local chunk, err = loadfile(path)
                local ok = chunk and true
                if chunk then ok, err = pcall(chunk, { id = id, dir = dir, mod = mod, scripts = scripts }) end
                if not ok then print("nightdrive: plugin " .. id .. ": " .. tostring(err)) end
            end
        end
        f:close()
    end
end
hl.bind(mod .. " + SHIFT + E",   hl.dsp.exec_cmd("qs ipc call launcher openLevel emoji"))   -- emoji picker
hl.bind(mod .. " + SHIFT + V",   hl.dsp.exec_cmd("qs ipc call launcher openLevel clipboard"))   -- clipboard history
-- Claude writes the selected text out (scripts/claude-write, quickshell/ClaudeWrite.qml). Pressed again while its preview
-- has the keyboard: another version. In Nightdrive Mail the key stays the app's own (the script sends it there)
hl.bind(mod .. " + SHIFT + C", function ()
    if NIGHTDRIVE_LAYER_HAS_KEYBOARD() then
        hl.dispatch(hl.dsp.exec_cmd("qs ipc call write again"))
    else
        hl.dispatch(hl.dsp.exec_cmd(scripts .. "/claude-write"))
    end
end)
-- Shelf (quickshell/Shelf.qml): no key, a file dragged to the top edge of the screen opens it (qs ipc call shelf toggle)
hl.bind(mod .. " + ESCAPE",      hl.dsp.exec_cmd("qs ipc call menu toggle notifications"))
hl.bind(mod .. " + CTRL + L",    hl.dsp.exec_cmd("loginctl lock-session"))
-- ⌃⌥F3 brings back a lock that died (Hyprland's "lockscreen app died" screen, still locked): that screen says to switch to
-- a text console with Ctrl+Alt+F3, but a Mac keyboard's F3 is Mission Control without Fn, so this key starts the lock
-- again instead (scripts/lock does nothing while one is up; unlocked, it locks). Where F3 is F3, Hyprland switches to
-- the console first.
hl.bind("CTRL + ALT + XF86LaunchA", hl.dsp.exec_cmd(scripts .. "/lock"), { locked = true })
hl.bind(mod .. " + SHIFT + S",   hl.dsp.exec_cmd(scripts .. "/screenshot clip"))   -- region screenshot to clipboard
hl.bind(mod .. " + ALT + S",     hl.dsp.exec_cmd(scripts .. "/screenshot winclip"))   -- window screenshot to clipboard
hl.bind(mod .. " + ALT + SHIFT + S", hl.dsp.exec_cmd(scripts .. "/screenshot fullclip"))   -- whole screen to clipboard
hl.bind(mod .. " + SHIFT + SPACE", hl.dsp.exec_cmd("qs ipc call menu nav"))   -- top bar via keyboard: ←/→ menu, ↑/↓ row, Enter, Esc
hl.bind(mod .. " + SHIFT + K",     hl.dsp.exec_cmd(scripts .. "/terminal --class floating-help -- sh -c '" .. scripts .. "/shortcuts | less'"))   -- SHORTCUTS.md for the installed parts

-- Universal copy/paste/cut ⌘C/⌘V/⌘X in every app (the Omarchy way)
hl.bind(mod .. " + C", hl.dsp.send_shortcut({ mods = "CTRL",  key = "Insert" }))
-- In a terminal, a picture on the clipboard goes in as Ctrl+V (scripts/paste): asked there, not here, so that reading the
-- clipboard doesn't hold up Hyprland
hl.bind(mod .. " + V", function ()
    if NIGHTDRIVE_IS_TERMINAL(hl.get_active_window()) then
        hl.dispatch(hl.dsp.exec_cmd(scripts .. "/paste"))
    else
        hl.dispatch(hl.dsp.send_shortcut({ mods = "SHIFT", key = "Insert" }))
    end
end)
hl.bind(mod .. " + X", hl.dsp.send_shortcut({ mods = "CTRL",  key = "X" }))

-- The apps' own keys, sent as Ctrl+…: undo / redo / select all / save / reload / reload without the cache / find / new tab /
-- downloads (⌘Z / ⌘⇧Z / ⌘A / ⌘S / ⌘R / ⌘⇧R / ⌘F / ⌘T / ⌘J). Not in terminals (any of them, and their floating windows): there
-- Ctrl+Z would suspend the running program, Ctrl+A jumps to the start of the line, Ctrl+S freezes the output (XOFF),
-- Ctrl+R searches the shell's history and Ctrl+J is Enter. The launcher over a terminal gets them all the same
for _, k in ipairs({ { "", "Z" }, { " SHIFT", "Z" }, { "", "A" }, { "", "S" }, { "", "R" }, { " SHIFT", "R" },
                     { "", "F" }, { "", "T" }, { "", "J" } }) do
    local shift, key = k[1], k[2]
    hl.bind(mod .. (shift ~= "" and " +" .. shift or "") .. " + " .. key, function ()
        local w = hl.get_active_window()
        if NIGHTDRIVE_IS_TERMINAL(w) and not NIGHTDRIVE_LAYER_HAS_KEYBOARD() then return end
        hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL" .. shift, key = key }))
    end)
end

-- ⌘⌫ = Delete (move to trash) in the file manager, like in macOS Finder. Elsewhere it messages the launcher:
-- in Settings › Background it removes the selected custom wallpaper (otherwise it does nothing).
-- With the Mac Keyboard Shortcuts plugin (plugins/keyd) keyd does ⌘⌫ and ⌥⌫ instead, as real key presses, per app
-- (its app.conf): Hyprland's synthetic Delete could get stuck repeating. The plugin's hyprland.lua starts its app mapper.
if not plugins.keyd then
    hl.bind(mod .. " + BACKSPACE", function ()
        local w = hl.get_active_window()
        if w and (w.class == "org.gnome.Nautilus" or w.class == "nautilus") then
            hl.dispatch(hl.dsp.send_shortcut({ mods = "", key = "Delete" }))
        else
            hl.dispatch(hl.dsp.exec_cmd("qs ipc call launcher deleteSelected"))
        end
    end)
end

-- ⌥← / ⌥→ move by word, like in macOS, in apps where Alt+arrows does something else: GtkSourceView editors swap
-- words with them, Chromium and its web apps go back/forward. These get Ctrl+arrows (word move; ⇧ selects).
-- Other apps get the keys as they were.
local WORD_ARROW_APPS = { ["org.gnome.gitlab.somas.Apostrophe"] = true, chromium = true, ["chromium-browser"] = true }
local function word_arrow_app(class)
    return class and (WORD_ARROW_APPS[class] or class:match("^chrome%-.*%-Default$")) and true or false
end
for _, key in ipairs({ "left", "right" }) do
    for _, shift in ipairs({ "", " SHIFT" }) do
        hl.bind("ALT" .. (shift ~= "" and " +" .. shift or "") .. " + " .. key, function ()
            local w = hl.get_active_window()
            local mods = (w and word_arrow_app(w.class)) and "CTRL" or "ALT"
            hl.dispatch(hl.dsp.send_shortcut({ mods = mods .. shift, key = key }))
        end, { repeating = true })
    end
end

-- Back/forward ⌃⌘← / ⌃⌘→ (browsers, web apps, Nautilus: Alt+arrows). Not in terminals or GtkSourceView editors,
-- where Alt+arrows edits text
for _, key in ipairs({ "left", "right" }) do
    hl.bind(mod .. " + CTRL + " .. key, function ()
        local w = hl.get_active_window()
        if w and (NIGHTDRIVE_IS_TERMINAL(w) or w.class == "org.gnome.gitlab.somas.Apostrophe") then return end
        hl.dispatch(hl.dsp.send_shortcut({ mods = "ALT", key = key }))
    end)
end

-- Next/previous tab ⌘⌥← / ⌘⌥→ in every app (Firefox, Chromium, Nautilus, Thunderbird: Ctrl+PageUp/PageDown)
hl.bind(mod .. " + ALT + left",  hl.dsp.send_shortcut({ mods = "CTRL", key = "Prior" }))
hl.bind(mod .. " + ALT + right", hl.dsp.send_shortcut({ mods = "CTRL", key = "Next" }))

-- Windows
hl.bind(mod .. " + W",          hl.dsp.exec_cmd(scripts .. "/close-or-hide"))   -- closes; background apps (hypr/background-apps) are hidden in the background instead
hl.bind(mod .. " + Q",           hl.dsp.exec_cmd(scripts .. "/quit-app"))   -- quits the app for real, background apps too (Deck, WhatsApp…); ⌘W hides them
hl.bind(mod .. " + SHIFT + U",   hl.dsp.exec_cmd(scripts .. "/reopen"))   -- opens the window last closed with ⌘W again, where it was; again: the one before it
-- The window's own keys are ⌘⇧: fullscreen, floating, split direction and the arrows that move it. ⌘F / ⌘T / ⌘J are the
-- apps' (find, new tab, downloads: the list below the copy keys)
hl.bind(mod .. " + SHIFT + F",   hl.dsp.window.fullscreen(), { dont_inhibit = true })   -- also over a VM window (dont_inhibit: see Workspaces)
-- ⌘⇧T: toggle floating. For Deck: tiled -> floating at its default size, centred; floating but moved/resized ->
-- back to default size, centred; floating already at default position -> tiled. (Size: DECK_SIZE, which the Deck plugin's
-- hyprland.lua sets after this file has run, so it's read at the key press)
local function xy(t) return t.x or t[1], t.y or t[2] end
local function deck_reset(w)
    hl.dispatch(hl.dsp.window.resize({ x = DECK_SIZE.w, y = DECK_SIZE.h, exact = true, window = "address:" .. w.address }))
    hl.dispatch(hl.dsp.window.center({ window = "address:" .. w.address }))
end
local function deck_at_default(w)
    local sw, sh = xy(w.size)
    local x, y = xy(w.at)
    local m = w.monitor
    local cx, cy = (m.width / m.scale - DECK_SIZE.w) / 2, (m.height / m.scale - DECK_SIZE.h) / 2
    return sw == DECK_SIZE.w and sh == DECK_SIZE.h and math.abs(x - cx) <= 3 and math.abs(y - cy) <= 30   -- y: the bar shifts the centre a little
end
-- A window floated with ⌘⇧T is always centred. A screen-sized one (e.g. a lone window: geometry stays screen-sized and
-- the border disappears off the left/top) is first shrunk to 70 % x 75 %
local function tame_float(w)
    if not (w and w.floating) then return end
    local m = w.monitor
    local mw, mh = m.width / m.scale, m.height / m.scale
    local sw, sh = xy(w.size)
    if sw >= mw * 0.95 and sh >= mh * 0.9 then
        hl.dispatch(hl.dsp.window.resize({ x = math.floor(mw * 0.7), y = math.floor(mh * 0.75), exact = true, window = "address:" .. w.address }))
    end
    hl.dispatch(hl.dsp.window.center({ window = "address:" .. w.address }))
end
local function deck_toggle_float()
    local w = hl.get_active_window()
    if w and w.class:gsub("^sh%.nightdrive%.", "") == "deck" and DECK_SIZE then
        if not w.floating then
            hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
            deck_reset(w)
        elseif deck_at_default(w) then
            hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
        else
            deck_reset(w)
        end
    else
        hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
        tame_float(hl.get_active_window())
    end
end
hl.bind(mod .. " + SHIFT + T",   deck_toggle_float)

hl.bind(mod .. " + SHIFT + J",   hl.dsp.layout("togglesplit"))

-- Focus with arrows, move window with Shift+arrows
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mod .. " + " .. dir,             hl.dsp.focus({ direction = dir }))
    hl.bind(mod .. " + SHIFT + " .. dir,     function() NIGHTDRIVE_SWAP(dir) end)   -- slides (hyprland.lua)
end

-- ⌥Tab / ⌥⇧Tab: the active app's next / previous window (same class), on any workspace (focus goes there), in the order
-- they opened. Not the ones hidden in special:bg (⌘W on a background app): those were put away on purpose.
local function cycle_app_windows(step)
    local w = hl.get_active_window()
    if not w then return end
    local list = {}
    for _, o in ipairs(hl.get_windows({ class = w.class })) do
        if o.class == w.class and o.mapped and not (o.workspace and o.workspace.name == "special:bg") then
            table.insert(list, o)
        end
    end
    if #list < 2 then return end
    table.sort(list, function (a, b) return a.stable_id < b.stable_id end)
    for i, o in ipairs(list) do
        if o.address == w.address then
            local target = list[(i - 1 + step) % #list + 1]
            hl.dispatch(hl.dsp.focus({ window = "address:" .. target.address }))
            -- Focus alone leaves a floating window under the others: raise it too
            hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = "address:" .. target.address }))
            return
        end
    end
end
hl.bind("ALT + TAB",         function () cycle_app_windows(1) end)
hl.bind("ALT + SHIFT + TAB", function () cycle_app_windows(-1) end)

-- ⌘⌥1–⌘⌥0: every window of the active workspace to workspace i (joining the ones there), and focus follows them.
-- To an empty workspace the whole workspace is renumbered, which keeps its layout as it was: moved one by one, dwindle
-- splits them anew. Not the laptop's own workspace with an external display: the laptop screen would lose it.
-- Otherwise one at a time with follow = false, so the source stays active until the last one has gone.
local function move_all_windows(i)
    local ws = hl.get_active_workspace()
    if not ws or ws.id == i then return end
    if not hl.get_workspace(i) and (ws.id ~= LAPTOP_WORKSPACE or #hl.get_monitors() == 1) then
        hl.dispatch(hl.dsp.workspace.change_id({ workspace = ws.id, id = i }))
        hl.dispatch(hl.dsp.exec_cmd("qs ipc call bar workspaces"))   -- no event for the new id: the bar would keep the old one
        return
    end
    for _, w in ipairs(hl.get_workspace_windows(ws.id) or {}) do
        hl.dispatch(hl.dsp.window.move({ workspace = i, follow = false, window = "address:" .. w.address }))
    end
    hl.dispatch(hl.dsp.focus({ workspace = i }))
end

-- Workspaces ⌘1–⌘0, move window ⌘⇧1–⌘⇧0, move all windows ⌘⌥1–⌘⌥0. With the drawer open ⌘1–⌘0 closes it first,
-- otherwise it stays over the new workspace. dont_inhibit: they work over a window that takes the keyboard (a VM's qemu
-- window, a remote desktop) too, so it can be left with them; the desktop inside a VM doesn't get them.
for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key, function()
        local special = hl.get_active_special_workspace()
        if special and special.name == "special:drawer" then hl.dispatch(hl.dsp.workspace.toggle_special("drawer")) end
        hl.dispatch(hl.dsp.focus({ workspace = i }))
    end, { dont_inhibit = true })
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { dont_inhibit = true })
    hl.bind(mod .. " + ALT + " .. key, function() move_all_windows(i) end, { dont_inhibit = true })
end
hl.bind(mod .. " + TAB",         hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }))

-- Drawer: a special workspace that slides up over the windows (look in hyprland.lua)
-- ⌘⇧D puts the active window in the drawer, or takes it back out; ⌘D shows/hides the drawer (⌘S is Save, above)
-- A window remembers where it came from (until Hyprland reloads its config): ⌘⇧D in the drawer takes it back to that
-- workspace, a floating one to its old place and size, a tiled one next to the window now at its old place
local drawerOrigin = {}   -- window address -> { ws, floating, x, y, w, h }
-- ⌘⇧D throws the window down off the screen before it goes into the drawer: it floats at its own place, slides down
-- (only this move is animated, windows otherwise switch instantly) and is tiled again in the drawer
hl.curve("throw", { type = "bezier", points = { {0.5, 0}, {0.75, 0} } })   -- ease in: speeds up as it falls
local function drawer_throw(w)
    local win = "address:" .. w.address
    local x, y = xy(w.at)
    local sw, sh = xy(w.size)
    local tiled = not w.floating
    drawerOrigin[w.address] = { ws = w.workspace.id, floating = w.floating, x = x, y = y, w = sw, h = sh }
    if tiled then
        hl.dispatch(hl.dsp.window.float({ action = "enable", window = win }))
        hl.dispatch(hl.dsp.window.resize({ x = sw, y = sh, exact = true, window = win }))
        hl.dispatch(hl.dsp.window.move({ x = x, y = y, exact = true, window = win }))
    end
    local m = w.monitor
    hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.5, bezier = "throw" })
    hl.dispatch(hl.dsp.window.move({ x = x, y = math.floor(m.y + m.height / m.scale) + 20, exact = true, window = win }))
    hl.timer(function()
        hl.animation({ leaf = "windowsMove", enabled = false })
        hl.dispatch(hl.dsp.window.move({ workspace = "special:drawer", follow = false, window = win }))
        if tiled then hl.dispatch(hl.dsp.window.float({ action = "disable", window = win }))
        else hl.dispatch(hl.dsp.window.center({ window = win })) end   -- a floating one: in the middle of the drawer
    end, { timeout = 360, type = "oneshot" })
end
-- Puts a window back where it was: o = { floating, x, y, w, h } from before (nil: anywhere), on workspace `target`.
-- With win = nil it only focuses the spot, so that the window opening next lands there. Returns the focus for
-- hl.dispatch: global for ⌘⇧U too (scripts/reopen, a window closed with ⌘W opened again), whose hyprctl dispatch
-- needs a dispatcher back.
function NIGHTDRIVE_PLACE(win, o, target)
    hl.dispatch(hl.dsp.focus({ workspace = target }))
    local spot = hl.dsp.focus({ workspace = target })
    if o and not o.floating then
        -- the tiled window at the old spot's centre gets split, so the window lands about where it was
        local cx, cy = o.x + o.w / 2, o.y + o.h / 2
        for _, t in ipairs(hl.get_workspace_windows(target) or {}) do
            local tx, ty = xy(t.at)
            local tw, th = xy(t.size)
            if not t.floating and "address:" .. t.address ~= win and cx >= tx and cx < tx + tw and cy >= ty and cy < ty + th then
                spot = hl.dsp.focus({ window = "address:" .. t.address })
                break
            end
        end
    end
    hl.dispatch(spot)
    if not win then return spot end
    if o then hl.dispatch(hl.dsp.window.float({ action = o.floating and "enable" or "disable", window = win })) end
    hl.dispatch(hl.dsp.window.move({ workspace = target, window = win }))
    if o and not o.floating then
        -- the new half may be on the wrong side (dwindle puts it right/below): swap towards the old spot
        local n = hl.get_window(win)
        if n then
            local nx, ny = xy(n.at)
            local nw, nh = xy(n.size)
            local dx, dy = (o.x + o.w / 2) - (nx + nw / 2), (o.y + o.h / 2) - (ny + nh / 2)
            if math.max(math.abs(dx), math.abs(dy)) > 50 then
                local dir = math.abs(dx) > math.abs(dy) and (dx < 0 and "left" or "right") or (dy < 0 and "up" or "down")
                NIGHTDRIVE_SWAP(dir, win)
            end
        end
    end
    if o and o.floating then
        hl.dispatch(hl.dsp.window.resize({ x = o.w, y = o.h, exact = true, window = win }))
        hl.dispatch(hl.dsp.window.move({ x = o.x, y = o.y, exact = true, window = win }))
    end
    return hl.dsp.focus({ window = win })
end
local function drawer_return(w)
    local o = drawerOrigin[w.address]
    drawerOrigin[w.address] = nil
    local target = o and hl.get_workspace(o.ws) and o.ws or w.monitor.active_workspace.id
    hl.dispatch(hl.dsp.workspace.toggle_special("drawer"))   -- hide the drawer, the window is shown where it lands
    hl.dispatch(NIGHTDRIVE_PLACE("address:" .. w.address, o, target))
end
local function drawer_send()
    local w = hl.get_active_window()
    if not w then return end
    if w.workspace and w.workspace.name == "special:drawer" then
        drawer_return(w)
    else
        drawer_throw(w)
    end
end
hl.bind(mod .. " + SHIFT + D", drawer_send)
hl.bind(mod .. " + D", hl.dsp.workspace.toggle_special("drawer"))   -- empty, it shows a hint (quickshell/Drawer.qml)

-- Mouse: ⌘+drag moves, ⌘+right-drag resizes. Over the top bar there's no window, so the press goes on to the bar, where
-- ⌘+drag moves an icon (quickshell/Bar.qml); the bar has no keyboard focus to see ⌘, so this event tells it. It comes
-- first: the last binding's result decides whether the press goes on.
hl.bind(mod .. " + mouse:272", hl.dsp.event("nightdrive-cmd-press"), { non_consuming = true })
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })


-- Media keys (MacBook top row)
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 ; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ ; qs ipc call osd volume"), { locked = true, repeating = true })
-- At 0 % the speakers (Asahi's filter chain) still let sound through, so the step that reaches 0 also mutes.
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ; if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q 'Volume: 0.00'; then wpctl set-mute @DEFAULT_AUDIO_SINK@ 1; else wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; fi ; qs ipc call osd volume"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ; qs ipc call osd volume"),     { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(scripts .. "/brightness screen up"),   { locked = true, repeating = true })   -- F2: screen brightness in steps of ten
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(scripts .. "/brightness screen down"), { locked = true, repeating = true })   -- F1
hl.bind(mod .. " + XF86MonBrightnessUp",   hl.dsp.exec_cmd(scripts .. "/brightness kbd up"),   { locked = true, repeating = true })   -- ⌘F2: keyboard backlight (steps of ten)
hl.bind(mod .. " + XF86MonBrightnessDown", hl.dsp.exec_cmd(scripts .. "/brightness kbd down"), { locked = true, repeating = true })   -- ⌘F1
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("qs ipc call power toggle"))   -- power button (Touch ID key): power dialog (PowerDialog.qml) instead of an instant shutdown; logind must be set to ignore the key, see config/system/logind-power-key.conf
hl.bind("XF86Sleep", hl.dsp.exec_cmd(scripts .. "/dnd"), { locked = true })   -- F6 (Apple keyboard sends KEY_SLEEP): do not disturb (Quickshell notifications + toast); logind must be set to ignore the key, see config/system/logind-ignore-sleep-key.conf
-- The player that is playing, else the one that played last (hypr/scripts/media), not the first one playerctl lists
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(scripts .. "/media next"),     { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(scripts .. "/media pause"),    { locked = true })   -- always pause, never toggle: Bluetooth headphones send PAUSE when taken off
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(scripts .. "/media play"),     { locked = true })   -- F8: play/pause, or starts Deck (if installed) if no player is open
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(scripts .. "/media previous"), { locked = true })

-- Top bar menu opened by clicking: keys are routed to Quickshell via a submap (no keyboard focus -> a second click on the bar
-- closes the menu normally). Quickshell (shell.qml) enters the submap when the menu opens and resets it when it closes.
-- Safety: Esc always returns to the default map. All other bindings work in it too (NIGHTDRIVE_BINDS, above).
-- hyprland.lua calls this after local.lua and local.d, so their bindings are included.
local function qsnav(a) return hl.dsp.exec_cmd("qs ipc call menu navkey " .. a) end
local menuKeys = { ESCAPE = true, LEFT = true, RIGHT = true, UP = true, DOWN = true, RETURN = true }
function NIGHTDRIVE_DEFINE_MENU_SUBMAP()
    hl.define_submap("qsmenu", function ()
        NIGHTDRIVE_IN_SUBMAP = true
        hl.bind("ESCAPE", function ()
            hl.dispatch(hl.dsp.submap("reset"))
            hl.dispatch(qsnav("esc"))
        end)
        hl.bind("LEFT",   qsnav("left"),  { repeating = true })
        hl.bind("RIGHT",  qsnav("right"), { repeating = true })
        hl.bind("UP",     qsnav("up"),    { repeating = true })
        hl.bind("DOWN",   qsnav("down"),  { repeating = true })
        hl.bind("RETURN", qsnav("enter"))
        for _, b in ipairs(NIGHTDRIVE_BINDS) do
            if not menuKeys[b[1]] then hl.bind(b[1], b[2], b[3]) end
        end
        NIGHTDRIVE_IN_SUBMAP = false
    end)
end
