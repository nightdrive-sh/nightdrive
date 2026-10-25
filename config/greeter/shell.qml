import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

// Login screen (greetd + Quickshell, runs in its own Hyprland session, see hyprland-greeter.lua).
// Password only; user here, the look in LoginView.qml (shared with the lock at startup, lock.qml).
// One user, the one who installed Nightdrive: another logs in at the text login (switch.sh text) or on Ctrl+Alt+F3.
// Preview in the current session: `qs -p ~/.config/greeter` (Esc closes, no login is performed).
ShellRoot {
    id: root

    // --- Settings ---
    readonly property string user: "@USER@"   // install.sh fills in the user who installs it
    readonly property var sessionCommand: ["start-hyprland"]

    property string pending: ""     // typed password, waiting for PAM's prompt
    property bool busy: false
    property string message: ""

    function submit(pw) {
        if (busy || pw === "") return
        busy = true; root.message = ""; pending = pw
        if (!Greetd.available) { demo.start(); return }
        Greetd.createSession(user)
    }
    function reset(msg) { busy = false; pending = ""; root.message = msg; Greetd.cancelSession() }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) { Greetd.respond(root.pending); root.pending = "" }
        }
        function onAuthFailure(message) { root.reset("Wrong password") }
        function onReadyToLaunch() { Greetd.launch(root.sessionCommand, [], true) }
        function onError(error) { root.reset(error) }
    }
    // Preview without greetd: shows an error
    Timer { id: demo; interval: 600; onTriggered: { root.busy = false; root.pending = ""; root.message = "Preview mode: no login" } }

    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#1a1b26"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        LoginView {
            id: login
            anchors.fill: parent
            busy: root.busy
            message: root.message
            onTyping: root.message = ""
            onSubmitted: password => root.submit(password)
            onEscapePressed: if (!Greetd.available) Qt.quit()
        }
    }
}
