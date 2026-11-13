-- The look: gaps, borders, rounding, shadow and blur, the animations (the workspace slide, the swap, the drawer), the
-- layout and Hyprland's own misc settings. Required from hyprland.lua; the theme's colours follow from look.lua.

local HOME = os.getenv("HOME")

hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 10,
        border_size = 2,
        col = {
            -- Borders and shadow below: until the theme's look.lua (after this block) has been written
            active_border   = "rgba(7aa2f7ff)",       -- Omarchy's Tokyo Night: theme accent
            inactive_border = "rgba(595959aa)",       -- Omarchy default
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 4,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },
        blur = {
            enabled = true,
            size    = 3,
            passes  = 1,
        },
    },
    animations = {
        enabled = true,   -- only the workspace slide is on (below); everything else stays instant
    },
})
-- The look's borders and shadow (`nightdrive theme set`, hypr/scripts/theme writes the file and runs it over IPC)
pcall(dofile, HOME .. "/.cache/nightdrive/look.lua")
-- Workspace switch slides like macOS Spaces, so a swipe finishes (or snaps back) smoothly after the fingers lift
hl.curve("spaces", { type = "bezier", points = { {0.25, 1}, {0.5, 1} } })
hl.animation({ leaf = "global",           enabled = false })
hl.animation({ leaf = "workspaces",       enabled = true, speed = 3, bezier = "spaces", style = "slide" })
-- Swapping windows (⌘⇧ + arrows, 4-finger swipe, the drawer) slides them quickly to their new places: the move animation
-- is on only for the swap, so windows otherwise still switch instantly
function NIGHTDRIVE_SWAP(dir, window)
    hl.animation({ leaf = "windowsMove", enabled = true, speed = 2, bezier = "spaces" })
    hl.dispatch(hl.dsp.window.swap({ direction = dir, window = window }))
    hl.timer(function() hl.animation({ leaf = "windowsMove", enabled = false }) end, { timeout = 220, type = "oneshot" })
end
-- Drawer (⌘D, bindings.lua): slides up from the bottom over the windows, 95 % of the screen high, the rest dimmed
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "spaces", style = "slidevert" })
hl.config({ decoration = { dim_special = 0.6, blur = { special = true } } })   -- dimmed and blurred behind the drawer
local drawerTop = 49    -- 5 % of the screen height, so the drawer is 95 % high
local mon = hl.get_monitors()[1]
if mon then drawerTop = math.floor(mon.height / mon.scale * 0.05) end
hl.workspace_rule({ workspace = "special:drawer", gaps_out = { top = drawerTop, right = 10, bottom = 10, left = 10 } })   -- the same 10 px gaps as other windows

hl.config({
    dwindle = {
        preserve_split = true,
        force_split    = 2,   -- new windows always open to the right (or below), not on the cursor's side
    },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        background_color        = 0xff1a1b26,   -- background colour until swaybg draws the wallpaper (softens the flash after login)
        focus_on_activate       = true,   -- apps may request focus: e.g. opening a link → Firefox comes to the front (switches workspace)
        -- A lock that crashed (lock.qml) is taken over by a new one (hypr/scripts/lock) instead of leaving the "lock
        -- died" screen, whose way out is a text console. Turning it off wouldn't guard against anything: a program of
        -- the user's own could turn it on with hyprctl, and without one at the keyboard nobody runs anything.
        allow_session_lock_restore = true,
        -- Until a new lock has drawn on every screen, Hyprland draws the desktop under it for this long: the desktop
        -- showed for a second after sleep (hypr/scripts/relock). At 0 it is black instead, or the "lock died" screen.
        lockdead_screen_delay = 0,
    },
    -- Hyprland's own "updated to …" window after an update: Hyprland comes with `nightdrive update`, and the window
    -- (Hyprland's news, not in the desktop's look) is about Hyprland, not what changed in Nightdrive
    ecosystem = {
        no_update_news = true,
    },
    -- X11 apps (REAPER, Steam, Discord) draw at the screen's own resolution instead of 1× stretched by the scale,
    -- which made them blurry. They come out small unless they scale themselves (README › Make it yours).
    xwayland = {
        force_zero_scaling = true,
    },
})
