import QtQuick
import Quickshell

// The launcher's Settings › Mouse (the wheel's scroll speed), Launcher (fuzzy search, shortcut hints), Firefox (its links, tab bar and start), Computer name, Remote login (sshd), Notifications (how long a popup stays,
// the two sounds, the desktop's own sounds on/off, FUMonitor's alerts), Crash reports and Update channel. Startup stays in Launcher.qml: its rows are the app rows.
// Launcher.qml asks it like DefaultAppsLevels (levels, titles, parents, items, activate, footer, entered), shows compName
// channel and the mouse's speed on Settings' own rows, and calls entered("settings") to read them.
Item {
    id: b
    property var launcher: null

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    readonly property var inputs: ["compname"]   // text fields: ⌘⇧V pastes into them (ClipPicker)
    readonly property var levels: ["launcherprefs", "compname", "remotelogin", "sounds", "notiftime", "soundregular", "soundurgent", "channel", "browser", "mousescroll", "crashreports"]
    readonly property var titles: ({ launcherprefs: "Settings › Launcher", compname: "Settings › Computer name", remotelogin: "Settings › Remote login", channel: "Settings › Update channel",
                                     browser: "Apps › Firefox", mousescroll: "Settings › Mouse", crashreports: "Settings › Crash reports",
                                     sounds: "Settings › Notifications", notiftime: "Notifications › Show for",
                                     soundregular: "Notifications › Regular sound", soundurgent: "Notifications › Urgent sound" })
    readonly property var parents: ({ launcherprefs: "settings", compname: "settings", remotelogin: "settings", channel: "settings", sounds: "settings", browser: "appsettings", mousescroll: "settings", crashreports: "settings",
                                      notiftime: "sounds", soundregular: "sounds", soundurgent: "sounds" })

    // Settings › Computer name: the pretty host name, or the host name as LocalSend and Ferry show it without one
    property string compName: ""
    Sh {
        id: compNameProc
        script: 'n=$(hostnamectl --pretty 2>/dev/null); [ -n "$n" ] || { n=$(uname -n); n=${n%%.*}; n=${n^}; }; echo "$n"'
        onResult: text => b.compName = text.trim()
    }
    // Settings › Remote login: SSH into this computer, off by default like a Mac's (Fedora's preset leaves sshd off).
    // When on, the firewall lets it in over Tailscale and on the networks trusted (scripts/remote-login), not on a
    // café's. on | off | none (no openssh-server), "" = not read yet. remoteNet: the network the traffic goes out on
    // ({uuid, name, allowed: yes | no | ""}), empty off Wi-Fi and cable or without firewalld
    property string remoteLogin: ""
    property var remoteNet: ({})
    // From the change until the state is read again (the password prompt open meanwhile), its switches wait in place:
    // setting the new state at once showed it on before the password, and back off a while after a cancel
    property bool remoteBusy: false
    property bool remoteRecheck: false
    readonly property var remoteLoginItems: remoteLogin === "on" || remoteLogin === "off"
        ? [{ kind: "nav", name: "Remote login", glyph: "terminal", target: "remotelogin", summary: remoteLogin }] : []
    Sh {
        id: remoteLoginProc
        script: '"$HOME/.config/hypr/scripts/remote-login" status'
        onResult: text => {
            const f = text.replace(/\n$/, "").split("\n")
            b.remoteLogin = f[0] || ""
            b.remoteNet = f[1] ? { uuid: f[1], name: f[2] || "", allowed: f[3] || "" } : {}
            if (b.remoteRecheck) { b.remoteRecheck = false; b.remoteBusy = false }
        }
    }
    // firewalld's and systemd's polkit ask for the password; cancelling either leaves the switch as it was, without a
    // notification (remote-login says "Not authorized" for firewall-cmd, systemctl "Access denied")
    Sh {
        id: remoteLoginSetProc
        onResult: text => {
            if (exitCode !== 0 && !/not authorized|authorization failed|access denied|cancel/i.test(text))
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Settings", "Remote login failed", text.trim()])
            b.remoteRecheck = true
            remoteLoginProc.running = true
        }
    }
    function setRemoteLogin(on) {
        remoteBusy = true
        remoteLoginSetProc.script = '"$HOME/.config/hypr/scripts/remote-login" ' + (on ? "on" : "off")
        remoteLoginSetProc.running = true
    }
    function setRemoteNet(allow) {
        remoteBusy = true
        remoteLoginSetProc.script = '"$HOME/.config/hypr/scripts/remote-login" ' + (allow ? "allow" : "deny") + " " + remoteNet.uuid
        remoteLoginSetProc.running = true
    }
    // Settings › Update channel: stable | dev | custom (nightdrive channel; the channel is the checkout's branch)
    property string channel: ""
    property string channelBranch: ""
    readonly property var channels: [["stable", "Stable", "shield-check"], ["dev", "Development", "flask-conical"]]
    Sh {
        id: channelProc
        script: '"$HOME/.local/bin/nightdrive" channel'
        onResult: text => {
            const m = text.trim().match(/^(\S+)(?: \(branch (.+)\))?/)
            b.channel = m ? m[1] : ""
            b.channelBranch = m && m[2] ? m[2] : ""
            const l = b.launcher
            if (l.level === "channel" && l.query === "") l.selectWhere(r => r.value === b.channel)
        }
    }
    // Settings › Apps › Firefox (hypr/scripts/firefox-prefs): "" until read, "none" without a Firefox profile, else
    // { links: window|tab, tabbar: auto|always, startup: empty|restore }. Its row in Settings shows only with a profile.
    property var firefox: ""
    readonly property var browserItems: firefox !== "" && firefox !== "none"
        ? [{ kind: "nav", name: "Firefox", glyph: "globe", target: "browser" }] : []
    Sh {
        id: firefoxProc
        command: [b.scripts + "/firefox-prefs", "status"]
        onResult: text => {
            const t = text.trim()
            if (t === "none" || t === "") { b.firefox = t; return }
            const o = {}
            t.split(" ").forEach(kv => { const i = kv.indexOf("="); o[kv.slice(0, i)] = kv.slice(i + 1) })
            b.firefox = o
        }
    }
    function setFirefox(key, value) {
        const o = Object.assign({}, firefox); o[key] = value; firefox = o
        Quickshell.execDetached([scripts + "/firefox-prefs", key, value])
    }
    // Settings › Mouse: the wheel's scroll speed, a multiplier in a state file that hyprland.lua reads when it loads (input
    // scroll_factor; the trackpad has its own). "" = not read yet
    readonly property string mouseScrollFile: Quickshell.env("HOME") + "/.local/state/nightdrive/mouse-scroll"
    readonly property var mouseScrolls: [0.5, 0.75, 1, 1.5, 2, 3]
    property string mouseScroll: ""
    Sh {
        id: mouseScrollProc
        script: 'v=$(cat "$HOME/.local/state/nightdrive/mouse-scroll" 2>/dev/null); echo "${v:-1}"'
        onResult: text => {
            b.mouseScroll = String(Number(text.trim()) || 1)
            const l = b.launcher
            if (l.level === "mousescroll" && l.query === "") l.selectWhere(r => r.value === Number(b.mouseScroll))
        }
    }
    // Saved, then set in the running Hyprland: no reload needed
    function setMouseScroll(v) {
        mouseScroll = String(v)
        Quickshell.execDetached(["bash", "-c",
            'mkdir -p "$(dirname "$2")" && printf "%s\\n" "$1" > "$2.tmp" && mv "$2.tmp" "$2" && hyprctl eval "hl.config({ input = { scroll_factor = $1 } })" >/dev/null',
            "_", String(v), mouseScrollFile])
    }
    // Settings › Notifications (hypr/scripts/sounds): file name, shown name, icon
    property string soundRegular: ""
    property string soundUrgent: ""
    readonly property var soundChoices: ({
        regular: [["plip", "Plip", "bell"], ["drop", "Drop", "bell"], ["tick", "Tick", "bell"], ["retro", "Retro", "bell"], ["glass", "Glass", "bell"]],
        urgent: [["double-plip", "Double plip", "bell-ring"], ["plip-fall", "Falling plip", "bell-ring"], ["synth-fall", "Synth fall", "bell-ring"],
                 ["arpeggio", "Arpeggio", "bell-ring"], ["pulse", "Pulse", "bell-ring"]]
    })
    readonly property var soundDefaults: ({ regular: "plip", urgent: "double-plip" })
    // The desktop's own sounds (hypr/scripts/sounds event: screenshot, charger, devices, lock…) and the volume keys'
    // tick: on | off, "" = not read yet (shown on)
    property string systemSounds: ""
    property string volumeTick: ""
    property string fumon: ""                 // uwsm's failed unit monitor (hypr/scripts/fumon): on | off | none, "" = not read yet
    function soundName(which, v) { return v === "none" ? "none" : (soundChoices[which].find(t => t[0] === v) || [])[1] }
    // Settings › Notifications › Show for: how long a popup stays (Notifs.timeout, read from its file)
    readonly property var notifTimes: [2, 3, 4, 5, 7, 10, 15, 20, 30]
    function setNotifTime(sec) {
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$2")" && printf "%s\\n" "$1" > "$2.tmp" && mv "$2.tmp" "$2"',
                                 "_", JSON.stringify({ seconds: sec }), Notifs.prefsFile])
    }
    // Settings › Notifications: how long they show, and the two choices with their current sound
    function soundsItems() {
        return [
            { kind: "nav", name: "Show for", glyph: "timer", target: "notiftime", summary: Math.round(Notifs.timeout / 1000) + " s" },
            { kind: "nav", name: "Regular sound", glyph: "bell", target: "soundregular", summary: soundName("regular", soundRegular) },
            { kind: "nav", name: "Urgent sound", glyph: "bell-ring", target: "soundurgent", summary: soundName("urgent", soundUrgent) },
            { kind: "syssound", key: "system", name: "System sounds", glyph: "volume-2", switchOn: systemSounds !== "off",
              sub: "Screenshot, charger, battery, devices, lock, log out, errors" },
            { kind: "syssound", key: "volume", name: "Volume key tick", glyph: "volume-1", switchOn: volumeTick !== "off",
              sub: systemSounds === "off" ? "Off with the system sounds" : "A tick at the new level on each step" }
        ].concat(fumon === "on" || fumon === "off" ? [   // only where uwsm has fumon (up to 0.26)
            { kind: "fumon", name: "Failed service alerts", glyph: "triangle-alert", switchOn: fumon === "on",
              sub: "FUMonitor’s “Failed unit detected” and “Unit recovered”" }] : [])
    }
    // ⇧Enter on a sound: plays it without choosing it ("None" has nothing to play)
    function listenSound(it) {
        if (it.value === "none") { launcher.shakeNow(); return }
        Quickshell.execDetached([scripts + "/sounds", "play", it.which, it.value])
    }
    // Settings › Notifications: the current sounds; select the current one
    Sh {
        id: soundsProc
        script: 's="$HOME/.config/hypr/scripts/sounds"; "$s" regular; "$s" urgent; "$s" system; "$s" volume'
        onResult: text => {
            const f = text.trim().split("\n")
            b.soundRegular = f[0] || ""
            b.soundUrgent = f[1] || ""
            b.systemSounds = f[2] || ""
            b.volumeTick = f[3] || ""
            const l = b.launcher
            if ((l.level === "soundregular" || l.level === "soundurgent") && l.query === "")
                l.selectWhere(r => r.value === (l.level === "soundregular" ? b.soundRegular : b.soundUrgent))
        }
    }
    // Settings › Crash reports (hypr/scripts/crash-report): on | off, "" = not read yet (its row shows once read)
    property string crashReports: ""
    readonly property var crashReportItems: crashReports !== ""
        ? [{ kind: "nav", name: "Crash reports", glyph: "bug", target: "crashreports", summary: crashReports }] : []
    Sh {
        id: crashReportsProc
        command: [b.scripts + "/crash-report", "status"]
        onResult: text => { b.crashReports = text.trim() }
    }
    // Settings › Notifications: whether FUMonitor runs (its row shows only where uwsm has it)
    Sh {
        id: fumonProc
        script: '"$HOME/.config/hypr/scripts/fumon" status'
        onResult: text => { b.fumon = text.trim() }
    }

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (level === "launcherprefs" || cur.kind === "firefox" || cur.kind === "remotelogin" || cur.kind === "remotenet" || cur.kind === "fumon" || cur.kind === "crashreports") return "Enter: on/off"
        if (cur.kind === "syssound") return "Enter: on/off  ·  Shift+Enter: listen"
        if (cur.kind === "mousescroll") return "Enter: choose, then try the wheel"
        if (cur.kind === "sound") return "Enter: choose  ·  Shift+Enter: listen"
        if (level === "compname" && query.trim() !== "") return "Enter: rename (asks for your password)"
        return ""
    }
    // The rows that show only once read (Firefox, Remote login, Crash reports) are in the root search too, so read
    // them on every open, not only on entering Settings: after a reload they were missing until Settings was opened
    function opened() { firefoxProc.running = true; remoteLoginProc.running = true; crashReportsProc.running = true }
    function entered(level) {
        if (level === "settings" || level === "compname") compNameProc.running = true
        if (level === "settings" || level === "channel") channelProc.running = true
        if (level === "settings" || level === "remotelogin") remoteLoginProc.running = true
        if (level === "settings" || level === "browser") firefoxProc.running = true
        if (level === "settings" || level === "mousescroll") mouseScrollProc.running = true
        if (level === "sounds" || level === "soundregular" || level === "soundurgent") soundsProc.running = true
        if (level === "sounds") fumonProc.running = true
        if (level === "settings" || level === "crashreports") crashReportsProc.running = true
        if (level === "notiftime") Qt.callLater(() => launcher.selectWhere(r => r.summary === "current"))   // the cursor on the current time
    }
    function shiftActivate(it) {
        if (it.kind === "sound") listenSound(it)
        if (it.kind === "syssound") Quickshell.execDetached([scripts + "/sounds", "file", Quickshell.env("HOME") + "/.local/share/nightdrive/sounds/system/" + (it.key === "volume" ? "volume" : "screenshot") + ".wav"])
    }

    function items(level, q) {
        if (level === "launcherprefs") {
            // The footer's key hints always show; these are the extras
            return [{ kind: "lpref", key: "fuzzy", name: "Fuzzy search", glyph: "wand-sparkles",
                      sub: "Typos and initials also match: firefx, vsc", switchOn: launcher.prefs.fuzzy },
                    { kind: "lpref", key: "shortcuts", name: "Shortcut hints", glyph: "keyboard",
                      sub: "An app’s or menu’s keys on its row (Hyper P)", switchOn: launcher.prefs.shortcuts }]
                .concat([{ kind: "lpref", key: "comma", name: "Decimal comma in results", glyph: "calculator",
                      sub: "The calculator answers 3,5 instead of 3.5 (type either)", switchOn: launcher.prefs.comma }])
                .concat(Plugins.has("deck") ? [{ kind: "lpref", key: "deck", name: "Include Deck artists, albums and songs", glyph: "disc-3",
                      sub: "Your shelf and Curated in the search, and a row to search Spotify", switchOn: launcher.prefs.deck }] : [])
                .concat(Plugins.has("contacts") ? [{ kind: "lpref", key: "contacts", name: "Include contacts", glyph: "contact",
                      sub: "People by name, company, address or number; Enter shows their numbers and addresses", switchOn: launcher.prefs.contacts }] : [])
        }
        if (level === "mousescroll") {
            const cur = Number(mouseScroll)
            return [{ kind: "header", name: "Scroll speed" }].concat(mouseScrolls.map(v => ({ kind: "mousescroll", value: v, name: v + "× " + (v < 1 ? "slower" : v > 1 ? "faster" : "(normal)"),
                glyph: v === cur ? "check" : "mouse", summary: v === cur ? "current" : (v === 1 ? "default" : undefined) })))
                .concat([{ kind: "note", name: "The mouse wheel’s speed. The trackpad keeps its own" }])
        }
        if (level === "browser") {
            // Firefox reads them when it starts (user.js, userChrome.css)
            if (typeof firefox !== "object") return []
            return [{ kind: "firefox", key: "links", on: "window", off: "tab", name: "Links from other apps in a new window", glyph: "app-window",
                      sub: "A link from Mail or chat opens on its own, not among your tabs", switchOn: firefox.links === "window" },
                    { kind: "firefox", key: "tabbar", on: "auto", off: "always", name: "Tab bar only with several tabs", glyph: "panel-top",
                      sub: "One tab, no tab bar: more room for the page", switchOn: firefox.tabbar === "auto" },
                    { kind: "firefox", key: "startup", on: "empty", off: "restore", name: "Start with an empty window", glyph: "history",
                      sub: "A fresh start, not the last session’s tabs again", switchOn: firefox.startup !== "restore" },
                    { kind: "note", name: "Changes apply when Firefox restarts" }]
        }
        if (level === "compname") {
            // Phones see it in LocalSend, AirPlay and Ferry. The name as typed: q is lower-cased
            const name = launcher.query.trim()
            if (name === "") return launcher.hint("Now “" + compName + "”. Type a new name")
            return [{ kind: "compset", name: "Rename to “" + name + "”", glyph: "laptop", value: name }]
        }
        if (level === "remotelogin") {
            const on = remoteLogin === "on"
            return [{ kind: "remotelogin", name: "Remote login", glyph: "terminal", switchOn: on, switchBusy: remoteBusy,
                      sub: "Log in to this computer from another one with SSH" }]
                .concat(on && remoteNet.uuid ? [{ kind: "remotenet", name: "Allow from “" + remoteNet.name + "”", glyph: "house",
                      switchOn: remoteNet.allowed === "yes", switchBusy: remoteBusy, sub: "Safe at home or work, not on a café’s or hotel’s network" }] : [])
                .concat(remoteBusy ? [{ kind: "note", name: "Asking for your password…" }]
                        : on ? [] : [{ kind: "note", name: "Off by default. Turning it on asks for your password" }])
        }
        if (level === "crashreports") {
            return [{ kind: "crashreports", name: "Crash reports to Claude", glyph: "bug", switchOn: crashReports === "on",
                      sub: "When an app crashes: a notification, and Ask Claude finds out why" }]
        }
        if (level === "sounds") return { all: soundsItems().map(t => ({ item: t, text: t.name })) }
        if (level === "notiftime") {
            const cur = Math.round(Notifs.timeout / 1000)
            return notifTimes.map(v => ({ kind: "notiftime", value: v, name: v + " seconds", glyph: v === cur ? "check" : "timer",
                summary: v === cur ? "current" : (v * 1000 === Notifs.defaultTimeout ? "default" : undefined) }))
        }
        if (level === "soundregular" || level === "soundurgent") {
            const which = level === "soundregular" ? "regular" : "urgent"
            const cur = which === "regular" ? soundRegular : soundUrgent
            return soundChoices[which].concat([["none", "None", "bell-off"]]).map(t => ({ kind: "sound", which: which, value: t[0], name: t[1],
                glyph: t[0] === cur ? "check" : t[2], summary: t[0] === cur ? "current" : (t[0] === soundDefaults[which] ? "default" : undefined) }))
        }
        if (level === "channel") {
            // Choosing the other one switches the branch and updates in a terminal (it says why if it can't, e.g. own changes)
            return channels.map(t => ({ kind: "channel", value: t[0], name: t[1], glyph: t[0] === channel ? "check" : t[2], armKey: "channel:" + t[0],
                                        summary: t[0] === channel ? "current" : (t[0] === "stable" ? "default" : undefined) }))
                .concat([{ kind: "note", name: channel === "custom" ? "On a branch of its own (" + (channelBranch || "none") + "): choosing one switches to it"
                                                                   : "Development gets the bigger changes before Stable" }])
        }
        return []
    }

    function activate(it) {
        const l = launcher
        if (it.kind === "lpref") { l.keepSelection(); l.setPref(it.key, !l.prefs[it.key]); return true }
        if (it.kind === "firefox") { l.keepSelection(); setFirefox(it.key, it.switchOn ? it.off : it.on); return true }
        if (it.kind === "mousescroll") { l.keepSelection(); setMouseScroll(it.value); return true }   // stays open: try it, then another
        if (it.kind === "notiftime") {   // stays open, like the sounds: the check moves once Notifs has read the file
            l.keepSelection()
            setNotifTime(it.value)
            return true
        }
        if (it.kind === "crashreports") {
            l.keepSelection()
            crashReports = crashReports === "on" ? "off" : "on"
            Quickshell.execDetached([scripts + "/crash-report", crashReports])
            return true
        }
        if (it.kind === "remotelogin") { l.keepSelection(); setRemoteLogin(!it.switchOn); return true }
        if (it.kind === "remotenet") { l.keepSelection(); setRemoteNet(!it.switchOn); return true }
        if (it.kind === "fumon") {
            l.keepSelection()
            fumon = fumon === "on" ? "off" : "on"
            Quickshell.execDetached([scripts + "/fumon", fumon])
            return true
        }
        if (it.kind === "syssound") {    // turned on, it plays one (the tick, or the screenshot's shutter) to hear it
            l.keepSelection()
            const on = !it.switchOn
            if (it.key === "system") systemSounds = on ? "on" : "off"
            else volumeTick = on ? "on" : "off"
            Quickshell.execDetached(["bash", "-c", '"$1" "$2" "$3" && [ "$3" = on ] && "$1" event "$4"', "_", scripts + "/sounds",
                                     it.key, on ? "on" : "off", it.key === "volume" ? "volume" : "screenshot"])
            return true
        }
        if (it.kind === "sound") {       // stays open: each sound plays as it's chosen, so they can be compared
            l.keepSelection()
            if (it.which === "regular") soundRegular = it.value
            else soundUrgent = it.value
            Quickshell.execDetached(["bash", "-c", '"$1" "$2" "$3" && "$1" play "$2"', "_", scripts + "/sounds", it.which, it.value])
            return true
        }
        if (it.kind === "channel") {
            if (it.value === channel) { l.shakeNow(); return true }
            if (!arm(it.armKey)) return true
            l.open = false
            Quickshell.execDetached(l.term('"$HOME/.local/bin/nightdrive" channel "$1" --update', it.value))
            return true
        }
        if (it.kind === "compset") {
            // The pretty host name (systemd-hostnamed; polkit asks for the password). AirPlay Receiver reads it when it
            // starts; LocalSend and Ferry on every use
            l.open = false
            Quickshell.execDetached(["bash", "-c",
                'out=$(hostnamectl set-hostname --pretty "$1" 2>&1) && { systemctl --user try-restart nightdrive-airplay.service; notify-send -a Settings "Computer name" "$1"; } || notify-send -u critical -a Settings "Renaming failed" "$out"',
                "_", it.value])
            return true
        }
        return false
    }
    // Rows that need a second Enter (the launcher shows "Enter again to confirm" while armed); true = confirmed
    function arm(key) {
        if (launcher.armed !== key) { launcher.armed = key; disarmTimer.restart(); return false }
        launcher.armed = ""
        return true
    }
    Timer { id: disarmTimer; interval: 4000; onTriggered: if (b.launcher) b.launcher.armed = "" }
}
