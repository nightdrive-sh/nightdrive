-- When the last key was pressed, for Claude's window tools (Dashboard #1832): they don't move the focus while you
-- type, so a password you are typing doesn't land in the window Claude brings forward. Only the time is kept, never
-- which key. `hyprctl repl 'return NightdriveKeyAge()'` gives the whole seconds since (hypr/scripts/windows:
-- not_typing). os.time is whole seconds, which is enough for a wait of a couple of them, and costs a key nothing but
-- setting a number.

local last = 0

hl.on("input.keyboard.key", function () last = os.time() end)

function NightdriveKeyAge()
    return os.time() - last
end
