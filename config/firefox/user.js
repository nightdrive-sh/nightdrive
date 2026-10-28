// Allows the profile's chrome/userChrome.css (needed to move the tabs below the address bar)
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
// Spell checking off (in every text field)
user_pref("layout.spellcheckDefault", 0);
// Dark UI (Nightdrive's colours)
user_pref("browser.theme.toolbar-theme", 0);
user_pref("browser.theme.content-theme", 0);
// Scroll speed (default 100). The touchpad speed is set in hypr/scroll.lua with every other app's. Needs a Firefox restart.
user_pref("mousewheel.default.delta_multiplier_y", 100);   // the default, set explicitly so an older value in prefs.js is reset
// Touchpad momentum like macOS: a fling glides a little longer (friction, default 0.002), and quick repeated flings
// in the same direction speed up (multipliers, default 1.0)
user_pref("apz.fling_friction", "0.0015");
user_pref("apz.fling_accel_base_mult", "1.3");
user_pref("apz.fling_accel_supplemental_mult", "1.2");
// Browser Toolbox off, with the debugger's connection prompt: Firefox's defaults, set explicitly so the values earlier
// versions set (which prefs.js keeps) are reset. A developer turns it on in config/firefox/user.local.js.
user_pref("devtools.chrome.enabled", false);
user_pref("devtools.debugger.remote-enabled", false);
user_pref("devtools.debugger.prompt-connection", true);
// Default background of a blank page (about:blank) in dark mode: Nightdrive's violet (default #1c1b22)
user_pref("browser.display.background_color.dark", "#1f2033");
