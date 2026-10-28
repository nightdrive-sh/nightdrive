pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland

// Notification server (org.freedesktop.Notifications; replaced mako on 14.10.2026). NotificationPopups.qml draws the popups,
// NotificationsMenu.qml the history. The app's icon comes from its .desktop file, so every notification shows one.
// Like mako's ignore-timeout: every popup goes after `timeout` whatever the app asks (Chromium and nm-applet ask for never);
// critical ones stay until clicked. Do not disturb hides the popups, the history keeps them.
// Under the login screen at an autologin start (greeter/lock.qml) they're quiet and wait: their popups show after the
// password, and they never chime.
// A new notification plays a sound (hypr/scripts/sounds; Settings › Notifications): regular or urgent by its urgency,
// none for low ones, in do not disturb, for an update of one already shown, when its app is the focused window (you are
// looking at it), or when the same app chimed under `soundGap` ago (a burst of messages chimes once).
// The history keeps what still matters (stale rows are noise that buries the rest):
// - Replaced: a notification with the same stack tag as an earlier one from its app (hints x-dunst-stack-tag or
//   x-canonical-private-synchronous: `notify-send -h string:x-dunst-stack-tag:NAME`) takes its place without a sound,
//   and one with the same text as an earlier one moves that row to the top instead of adding a second.
// - Withdrawn: a notification stays open after its popup goes, so its app can still close it (a chat read on the phone,
//   a reminder whose meeting began), and then its row goes too. Not when the app has no window left: apps close their
//   notifications when they quit, and those rows stay.
// - Expired: hint x-nightdrive-expires (int, seconds: `-h int:x-nightdrive-expires:3600`) removes the row that long after.
// - Transient (`notify-send -e`, "Copied" and the like): only the popup, never a row.
//   qs ipc call notifications toggleDnd     → "true" when do not disturb is now on (hypr/scripts/dnd, F6)
//   qs ipc call notifications dismissAll | clear | count
Singleton {
    id: s

    // ms a popup stays (hover keeps it): launcher › Settings › Notifications › Show for, in
    // ~/.local/state/nightdrive/notifications.json ({ "seconds": N }; missing = the default)
    readonly property int defaultTimeout: 5000
    readonly property string prefsFile: Quickshell.env("HOME") + "/.local/state/nightdrive/notifications.json"
    property int timeout: defaultTimeout
    FileView {
        path: s.prefsFile; watchChanges: true; onFileChanged: reload(); printErrors: false
        onLoaded: {
            let v = {}
            try { v = JSON.parse(text()) || {} } catch (e) {}
            s.timeout = v.seconds > 0 ? v.seconds * 1000 : s.defaultTimeout
        }
        onLoadFailed: s.timeout = s.defaultTimeout
    }
    readonly property int maxHistory: 50
    readonly property int maxPopups: 6
    readonly property int soundGap: 2000      // ms: an app's notifications closer together than this chime once

    property var popups: []                   // [{ uid, n (Notification), entry (history row) }], newest first
    property var history: []                  // [{ uid, app, summary, body, icon, image, preview, entry, time, tag, expires }], newest first
    property var live: ({})                   // uid → its Notification, while it's open (popup shown or not)
    property var shownAtReload: []            // uids that had a popup when Quickshell reloaded
    property alias dnd: persist.dnd
    property double now: Date.now()           // for "2 min ago": updated every 30 s
    // The notification menu is open (NotificationsMenu.qml): the popups go (the menu lists them) and new ones skip the
    // popup, they show up in the menu's list
    property bool menuOpen: false
    onMenuOpenChanged: if (menuOpen) dismissAll()

    // The session is under the login screen: hyprland.lua has started it (nightdrive-session-started) but not yet the
    // login apps (nightdrive-apps-started, after the password). Checked again every half second while it lasts; true
    // until the first check, so nothing chimes in the moment before it.
    property bool locked: true
    property var held: []                     // popups waiting for the password: [{ uid, n, entry }], oldest first
    Process {
        id: lockCheck
        running: true
        command: ["sh", "-c", 'r=${XDG_RUNTIME_DIR:-/tmp}; [ -e "$r/nightdrive-session-started" ] && [ ! -e "$r/nightdrive-apps-started" ]']
        onExited: code => { s.locked = code === 0; if (s.locked) lockPoll.start() }
    }
    Timer { id: lockPoll; interval: 500; onTriggered: lockCheck.running = true }
    onLockedChanged: if (!locked) {
        const waiting = held
        held = []
        for (const p of waiting) pop(p)
    }

    // Survive Quickshell's reload on save (a restart still starts empty, as mako did). The history goes over as JSON
    // text: a JS array can't move to the reloaded config's engine ("JSValue can't be reassigned"), it came back undefined.
    PersistentProperties {
        id: persist
        reloadableId: "notifs"
        property string historyJson: "[]"
        property bool dnd: false
        property int uid: 0
        // The server hands the open notifications over again after a reload: only these get their popup back
        property string shownJson: "[]"
        onLoaded: {
            try { s.history = JSON.parse(historyJson) } catch (e) { s.history = [] }
            try { s.shownAtReload = JSON.parse(shownJson) } catch (e) { s.shownAtReload = [] }
        }
    }
    onPopupsChanged: persist.shownJson = JSON.stringify(popups.map(p => p.uid))
    onHistoryChanged: {
        persist.historyJson = JSON.stringify(history)
        // A row that went (×, Clear, pushed out, replaced, expired) closes its notification: the app may stop waiting on it
        for (const u of Object.keys(live))
            if (!live[u].transient && !history.some(h => String(h.uid) === u)) live[u].expire()
    }
    Timer {
        interval: 30000; repeat: true; running: true
        onTriggered: {
            s.now = Date.now()
            if (s.history.some(h => h.expires && h.expires <= s.now)) s.history = s.history.filter(h => !h.expires || h.expires > s.now)
        }
    }

    // "now", "5 min", "2 h", then the time of day
    function ago(t) {
        const m = Math.floor((now - t) / 60000)
        if (m < 1) return "now"
        if (m < 60) return m + " min"
        if (m < 6 * 60) return Math.floor(m / 60) + " h"
        return Qt.formatTime(new Date(t), "HH:mm")
    }

    // Icons for names the icon theme doesn't have (blueman's headphones), recoloured by hypr/scripts/theme
    readonly property string ownIcons: Quickshell.env("HOME") + "/.cache/nightdrive/notify-icons/32x32/devices/"
    readonly property var ownIconNames: ["audio-headphones", "audio-headset"]
    function iconPath(name) {
        if (!name) return ""
        if (name.startsWith("lucide:")) return name   // a Lucide glyph (NotificationCard.qml draws it from the font)
        if (name.startsWith("/")) return "file://" + name
        if (name.indexOf("://") > 0) return name
        if (ownIconNames.indexOf(name) >= 0) return "file://" + ownIcons + name + ".svg"
        return Quickshell.iconPath(name, true)
    }
    // The app's .desktop entry: the desktop-entry hint, else by the app's name ("Firefox" → org.mozilla.firefox,
    // "Telegram Desktop" → org.telegram.desktop). DesktopEntries.heuristicLookup finds neither of those.
    function desktopEntry(n) {
        const all = DesktopEntries.applications.values
        const id = e => (e.id || "").replace(/\.desktop$/, "").toLowerCase()
        if (n.desktopEntry) {
            const want = n.desktopEntry.replace(/\.desktop$/, "").toLowerCase()
            const hit = all.find(e => id(e) === want)
            if (hit) return hit
        }
        const a = (n.appName || "").trim().toLowerCase()
        if (a === "") return null
        const dotted = a.replace(/\s+/g, ".")
        const first = a.split(/\s+/)[0]
        return all.find(e => id(e) === a || id(e).split(".").pop() === a || (e.name || "").toLowerCase() === a
                             || (e.startupClass || "").toLowerCase() === a)
            || all.find(e => id(e).endsWith("." + dotted) || (e.name || "").toLowerCase() === first || id(e).startsWith(a + "-"))   // blueman → blueman-manager
            || null
    }

    function remove(uid) {
        popups = popups.filter(p => p.uid !== uid)
        held = held.filter(p => p.uid !== uid)
    }
    // A popup on top (or, under the login screen, after the password)
    function pop(p) {
        if (locked) { held = held.filter(h => h.uid !== p.uid).concat([p]); return }
        if (dnd || menuOpen) { if (p.n.transient) p.n.expire(); return }
        const all = [p].concat(popups.filter(q => q.uid !== p.uid))
        // Too many: the oldest go (into the history only)
        popups = all.slice(0, maxPopups)
        for (const q of all.slice(maxPopups)) if (q.n.transient) q.n.expire()
    }
    // The popup goes; the notification stays open for the history unless it's transient
    function hide(uid) {
        const p = popups.find(p => p.uid === uid)
        remove(uid)
        if (p && p.n && p.n.transient) p.n.expire()
    }

    // The app closed its notification: the row goes after `withdrawWait` if the app still has a window (it withdrew it),
    // stays if not (it quit). The window may close a moment after the notifications do.
    readonly property int withdrawWait: 1500
    property var withdrawn: []                // [uid]
    function closed(uid, reason) {
        delete live[uid]
        remove(uid)
        if (reason !== NotificationCloseReason.CloseRequested) return
        withdrawn = withdrawn.concat([uid])
        withdrawTimer.restart()
    }
    Timer {
        id: withdrawTimer
        interval: s.withdrawWait
        onTriggered: {
            const gone = s.withdrawn
            s.withdrawn = []
            const keep = s.history.filter(h => gone.indexOf(h.uid) < 0 || !s.appRunning(h))
            if (keep.length !== s.history.length) s.history = keep
        }
    }

    // Chromium sends every site's notification as its own (app name Chromium, desktop entry chromium-browser, its logo as
    // the app icon) and puts the site's address first in the body: "app.slack.com\n\nNew message". That address is all
    // that tells the webapps apart: Quickshell doesn't give the sender's process, whose --user-data-dir would.
    function chromium(n) { return /^chromium/i.test(n.desktopEntry || "") }
    function site(n) {
        if (!chromium(n)) return ""
        const m = (n.body || "").match(/^([^\s\/]+)\n\n/)
        return m ? m[1] : ""
    }
    // The buttons a card shows. Not "default" (the click on the card is that), nor Chromium's own Settings on every site's
    // notification: its notification permissions page, beside a site's own buttons (Salli, Kiellä) only noise.
    function buttons(n) {
        return n.actions.filter(a => a.identifier !== "default" && !(a.identifier === "settings" && chromium(n)))
    }
    // The text without the site's line when a webapp's name says it already; a browser tab's keeps it (which site)
    function bodyOf(n) {
        return webapp(n) ? n.body.slice(site(n).length + 2) : n.body
    }
    // The webapp whose site sent it (webapp-add: Exec=chromium-browser … --app=https://<site>/…)
    function webapp(n) {
        const host = site(n).toLowerCase().replace(/^www\./, "")
        if (!host) return null
        return DesktopEntries.applications.values.find(e => {
            const m = (e.execString || "").match(/--app=[a-z]+:\/\/([^\/\s?#]+)/i)
            return !!m && m[1].toLowerCase().replace(/^www\./, "") === host
        }) || null
    }

    // The app a notification is about, where the sender's own name would mislead. A webapp's: its name, icon and window
    // (the site's line leaves the text; a site without a webapp, a browser tab, stays Chromium's).
    // nm-applet calls itself "NetworkManager Applet" and sends a signal-strength picture: shown as Wi-Fi with its glyph, or
    // as Network when it isn't about Wi-Fi (a cable, VPN; untested so far)
    function relabel(row, n) {
        const web = webapp(n)
        if (web) {
            row.app = web.name
            row.icon = web.icon || row.icon
            row.entry = web.id
            row.wmclass = web.startupClass
            row.body = bodyOf(n)
            return
        }
        if (!/^(networkmanager applet|nm-applet)$/i.test(n.appName || "")) return
        const wifi = /wireless|signal|wifi/i.test(n.appIcon || "") || /wi-?fi/i.test(n.summary + " " + n.body)
        row.app = wifi ? "Wi-Fi" : "Network"
        row.icon = "lucide:" + (wifi ? (/disconnect/i.test(n.summary) ? "wifi-off" : "wifi") : "network")
    }

    property var lastChime: ({})              // app → time of its last sound
    // The focused window belongs to the notification's app: its class is the app's name, (the last part of) its desktop id
    // (firefox ↔ org.mozilla.firefox, Slack ↔ com.slack.Slack) or its StartupWMClass (webapps: chrome-<site>-Default)
    function isApp(appId, row) {
        const cls = (appId || "").toLowerCase()
        if (cls === "") return false
        const id = (row.entry || "").replace(/\.desktop$/, "").toLowerCase()
        return cls === (row.app || "").toLowerCase() || (id !== "" && (cls === id || cls === id.split(".").pop()))
            || cls === (row.wmclass || "").toLowerCase()
    }
    function appFocused(row) {
        const t = ToplevelManager.activeToplevel
        return !!t && t.activated && isApp(t.appId, row)
    }
    function appRunning(row) { return ToplevelManager.toplevels.values.some(t => isApp(t.appId, row)) }
    function chime(row, n) {
        // suppress-sound: the standard hint for a sender that plays its own sound
        if (n.urgency === NotificationUrgency.Low || appFocused(row) || (n.hints || {})["suppress-sound"]) return
        const key = row.app || row.entry
        const now = Date.now()
        if (now - (lastChime[key] || 0) < soundGap) return
        lastChime[key] = now
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "play", row.critical ? "urgent" : "regular"])
    }

    NotificationServer {
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodyMarkupSupported: false
        persistenceSupported: true
        onNotification: n => {
            // A replacement (same id) updates the Notification already open: move it to the top as new
            const oldUid = Object.keys(s.live).find(u => s.live[u] === n)
            const old = oldUid !== undefined
            const hints = n.hints || {}
            const e = s.desktopEntry(n)
            // Quickshell hands an icon name sent as the notification's picture as image://icon/<name>: a name we look up
            // ourselves (the icon provider draws a checkerboard for one the theme doesn't have)
            const named = n.image.startsWith("image://icon/") ? n.image.slice(13) : ""
            // The app's icon as a name (AppIcon finds it even when the app was installed after Quickshell started), or
            // an icon named like the app (blueman)
            const lower = (n.appName || "").toLowerCase()
            const appIcon = (e && e.icon) || (lower && Quickshell.iconPath(lower, true) ? lower : "")
            const own = s.iconPath(n.appIcon || named)
            // The same notification again: a replacement, or one still shown when Quickshell reloaded (the server keeps
            // it and hands it over again). Its history row is updated, not added twice.
            const prev = s.history.find(h => h.nid === n.id)
            const same = prev && prev.summary === n.summary && prev.body === n.body
            const row = {
                uid: old ? Number(oldUid) : prev ? prev.uid : ++persist.uid,
                nid: n.id,
                app: n.appName || (e ? e.name : ""),
                summary: n.summary, body: n.body,
                // The app's icon; the notification's own picture (an avatar, a cover) goes to the right, and so does
                // a device icon (blueman's headphones). Any other app_icon is the app's own icon again: shown once.
                // A Lucide glyph asked for by name (lucide:<name>) wins over an icon named like the app ("Battery")
                icon: own.startsWith("lucide:") ? own : appIcon || own,
                image: (n.image && !named ? n.image : "") || (appIcon && s.ownIconNames.indexOf(n.appIcon || named) >= 0 ? own : ""),
                // A picture to show under the text, not as a square (screenshots: hypr/scripts/screenshot; a photo
                // Ferry received: the standard transfer.complete)
                preview: !!n.image && !named && (hints.category === "x-nightdrive.preview" || hints.category === "transfer.complete"),
                // Only an app the launcher lists: a click starts it when it has no window (hypr/scripts/focus-app), and
                // the desktop-entry hint is the sender's word, so it mustn't name a hidden entry (a handler, a helper)
                entry: e && !e.noDisplay ? e.id : "",
                wmclass: e ? e.startupClass : "",
                time: same ? prev.time : Date.now(),
                critical: n.urgency === NotificationUrgency.Critical,
                // A level to show as a meter under the text, 0–100 (hint value: `-h int:value:N`; -1 = none)
                value: typeof hints.value === "number" ? Math.max(0, Math.min(100, hints.value)) : -1,
                tag: "",
                expires: hints["x-nightdrive-expires"] > 0 ? Date.now() + hints["x-nightdrive-expires"] * 1000 : 0
            }
            s.relabel(row, n)
            const stack = hints["x-dunst-stack-tag"] || hints["x-canonical-private-synchronous"] || ""
            if (stack) row.tag = row.app + "\n" + stack
            // The earlier one this replaces: the same stack tag, or else the same text (in the history, or a transient popup)
            const twin = s.history.concat(s.popups.map(p => p.entry)).find(h => h.uid !== row.uid && h.app === row.app
                && (row.tag ? h.tag === row.tag : h.summary === row.summary && h.body === row.body))
            const others = s.history.filter(h => h.uid !== row.uid && (!twin || h.uid !== twin.uid))
            // (twin's notification closes as its row goes: onHistoryChanged)
            s.history = n.transient ? others : [row].concat(others).slice(0, s.maxHistory)
            if (twin && s.live[twin.uid] && s.live[twin.uid].transient) s.live[twin.uid].expire()
            if (!s.dnd && !s.locked && !old && !prev && !(twin && row.tag)) s.chime(row, n)
            n.tracked = true
            if (!old) {
                s.live[row.uid] = n
                n.closed.connect(reason => s.closed(row.uid, reason))
            }
            // Handed over again after a reload: its popup comes back only if it was showing
            const reloaded = !old && prev && same
            if (reloaded && s.shownAtReload.indexOf(row.uid) < 0) {
                if (n.transient) n.expire()
                return
            }
            s.pop({ uid: row.uid, n: n, entry: row })
        }
    }

    // A click on a popup: the app's default action if it has one, otherwise its window comes up (hypr/scripts/focus-app)
    function activate(p) {
        const def = p.n.actions.find(a => a.identifier === "default")
        if (!def) openApp(p.entry)
        if (def) def.invoke()              // closes the notification unless the app marked it resident
        if (p.n && !p.n.resident) p.n.dismiss()
        remove(p.uid)
    }
    // The notification menu: a row's app comes up; × forgets a row (and its popup, if it's still shown)
    function openApp(row) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/focus-app", row.app, row.entry, row.wmclass || ""])
    }
    function forget(uid) {
        if (live[uid]) live[uid].dismiss()
        history = history.filter(h => h.uid !== uid)
    }
    // The popups go (the menu opened, do not disturb); the notifications stay open for the history
    function dismissAll() { for (const p of popups.slice()) hide(p.uid) }

    IpcHandler {
        target: "notifications"
        function toggleDnd(): string { s.dnd = !s.dnd; if (s.dnd) s.dismissAll(); return String(s.dnd) }
        function setDnd(on: bool): void { s.dnd = on; if (on) s.dismissAll() }
        function getDnd(): string { return String(s.dnd) }
        function dismissAll(): void { s.dismissAll() }
        function clear(): void { s.history = [] }
        function count(): int { return s.history.length }
        // For testing: the rows as JSON (app, summary, body, tag, expires)
        function rows(): string { return JSON.stringify(s.history.map(h => ({ app: h.app, summary: h.summary, body: h.body, tag: h.tag, expires: h.expires }))) }
    }
}
