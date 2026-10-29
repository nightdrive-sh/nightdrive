import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The apps open now, by window class, with their names: what a list choice (the apps whose windows Claude sees without
// asking, Dashboard #1832) offers to add. Not Quickshell's own windows (this one, the launcher), nor the apps Send to
// Claude always leaves out (password managers: `claude-write always`), as Claude never sees those anyway.
QtObject {
    id: apps
    property var always: null           // the regex of the classes always left out, once read
    readonly property var classes: {
        const seen = {}
        return ToplevelManager.toplevels.values.map(t => t.appId || "")
            .filter(c => c && c !== "org.quickshell" && always !== null && !always.test(c)   // none until it's read
                       && !seen[c.toLowerCase()] && (seen[c.toLowerCase()] = true))
    }

    // An app's name for its window class, as the launcher finds it (ClaudeWriteLevels.appOf)
    function name(cls) {
        const c = cls.toLowerCase()
        const all = DesktopEntries.applications.values
        const e = all.find(d => (d.startupClass || "").toLowerCase() === c)
               || all.find(d => d.id.replace(/\.desktop$/, "").toLowerCase() === c)
               || DesktopEntries.heuristicLookup(cls)
        return e ? e.name : cls
    }

    property Process reader: Process {
        command: [Quickshell.shellDir + "/../hypr/scripts/claude-write", "always"]
        stdout: StdioCollector {
            onStreamFinished: { try { apps.always = new RegExp(text.trim(), "i") } catch (e) { apps.always = null } }
        }
    }
    Component.onCompleted: reader.running = true
}
