import QtQuick
import Quickshell
import Quickshell.Io

// The launcher's System › Install pages: Software (Search, and Browse's categories), Webapp (your own, by name and
// address, and the ready-made ones), Recommended and Plugins. Install itself is a static list in Launcher.qml. Enter on a
// package or plugin row opens its details (DetailCard.qml, as Remove's rows do).
// Install › Software: Fedora's packages and Flathub's apps in one search (hypr/scripts/pkg-search): apps first, one row per
// app (Fedora's if both have it), then command-line tools. Software itself has Search and Browse: Popular and the
// categories, lists from data/software.json (hypr/scripts/software-catalog) for this machine's architecture.
// Settings › Apps › Nightdrive apps (ndapps): the installed apps of group app (Mail, Deck), each one's details with its
// on/off switch; one removed is back in Recommended, the user's own way to get it again (nightdrive update never is).
// Launcher.qml asks it like DefaultAppsLevels (levels, titles, parents, items, activate, footer, entered).
Item {
    id: n
    property var launcher: null

    property var results: []                  // Software › Search: the search's rows
    property var swCats: []                   // Software › Browse: [{ key, name, glyph }] (data/software.json)
    property var swCat: ({ key: "", name: "" })   // the open category (level swcat)
    property var swList: null                 // its rows (pkg-search --list), null = loading
    property string webName: ""               // Webapp: the name, while asking for the address
    property var pluginList: null             // Recommended, Plugins and Webapp's ready-made ones: [{ id, name, icon, desc, installed, group, off, external }] (nightdrive plugins), null = loading

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    readonly property var inputs: ["webname", "webaddr"]   // text fields: ⌘⇧V pastes into them (ClipPicker)
    readonly property var levels: ["software", "swcat", "swsearch", "webapp", "webname", "webaddr", "recommended", "plugins", "ndapps"]
    readonly property var titles: ({ software: "Install › Software", swcat: "Software › " + swCat.name, swsearch: "Software › Search", webapp: "Install › Webapp",
                                     recommended: "Install › Recommended", plugins: "Install › Plugins", webname: "Install › Webapp › Name",
                                     webaddr: "Install › Webapp › Address", ndapps: "Settings › Apps › Nightdrive apps" })
    readonly property var parents: ({ software: "install", swcat: "software", swsearch: "software", webapp: "install", recommended: "install",
                                      plugins: "install", webname: "webapp", webaddr: "webname", ndapps: "appsettings" })

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (level === "webapp" && cur.ready) return cur.installed ? "Enter: add again" : "Enter: add"
        if (level === "webname" && query.trim() !== "") return "Enter: continue to the address"
        if (level === "webaddr" && query.trim() !== "") return "Enter: create the webapp"
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level === "swsearch") results = []
        if (level === "swcat") { swList = null; swProc.command = [scripts + "/pkg-search", "--list", swCat.key]; swProc.running = true }
        if (level === "plugins" || level === "recommended" || level === "webapp" || level === "ndapps") pluginsProc.running = true
    }
    function shiftActivate(it) {}
    // A category from elsewhere too (Default apps › Find more)
    function openCategory(key, name) { swCat = { key: key, name: name }; launcher.go("swcat") }
    // The list again after a plugin was turned on or off (its details card)
    function reloadPlugins() { pluginsProc.running = true }

    function items(level, q) {
        const l = launcher
        if (level === "software") {
            const browse = [{ kind: "swcat", name: "Popular", glyph: "trending-up", key: "popular", summary: "top 100" }]
                .concat(swCats.map(c => ({ kind: "swcat", name: c.name, glyph: c.glyph, key: c.key })))
            if (q === "") return [{ kind: "swsearch", name: "Search", glyph: "search", summary: "Fedora + Flathub" },
                                  { kind: "header", name: "Browse" }].concat(browse)
            // What's typed can always go on to the package search (the categories rarely match an app's name)
            return { all: browse.map(r => ({ item: r, text: r.name })),
                     tail: [{ kind: "swsearch", name: "Search for “" + l.query.trim() + "”", glyph: "search", summary: "Fedora + Flathub" }] }
        }
        if (level === "swsearch") {
            if (q.replace(/[^a-z0-9._+\-]/g, "").length < 2) return [{ kind: "hint", name: "Type at least 2 characters to search apps and tools" }]
            if (results.length === 0) return [{ kind: "hint", name: searchProc.running ? "Searching…" : "Nothing found" }]
            return results
        }
        if (level === "swcat") {
            if (swList === null) return l.hint("Loading…")
            if (swList.length === 0) return l.hint("Nothing for this computer here")
            return { all: swList.map(r => ({ item: r, text: r.name, extra: r.sub || "" })) }
        }
        if (level === "webname") {
            if (l.query.trim() === "") return l.hint("Type the webapp’s name")
            return [{ kind: "wname", name: "Name: " + l.query.trim(), summary: "next: address", glyph: "arrow-right", value: l.query.trim() }]
        }
        if (level === "webaddr") {
            if (l.query.trim() === "") return l.hint("Type the address for “" + webName + "” (e.g. web.whatsapp.com)")
            return [{ kind: "wadd", name: "Add “" + webName + "”", summary: l.query.trim(), glyph: "app-window", value: l.query.trim() }]
        }
        if (level === "plugins" || level === "recommended" || level === "ndapps") {
            // Enter opens the details (src "plugin"), whose Enter runs the installer in a terminal (they ask things: sudo, tokens,
            // logins); an installed one can be run again (rerun)
            if (pluginList === null) return l.hint("Loading…")
            // "experimental" in the description becomes a tag after the name (plugins.txt keeps it in the text for install.sh)
            const exp = /\bexperimental\b/i
            const plain = d => d.replace(/\s*\(experimental\)/i, "").replace(/,\s*experimental(?=[;)])/i, "").replace(/\(experimental;\s*/i, "(")
            // Recommended also has Nightdrive's apps while one isn't installed (as the App Store has Apple's own once removed)
            const inGroup = (p, group) => group === "ndapps" ? p.group === "app" && p.installed
                                                             : p.group === group || (group === "recommended" && p.group === "app" && !p.installed)
            const rows = (group, from) => pluginList.filter(p => inGroup(p, group)).map(p => ({ item: { kind: "action", name: p.name, glyph: p.icon, sub: plain(p.desc), installed: p.installed,
                                                 experimental: exp.test(p.desc), external: p.external,
                                                 src: "plugin", id: p.id, rerun: true, groupTag: from,
                                                 summary: p.installed ? (p.off ? "off" : group === "ndapps" ? "on" : "installed") : undefined,
                                                 cmd: l.term('"$HOME/.local/bin/nightdrive" plugins install "$1"', p.id) },
                                         text: p.name, extra: p.desc }))
            if (level === "ndapps") {
                const r = rows("ndapps")
                return r.length ? { all: r } : l.hint("None installed: they are in System › Install › Recommended")
            }
            // A search also finds the other group's rows, tagged with it: whether something is a plugin or a recommended app
            // isn't obvious ("tailscale" in Plugins found only Ferry, whose description mentions it; Tailscale is Recommended)
            return { all: level === "plugins" ? rows("plugin").concat(q !== "" ? rows("recommended", "Recommended") : [])
                                              : rows("recommended").concat(q !== "" ? rows("plugin", "Plugins") : []) }
        }
        if (level === "webapp") {
            // Your own first, then the ready-made ones (plugins.txt, group webapp): added without a terminal, nothing to ask
            const own = [
                { kind: "nav", name: "Add your own", glyph: "plus", target: "webname" },
                { kind: "action", name: "Add your own in a terminal", glyph: "terminal",
                  cmd: l.term('read -rp "Name: " n; read -rp "Address: " u; "$HOME/.config/hypr/scripts/webapp-add" "$n" "$u"') }
            ]
            const ready = (pluginList || []).filter(p => p.group === "webapp").map(p => ({
                item: { kind: "action", ready: true, name: p.name, glyph: p.icon, installed: p.installed,
                        summary: p.installed ? "added" : undefined,
                        cmd: ["bash", "-c", 'out=$("$HOME/.local/bin/nightdrive" plugins install "$1" 2>&1) && notify-send -a Webapp "Webapp added" "$2" || notify-send -u critical -a Webapp "Adding webapp failed" "$out"', "_", p.id, p.name] },
                text: p.name, extra: p.desc }))
            return { all: own.map(r => ({ item: r, text: r.name }))
                .concat(ready.length ? [{ item: { kind: "header", name: "Ready-made" }, text: "" }] : [], ready) }
        }
        return []
    }

    // Package and plugin rows are the launcher's (kind action with src: their details, or cmd)
    function activate(it) {
        const l = launcher
        if (it.kind === "swcat") { openCategory(it.key, it.name); return true }
        if (it.kind === "swsearch") { l.search("swsearch", l.query); return true }
        if (it.kind === "wname") { webName = it.value; l.go("webaddr"); return true }
        if (it.kind === "wadd") {
            l.open = false
            Quickshell.execDetached(["bash", "-c",
                'out=$("$HOME/.config/hypr/scripts/webapp-add" "$1" "$2" 2>&1) && notify-send -a Webapp "Webapp added" "$1" || notify-send -u critical -a Webapp "Adding webapp failed" "$out"',
                "_", webName, it.value])
            return true
        }
        return false
    }

    // Software › Search: search while typing (300 ms delay), hypr/scripts/pkg-search: { apps, tools }
    // Spaces stay (one between words): pkg-search looks for the words as a phrase, "image viewer" (without them nothing
    // two-word was found: "documentviewer")
    function sanitized() { return launcher.query.toLowerCase().replace(/[^a-z0-9._+\- ]/g, "").replace(/\s+/g, " ").trim() }
    function runSearch() {
        const q = sanitized()
        if (q.length < 2) { results = []; return }
        if (searchProc.running) return                 // the running one notices the query went stale and starts again
        searchProc.command = [scripts + "/pkg-search", q]
        searchProc.forQ = q
        searchProc.running = true
    }
    // A pkg-search row → a launcher row (Enter opens its details)
    function pkgRow(p, glyph) {
        return { kind: "action", name: p.name, sub: p.summary, iconFile: p.icon || undefined,
                 glyph: p.icon ? undefined : (p.glyph || glyph), src: p.src, id: p.id, alt: p.alt,
                 summary: p.installed ? "installed" : undefined, cmd: launcher.installCmd(p.src, p.id) }
    }
    Connections {
        target: n.launcher
        function onQueryChanged() { if (n.launcher.level === "swsearch") { n.launcher.armed = ""; searchDelay.restart() } }
    }
    Timer { id: searchDelay; interval: 300; onTriggered: n.runSearch() }
    Sh {
        id: searchProc
        property string forQ: ""
        onResult: text => {
            if (n.launcher.level !== "swsearch") return    // left the level while searching
            if (n.sanitized() !== forQ) { n.runSearch(); return }
            let r
            try { r = JSON.parse(text) } catch (e) { n.results = []; return }
            // The headers only when both are there: one kind alone needs no title
            const both = r.apps.length > 0 && r.tools.length > 0
            const out = []
            if (both) out.push({ kind: "header", name: "Apps" })
            for (const p of r.apps) out.push(n.pkgRow(p, "package-plus"))
            if (both) out.push({ kind: "header", name: "Command-line tools" })
            for (const p of r.tools) out.push(n.pkgRow(p, "terminal"))
            n.results = out
            n.launcher.selectFirst()
        }
    }
    // Software › a category: pkg-search --list (the most installed apps this machine can run)
    Sh {
        id: swProc
        onResult: text => {
            if (n.launcher.level !== "swcat") return
            let r
            try { r = JSON.parse(text) } catch (e) { n.swList = []; return }
            n.swList = r.apps.map(p => n.pkgRow(p, "package-plus"))
            n.launcher.selectFirst()
        }
    }
    // Browse's categories: their names and icons come with the lists (software-catalog writes both), read again when an
    // update brings a new file
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/data/software.json"; printErrors: false
        watchChanges: true; onFileChanged: reload()
        onLoaded: { try { n.swCats = JSON.parse(text()).categories || [] } catch (e) { n.swCats = [] } }
    }
    // Recommended, Plugins and Webapp: plugins.txt via `nightdrive plugins` (id, name, icon, description, default,
    // installer, installed 1/0, group, folder, off 1/0, source repo/external)
    Sh {
        id: pluginsProc
        command: [Quickshell.env("HOME") + "/.local/bin/nightdrive", "plugins"]
        onResult: text => {
            n.pluginList = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 8)
                .map(f => ({ id: f[0], name: f[1], icon: f[2], desc: f[3], installed: f[6] === "1", group: f[7], off: f[9] === "1", external: f[10] === "external" }))
        }
    }
}
