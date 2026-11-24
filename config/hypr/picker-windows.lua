-- Files' Open and Save window (plugins/files, README.md › Open and Save: app/picker.qml, app id nightdrive-picker)
-- floats over the window of the app that asked, as a dialog does, from its first frame. Placed afterwards over hyprctl
-- (lib/pickrun.py does that where this file isn't loaded), it showed as a tile first and the other windows jumped.
--
-- The app that asked is the window that had the keyboard before the picker: it asks as the user clicks Save in it. The
-- picker is as large as SIZE, no larger than that window less MARGIN on each side, never under MIN: the same as
-- pickrun.py's geometry(). With no such window it is centred on the screen.
--
-- While the picker is on (`files picker on` made its portal folder), the apps started here ask the portal for their
-- Open and Save window even where they wouldn't by themselves: GTK 4 (zenity: Nightdrive's own pickers, Ferry) with
-- GDK_DEBUG=portals, GTK 3 and Firefox with GTK_USE_PORTAL=1. picker-setup sets the same in the running Hyprland
-- (hyprctl eval), as hypr/scripts/region does LC_TIME; apps already running keep what they had.

local CLASS  = "nightdrive-picker"
local SIZE   = { w = 1000, h = 680 }
local MIN    = { w = 420, h = 360 }
local MARGIN = 40

local data = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
local on = io.open(data .. "/nightdrive/portals/nightdrive.portal")
if on then
    on:close()
    local debug = os.getenv("GDK_DEBUG") or ""
    if not debug:find("portals", 1, true) then hl.env("GDK_DEBUG", debug == "" and "portals" or debug .. ",portals") end
    hl.env("GTK_USE_PORTAL", "1")
end

-- The picker keeps the keyboard while it is open, as a dialog does. With follow_mouse, a drag that selects the name and
-- ends past the picker's edge gave the keyboard to the window under the pointer on the next move after the release, and
-- the selection was gone (#3534); a click elsewhere took it too, though the app behind waits for the answer. Layers (the
-- launcher, the bar's menus) still get the keyboard.
hl.window_rule({
    name  = "picker-stays-focused",
    match = { class = "^" .. CLASS .. "$" },
    stay_focused = true,
})

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- The window that had the keyboard before w: the lowest focus history id but w's own
local function before(w)
    local prev
    for _, o in ipairs(hl.get_windows() or {}) do
        if o.address ~= w.address and o.mapped and o.focus_history_id and o.workspace and w.workspace
            and o.workspace.id == w.workspace.id
            and (not prev or o.focus_history_id < prev.focus_history_id) then prev = o end
    end
    return prev
end

hl.on("window.open", function (w)
    if not (w and w.class == CLASS) then return end
    local win = "address:" .. w.address
    if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "enable", window = win })) end
    local app = before(w)
    if not (app and app.at and app.size) then
        local m = w.monitor
        if m then
            hl.dispatch(hl.dsp.window.resize({ x = math.min(SIZE.w, math.floor(m.width / m.scale)),
                                               y = math.min(SIZE.h, math.floor(m.height / m.scale)), exact = true, window = win }))
        end
        hl.dispatch(hl.dsp.window.center({ window = win }))
        return
    end
    local pw = clamp(app.size.x - 2 * MARGIN, MIN.w, SIZE.w)
    local ph = clamp(app.size.y - 2 * MARGIN, MIN.h, SIZE.h)
    hl.dispatch(hl.dsp.window.resize({ x = pw, y = ph, exact = true, window = win }))
    hl.dispatch(hl.dsp.window.move({ x = app.at.x + math.floor((app.size.x - pw) / 2),
                                     y = app.at.y + math.floor((app.size.y - ph) / 2), exact = true, window = win }))
end)
