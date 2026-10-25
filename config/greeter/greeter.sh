# The login screen's session: greetd runs it as user "greetd" (config.toml, installed as /etc/greetd/greeter.sh) and
# starts the user's session once it ends. Run with sh: /etc/greetd's files are labelled as config for SELinux, read but
# not executed.
# If Hyprland doesn't start (no driver for the graphics card, say), a text login comes up on the same screen instead:
# without it greetd would end ("greeter exited without creating a session"), systemd would restart it five times and
# then give up, leaving a black screen.
MARKER=$XDG_RUNTIME_DIR/nightdrive-greeter-up   # left by hyprland-greeter.lua once Hyprland is up

rm -f "$MARKER"
# Hyprland's output off the text console: its ASCII logo and first log lines showed on tty1 between the boot splash and
# the login screen (the log is in $XDG_RUNTIME_DIR/hypr all the same)
start-hyprland -- -c /etc/greetd/hyprland-greeter.lua >/dev/null 2>&1
# Only the marker tells: start-hyprland exits with 0 after Hyprland crashed at start too
[ -e "$MARKER" ] && exit 0

# Cleared, with the cursor the boot splash's greetd drop-in hid (config/splash/greetd-plymouth.conf)
printf '\033[2J\033[H\033[?25h'
printf '%s\n' "Nightdrive's login screen didn't start: Hyprland couldn't start." "" \
  "Log in here: start-hyprland starts the desktop, or shows why it can't. Logging out (exit) tries the login screen again." \
  "@SWITCH@ text makes this text login the login screen; it starts the desktop after the password." ""
# The user's own shell: greetd runs the command with sh -c after setting SHELL, so it isn't expanded here
exec agreety --cmd '$SHELL'
