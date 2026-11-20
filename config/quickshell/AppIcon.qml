import QtQuick
import Quickshell

// An app's icon by its name (a .desktop file's Icon=), a path or a URL. Qt reads the icon themes once, when Quickshell
// starts, so an app installed after that (Tuba from Install › Software) wasn't found by name. Then the usual places are
// tried as files, one after another until one loads, but only the files that are there (IconFiles): a missing one would
// log "Cannot open" for every icon and cost a failed load.
Image {
    id: img
    property string name: ""
    property int attempt: 0
    readonly property string home: Quickshell.env("HOME")
    readonly property var candidates: {
        const n = name
        if (n === "") return []
        if (n.indexOf("://") > 0) return [n]
        if (n.startsWith("/")) return ["file://" + n]
        const out = []
        const add = path => { if (IconFiles.has(path) && out.indexOf("file://" + path) < 0) out.push("file://" + path) }
        // An icon of your own in ~/.local/share/icons/hicolor wins: Qt's lookup finds the system's first (link.sh puts
        // Steam's logo there over Fedora Asahi's locomotive).
        add(home + "/.local/share/icons/hicolor/scalable/apps/" + n + ".svg")
        const themed = Quickshell.iconPath(n, true)
        if (themed !== "") out.push(themed)
        for (const base of IconFiles.bases)
            for (const f of ["scalable/apps/" + n + ".svg", "256x256/apps/" + n + ".png", "128x128/apps/" + n + ".png",
                             "64x64/apps/" + n + ".png", "48x48/apps/" + n + ".png"])
                add(base + "/" + f)
        add("/usr/share/pixmaps/" + n + ".png")
        add("/usr/share/pixmaps/" + n + ".svg")
        return out
    }
    onCandidatesChanged: attempt = 0
    source: attempt < candidates.length ? candidates[attempt] : ""
    // A local file fails while source is still being set: stepping on right there is a binding loop, and after a few
    // misses in a row (a new app: no themed path, no SVG) Qt gives up before reaching the PNG. So step on afterwards.
    onStatusChanged: if (status === Image.Error) Qt.callLater(() => {
        if (status === Image.Error && attempt < candidates.length) attempt++
    })
    fillMode: Image.PreserveAspectFit
}
