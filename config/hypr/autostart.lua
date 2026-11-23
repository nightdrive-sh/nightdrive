-- What starts with the session, and the autologin start under the login screen (greeter/lock.qml). Required once
-- from hyprland.lua; returns the session's state for the rest of the config:
--   locked()   under the login screen at an autologin start (the screen's corners stay off then: corners.lua)
--   starts     the commands the plugins that are on start with the session (hyprland.lua's PLUGINS: p.start)
--   unlocked   run once the login apps have started (corners.lua sets it)

local HOME = os.getenv("HOME")
local session = { starts = {}, unlocked = function () end }

-- Autologin (config/greeter/switch.sh autologin) starts this session with NIGHTDRIVE_LOCKED_START=1: the login screen
-- (greeter/lock.qml) locks it first, and nothing else starts until the lock is secure. If the lock isn't up in
-- LOCK_TIMEOUT seconds, the session exits to greetd's login screen rather than stay open.
local LOCK_TIMEOUT = 20
local LOCKED_START = os.getenv("NIGHTDRIVE_LOCKED_START") == "1"
hl.env("NIGHTDRIVE_LOCKED_START", "")   -- not for apps started here (a nested Hyprland would lock itself too)
local RUNTIME = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
-- Flags rather than variables: they survive a config reload, and each step runs once even if the lock is started again
local LOCKED_FLAG   = RUNTIME .. "/nightdrive-session-started"
local UNLOCKED_FLAG = RUNTIME .. "/nightdrive-apps-started"

local function exists(path)
    local f = io.open(path)
    if f then f:close() end
    return f ~= nil
end
-- Under the login screen at an autologin start: before the password (the login apps start with it)
function session.locked()
    return (LOCKED_START or exists(LOCKED_FLAG)) and not exists(UNLOCKED_FLAG)
end

local function once(flag)
    local f = io.open(flag)
    if f then f:close(); return false end
    f = io.open(flag, "w")
    if f then f:close() end
    return true
end

-- Before the lock is secure at an autologin start, no key does anything: the session is open under no lock for that
-- moment (up to LOCK_TIMEOUT), and a key could start a terminal. Keys typed then go to no window, as there is none yet.
-- (catchall: every key, and a submap with no binding in it isn't registered)
hl.define_submap("boot", function () hl.bind("catchall", function () end) end)

-- The session: everything but the login apps. Runs under the lock at an autologin start (lock.qml calls it once secure).
function NightdriveLocked()
    if not once(LOCKED_FLAG) then return end
    hl.dispatch(hl.dsp.submap("reset"))   -- the keys again ("boot" above), the lock's own (volume, brightness) among them
    -- The keyring daemon that greetd's PAM started gets its secrets and pkcs11 parts (a desktop's login does this): without
    -- them the lock's PAM can't open the login keyring with the password, and an app asking for a secret started a
    -- second daemon that asked for the password again
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets,pkcs11")
    -- graphical-session.target for xdg-desktop-portal (config/systemd/user); restart: fresh environment after a re-login
    hl.exec_cmd("systemctl --user restart nightdrive-session.target")
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/lid watch")   -- the lid with an external display (display.lua)
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/vm-display watch")   -- in a VM, its screen follows its window (display.lua)
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/vm-clipboard watch")   -- in a Garage VM, the host's clipboard sent to it
    -- Theme colours (~/.cache/nightdrive, hypr/scripts/theme) first: Quickshell (the top bar, its menus and the notifications)
    -- reads them on startup. hypr/scripts/desktop-shell runs qs and starts it again after a crash.
    hl.exec_cmd("sh -c '\"$HOME/.config/hypr/scripts/theme\" apply; exec \"$HOME/.config/hypr/scripts/desktop-shell\" run'")
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/wallpaper restore")   -- swaybg with the remembered wallpaper (change: launcher › Settings › Background)
    hl.exec_cmd("env PATH=" .. HOME .. "/.local/bin:" .. os.getenv("PATH") .. " " .. HOME .. "/.config/hypr/scripts/dictate daemon")   -- speech to text (F5), Parakeet
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/idle start")   -- hypridle with the screensaver and screen-off times (launcher › Settings › Screensaver)
    -- Headphone EQ in the background (presets: config/easyeffects, picked from the headphone icon in the top bar). Only with
    -- PipeWire's socket (socket-activated, there before the session): without it EasyEffects aborts with a core dump, as in
    -- the sandbox, which has no audio. ee-follow starts it and starts it again when it stays on an old output (#2038).
    hl.exec_cmd("sh -c '[ -S \"$XDG_RUNTIME_DIR/pipewire-0\" ] && exec \"$HOME/.config/hypr/scripts/ee-follow\"'")
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/bt-audio-follow")   -- Bluetooth headphones become the output when they connect
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/jack-volume")   -- headphones or speakers in the jack: a volume for each, starts quiet
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/airplay-volume")   -- AirPlay speakers start at most at 30 %: their volume is the speaker's own
    hl.exec_cmd("playerctld daemon")   -- remembers which player played last, for the media keys (hypr/scripts/media)
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/headphones-ctl")   -- Sony / AirPods: listening mode in the headphones menu, AirPods ear detection
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/remote-login watch")   -- Remote login on: a network joined for the first time asks whether to allow it
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/net-watch")   -- "No internet" and "Back online" from NetworkManager's connectivity check
    -- reset-failed: the previous session's agent crash-loops after logout (Restart=on-failure) and hits the start limit
    hl.exec_cmd("sh -c 'systemctl --user reset-failed hyprpolkitagent; systemctl --user restart hyprpolkitagent'")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/bt-notify")   -- Connected / Disconnected with a Disconnect button, in place of Blueman's
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    for _, cmd in ipairs(session.starts) do hl.exec_cmd(cmd) end
end

-- The login apps: after the password at an autologin start, as they may ask the keyring (the lock's PAM opens it)
-- The lock calls it at every unlock (lock.qml, and hyprlock's in scripts/lock): the ones after the first are for schedule
-- and remind, whose commands and reminders that came due under the lock, or wait for the first unlock after waking,
-- come then, and for places
function NightdriveUnlocked()
    if not once(UNLOCKED_FLAG) then
        hl.exec_cmd(HOME .. "/.config/hypr/scripts/schedule unlocked")
        hl.exec_cmd(HOME .. "/.config/hypr/scripts/remind unlocked")   -- reminders that came under the lock, and wake's
        hl.exec_cmd(HOME .. "/.config/hypr/scripts/places check")   -- arrived or left while locked (net-watch tells the rest)
        return
    end
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/autostart")   -- the user's login apps (launcher › Settings › Apps › Startup; 1Password by default)
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/reopen session offer")   -- the battery ran out: open its windows again?
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/remind restore")   -- quick reminders: their timers again, the missed ones told
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/schedule restore")   -- scheduled commands: timers again, login's and missed ones run or asked
    -- Arriving at or leaving a place: --wake, as a login is like waking (it may have been shut down elsewhere)
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/places check --wake")
    hl.exec_cmd(HOME .. "/.config/welcome/welcome login")   -- a new install's first login: Welcome to Nightdrive (later ones: a reminder)
    session.unlocked()
end

hl.on("hyprland.start", function ()
    -- The flags are from an earlier session of this login (the runtime dir lives as long as the user has a session)
    os.remove(LOCKED_FLAG); os.remove(UNLOCKED_FLAG)
    if not LOCKED_START then
        NightdriveLocked(); NightdriveUnlocked()
        return
    end
    hl.dispatch(hl.dsp.submap("boot"))
    -- Through the lock script, which starts the lock again if it dies (a screen going away as it starts)
    hl.exec_cmd(HOME .. "/.config/hypr/scripts/lock --boot")
    hl.exec_cmd("sh -c 'sleep " .. LOCK_TIMEOUT .. "; [ -e \"" .. LOCKED_FLAG .. "\" ] || hyprctl dispatch \"hl.dsp.exit()\"'")
end)

return session
