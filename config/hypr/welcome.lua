-------------------------------
---- WELCOME TO NIGHTDRIVE ----
-------------------------------
-- The Welcome window (config/welcome) floats as a card in the middle, and what it starts in a terminal floats over it.
-- Hyprland draws floating windows over tiled ones, so everything else Welcome opens (the browser for Claude's sign-in
-- or an Open: button, a README in Apostrophe, an editor) would open tiled behind it. While Welcome is on the workspace,
-- a tiled window that comes to the front floats over it instead, and is tiled again once Welcome closes.
local WELCOME_TITLE = "Welcome to Nightdrive"
local LIFT_SIZE     = 0.85     -- of the screen: bigger than Welcome (960×600), so it covers it
local SETTLE_MS     = 150      -- after a window closes, before checking whether Welcome is still open

hl.window_rule({
    name  = "float-welcome",
    match = { class = "^org\\.quickshell$", title = "^" .. WELCOME_TITLE .. "$" },
    float = true,
    size  = "960 600",
    center = true,
})
-- What Welcome starts in a terminal (a step's command, a Claude session: scripts/claude-setup): floating over it, in
-- front, rather than tiled behind it
hl.window_rule({
    name  = "float-welcome-terminal",
    match = { class = "^(sh\\.nightdrive\\.)?nightdrive-(setup-.*|welcome)$" },
    float = true,
    size  = "900 560",
    center = true,
})

local function is_welcome(w)
    return w.class == "org.quickshell" and w.title == WELCOME_TITLE
end
local function is_own(w)
    return is_welcome(w) or (w.class or ""):find("nightdrive%-setup%-") ~= nil or (w.class or ""):find("nightdrive%-welcome$") ~= nil
end
local function welcome_on(ws)
    for _, w in ipairs(hl.get_workspace_windows(ws.id) or {}) do
        if is_welcome(w) then return true end
    end
    return false
end

-- Addresses of the windows floated over Welcome (lost if Hyprland reloads its config: they then stay floating)
local lifted = {}

local function lift(w)
    if not (w and w.workspace and w.monitor) or w.floating or is_own(w) or not welcome_on(w.workspace) then return end
    local m = w.monitor
    local win = "address:" .. w.address
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = win }))
    hl.dispatch(hl.dsp.window.resize({ x = math.floor(m.width / m.scale * LIFT_SIZE),
                                       y = math.floor(m.height / m.scale * LIFT_SIZE), exact = true, window = win }))
    hl.dispatch(hl.dsp.window.center({ window = win }))
    hl.dispatch(hl.dsp.focus({ window = win }))
    lifted[w.address] = true
end

-- Welcome gone (closed, or quit): the lifted windows that are still open go back to the tiling
local function settle()
    for _, w in ipairs(hl.get_windows() or {}) do
        if is_welcome(w) then return end
    end
    for _, w in ipairs(hl.get_windows() or {}) do
        if lifted[w.address] and w.floating then
            hl.dispatch(hl.dsp.window.float({ action = "disable", window = "address:" .. w.address }))
        end
    end
    lifted = {}
end

hl.on("window.active", function () lift(hl.get_active_window()) end)
hl.on("window.close", function ()
    if next(lifted) then hl.timer(settle, { timeout = SETTLE_MS, type = "oneshot" }) end
end)
