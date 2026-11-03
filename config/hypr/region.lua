-- Settings › Region (hypr/scripts/region): LC_TIME from ~/.config/locale.conf for every program started here, so dates
-- and times are the region's while the language stays. Fedora's login reads only /etc/locale.conf and ~/.i18n; the
-- script also sets it in the running Hyprland (hyprctl eval), so a change needs no new login
local f = io.open((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/locale.conf")
if f then
    for line in f:lines() do
        local v = line:match("^%s*LC_TIME=[\"']?([%w_.@-]+)")
        if v then hl.env("LC_TIME", v) end
    end
    f:close()
end
