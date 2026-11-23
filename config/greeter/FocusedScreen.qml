import QtQuick
import Quickshell
import Quickshell.Io

// The name of Hyprland's focused monitor, for the lock's prompt (lock.qml), read without Quickshell.Hyprland: that
// module's IPC client crashed the lock (SIGSEGV in HyprlandWorkspace::insertToplevel) once Hyprland 0.57 gave special
// workspaces no id and two of them held windows (special:bg, special:drawer), and a lock that dies leaves the session on
// Hyprland's "lockscreen app died" screen (#2899). The lock needs only this one name, so it asks hyprctl once and then
// follows the focusedmon events on Hyprland's event socket, which carry the monitor's name first in every version.
Scope {
    id: root

    property string name: ""

    Process {
        running: true
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const f = JSON.parse(text).find(m => m.focused)
                    if (f && root.name === "") root.name = f.name
                } catch (e) {}   // no Hyprland (a preview elsewhere): the lock falls back to its first screen
            }
        }
    }

    Socket {
        readonly property string sig: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
        path: sig ? `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${sig}/.socket2.sock` : ""
        connected: sig !== ""
        // focusedmon>>NAME,WORKSPACE (and focusedmonv2>>NAME,ID): the name up to the first comma
        parser: SplitParser {
            onRead: line => {
                const m = line.match(/^focusedmon(?:v2)?>>([^,]+),/)
                if (m) root.name = m[1]
            }
        }
    }
}
