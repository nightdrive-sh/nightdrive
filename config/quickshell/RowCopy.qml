import QtQuick

// ⌘C (Hyprland sends Ctrl+Insert) or Enter on a launcher row with a `copy` value (Wi-Fi's addresses, Tailscale's
// machines, the calculator's result): copies it, and the row says "copied" for a moment. A file of its own because the
// launcher and several Levels files share it (launcher.rowCopy); it was part of SystemLevels.qml before #1937.
// sensitive (a password, the row's `sensitive`): not in the clipboard history (cliphist), and cleared after 45 s.
// ClipCopy gives it to wl-copy on stdin: a command line is readable by every user in /proc (#1947)
Item {
    id: c
    property var launcher: null
    property string copied: ""       // the value copied last, for 1.5 s

    function sel() { if (launcher) launcher.keepSelection() }   // the rows rebuild when `copied` changes: keep the selected one
    function copyText(v, sensitive) { sel(); clip.copy(v, sensitive); copied = v; copiedTimer.restart() }
    Timer { id: copiedTimer; interval: 1500; onTriggered: { c.sel(); c.copied = "" } }
    ClipCopy { id: clip }
}
