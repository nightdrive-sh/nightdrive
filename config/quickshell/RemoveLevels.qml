import QtQuick
import Quickshell

// The launcher's System › Remove: Software (the packages you installed with dnf, and your Flatpak apps) and Webapps.
// A search on Remove itself looks in both, and the tag tells which a row is. Enter on a package opens its details
// (DetailCard.qml; src and remove: Enter there removes it in a terminal); a webapp asks twice, as its logins go with it.
// Ctrl+Enter on either removes at once (yesCmd: the same command without its question), for when you're sure.
// Launcher.qml asks it like DefaultAppsLevels (levels, titles, parents, items, activate, footer, entered, ctrlActivate).
Item {
    id: r
    property var launcher: null

    property var removeList: []               // Software: user-installed packages and Flatpak apps
    property bool removeLoaded: false
    property var webappList: []               // Webapps: the web apps (webapp-remove --list)

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    readonly property var levels: ["remove", "removesw", "removeweb"]
    readonly property var titles: ({ remove: "System › Remove", removesw: "Remove › Software", removeweb: "Remove › Webapps" })
    readonly property var parents: ({ remove: "system", removesw: "remove", removeweb: "remove" })

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (!cur.yesCmd) return ""
        return (cur.confirm ? "Enter: remove (asks again)" : "Enter: details") + "  ·  Ctrl+Enter: remove without asking"
    }
    function opened() {}
    function entered(level) { removeProc.running = true; webappProc.running = true }
    function shiftActivate(it) {}
    // The rows are the launcher's: a package's details, or a confirmed action
    function activate(it) { return false }
    function ctrlActivate(it) {
        if (!it.yesCmd) return false
        launcher.open = false
        Quickshell.execDetached(it.yesCmd)
        return true
    }

    function items(level, q) {
        if (level === "remove") {
            // Two kinds, Software and Webapps; a search looks in both, and the tag tells which a row is
            if (q === "") return [{ kind: "nav", name: "Software", glyph: "package-minus", target: "removesw", summary: "dnf + Flatpak" },
                                  { kind: "nav", name: "Webapps", glyph: "app-window", target: "removeweb",
                                    summary: webappList.length ? String(webappList.length) : undefined }]
            return { all: removeList.map(p => ({ item: Object.assign({}, p, { from: "Software" }), text: p.name, extra: p.summary }))
                .concat(webappList.map(w => ({ item: Object.assign({}, w, { from: "Webapp" }), text: w.name, extra: w.summary + " webapp" }))) }
        }
        if (level === "removesw") {
            if (!removeLoaded) return [{ kind: "hint", name: "Loading packages…" }]
            // The apps first, then the other packages (libraries, tools without a window); a search looks in both
            const appRows = removeList.filter(p => p.app), other = removeList.filter(p => !p.app)
            if (q === "") return [{ kind: "header", name: "Apps" }].concat(appRows, [{ kind: "header", name: "Other packages" }], other)
            return { all: appRows.concat(other).map(p => ({ item: p, text: p.name, extra: p.summary })) }
        }
        if (level === "removeweb") {
            if (webappList.length === 0) return [{ kind: "hint", name: "No webapps (add one in System › Install › Webapp)" }]
            return { all: webappList.map(w => ({ item: w, text: w.name, extra: w.summary })) }
        }
        return []
    }

    // dnf repoquery output ("name|summary" per line) → [{ name, summary }]
    function parsePackages(text) {
        const out = []
        for (const line of text.split("\n")) {
            const i = line.indexOf("|")
            if (i >= 0) out.push({ name: line.slice(0, i), summary: line.slice(i + 1) })
        }
        return out
    }
    // Software: packages the user installed, then the user's Flatpak apps (after a "--flatpak--" line, tab-separated)
    Sh {
        id: removeProc
        // After the Flatpak apps, each package's app (its .desktop file, not a hidden one): package, icon, name
        script: 'dnf repoquery --userinstalled -q --queryformat "%{name}|%{summary}\\n" 2>/dev/null | sort -u; echo --flatpak--; flatpak list --app --user --columns=application,name,description 2>/dev/null; '
              + 'echo --apps--; f=$(grep -L "^NoDisplay=true" /usr/share/applications/*.desktop); '
              + 'paste <(rpm -qf --qf "%{NAME}\\n" $f) <(for d in $f; do printf "%s\\t%s\\n" "$(sed -n "s/^Icon=//p" "$d" | head -1)" "$(sed -n "s/^Name=//p" "$d" | head -1)"; done)'
        onResult: text => {
            const term = r.launcher.term
            const [dnf, rest] = text.split("--flatpak--\n")
            const [fp, desk] = (rest || "").split("--apps--\n")
            const apps = (fp || "").split("\n").map(l => l.split("\t")).filter(f => f[1])
            // package → its app: { icon, name }. Of a package's several, the one with the package's own icon (blueman:
            // Bluetooth Manager, not Bluetooth Adapters), else the first
            const appOf = {}
            for (const [pkg, icon, name] of (desk || "").split("\n").map(l => l.split("\t")))
                if (pkg && name && !/ is not owned/.test(pkg) && (!appOf[pkg] || (icon === pkg && appOf[pkg].icon !== pkg))) appOf[pkg] = { icon: icon, name: name }
            // A package with an app shows as the app (its name and icon, the package's name after the summary)
            r.removeList = r.parsePackages(dnf).map(p => {
                const a = appOf[p.name]
                return { kind: "action", name: a ? a.name : p.name, summary: a && a.name.toLowerCase() !== p.name ? p.summary + "  ·  " + p.name : p.summary,
                         iconFile: a && a.icon ? a.icon : undefined, glyph: a && a.icon ? undefined : "package-minus", app: !!a,
                         src: "dnf", id: p.name, remove: true, cmd: term('sudo dnf remove "$1"', p.name),
                         yesCmd: term('sudo dnf remove -y "$1"', p.name) }
            }).concat(apps.map(([id, name, desc]) => ({ kind: "action", name: name, summary: (desc || "") + "  ·  Flatpak", iconFile: id, app: true,
                                                        src: "flatpak", id: id, remove: true, cmd: term('flatpak uninstall --user "$1"', id),
                                                        yesCmd: term('flatpak uninstall --user -y "$1"', id) })))
                .sort((a, b) => a.name.localeCompare(b.name))
            r.removeLoaded = true
        }
    }
    // Webapps: removing one takes its logins too (its Chromium profile), so Enter asks twice; Ctrl+Enter doesn't (yesCmd)
    Sh {
        id: webappProc
        command: [r.scripts + "/webapp-remove", "--list"]
        onResult: text => {
            r.webappList = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 4).map(([slug, name, icon, url]) => ({
                kind: "action", name: name, iconFile: icon || undefined, summary: url.replace(/^[a-z]+:\/\//, "").replace(/\/.*$/, ""),
                confirm: true, armHint: "Enter again: remove, logins too",
                cmd: ["bash", "-c", 'out=$("$0" "$1" 2>&1) && notify-send -a Webapp "Webapp removed" "$2" || notify-send -u critical -a Webapp "Removing webapp failed" "$out"',
                      r.scripts + "/webapp-remove", slug, name] })).map(w => Object.assign(w, { yesCmd: w.cmd }))
        }
    }
}
