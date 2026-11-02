import QtQuick
import Quickshell

// What the launcher lists: the open level's rows, or, while something is typed, the hits ranked (the whole name, its start,
// a word's start, inside it, the search words, letters in order), with the calculator's answer and Ask Claude's row
// among them. Kept apart from Launcher.qml so the ranking can be read and changed alone; the launcher's `results` is
// items() here.
Item {
    id: root
    required property var launcher

    // Lower case without diacritics: "keittio" finds Keittiö, "ylavalo" Ylävalo
    function fold(s) { return s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "") }
    // 0 = the whole name, 0.5 = starts with query, 1 = word start, 2 = contains, -1 = no match (q folded). The whole name
    // first: "code" puts Code before Code - OSS, whatever their order in the list.
    function score(text, q) {
        const t = fold(text)
        if (t === q) return 0
        if (t.startsWith(q)) return 0.5
        if (t.split(/[\s\-_.\/]+/).some(w => w.startsWith(q))) return 1
        if (t.includes(q)) return 2
        return -1
    }
    // The last tier: q's letters in order, but not just anywhere (that would match nearly everything). Each letter is at a
    // word start, right after the previous match, or a letter or two after it in the same word: "vsc" → Visual Studio
    // Code, "kattovlo" → Kattovalo. Both folded.
    function fuzzy(t, q) {
        const start = i => i === 0 || /[\s\-_.\/›:]/.test(t[i - 1])
        const from = (qi, ti) => {        // q[qi..] matches from t[ti..]; prev match at ti - 1
            if (qi === q.length) return true
            for (let i = ti; i < t.length; i++) {
                if (t[i] !== q[qi]) continue
                const gap = i - ti
                const ok = qi === 0 ? start(i) : gap === 0 || start(i) || (gap <= 2 && !/[\s\-_.\/›:]/.test(t.slice(ti, i)))
                if (ok && from(qi + 1, i + 1)) return true
            }
            return false
        }
        return q.length >= 2 && from(0, 0)
    }

    // Typed in the root search, a certain old command (only its hash is here) and Enter start hypr/shaders/warp
    readonly property string basicKey: "c6a812e51728d75227cd473fd4d23ff0"
    readonly property var basicRow: ({ kind: "action", name: "SEARCHING FOR *", sub: "LOADING", glyph: "save",
                                       cmd: ["bash", "-c", "pgrep -f '^qs -p .*/shaders/warp' >/dev/null || exec qs -p ~/.config/hypr/shaders/warp"] })

    function items() {
        // The launcher's state and parts under their old names, so the ranking below reads as it did in Launcher.qml
        const L = launcher, lv = L.levels, level = L.level, query = L.query, statics = L.statics, prefs = L.prefs
        const settingsAliases = L.settingsAliases, rootItems = L.menus.rootItems, pluginExts = L.pluginExts
        const installAliases = L.menus.installAliases, powerAliases = L.menus.powerAliases, apps = L.appState, sc = L.shortcuts
        const themes = lv.themes, look = lv.look, mirror = lv.mirror, sound = lv.sound, home = lv.home, calc = lv.calc, ask = lv.ask
        const q = query.trim().toLowerCase()
        let all, tail = [], short = false
        if (level === "root" && Qt.md5(q.replace(/\s+/g, "").replace(/[“”„]/g, '"')) === basicKey) return [basicRow]
        if (level === "root") {
            all = rootItems.map(r => ({ item: r, text: r.name, extra: r.extra || "" }))
            // When searching, the root level also finds rows from the sublevels, so there's no need to open a menu first.
            // "from" tells which menu a row comes from; extra adds search words (aliases, alternative spellings).
            if (q !== "") for (const src of [
                // Tools entries ("color" → Color Picker)
                statics.tools.map(t => ({ item: t, text: t.name })),
                // Screenshot actions ("region", "screenshot", "capture")
                statics.screenshot.map(t => ({ item: Object.assign({}, t, { from: "Screenshot" }), text: t.name, extra: "screenshot capture screen" })),
                // Settings items ("wallpaper" → Background, "wifi" → Wi-Fi) plus Theme and Top bar sub-items ("opacity")
                statics.settings.filter(t => t.kind !== "header").map(t => ({ item: Object.assign({}, t, { from: "Settings" }), text: t.name, extra: "settings " + (settingsAliases[t.name] || "") })),
                // (an app's own settings named so, not to come before the app: "mail" finds Mail first, then Mail settings)
                statics.appsettings.filter(t => t.kind !== "header").map(t => {
                    const name = t.appName ? t.appName + " settings" : t.name
                    return { item: Object.assign({}, t, { from: "Settings", name: name }), text: name, extra: "settings apps " + (settingsAliases[t.name] || "") }
                }),
                themes.themeItems().map(t => ({ item: Object.assign({}, t, { from: "Theme", summary: undefined }), text: t.name, extra: "theme " + (settingsAliases[t.name] || "") })),
                look.topbarItems().map(t => ({ item: Object.assign({}, t, { from: "Top bar", summary: undefined }), text: t.name, extra: settingsAliases[t.name] || "" })),
                // Display and Screensaver sub-items ("night" → Night light, "dim" → Brightness, "saver" → Start after)
                L.settingsRows.displayItems().map(t => ({ item: Object.assign({}, t, { from: "Display" }), text: t.name, extra: "display " + (settingsAliases[t.name] || "") })),
                // Screen Mirroring's receivers ("mirror", "airplay", "olohuone"): Enter starts mirroring right from the search
                mirror.mirrorRows().filter(t => t.kind === "mirrordev").map(t => ({ item: Object.assign({}, t, { from: "Screen Mirroring", summary: undefined }),
                                                                                  text: t.name, extra: "screen mirroring " + t.extra })),
                // AirPlay speakers ("airplay", "olohuone"): Enter makes it the sound output
                sound.sinks.filter(d => d.airplay).map(d => ({ item: { kind: "sounddev", id: d.id, name: d.name, glyph: "speaker", from: "Sound",
                                                                     trailGlyph: d.current ? "check" : undefined },
                                                             text: d.name, extra: "airplay sound audio output speaker" })),
                look.screensaverItems().map(t => ({ item: Object.assign({}, t, { from: "Screensaver", summary: undefined }), text: t.name, extra: "screensaver idle lock" })),
                // System's items ("upd" → Update, "cpu" → Status)
                statics.system.map(t => ({ item: Object.assign({}, t, { from: "System", summary: undefined }), text: t.name, extra: t.extra || "" })),
                // Install's sub-items ("flatpak", "webapp", "flathub" → Flatpak)
                statics.install.map(t => ({ item: Object.assign({}, t, { from: "Install", summary: undefined }), text: t.name,
                                            extra: "install " + (installAliases[t.name] || "") })),
                // Only found by searching: names the focused workspace (ToolsLevels › wsname)
                [{ item: { kind: "nav", name: "Rename current space", glyph: "pencil", target: "wsname" }, text: "Rename current space",
                   extra: "workspace name label" }],
                // Power actions ("shut" → Shut down)
                statics.power.map(t => ({ item: t, text: t.name, extra: powerAliases[t.name] || "" })),
                // Apps ("1pas" → 1Password), also one named like a root item (e.g. a webapp next to its menu): the APPS tag and
                // the open-window dot tell them apart
                apps.appEntries(q).map(a => Object.assign({}, a, { item: Object.assign({}, a.item, { from: "Apps" }) })),
                // Home Assistant's devices ("olohuone" → its lights): Enter turns one on/off right from the search
                home.rootRows(),
                // The plugins' own rows (rootRows: Deck's albums, "fm-84" → Atlas)
                ...pluginExts.map(e => e.rootRows ? e.rootRows() : [])
            ]) all = all.concat(src)
            // Rows after the hits as they are, whatever was typed (rootTail: Deck's Search Spotify row, when Deck is in the search)
            if (q !== "") tail = [].concat(...pluginExts.map(e => e.rootTail ? e.rootTail(q) : [])).map(r => Object.assign({ tail: true }, r))
        } else if (level === "apps") {
            all = apps.appEntries(q)
            if (q === "") all.sort((a, b) => a.text.localeCompare(b.text))
        } else if (level === "keys") {
            all = sc.keyList.map(k => ({ item: { kind: "key", name: k.name, sub: k.sub || undefined, keys: k.keys, section: k.section }, text: k.name,
                                      extra: k.keys + " " + k.section + " " + k.sub }))
        } else if (L.extOf(level)) {
            const r = L.extOf(level).items(level, q)
            if (!r.all) return r          // ready-made rows (hints, etc.)
            all = r.all                   // [{ item, text, extra }], filtered by the query below
            tail = r.tail || []           // rows after a search's hits
            short = r.short === true      // thousands of short names (Emoji): no fuzzy matching, the shortest first
        } else if (level === "startup") {
            all = apps.appEntries(q).map(a => {
                const on = apps.autostartIds.indexOf(apps.appId(a.item)) >= 0
                return Object.assign({}, a, { item: Object.assign({}, a.item, { summary: on ? (apps.bgApps[a.item.name] !== undefined ? "at login, hidden" : "at login") : undefined }) })
            })
            if (q === "") return all.sort((a, b) => a.text.localeCompare(b.text)).map(x => x.item)   // a fixed order: toggling doesn't move rows
        } else {
            all = (statics[level] || []).map(r => ({ item: r, text: r.kind === "header" ? "" : r.name }))   // a search drops the headers
        }
        if (q === "") return level === "keys" ? sc.grouped(all.map(x => x.item)) : all.map(x => x.item)
        const scored = []
        // Several words: each may hit the name or the search words ("olohuone kattovalo" → the room is in extra, the name in text)
        const fq = fold(q)
        const words = fq.split(/\s+/).filter(w => w !== "")
        const fuzzyOk = prefs.fuzzy && !short   // letters in order would hit too many of them
        all.forEach((x, i) => {
            let s = score(x.text, fq)
            // An app's own settings ("Firefox settings") right after the app while its name is being typed: "fire" hits
            // both as a start, and the settings come earlier in the list
            if (s >= 0 && s < 1 && x.item.appName && score(x.item.appName, fq) >= 0) s += 0.25
            const extra = x.extra ? fold(x.extra) : ""
            if (s < 0 && extra.includes(fq)) s = 3
            if (s < 0 && words.length > 1) {
                const hay = fold(x.text) + " " + extra
                if (words.every(w => hay.includes(w))) s = 4
                // 5: the same with typos and shortcuts, each word fuzzy ("olohuone kattovlo")
                else if (fuzzyOk && words.every(w => hay.includes(w) || fuzzy(hay, w))) s = 5
            }
            if (s < 0 && fuzzyOk && words.length === 1 && fuzzy(fold(x.text), fq)) s = 5
            if (s >= 0) scored.push({ x: x, s: s, i: i })
        })
        scored.sort((a, b) => (a.s - b.s) || (level === "apps" ? a.x.text.localeCompare(b.x.text) : short ? (a.x.text.length - b.x.text.length) || (a.i - b.i) : a.i - b.i))
        const res = scored.map(o => o.x.item).concat(tail)
        // The calculator's answer ("3*8" → "= 24") first, unless a name starts with what was typed: "7-zip" stays an app
        const sum = level === "root" ? calc.row(query) : null
        if (sum) res.splice(scored.filter(o => o.s <= 0.5).length, 0, sum)
        // A search that looks like a request: Ask Claude right after the hits, before the plugins' rows (Search Spotify)
        if (level === "root") { const t = res.findIndex(r => r.tail); res.splice(t < 0 ? res.length : t, 0, ...ask.tailRows(query, res)) }
        return level === "keys" ? sc.grouped(res) : res
    }
}
