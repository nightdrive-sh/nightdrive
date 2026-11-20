pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The app icon files that exist in the folders AppIcon tries, listed once with one find and kept as a set. AppIcon hands
// Image only paths from it: a path that isn't there makes Qt log "Cannot open" (a WARN that `sandbox check` counts as a
// QML error) and costs a failed load before the next candidate. Listed again, like Plugins, when an app's .desktop file
// comes or goes: an install adds its icons together with it. No polling.
Singleton {
    id: icf
    readonly property string home: Quickshell.env("HOME")
    // The hicolor folders AppIcon looks in, and the sizes it asks for there (the rest of a theme isn't needed)
    readonly property var bases: ["/usr/share/icons/hicolor", home + "/.local/share/flatpak/exports/share/icons/hicolor",
                                  "/var/lib/flatpak/exports/share/icons/hicolor", home + "/.local/share/icons/hicolor"]
    readonly property var sizes: ["scalable", "256x256", "128x128", "64x64", "48x48"]
    property var files: ({})                 // "/abs/path" → true; replaced as a whole so that bindings on it update
    property bool loaded: false
    function has(path) { return files[path] === true }

    property bool again: false               // a listing asked for while one runs: another one after it
    function scan() { if (proc.running) again = true; else proc.running = true }

    Process {
        id: proc
        // Missing folders (no Flatpak) are fine: find's complaints go to /dev/null and its exit code is ignored
        command: {
            const dirs = []
            for (const b of icf.bases) for (const s of icf.sizes) dirs.push(b + "/" + s + "/apps")
            return ["sh", "-c", 'find "$@" /usr/share/pixmaps -maxdepth 1 2>/dev/null; true', "sh"].concat(dirs)
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const set = {}
                for (const l of text.split("\n")) if (l !== "") set[l] = true
                icf.files = set
                icf.loaded = true
            }
        }
        onExited: if (icf.again) { icf.again = false; running = true }
    }
    // Apps added or removed: one listing after the burst (the first scan at start changes the list many times)
    Connections { target: DesktopEntries.applications; function onValuesChanged() { settle.restart() } }
    Timer { id: settle; interval: 2000; onTriggered: icf.scan() }
    Component.onCompleted: scan()
}
