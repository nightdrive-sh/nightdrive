-- Ferry's window (plugins/README.md › Hyprland settings): floating at its own size in the middle, as the Mac's popover.
-- On Hyprland Ferry lets it be resized, so ⌘⇧T (the core's bindings.lua) moves it into the tiling layout and back.
hl.window_rule({
    name  = "float-ferry",
    match = { class = "^sh\\.nightdrive\\.Ferry$" },
    float = true,
    size  = "400 620",                    -- Ferry's own (linux/app/ferry_app.py)
    center = true,
})
