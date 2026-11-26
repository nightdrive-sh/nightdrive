import QtQuick
import Quickshell

// The launcher's Settings › Sound and its Headphones page: the top bar's VolumeMenu, OutputList and HeadphonesMenu as
// launcher rows, so the launcher doesn't hand over to a menu. Headphones is here too because it is Sound's sublevel and
// its headphones are one of Sound's outputs. Launcher.qml asks it like its other Levels files (levels, titles, parents,
// items, activate, footer, entered), for the volume sliders (setSlider, stepSlider), the outputs (sinks: AirPlay speakers
// in the launcher's search) and soundRefresh when it opens. Split from SystemLevels.qml (#1937).
Item {
    id: s
    property var launcher: null

    readonly property var levels: ["sound", "headphones"]
    readonly property var titles: ({ sound: "Settings › Sound", headphones: "Sound › Headphones" })
    readonly property var parents: ({ sound: "settings", headphones: "sound" })
    readonly property string level: launcher ? launcher.level : ""
    readonly property bool shown: launcher !== null && launcher.open && levels.indexOf(level) >= 0

    function hint(t) { return [{ kind: "hint", name: t }] }
    function row(r) { return { item: r, text: r.kind === "header" || r.kind === "hint" ? "" : r.name, extra: r.extra || "" } }
    function sel() { if (launcher) launcher.keepSelection() }   // a refresh rebuilds the rows: keep the selected one

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "slider") return "Left+Right: " + cur.name.toLowerCase() + "  ·  Enter: mute on/off"
        if (cur.kind === "sounddev") return "Enter: use this"
        if (cur.kind === "btmic") return "Enter: switch to headset mode and use this"
        if (cur.kind === "hpdev") return "Enter: " + (cur.current ? "disconnect" : "use as output")
        if (cur.kind === "hpmode") return cur.trailGlyph ? "" : "Enter: switch"
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level === "sound") soundRefresh()
        if (level === "headphones") hpProc.running = true
    }
    function shiftActivate(item) {}

    function items(level, q) {
        if (level === "sound") return { all: soundRows().map(row) }
        if (level === "headphones") return { all: hpRows().map(row) }
        return []
    }

    // Enter on a row. Returns true when the row was one of ours.
    function activate(it) {
        if (it.kind === "slider") { sel(); toggleMute(it.key); return true }
        if (it.kind === "sounddev") {
            sel()
            // A microphone that isn't the headphones': the headphones go back to music mode (as in OutputList)
            const src = sources.find(x => x.id === it.id)
            if (src && !src.bt) Quickshell.execDetached(["bash", "-c", 'wpctl set-default "$1" && "$2" release', "_", String(it.id), btMic])
            else Quickshell.execDetached(["wpctl", "set-default", String(it.id)])
            soundSoon.restart()
            const d = sinks.find(x => x.id === it.id)
            if (d && d.airplay) Quickshell.execDetached([airplayCheck, "notify", d.node])   // warns if it refuses audio
            return true
        }
        if (it.kind === "btmic") {
            if (btMicBusy !== "") return true
            sel()
            btMicBusy = it.card; btMicFailed = ""
            btMicUse.environment = { "BTMIC": btMic, "CARD": it.card }
            btMicUse.running = true
            return true
        }
        if (it.kind === "hpdev") {
            sel()
            if (it.current) Quickshell.execDetached([eq, "disconnect"])
            else Quickshell.execDetached(["pactl", "set-default-sink", hp.sink])
            hpSoon.restart()
            return true
        }
        if (it.kind === "hpmode") { sel(); hpSet.command = [eq, "anc", it.name]; hpSet.running = true; return true }
        return false
    }

    // ---- Sliders (Sound): ←/→ and the row's slider call these ----
    function sliderValue(key) { return key === "mic" ? micVolume : volume }
    function setSlider(key, v) {
        sel()
        if (key === "mic") { micVolume = v; micPending = v } else { volume = v; pending = v }
        if (!volApply.running) volApply.start()
    }
    function stepSlider(key, dir) {
        const p = Math.round(sliderValue(key) * 100)
        const n = dir > 0 ? (Math.floor(p / 5) + 1) * 5 : (p % 5 === 0 ? p - 5 : Math.floor(p / 5) * 5)
        setSlider(key, Math.max(0, Math.min(100, n)) / 100)
    }

    // ================= Sound (wpctl, pw-dump; as in VolumeMenu and OutputList) =================
    property real volume: 0
    property bool muted: false
    property real pending: -1
    property real micVolume: 0
    property bool micMuted: false
    property real micPending: -1
    property var sinks: []           // [{ id, name, current, bt }]
    property var sources: []
    // Connected headphones in music mode, which have no microphone then: listed as one anyway, Enter switches them to
    // headset mode (hypr/scripts/bt-mic, as in OutputList)
    readonly property string btMic: Quickshell.env("HOME") + "/.config/hypr/scripts/bt-mic"
    property var btMics: []          // [{ card, name }]
    property string btMicBusy: ""    // switching this card to headset mode
    property string btMicFailed: ""  // the last switch of this card gave no microphone (it stays in music mode)
    // AirPlay speakers that refuse PipeWire's AirPlay 1 (RTSP 403): Apple TV / HomePod since OS 27 (Apple bug FB24452968).
    // Probed live, so the warning disappears by itself once Apple fixes it. See docs/known-issues.md.
    property var airplayRefused: []  // [node.name]
    readonly property string airplayCheck: Quickshell.env("HOME") + "/.config/hypr/scripts/airplay-check"
    property real airplayProbedAt: 0
    function soundRefresh() { volProc.running = true; micProc.running = true; dumpProc.running = true; if (!btMicProc.running) btMicProc.running = true }
    Sh {
        id: btMicProc
        command: [s.btMic, "list"]
        onResult: text => {
            let v = []
            try { v = JSON.parse(text) } catch (e) {}
            if (JSON.stringify(v) !== JSON.stringify(s.btMics)) { s.sel(); s.btMics = v }
        }
    }
    Sh {
        id: btMicUse
        script: '"$BTMIC" use "$CARD"'
        onResult: text => { s.sel(); s.btMicFailed = btMicUse.exitCode !== 0 ? s.btMicBusy : ""; s.btMicBusy = ""; s.soundRefresh() }
    }
    function toggleMute(key) {
        if (key === "mic") micMuted = !micMuted; else muted = !muted
        Quickshell.execDetached(["wpctl", "set-mute", key === "mic" ? "@DEFAULT_AUDIO_SOURCE@" : "@DEFAULT_AUDIO_SINK@", "toggle"])
        soundSoon.restart()
    }
    function devIcon(d, source) {
        return d.bt || /head|buds|airpods/i.test(d.name) ? "headphones" : source ? "mic"
             : /macbook|built-in|laptop/i.test(d.name) ? "laptop" : /tv|display|monitor/i.test(d.name) ? "tv" : "speaker"
    }
    function soundRows() {
        const pct = v => Math.round(v * 100) + "%"
        const r = [{ kind: "header", name: "Output" },
                   { kind: "slider", key: "volume", name: "Volume", value: volume, dimmed: muted, extra: "mute",
                     glyph: muted || volume === 0 ? "volume-x" : volume < 0.34 ? "volume" : volume < 0.67 ? "volume-1" : "volume-2",
                     summary: muted ? "muted" : pct(volume) }]
        for (const d of sinks)
            r.push({ kind: "sounddev", id: d.id, name: d.name, glyph: devIcon(d, false), trailGlyph: d.current ? "check" : undefined,
                     summary: s.airplayRefused.includes(d.node) ? "no audio (Apple bug)" : d.airplay && !d.current ? "AirPlay" : undefined,
                     extra: "output speakers" + (d.airplay ? " airplay" : "") })
        r.push({ kind: "header", name: "Microphone" },
               { kind: "slider", key: "mic", name: "Microphone", value: micVolume, dimmed: micMuted, extra: "mute input",
                 glyph: micMuted ? "mic-off" : "mic", summary: micMuted ? "muted" : pct(micVolume) })
        for (const d of sources)
            r.push({ kind: "sounddev", id: d.id, name: d.name, glyph: devIcon(d, true), trailGlyph: d.current ? "check" : undefined,
                     summary: d.bt ? "headset mode" : undefined, extra: "input microphone" })
        for (const d of btMics)
            r.push({ kind: "btmic", card: d.card, name: d.name, glyph: "headphones", extra: "input microphone headphones",
                     summary: btMicBusy === d.card ? "switching…" : btMicFailed === d.card ? "didn't switch" : "headset mode" })
        r.push({ kind: "header", name: "More" })
        // Bluetooth headphones' own page (modes, battery, equalizer), while they are connected
        const bt = sinks.find(d => d.bt)
        if (bt) r.push({ kind: "nav", name: "Headphones", glyph: "headphones", target: "headphones", summary: bt.name, extra: "headphones airpods noise" })
        r.push({ kind: "action", name: "Sound settings…", glyph: "settings", cmd: ["pavucontrol"] })
        return r
    }
    Timer { interval: 1000; repeat: true; running: s.shown && s.level === "sound"; onTriggered: { s.soundRefresh(); s.probeAirplay() } }
    function probeAirplay() {
        const nodes = sinks.filter(d => d.airplay).map(d => d.node)
        if (nodes.length === 0 || airplayProbe.running || Date.now() - airplayProbedAt < 30000) return
        airplayProbedAt = Date.now()
        airplayProbe.command = [airplayCheck, "refused"].concat(nodes)
        airplayProbe.running = true
    }
    Sh {
        id: airplayProbe
        onResult: text => {
            const refused = text.split("\n").filter(l => l !== "")
            if (JSON.stringify(refused) === JSON.stringify(s.airplayRefused)) return
            s.sel(); s.airplayRefused = refused
        }
    }
    Timer { id: soundSoon; interval: 150; onTriggered: s.soundRefresh() }
    Timer {
        id: volApply; interval: 60
        onTriggered: {
            if (s.pending >= 0) { Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", s.pending.toFixed(2)]); s.pending = -1 }
            if (s.micPending >= 0) { Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", s.micPending.toFixed(2)]); s.micPending = -1 }
        }
    }
    Sh {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        onResult: text => {
            const r = text.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
            if (!r || s.pending >= 0 || (parseFloat(r[1]) === s.volume && !!r[2] === s.muted)) return
            s.sel(); s.volume = parseFloat(r[1]); s.muted = !!r[2]
        }
    }
    Sh {
        id: micProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        onResult: text => {
            const r = text.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
            if (!r || s.micPending >= 0 || (parseFloat(r[1]) === s.micVolume && !!r[2] === s.micMuted)) return
            s.sel(); s.micVolume = parseFloat(r[1]); s.micMuted = !!r[2]
        }
    }
    Sh {
        id: dumpProc
        command: ["pw-dump"]
        onResult: text => {
            let objs
            try { objs = JSON.parse(text) } catch (e) { return }
            const def = {}
            for (const ob of objs) {
                if (ob.type !== "PipeWire:Interface:Metadata") continue
                for (const e of (ob.metadata || []))
                    if ((e.key === "default.audio.sink" || e.key === "default.audio.source") && e.value) def[e.key] = e.value.name
            }
            const out = { "Audio/Sink": [], "Audio/Source": [] }
            for (const ob of objs) {
                if (ob.type !== "PipeWire:Interface:Node") continue
                const p = (ob.info || {}).props || {}
                const list = out[p["media.class"]]
                if (!list || /^easyeffects_/.test(p["node.name"])) continue   // EasyEffects' virtual device, not a real one
                const key = p["media.class"] === "Audio/Sink" ? "default.audio.sink" : "default.audio.source"
                list.push({ id: ob.id, name: p["node.description"] || p["node.name"], current: p["node.name"] === def[key], bt: /^bluez_/.test(p["node.name"]),
                            airplay: /^raop_sink\./.test(p["node.name"]),   // PipeWire's AirPlay speakers (RAOP)
                            node: p["node.name"] })
            }
            // The same kinds together, as in OutputList: the machine's own, Bluetooth headphones, other wired, AirPlay
            const rank = d => /^MacBook Pro/i.test(d.name) ? 0 : /^Built-in/i.test(d.name) ? 1 : d.bt ? 2 : d.airplay ? 5 : 4
            for (const k in out) out[k].sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name))
            if (JSON.stringify(out["Audio/Sink"]) === JSON.stringify(s.sinks) && JSON.stringify(out["Audio/Source"]) === JSON.stringify(s.sources)) return
            s.sel()
            s.sinks = out["Audio/Sink"]
            s.probeAirplay()
            s.sources = out["Audio/Source"]
        }
    }

    // ================= Headphones (as in HeadphonesMenu: topbar/scripts/eq info) =================
    readonly property string eq: Quickshell.env("HOME") + "/.config/topbar/scripts/eq"
    property var hp: ({})
    function hpRows() {
        if (!hp.sink) return hint("No headphones connected")
        const r = [{ kind: "hpdev", name: hp.name, glyph: "headphones", current: !!hp.default, summary: hp.codec || undefined,
                     trailGlyph: hp.default ? "check" : undefined }]
        // Battery: AirPods per pod and case (hypr/scripts/headphones-ctl), other headphones the level BlueZ reports
        const pods = (hp.airpods && hp.airpods.pods) || {}
        const bats = ["left", "right", "case"].filter(k => pods[k]).map(k => Object.assign({ key: k }, pods[k]))
        if (bats.length === 0 && /^\d+$/.test(hp.battery || "")) bats.push({ key: "", level: parseInt(hp.battery) })
        if (bats.length > 0) r.push({ kind: "header", name: "Battery" })
        for (const b of bats) {
            const where = b.key === "case" ? (b.stale ? "earlier" : b.charging ? "charging" : "")
                        : b.charging ? "charging" : ({ ear: "in ear", out: "out", case: "in case" })[b.where] || ""
            r.push({ kind: "battery", name: ({ left: "Left", right: "Right", case: "Case", "": "Battery" })[b.key], value: b.level / 100,
                     charging: !!b.charging, dimmed: !!b.stale, low: b.level < 20 && !b.charging && !b.stale,
                     glyph: b.charging ? "zap" : b.where === "ear" ? "ear" : "battery-medium",
                     summary: b.level + "%" + (where ? " · " + where : "") })
        }
        if ((hp.ancModes || []).length > 1) {
            r.push({ kind: "header", name: "Listening mode" })
            const icons = { "Noise cancelling": "ear-off", "Adaptive": "sparkles", "Transparency": "ear", "Passive": "mic-audio-lines" }
            const rank = m => { const i = Object.keys(icons).indexOf(m); return i < 0 ? 99 : i }   // in the menu's order
            for (const m of hp.ancModes.slice().sort((a, b) => rank(a) - rank(b)))
                r.push({ kind: "hpmode", name: m, glyph: icons[m] || "headphones", trailGlyph: hp.anc === m ? "check" : undefined })
        }
        r.push({ kind: "header", name: "More" })
        if (hp.airpods) r.push({ kind: "action", name: "AirPods settings…", glyph: "settings", cmd: ["qs", "ipc", "call", "airpods", "open"] })
        r.push({ kind: "menu", name: "Equalizer…", glyph: "sliders-horizontal", target: "headphones",
                 summary: hp.preset && hp.preset !== "off" ? hp.preset : "off" })
        return r
    }
    Timer { interval: 2000; repeat: true; running: s.shown && s.level === "headphones"; onTriggered: hpProc.running = true }
    Timer { id: hpSoon; interval: 800; onTriggered: hpProc.running = true }
    Sh {
        id: hpProc
        command: [s.eq, "info"]
        onResult: text => {
            let v
            try { v = JSON.parse(text) } catch (e) { return }
            if (JSON.stringify(v) === JSON.stringify(s.hp)) return
            s.sel()
            s.hp = v
        }
    }
    Sh {
        id: hpSet
        onResult: () => { hpProc.running = true; TopBar.refresh("headphones") }
    }
}
