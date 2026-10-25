import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pam

// The lock at startup, and later the session's lock too (hypr/scripts/lock: idle, sleep, ⌃⌘L). With greetd's autologin
// (switch.sh autologin) Hyprland starts straight into the desktop session, and this login screen covers it as an
// ext-session-lock, so the screen changes hands only once at boot (Plymouth → Hyprland). hyprland.lua starts it first;
// once the lock is secure it starts the session (NightdriveLocked), and the login apps after the password
// (NightdriveUnlocked: they may ask the keyring, which the password opens). Both run once per login.
// If this process dies while locked, Hyprland keeps the session locked (the "lockdead" screen).
// Preview without locking: `nightdrive preview login` (checks the password, Esc closes).
ShellRoot {
    id: root

    readonly property bool preview: Quickshell.env("NIGHTDRIVE_LOCK_PREVIEW") === "1"
    // /etc/pam.d/nightdrive-lock (switch.sh autologin) also opens the keyring; hyprland.lua passes it when it exists, as
    // a missing service would fall back to PAM's "other", which refuses every password
    // A lock later in the session (hypr/scripts/lock): straight to the prompt, the intro is for the boot
    readonly property bool quick: Quickshell.env("NIGHTDRIVE_LOCK_QUICK") === "1"
    readonly property string pamService: Quickshell.env("NIGHTDRIVE_LOCK_PAM") || "login"
    // A screensaver never sees the input that would close it while locked, so the lock ends it: once up, and at the
    // unlock for one that started in between (screensaver/start also won't start under the lock)
    readonly property string saverStop: Quickshell.env("HOME") + "/.config/screensaver/stop"

    // The screen with the prompt: the focused monitor, where the keyboard goes; the first screen before Hyprland's state has
    // arrived or if it names none of them, so there's always one. By name: monitorFor() gave another object than
    // focusedMonitor, and no screen had the prompt.
    readonly property string promptScreen: {
        const f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        if (Quickshell.screens.some(s => s.name === f)) return f
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }
    property string pending: ""     // typed password, waiting for PAM's prompt
    property bool busy: false
    property string message: ""

    function submit(pw) {
        if (busy) return
        busy = true; message = ""; pending = pw
        if (!pam.start()) fail("Can't check the password")
    }
    function fail(msg) { busy = false; pending = ""; message = msg }
    function unlock() {
        if (preview) { root.endPreview(); return }
        lock.locked = false
        Quickshell.execDetached([root.saverStop])
        Quickshell.execDetached(["hyprctl", "eval", "NightdriveCornersHidden(false)"])
        Quickshell.execDetached(["hyprctl", "eval", "NightdriveUnlocked()"])
        quit.start()
    }

    PamContext {
        id: pam
        config: root.pamService
        onPamMessage: if (responseRequired) { respond(root.pending); root.pending = "" }
        onCompleted: result => {
            if (result === PamResult.Success) root.unlock()
            else root.fail(result === PamResult.MaxTries ? "Too many tries" : "Wrong password")
        }
        onError: error => root.fail("Can't check the password")
    }

    // Exits once the compositor has had the unlock
    Timer { id: quit; interval: 1000; onTriggered: Qt.quit() }

    WlSessionLock {
        id: lock
        locked: !root.preview
        // NightdriveLocked starts the session once, at boot; a later lock only hides the corners
        onSecureChanged: if (secure) {
            Quickshell.execDetached([root.saverStop])
            Quickshell.execDetached(["hyprctl", "eval", "NightdriveCornersHidden(true)"])
            Quickshell.execDetached(["hyprctl", "eval", "NightdriveLocked()"])
        }

        WlSessionLockSurface {
            id: surface
            color: "#1a1b26"
            LoginView {
                anchors.fill: parent
                main: surface.screen !== null && surface.screen.name === root.promptScreen
                intro: !root.quick
                busy: root.busy
                message: root.message
                onTyping: root.message = ""
                onSubmitted: password => root.submit(password)
            }
        }
    }

    // Preview: the same view in a window of its own, nothing locked; the screen's rounded corners go while it shows, as
    // under the real lock (hyprland.lua)
    function endPreview() {
        Quickshell.execDetached(["hyprctl", "eval", "NightdriveCornersHidden(false)"])
        Qt.quit()
    }
    Component.onCompleted: if (preview) Quickshell.execDetached(["hyprctl", "eval", "NightdriveCornersHidden(true)"])
    LazyLoader {
        active: root.preview
        PanelWindow {
            anchors { top: true; bottom: true; left: true; right: true }
            color: "#1a1b26"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            LoginView {
                anchors.fill: parent
                busy: root.busy
                message: root.message
                onTyping: root.message = ""
                onSubmitted: password => root.submit(password)
                onEscapePressed: root.endPreview()
            }
        }
    }
}
