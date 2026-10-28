-- Hyprland session for the login screen (greetd runs this as user "greetd"). Not used in the normal session.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2.0 })
-- In a Garage VM the login screen follows its window's size too, as the session does (hypr/vm-display.lua): without
-- it a window resized while the VM boots stretches the login screen's first size. Installed beside this file
dofile("/etc/greetd/vm-display.lua")({}, {})

hl.config({
    input = { kb_layout = "fi", kb_variant = "mac" },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        background_color = 0xff1a1b26,
    },
    animations = { enabled = false },
})

hl.on("hyprland.start", function ()
    -- Its watcher, which quits at once outside a VM. Run with bash: /etc/greetd's files aren't executed (greeter.sh)
    hl.exec_cmd("bash /etc/greetd/vm-display watch")
    -- The marker tells greeter.sh that Hyprland started (no text login in its place once it exits)
    -- Quickshell login screen; once login is done (or the screen closes), this Hyprland exits
    hl.exec_cmd("touch \"$XDG_RUNTIME_DIR/nightdrive-greeter-up\"; qs -p /etc/greetd/greeter; hyprctl dispatch 'hl.dsp.exit()'")
end)
