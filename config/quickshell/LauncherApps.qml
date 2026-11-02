import QtQuick
import Quickshell

// The launcher's apps and what it knows about them: the allow-listed and hidden ones (sync-apps), those whose program is
// gone, which have a window open (the green dot, ⌘Q's pulse), ⌃Enter's show / hide in Apps and ⌥Enter's start at
// login. State and processes only, apart from Launcher.qml's navigation and rows; the launcher reaches it as
// launcher.appState.
Item {
    id: root
    required property var launcher

    // Reference at startup: the app list only loads on first reference
    property var apps: DesktopEntries.applications.values
    property var syncHidden: []               // apps hidden by sync-apps: [{ path, name, icon, extra }]
    property var missingApps: ({})            // ids of entries whose program isn't installed (missing-apps.sh): left out

    // Re-read on every level change: an app hidden or installed meanwhile shows up at once
    function rescan() { hiddenProc.running = true; missingProc.running = true }
    // On every open: the window list, the background apps' list and the login apps
    function opened() { bgProc.running = true; bgAppsProc.running = true; autostartProc.running = true }
    function refreshWindows() { bgProc.running = true }

    // App rows: with an empty query only allow-listed apps; when searching, also those hidden by sync-apps
    function appEntries(q) {
        const all = apps.filter(e => !e.noDisplay && !missingApps[appId({ entry: e })]).map(e => ({
            item: { kind: "app", name: e.name, icon: e.icon, entry: e, shown: true },
            text: e.name,
            extra: (e.genericName || "") + " " + (e.keywords || []).join(" ")
        }))
        if (q !== "") for (const h of syncHidden) if (!missingApps[appId({ path: h.path })]) all.push({ item: { kind: "app", name: h.name, icon: h.icon, path: h.path, shown: false }, text: h.name, extra: h.extra })
        // An app just moved with ⌃Enter: the two sources (DesktopEntries, hidden-apps.sh) update at different moments, so
        // until its new place shows up the row is kept from the snapshot, and its old place is left out
        const out = all.filter(a => { const p = pinPending[appId(a.item)]; return !p || p.shown === a.item.shown })
        for (const id in pinPending) {
            const p = pinPending[id]
            if (!out.some(a => appId(a.item) === id) && (p.shown || q !== "")) out.push({ item: p, text: p.name, extra: "" })
        }
        return out
    }

    // Background apps (⌘W hides them to special:bg, ⌘Q quits): app name -> window class regex, from hypr/background-apps(.local),
    // the same list close-or-hide uses. An open app (also a hidden one) gets a green dot at the right end of its row.
    property var bgApps: ({})
    Sh {
        id: bgAppsProc   // re-read on every open, so an app added to the list works without restarting the shell
        script: 'cd "$HOME/.config/hypr" && cat background-apps background-apps.local 2>/dev/null'
        running: true
        onResult: text => {
            const m = {}
            for (const l of text.split("\n")) {
                const i = l.indexOf(" = ")
                if (i > 0 && !l.startsWith("#")) m[l.slice(0, i).trim()] = l.slice(i + 3).trim()
            }
            root.bgApps = m
        }
    }
    property var runningClasses: []    // classes of all open windows (lowercase)
    // Whether an app has a window open (on any workspace, also in the background): background apps by their class list (bgApps),
    // others by the .desktop file's StartupWMClass or id
    function appRunning(item) { return item.kind === "app" && (item.entry !== undefined || item.path !== undefined) && appClassRe(item) !== "" }
    // The window class regex of a running app (for quit-app --class), "" when it has no window open. A row hidden by
    // sync-apps has only the .desktop file's path: its id is the file name.
    function appClassRe(item) {
        const re = bgApps[item.name]
        if (re !== undefined) return runningClasses.some(c => new RegExp(re, "i").test(c)) ? re : ""
        const wm = (item.entry && item.entry.startupClass || "").toLowerCase()
        const id = appId(item).replace(/\.desktop$/, "").toLowerCase()
        const c = [wm, id].find(c => c !== "" && runningClasses.includes(c))
        return c ? "^" + c.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$" : ""
    }
    // Apps quit with ⌘Q: class regex -> when. Their green dot pulses until the app is gone (or 10 s: it asked about unsaved
    // work or refused), the window list is re-read often meanwhile.
    property var quitting: ({})
    readonly property bool anyQuitting: Object.keys(quitting).length > 0
    function quitPending(item) { const re = appClassRe(item); return re !== "" && quitting[re] !== undefined }
    onRunningClassesChanged: {
        if (!anyQuitting) return
        const left = {}
        for (const re in quitting)
            if (Date.now() - quitting[re] < 10000 && runningClasses.some(c => new RegExp(re, "i").test(c))) left[re] = quitting[re]
        quitting = left
    }
    Timer { interval: 300; repeat: true; running: root.anyQuitting; onTriggered: bgProc.running = true }
    Sh {
        id: bgProc
        script: 'hyprctl -j clients | jq -r \'.[].class\''
        onResult: text => { root.runningClasses = text.split("\n").filter(l => l !== "" && !l.startsWith("__")).map(l => l.toLowerCase()) }
    }
    Timer { interval: 1500; repeat: true; running: root.launcher.open; onTriggered: bgProc.running = true }
    // ⌃Enter on an app: the choice goes to ~/.local/state/nightdrive/apps.json ({"shown": [ids], "hidden": [ids]}), then sync-apps
    // updates the overrides (fuzzel/sync-apps) and the list follows
    function appId(item) {
        const id = item.entry ? item.entry.id : item.path.split("/").pop()
        return id.endsWith(".desktop") ? id : id + ".desktop"
    }
    property var pinPending: ({})           // id -> the app's row in its new state, until both sources have caught up
    function togglePin(item) {
        launcher.keepSelection()
        const n = Object.assign({}, pinPending)
        n[appId(item)] = Object.assign({}, item, { shown: !item.shown })
        pinPending = n
        pinProc.environment = { "ID": appId(item), "TO": item.shown ? "hidden" : "shown" }
        pinProc.running = true
    }
    // A pending app is done once its new place is in the sources (and its old place is gone); the timer is a fallback
    function prunePins() {
        let changed = false
        const n = Object.assign({}, pinPending)
        for (const id in n) {
            const inApps = apps.some(e => !e.noDisplay && appId({ entry: e }) === id)
            const inHidden = syncHidden.some(h => appId({ path: h.path }) === id)
            if (n[id].shown ? inApps && !inHidden : inHidden && !inApps) { delete n[id]; changed = true }
        }
        if (changed) pinPending = n
    }
    onAppsChanged: prunePins()
    onSyncHiddenChanged: prunePins()
    Timer { id: pinSettle; interval: 5000; onTriggered: root.pinPending = ({}) }
    Sh {
        id: pinProc
        // The id moves to one list and out of the other; other keys in the file are kept (room for more settings later)
        script: 'f="$HOME/.local/state/nightdrive/apps.json"; mkdir -p "${f%/*}"; [ -s "$f" ] || echo "{}" > "$f"
jq --arg id "$ID" --arg to "$TO" \'.shown = ((.shown // []) - [$id]) | .hidden = ((.hidden // []) - [$id]) | .[$to] += [$id]\' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
"$HOME/.config/fuzzel/sync-apps" >/dev/null'
        onResult: { hiddenProc.running = true; pinSettle.restart() }   // (prunePins runs when the lists change)
    }

    // Login apps (Settings › Apps › Startup, ⌥Enter on an app): hypr/scripts/autostart keeps the list and starts them at login
    property var autostartIds: []
    Sh {
        id: autostartProc
        command: [root.launcher.scripts + "/autostart", "list"]
        onResult: text => { root.autostartIds = text.split("\n").filter(l => l !== "") }
    }
    function toggleAutostart(item) {
        launcher.keepSelection()
        const id = appId(item)
        autostartIds = autostartIds.indexOf(id) >= 0 ? autostartIds.filter(x => x !== id) : autostartIds.concat([id])   // shown at once
        Quickshell.execDetached([launcher.scripts + "/autostart", "toggle", id])
    }

    // overrides marked by sync-apps → ids of hidden apps
    Sh {
        id: hiddenProc
        command: [Quickshell.env("HOME") + "/.config/quickshell/hidden-apps.sh"]
        onResult: text => {
            root.syncHidden = text.split("\n").filter(l => l.includes("|")).map(l => {
                const f = l.split("|")
                return { path: f[0], name: f[1], icon: f[2], extra: f[3] || "" }
            })
        }
    }

    // entries whose program is gone (a removed package's local copy or link) → ids to leave out of Apps
    Sh {
        id: missingProc
        command: [Quickshell.env("HOME") + "/.config/quickshell/missing-apps.sh"]
        onResult: text => {
            const m = {}
            for (const id of text.split("\n")) if (id) m[id] = true
            root.missingApps = m
        }
    }
}
