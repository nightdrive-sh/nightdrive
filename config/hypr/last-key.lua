-- When the last key was pressed, and so whether the user is typing: one rule for Claude's window tools (Dashboard
-- #1832, #1986), which don't move the focus while you type, so a password you are typing doesn't land in the window
-- Claude brings forward, and for Claude's confirmation card (#1987), which takes the keyboard only once you pause.
-- Only the time is kept, never which key. `hyprctl repl 'return NightdriveTyping()'` answers true or false
-- (hypr/scripts/windows: not_typing, quickshell/Typing.qml); NightdriveKeyAge() gives the whole seconds since.
-- os.time is whole seconds, which is enough for a wait of a couple of them, and costs a key nothing but setting a number.

local QUIET = 1   -- whole seconds: a key 1.9 s ago still counts as 1, so typing ends after a pause of 1–2 s

local last = 0

hl.on("input.keyboard.key", function () last = os.time() end)

function NightdriveKeyAge()
    return os.time() - last
end

function NightdriveTyping()
    return os.time() - last <= QUIET
end
